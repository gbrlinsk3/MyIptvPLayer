import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';

/// Programação do provedor guardada para um canal e se ainda está na validade.
typedef ProviderEpgCache = ({List<EpgProgram> rows, bool fresh});

/// O que está no ar nos canais de um cartão (as versões do mesmo canal).
class NowEntry extends ChangeNotifier {
  NowEntry._(this._versions);

  List<LiveChannel> _versions;
  SavedAccount? _account;
  List<EpgProgram> _user = const [];
  List<EpgProgram> _provider = const [];

  /// Programa no ar, ou null quando nenhuma fonte tem.
  EpgProgram? program;

  int _watchers = 0;
  int _loadedAt = 0; // segundos; 0 = precisa ler de novo
  bool _loading = false;
  Timer? _settle;

  void _changed() => notifyListeners();

  /// Canal usado no guia do provedor: a primeira versão com código de EPG (sem
  /// o código, não se pede nada ao provedor).
  LiveChannel? get _providerChannel {
    for (final v in _versions) {
      if (v.epgKey != null) return v;
    }
    return null;
  }
}

/// Programa no ar para os cartões de canal. Junta o guia do provedor e as
/// fontes do usuário, na ordem escolhida em "Preferir minhas fontes".
///
/// O que está salvo no computador aparece na hora. Ao provedor, o pedido é de
/// um canal por vez, só para cartões que continuam na tela por [settle], com no
/// máximo [maxParallel] pedidos ao mesmo tempo. Depois de [maxFailures] falhas
/// seguidas, para de pedir durante [pause].
class NowPlaying {
  NowPlaying({
    required this.userPrograms,
    required this.cached,
    required this.fetch,
    required this.preferUser,
    this.settle = const Duration(milliseconds: 700),
    this.tick = const Duration(seconds: 30),
    this.pause = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int maxParallel = 2;
  static const int maxFailures = 3;

  /// De quanto em quanto tempo as fontes são lidas de novo (segundos).
  static const int _reloadSeconds = 3600;

  final Future<List<EpgProgram>> Function(List<LiveChannel> versions)
      userPrograms;
  final Future<ProviderEpgCache> Function(LiveChannel channel) cached;
  final Future<List<EpgProgram>> Function(
    LiveChannel channel,
    SavedAccount account,
  ) fetch;
  final bool Function() preferUser;
  final Duration settle;
  final Duration tick;
  final Duration pause;
  final DateTime Function() _clock;

  final Map<int, NowEntry> _entries = {};
  final List<NowEntry> _queue = [];
  Timer? _ticker;
  DateTime? _pausedUntil;
  int _running = 0;
  int _failures = 0;
  int _generation = 0;
  bool _disposed = false;

  int _now() => _clock().millisecondsSinceEpoch ~/ 1000;

  /// Um cartão entrou na tela. Chame [release] quando ele sair.
  NowEntry watch(List<LiveChannel> versions, SavedAccount? account) {
    final entry = _entries.putIfAbsent(
      versions.first.streamId,
      () => NowEntry._(versions),
    );
    entry
      .._versions = versions
      .._account = account
      .._watchers += 1;
    _ticker ??= Timer.periodic(tick, (_) => _onTick());
    if (_stale(entry)) {
      unawaited(_load(entry));
    } else {
      entry.program = _pick(entry);
    }
    return entry;
  }

  void release(NowEntry entry) {
    if (entry._watchers > 0) entry._watchers--;
    if (entry._watchers > 0) return;
    // Saiu da tela antes do pedido ao provedor: tenta de novo quando voltar.
    final waiting = (entry._settle?.isActive ?? false) || _queue.remove(entry);
    entry._settle?.cancel();
    entry._settle = null;
    if (waiting) entry._loadedAt = 0;
    if (_entries.values.every((e) => e._watchers == 0)) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// As fontes mudaram (adicionada, removida, atualizada ou a ordem).
  void invalidate() {
    if (_disposed) return;
    _generation++;
    _queue.clear();
    _failures = 0;
    _pausedUntil = null;
    for (final e in _entries.values) {
      e._settle?.cancel();
      e._loadedAt = 0;
      e._loading = false;
      if (e._watchers > 0) unawaited(_load(e));
    }
  }

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _queue.clear();
    for (final e in _entries.values) {
      e._settle?.cancel();
    }
  }

  bool _stale(NowEntry e) =>
      e._loadedAt == 0 || _now() - e._loadedAt >= _reloadSeconds;

  void _onTick() {
    for (final e in _entries.values.toList()) {
      if (e._watchers == 0) continue;
      if (_stale(e)) {
        unawaited(_load(e));
      } else {
        _update(e);
      }
    }
  }

  Future<void> _load(NowEntry entry) async {
    if (entry._loading || _disposed) return;
    entry._loading = true;
    final generation = _generation;
    final channel = entry._providerChannel;
    var user = const <EpgProgram>[];
    ProviderEpgCache saved = (rows: const <EpgProgram>[], fresh: true);
    try {
      user = await userPrograms(entry._versions);
      if (channel != null) saved = await cached(channel);
    } catch (_) {
      // Sem leitura do banco: o cartão fica sem programa até a próxima volta.
    }
    if (_disposed || generation != _generation) return;
    entry
      .._loading = false
      .._user = user
      .._provider = saved.rows
      .._loadedAt = _now();
    _update(entry);

    final userIsEnough = preferUser() && _current(user) != null;
    if (channel == null || saved.fresh || userIsEnough) return;
    if (entry._account == null || entry._watchers == 0) {
      entry._loadedAt = 0;
      return;
    }
    entry._settle?.cancel();
    entry._settle = Timer(settle, () {
      _queue
        ..remove(entry)
        ..add(entry);
      _pump();
    });
  }

  void _pump() {
    while (!_disposed && _running < maxParallel && _queue.isNotEmpty) {
      final until = _pausedUntil;
      if (until != null && _clock().isBefore(until)) {
        for (final e in _queue) {
          e._loadedAt = 0;
        }
        _queue.clear();
        return;
      }
      // O último a entrar é o que acabou de aparecer na tela.
      unawaited(_request(_queue.removeLast()));
    }
  }

  Future<void> _request(NowEntry entry) async {
    final channel = entry._providerChannel;
    final account = entry._account;
    if (channel == null || account == null) return;
    final generation = _generation;
    _running++;
    try {
      final rows = await fetch(channel, account);
      _failures = 0;
      if (!_disposed && generation == _generation) {
        entry._provider = rows;
        _update(entry);
      }
    } catch (_) {
      if (++_failures >= maxFailures) {
        _failures = 0;
        _pausedUntil = _clock().add(pause);
      }
    } finally {
      _running--;
      _pump();
    }
  }

  EpgProgram? _current(List<EpgProgram> rows) {
    final now = _now();
    for (final p in rows) {
      if (p.start <= now && now < p.stop) return p;
    }
    return null;
  }

  EpgProgram? _pick(NowEntry e) => preferUser()
      ? _current(e._user) ?? _current(e._provider)
      : _current(e._provider) ?? _current(e._user);

  void _update(NowEntry e) {
    final before = e.program;
    e.program = _pick(e);
    // Com programa no ar, avisa mesmo sem troca: a barra de progresso anda.
    if (e._watchers > 0 && (e.program != null || before != null)) {
      e._changed();
    }
  }
}
