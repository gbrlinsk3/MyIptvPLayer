import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'package:path/path.dart' as p;

import '../../core/app_log.dart';
import '../../core/format.dart';
import '../../core/system_dialogs.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../window/title_bar.dart';
import 'player_episodes_panel.dart';
import 'player_scrub.dart';

/// Abre o player de filmes/séries cobrindo a janela inteira.
/// Para a TV ao vivo antes (evita ocupar duas conexões do provedor) e, ao
/// voltar, avisa o catálogo para atualizar o progresso.
Future<void> playItems(
  BuildContext context, {
  required List<PlayItem> items,
  int index = 0,
  Duration? startAt,
}) async {
  final app = AppScope.read(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  await app.playback.stop();
  // Só filmes/séries pela internet ocupam uma conexão da conta; arquivo local não.
  final remote = items.any((i) => i.url.startsWith('http'));
  if (remote) {
    app.downloads.suspendForPlayback();
    app.catalog.beginPlayback(); // sem trabalho novo em segundo plano
  }
  try {
  await navigator.push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: VodPlayerPage(
          app: app,
          items: items,
          index: index,
          startAt: startAt,
        ),
      ),
    ),
  );
  } finally {
    if (remote) {
      app.catalog.endPlayback();
      unawaited(app.downloads.resumeAfterPlayback());
    }
  }
  app.catalog.bumpProgress();
}

enum _NextPanel { hidden, expanded, minimized }

class VodPlayerPage extends StatefulWidget {
  const VodPlayerPage({
    super.key,
    required this.app,
    required this.items,
    required this.index,
    this.startAt,
  });

  final AppController app;
  final List<PlayItem> items;
  final int index;
  final Duration? startAt;

  @override
  State<VodPlayerPage> createState() => _VodPlayerPageState();
}

