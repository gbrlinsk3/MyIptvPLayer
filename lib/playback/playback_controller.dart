import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/disk_space.dart';

enum RecState { idle, recording, paused }

/// Dono do player (libmpv) e do "vigia" de reprodução.
///
/// O vigia reabre o canal sozinho quando:
///  - o player reporta erro (ex.: "Error decoding audio");
///  - a transmissão é encerrada pelo servidor;
///  - a posição de reprodução para de avançar por alguns segundos.
/// Depois de [_maxAttempts] tentativas seguidas sem sucesso, mostra o erro.
///
/// Os limites de tempo abaixo são valores iniciais escolhidos por mim, não
/// medidos no seu provedor.
class PlaybackController extends ChangeNotifier {
  PlaybackController() {
    _subs.add(player.stream.error.listen(_onError));
    _subs.add(player.stream.buffering.listen(_onBuffering));
    _subs.add(player.stream.position.listen(_onPosition));
    _subs.add(player.stream.completed.listen(_onCompleted));
    _watchdog = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  static const _maxAttempts = 5;
  static const _stallLimit = Duration(seconds: 12);
  static const _startLimit = Duration(seconds: 25);
  static const _healthyAfter = Duration(seconds: 20);

  final Player player = Player();
  late final VideoController video = VideoController(player);

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _watchdog;
  Timer? _retryTimer;

  // ---- estado visível pela interface ------------------------------------

  int? openedChannelId;
  int openedNonce = -1;

  /// Preenchido só depois de esgotar as tentativas automáticas.
  String? error;
  bool buffering = false;
  bool reconnecting = false;

  double volume = 100;
  bool get muted => volume <= 0;

  // ---- gravação (conexão HTTP própria, independente do libmpv) ------------
  //
  // Baixa o mesmo link do canal (trocando .m3u8 por .ts, se for o caso) direto
  // para um arquivo, sem converter. É uma **segunda conexão** com o provedor.
  // "Pausar" fecha o arquivo atual e "continuar" abre outro (nome com " (2)",
  // " (3)"...). A versão anterior usava a propriedade `stream-record` do libmpv,
  // que não gerou arquivo no teste do usuário.

  RecState recState = RecState.idle;

  /// Último arquivo aberto pela gravação.
  String? recFile;

  /// Arquivos gerados pela gravação atual.
  final List<String> recFiles = [];

  /// Aviso da gravação (ex.: conexão caiu); null se está tudo certo.
  String? recNotice;
  int recBytes = 0;
  HttpClient? _recClient;
  IOSink? _recSink;
  StreamSubscription<List<int>>? _recSub;
  Timer? _recRetry;

  final Stopwatch _recWatch = Stopwatch();
  Timer? _recTimer;
  String? _recBase;
  int _recSegment = 0;

  /// Tempo realmente gravado (sem os intervalos pausados).
  Duration get recElapsed => _recWatch.elapsed;

  static String _cleanName(String name) {
    var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    if (s.length > 80) s = s.substring(0, 80).trim();
    return s.isEmpty ? 'Canal' : s;
  }

  /// Começa a gravar o canal aberto em [folder]. Devolve uma mensagem de erro
  /// (ou null se deu certo).
  Future<String?> startRecording({
    required String folder,
    required String channelName,
  }) async {
    if (recState != RecState.idle) return null;
    if (!_active || _url == null) return 'Abra um canal antes de gravar.';
    final free = await DiskSpace.freeBytes(folder);
    if (free != null && free < 1024 * 1024 * 1024) {
      return 'Menos de 1 GB livre na pasta de gravação.';
    }
    try {
      await Directory(folder).create(recursive: true);
    } catch (e, st) {
      AppLog.error('gravacao.pasta', e, st);
      return 'Não consegui criar a pasta de gravação: $e';
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}-${two(now.minute)}';
    _recBase = p.join(folder, '${_cleanName(channelName)} - $stamp');
    _recSegment = 0;
    recFiles.clear();
    recBytes = 0;
    recNotice = null;
    final err = await _beginSegment();
    if (err != null) return err;
    recState = RecState.recording;
    _recWatch
      ..reset()
      ..start();
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    _notify();
    return null;
  }

  Future<String?> _beginSegment() async {
    final raw = _url;
    if (raw == null) return 'Abra um canal antes de gravar.';
    var uri = Uri.parse(raw);
    if (uri.path.endsWith('.m3u8')) {
      uri = uri.replace(path: uri.path.replaceFirst(RegExp(r'\.m3u8$'), '.ts'));
    }
    _recSegment++;
    final path = '$_recBase${_recSegment == 1 ? '' : ' ($_recSegment)'}.ts';
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(uri);
      _headers?.forEach(req.headers.set);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close(force: true);
        return 'O servidor recusou a gravação (HTTP ${resp.statusCode}). '
            'Pode ser o limite de conexões do seu provedor.';
      }
      final sink = File(path).openWrite();
      _recClient = client;
      _recSink = sink;
      recFile = path;
      recFiles.add(path);
      recNotice = null;
      _recSub = resp.listen(
        (chunk) {
          sink.add(chunk);
          recBytes += chunk.length;
        },
        onError: (Object e, StackTrace st) {
          AppLog.error('gravacao.rede', e, st);
          _recDropped();
        },
        onDone: _recDropped,
        cancelOnError: true,
      );
      return null;
    } catch (e, st) {
      AppLog.error('gravacao.iniciar', e, st);
      client?.close(force: true);
      return 'Falha ao iniciar a gravação: $e';
    }
  }

  /// A conexão da gravação caiu sozinha: tenta abrir outro arquivo em 2 s.
  void _recDropped() {
    if (recState != RecState.recording || _disposed) return;
    unawaited(_closeSegmentFile());
    recNotice = 'Conexão da gravação caiu; tentando de novo…';
    _notify();
    _recRetry?.cancel();
    _recRetry = Timer(const Duration(seconds: 2), () async {
      if (recState != RecState.recording) return;
      final err = await _beginSegment();
      if (err != null) {
        _recWatch.stop();
        recState = RecState.paused;
        recNotice = err;
      }
      _notify();
    });
  }

  Future<void> _closeSegmentFile() async {
    final sub = _recSub;
    final sink = _recSink;
    final client = _recClient;
    _recSub = null;
    _recSink = null;
    _recClient = null;
    try {
      await sub?.cancel();
      await sink?.flush();
      await sink?.close();
    } catch (e, st) {
      AppLog.error('gravacao.fechar', e, st);
    }
    client?.close(force: true);
  }

  Future<void> _endSegment() => _closeSegmentFile();

  Future<void> pauseRecording() async {
    if (recState != RecState.recording) return;
    _recWatch.stop();
    await _endSegment();
    recState = RecState.paused;
    _notify();
  }

  Future<String?> resumeRecording() async {
    if (recState != RecState.paused) return null;
    final err = await _beginSegment();
    if (err != null) return err;
    _recWatch.start();
    recState = RecState.recording;
    _notify();
    return null;
  }

  /// Encerra a gravação e devolve os arquivos gerados.
  Future<List<String>> stopRecording() async {
    if (recState == RecState.idle) return const [];
    _recTimer?.cancel();
    _recRetry?.cancel();
    _recWatch.stop();
    await _endSegment();
    recState = RecState.idle;
    _notify();
    // Só os arquivos que existem e têm conteúdo.
    return [
      for (final f in recFiles)
        if (File(f).existsSync() && File(f).lengthSync() > 0) f,
    ];
  }

  // ---- estado interno ----------------------------------------------------

  double _lastVolume = 100;
  String? _url;
  Map<String, String>? _headers;
  bool _active = false;
  bool _disposed = false;
  int _attempts = 0;
  DateTime _lastProgress = DateTime.now();
  DateTime? _firstProgressAt;
  Duration _lastPosition = Duration.zero;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Abre o canal. Chamadas repetidas com o mesmo canal e o mesmo [nonce]
  /// são ignoradas; um [nonce] novo reabre o canal do zero.
  Future<void> play({
    required int channelId,
    required int nonce,
    required String url,
    Map<String, String>? headers,
  }) async {
    if (_active && channelId == openedChannelId && nonce == openedNonce) {
      return;
    }
    if (recState != RecState.idle) unawaited(stopRecording());
    openedChannelId = channelId;
    openedNonce = nonce;
    _url = url;
    _headers = headers;
    _attempts = 0;
    error = null;
    reconnecting = false;
    _active = true;
    await _open();
  }

  Future<void> stop() async {
    await stopRecording();
    _active = false;
    _retryTimer?.cancel();
    openedChannelId = null;
    openedNonce = -1;
    _url = null;
    error = null;
    reconnecting = false;
    buffering = false;
    _notify();
    await player.stop();
  }

  Future<void> _open() async {
    final url = _url;
    if (url == null || _disposed) return;
    _retryTimer?.cancel();
    final now = DateTime.now();
    _lastProgress = now;
    _firstProgressAt = null;
    _lastPosition = Duration.zero;
    _notify();
    try {
      await player.open(Media(url, httpHeaders: _headers));
    } catch (e) {
      _fail('$e');
    }
  }

  // ---- reações aos eventos do player ------------------------------------

  void _onError(String message) {
    if (message.isEmpty) return;
    _fail(message);
  }

  void _onBuffering(bool value) {
    if (buffering == value) return;
    buffering = value;
    _notify();
  }

  void _onPosition(Duration position) {
    if (!_active || position == _lastPosition) return;
    _lastPosition = position;
    final now = DateTime.now();
    _lastProgress = now;
    _firstProgressAt ??= now;
    // Reproduziu por um tempo seguido: zera o contador de falhas.
    if (now.difference(_firstProgressAt!) >= _healthyAfter) _attempts = 0;
    if (reconnecting) {
      reconnecting = false;
      _notify();
    }
  }

  void _onCompleted(bool done) {
    if (!done || !_active || error != null) return;
    _fail('A transmissão foi encerrada pelo servidor.');
  }

  void _tick(Timer timer) {
    if (!_active || error != null || _disposed) return;
    if (_retryTimer?.isActive ?? false) return;
    final limit = _firstProgressAt == null ? _startLimit : _stallLimit;
    final stalled = DateTime.now().difference(_lastProgress);
    if (stalled > limit) {
      _fail('Sem dados do servidor há ${stalled.inSeconds}s.');
    }
  }

  void _fail(String message) {
    if (!_active || _disposed) return;
    if (_retryTimer?.isActive ?? false) return; // já há uma tentativa agendada
    if (_attempts >= _maxAttempts) {
      error = message;
      reconnecting = false;
      _notify();
      return;
    }
    _attempts++;
    reconnecting = true;
    error = null;
    final seconds = _attempts == 1 ? 1 : math.min(_attempts * 2, 8);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (_active) unawaited(_open());
    });
    _notify();
  }

  // ---- volume ------------------------------------------------------------

  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 100.0).toDouble();
    volume = v;
    if (v > 0) _lastVolume = v;
    _notify();
    await player.setVolume(v);
  }

  Future<void> toggleMute() => setVolume(volume > 0 ? 0 : _lastVolume);

  @override
  void dispose() {
    _disposed = true;
    _recTimer?.cancel();
    _recRetry?.cancel();
    if (recState != RecState.idle) unawaited(_endSegment());
    _watchdog?.cancel();
    _retryTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