class _VodPlayerPageState extends State<VodPlayerPage> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];

  late int _index = widget.index;
  PlayItem get _item => widget.items[_index];
  bool get _hasNext => _index + 1 < widget.items.length;

  bool _playing = false;
  bool _buffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _pendingSeek;
  Duration _lastSavedAt = Duration.zero;
  bool _finished = false;

  String? _lastError;
  String? _error;
  DateTime _lastProgress = DateTime.now();

  Tracks _tracks = const Tracks();
  Track _track = const Track();

  double _volume = 100;
  double _lastVolume = 100;
  bool _fullscreen = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _tick;

  double? _dragValue;
  bool _episodesOpen = false;
  ScrubPreviewer? _previewer;
  int? _nextCountdown;
  Timer? _nextTimer;

  /// Painel "Próximo episódio": aparece quando faltam 2 min (episódios), fica
  /// aberto 13 s sem interação e vira uma aba com seta; ao terminar o episódio
  /// reabre com contagem de 8 s.
  _NextPanel _nextPanel = _NextPanel.hidden;
  Timer? _nextPanelTimer;
  bool _nextTabHover = false;

  /// Já marcado como assistido nesta reprodução (faltando 2 min no episódio,
  /// 10 min no filme).
  bool _autoWatched = false;

  @override
  void initState() {
    super.initState();
    _volume = widget.app.playback.volume;
    if (_volume > 0) _lastVolume = _volume;
    unawaited(_player.setVolume(_volume));

    _subs.addAll([
      _player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
        _poke();
      }),
      _player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }),
      _player.stream.position.listen(_onPosition),
      _player.stream.duration.listen(_onDuration),
      _player.stream.completed.listen(_onCompleted),
      _player.stream.error.listen((message) {
        if (message.isNotEmpty) _lastError = message;
      }),
      _player.stream.tracks.listen((t) {
        if (mounted) setState(() => _tracks = t);
      }),
      _player.stream.track.listen((t) {
        if (mounted) setState(() => _track = t);
      }),
    ]);

    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _watch());
    _poke();
    unawaited(_openCurrent(widget.startAt));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _nextTimer?.cancel();
    _nextPanelTimer?.cancel();
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _save(force: true);
    if (_fullscreen) unawaited(windowManager.setFullScreen(false));
    unawaited(_previewer?.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  // ---- reprodução ---------------------------------------------------------------

  Future<void> _openCurrent(Duration? startAt) async {
    _nextTimer?.cancel();
    _nextPanelTimer?.cancel();
    setState(() {
      _error = null;
      _lastError = null;
      _finished = false;
      _autoWatched = false;
      _nextPanel = _NextPanel.hidden;
      _nextCountdown = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffering = true;
      _lastSavedAt = Duration.zero;
      _lastProgress = DateTime.now();
      _pendingSeek = startAt != null && startAt > Duration.zero ? startAt : null;
    });
    // Prévia na barra de tempo só para arquivo local (streaming abriria uma
    // segunda conexão no provedor).
    unawaited(_previewer?.dispose());
    _previewer = _item.url.startsWith('http') ? null : ScrubPreviewer(_item.url);
    try {
      await _player.open(
        Media(_item.url, httpHeaders: widget.app.playbackHeaders),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onPosition(Duration p) {
    if (p != _position) _lastProgress = DateTime.now();
    if (_lastError != null && p > _position) {
      _lastError = null;
      if (_error != null && mounted) setState(() => _error = null);
    }
    if (!mounted) return;
    // Só reconstrói a tela a cada mudança visível (a cada ~0,25 s o player avisa).
    setState(() => _position = p);
    _checkEnding(p);
  }

  /// Perto do fim: marca como assistido (2 min para episódio, 10 min para
  /// filme; em vídeo curto, no máximo 25% do tempo) e, se houver próximo
  /// episódio, mostra o painel. A posição onde parou continua salva.
  void _checkEnding(Duration p) {
    final dur = _duration;
    if (dur <= Duration.zero || _finished) return;
    final limit = Duration(minutes: _item.kind == CatalogKind.movies ? 10 : 2);
    final quarter = dur * 0.25;
    final threshold = quarter < limit ? quarter : limit;
    if (dur - p > threshold) return;
    if (!_autoWatched) {
      _autoWatched = true;
      _save(force: true, watched: true);
    }
    if (_hasNext && _nextPanel == _NextPanel.hidden) {
      setState(() => _nextPanel = _NextPanel.expanded);
      _armNextPanelTimer();
    }
  }

  void _armNextPanelTimer() {
    _nextPanelTimer?.cancel();
    if (_nextPanel != _NextPanel.expanded || _nextCountdown != null) return;
    _nextPanelTimer = Timer(const Duration(seconds: 13), () {
      if (mounted && _nextCountdown == null && _nextPanel == _NextPanel.expanded) {
        setState(() => _nextPanel = _NextPanel.minimized);
      }
    });
  }

  void _onDuration(Duration d) {
    if (!mounted) return;
    setState(() => _duration = d);
    final seek = _pendingSeek;
    if (seek != null && d > Duration.zero) {
      _pendingSeek = null;
      // Se o ponto salvo está no fim, volta ao começo.
      final target = seek >= d - const Duration(seconds: 15) ? Duration.zero : seek;
      unawaited(_player.seek(target));
    }
  }

  void _onCompleted(bool done) {
    if (!done || _finished || !mounted) return;
    _finished = true;
    _autoWatched = true;
    _save(force: true, watched: true); // terminou: a posição volta ao início
    if (_hasNext) {
      _nextPanelTimer?.cancel();
      setState(() {
        _nextPanel = _NextPanel.expanded;
        _nextCountdown = 8;
      });
      _nextTimer?.cancel();
      _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        final left = (_nextCountdown ?? 0) - 1;
        if (left <= 0) {
          t.cancel();
          _goNext();
        } else if (mounted) {
          setState(() => _nextCountdown = left);
        }
      });
    } else {
      _close();
    }
  }

  /// Se o player reportou erro e a posição não anda há um tempo, mostra o erro.
  void _watch() {
    if (!mounted || _error != null || _finished) return;
    final stalled = DateTime.now().difference(_lastProgress);
    if (_lastError != null && stalled > const Duration(seconds: 12)) {
      setState(() => _error = _lastError);
    } else if (_duration == Duration.zero && stalled > const Duration(seconds: 40)) {
      setState(() => _error = _lastError ?? 'O servidor não enviou o vídeo.');
    }
  }

  Future<void> _goNext() async {
    if (!_hasNext) return;
    _save(force: true, watched: true);
    setState(() => _index++);
    await _openCurrent(null);
  }

  /// Troca para outro item da fila (painel de episódios), retomando de onde parou.
  Future<void> _jumpTo(int i) async {
    if (i == _index || i < 0 || i >= widget.items.length) return;
    _save(force: true);
    setState(() => _index = i);
    final p = await widget.app.catalog.progressOf(_item);
    await _openCurrent(
      (p != null && p.canResume) ? Duration(milliseconds: p.positionMs) : null,
    );
  }

  Future<void> _retry() async {
    final at = _position;
    await _openCurrent(at);
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  /// Salva a posição. [watched] força "assistido"; sem ele, vale a regra de 92%.
  void _save({bool force = false, bool? watched}) {
    final dur = _duration;
    if (dur <= Duration.zero) return;
    final pos = _position;
    if (!force && (pos - _lastSavedAt).abs() < const Duration(seconds: 5)) return;
    _lastSavedAt = pos;
    final done = watched ?? _autoWatched;
    // Só reinicia o tempo se assistiu até o fim; senão guarda onde parou.
    final posMs = _finished ? 0 : pos.inMilliseconds;
    unawaited(
      widget.app.catalog.saveProgress(
        _item,
        positionMs: posMs,
        durationMs: dur.inMilliseconds,
        watched: done,
      ),
    );
  }

  // ---- controles ------------------------------------------------------------------

  /// Carrega uma legenda de um arquivo do computador (.srt, .ass, .ssa, .vtt,
  /// .sub) e já a ativa. Ela fica só nesta reprodução.
  Future<void> _loadSubtitleFile() async {
    final path = await SystemDialogs.pickFile(
      title: 'Escolha o arquivo de legenda',
      filter: 'Legendas|*.srt;*.ass;*.ssa;*.vtt;*.sub|Todos os arquivos|*.*',
    );
    if (path == null || path.isEmpty || !mounted) return;
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: p.basename(path)),
      );
      AppLog.info('legenda', 'Legenda externa carregada: ${p.basename(path)}');
    } catch (e, st) {
      AppLog.error('legenda', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui carregar essa legenda.')),
      );
    }
    _poke();
  }

  void _poke() {
    // Mexer o mouse conta como interação: o painel "Próximo episódio" aberto
    // espera mais 13 s antes de minimizar.
    if (_nextPanel == _NextPanel.expanded) _armNextPanelTimer();
    _hideTimer?.cancel();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_episodesOpen) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _seekBy(Duration delta) async {
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await _player.seek(target);
    _poke();
  }

  Future<void> _setVolume(double v) async {
    final value = v.clamp(0.0, 100.0).toDouble();
    setState(() => _volume = value);
    if (value > 0) _lastVolume = value;
    await _player.setVolume(value);
    await widget.app.playback.setVolume(value);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullscreen = next);
    _poke();
  }

  Future<void> _escape() async {
    if (_episodesOpen) {
      setState(() => _episodesOpen = false);
    } else if (_fullscreen) {
      await _toggleFullscreen();
    } else {
      _close();
    }
  }

  IconData get _volumeIcon {
    if (_volume <= 0) return Icons.volume_off;
    if (_volume < 50) return Icons.volume_down;
    return Icons.volume_up;
  }

  String _trackLabel(String id, String? title, String? language, int n) {
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? 'Faixa $n' : parts.join(' · ');
  }

  // ---- interface --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final video = Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _video,
          controls: (state) => const SizedBox.shrink(),
          fill: Colors.black,
        ),
        // Clique simples: pausa/continua. Duplo clique: tela cheia.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _player.playOrPause();
              _poke();
            },
            onDoubleTap: _toggleFullscreen,
          ),
        ),
        if (_buffering && _error == null)
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ),
        _TopBar(
          visible: _controlsVisible,
          title: _item.title,
          subtitle: _item.subtitle,
          onBack: _close,
        ),
        _BottomBar(
          visible: _controlsVisible,
          child: _buildControls(),
        ),
        if (widget.items.length > 1)
          Positioned(
            right: 16,
            top: 72,
            bottom: 112,
            child: AnimatedSlide(
              offset: _episodesOpen ? Offset.zero : const Offset(1.1, 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _episodesOpen ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_episodesOpen,
                  child: PlayerEpisodesPanel(
                    key: ValueKey('eps-$_index-$_episodesOpen'),
                    items: widget.items,
                    current: _index,
                    onSelect: _jumpTo,
                    onClose: () => setState(() => _episodesOpen = false),
                  ),
                ),
              ),
            ),
          ),
        if (_nextPanel != _NextPanel.hidden && _hasNext) _buildNextCard(),
        if (_error != null) _buildError(),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.space): () {
          _player.playOrPause();
          _poke();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekBy(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekBy(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _setVolume(_volume + 5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _setVolume(_volume - 5),
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM): () =>
            _setVolume(_volume > 0 ? 0 : _lastVolume),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            cursor: _controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _poke(),
            child: Column(
              children: [
                if (!_fullscreen) const TitleBar(),
                Expanded(child: video),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final durMs = _duration.inMilliseconds;
    final maxMs = durMs <= 0 ? 1.0 : durMs.toDouble();
    final posMs = _position.inMilliseconds.clamp(0, durMs <= 0 ? 1 : durMs);
    final value = (_dragValue ?? posMs.toDouble()).clamp(0.0, maxMs).toDouble();

    final audio = [
      for (final t in _tracks.audio)
        if (t.id != 'auto' && t.id != 'no') t,
    ];
    final subs = [
      for (final t in _tracks.subtitle)
        if (t.id != 'auto' && t.id != 'no') t,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              formatDuration(Duration(milliseconds: value.round())),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Expanded(
              child: ScrubBar(
                value: value,
                max: maxMs,
                enabled: durMs > 0,
                previewer: _previewer,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) async {
                  setState(() => _dragValue = null);
                  await _player.seek(Duration(milliseconds: v.round()));
                },
              ),
            ),
            Text(
              formatDuration(_duration),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        Row(
          children: [
            _iconBtn(
              _playing ? Icons.pause : Icons.play_arrow,
              _playing ? 'Pausar' : 'Continuar',
              () {
                _player.playOrPause();
                _poke();
              },
              size: 28,
            ),
            _iconBtn(Icons.replay_10, 'Voltar 10 s',
                () => _seekBy(const Duration(seconds: -10))),
            _iconBtn(Icons.forward_10, 'Avançar 10 s',
                () => _seekBy(const Duration(seconds: 10))),
            if (_hasNext)
              _iconBtn(Icons.skip_next, 'Próximo episódio', _goNext),
            if (widget.items.length > 1)
              _iconBtn(
                Icons.view_list_rounded,
                'Episódios',
                () {
                  setState(() => _episodesOpen = !_episodesOpen);
                  _poke();
                },
              ),
            const SizedBox(width: 8),
            _iconBtn(
              _volumeIcon,
              _volume > 0 ? 'Silenciar' : 'Ativar som',
              () => _setVolume(_volume > 0 ? 0 : _lastVolume),
            ),
            SizedBox(
              width: 100,
              height: 36,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  onChanged: _setVolume,
                  onChangeEnd: (v) => widget.app.saveVolume(v),
                ),
              ),
            ),
            const Spacer(),
            PopupMenuButton<Object>(
              tooltip: 'Áudio e legendas',
              icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
              color: AppColors.surface,
              onSelected: (choice) {
                if (choice == 'load-subtitle') {
                  unawaited(_loadSubtitleFile());
                  return;
                }
                if (choice is AudioTrack) _player.setAudioTrack(choice);
                if (choice is SubtitleTrack) _player.setSubtitleTrack(choice);
                _poke();
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<Object>>[
                  PopupMenuItem<Object>(
                    enabled: false,
                    height: 32,
                    child: Text(
                      'Áudio',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ];
                if (audio.isEmpty) {
                  items.add(const PopupMenuItem<Object>(
                    enabled: false,
                    height: 32,
                    child: Text('Nenhuma faixa informada'),
                  ));
                }
                for (var i = 0; i < audio.length; i++) {
                  final t = audio[i];
                  items.add(PopupMenuItem<Object>(
                    value: t,
                    height: 36,
                    child: _menuRow(
                      _trackLabel(t.id, t.title, t.language, i + 1),
                      _track.audio.id == t.id,
                    ),
                  ));
                }
                items.add(const PopupMenuDivider());
                items.add(PopupMenuItem<Object>(
                  enabled: false,
                  height: 32,
                  child: Text(
                    'Legenda',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ));
                items.add(PopupMenuItem<Object>(
                  value: SubtitleTrack.no(),
                  height: 36,
                  child: _menuRow('Desativada', _track.subtitle.id == 'no'),
                ));
                for (var i = 0; i < subs.length; i++) {
                  final t = subs[i];
                  items.add(PopupMenuItem<Object>(
                    value: t,
                    height: 36,
                    child: _menuRow(
                      _trackLabel(t.id, t.title, t.language, i + 1),
                      _track.subtitle.id == t.id,
                    ),
                  ));
                }
                items.add(const PopupMenuDivider());
                items.add(const PopupMenuItem<Object>(
                  value: 'load-subtitle',
                  height: 36,
                  child: Row(
                    children: [
                      SizedBox(width: 20, child: Icon(Icons.folder_open, size: 16)),
                      Flexible(child: Text('Carregar legenda de um arquivo…')),
                    ],
                  ),
                ));
                return items;
              },
            ),
            _iconBtn(
              _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              _fullscreen ? 'Sair da tela cheia' : 'Tela cheia',
              _toggleFullscreen,
              size: 26,
            ),
          ],
        ),
      ],
    );
  }

  Widget _menuRow(String label, bool selected) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: selected
              ? Icon(Icons.check, size: 16, color: AppColors.accent)
              : null,
        ),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    double size = 24,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: size),
    );
  }

  Widget _buildNextCard() {
    final next = widget.items[_index + 1];
    final counting = _nextCountdown != null;

    if (_nextPanel == _NextPanel.minimized && !counting) {
      // Aba com seta; com o mouse em cima ganha o texto e continua com o ícone.
      // Fica no canto inferior direito durante o resto do episódio; quando a
      // interface aparece, sobe para não ficar por cima dos controles.
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        right: 0,
        bottom: _controlsVisible ? 110 : 28,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _nextTabHover = true),
          onExit: (_) => setState(() => _nextTabHover = false),
          child: GestureDetector(
            onTap: _goNext,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xE6181817),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                border: Border.fromBorderSide(BorderSide(color: Colors.white24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_nextTabHover) ...[
                    const Text(
                      'Próximo episódio',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: 24,
      bottom: 96,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xE6181817),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    counting
                        ? 'Próximo episódio em ${_nextCountdown}s'
                        : 'Próximo episódio',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (!counting)
                  InkWell(
                    onTap: () {
                      _nextPanelTimer?.cancel();
                      setState(() => _nextPanel = _NextPanel.minimized);
                    },
                    child: const Tooltip(
                      message: 'Minimizar',
                      child: Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              next.subtitle ?? next.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: _goNext,
                  child: const Text('Assistir agora'),
                ),
                if (counting) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _nextTimer?.cancel();
                      setState(() {
                        _nextCountdown = null;
                        _nextPanel = _NextPanel.minimized;
                      });
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Cancelar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xE6000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white70, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Não foi possível reproduzir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Tentar de novo'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      child: const Text('Voltar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final bool visible;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    // min: sem isso a coluna ocupava a tela toda e o botão
                    // voltar ficava centralizado na vertical.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.title(24, color: Colors.white, spacing: 1),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x99000000), Color(0xE6000000)],
                stops: [0, 0.55, 1],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
