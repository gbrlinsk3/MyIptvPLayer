import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';
import '../data/epg_parsing.dart';
import '../data/models.dart';
import '../data/xtream_client.dart';

class _Found {
  const _Found(this.programs, this.label);

  final List<EpgProgram> programs;
  final String label;
}

class _Resolved {
  const _Resolved(this.found, this.error);

  final _Found? found;
  final String? error;
}

/// Guia de programação (EPG).
///
/// Fontes, na ordem padrão: (1) EPG do provedor Xtream, buscado por canal
/// quando o canal é selecionado e guardado em cache por 1 hora; (2) fontes
/// XMLTV por URL adicionadas pelo usuário, que só preenchem os canais em
/// falta. Com [preferUser] ligado, a ordem se inverte.
///
/// A ligação canal <-> fonte XMLTV usa o código de EPG que o provedor informa
/// para o canal (sem tentar adivinhar por nome).
class EpgController extends ChangeNotifier {
  EpgController(this._db);

  final AppDatabase _db;

  static const _providerSource = 'provider';
  static const _providerFreshSeconds = 3600;
  static const _pastSeconds = 3 * 3600;
  static const _futureSeconds = 5 * 24 * 3600;
  static const _staleSourceAge = Duration(hours: 12);

  // ---- ajustes -----------------------------------------------------------

  bool preferUser = false;
  bool collapsed = false;
  List<EpgSource> sources = const [];
  bool refreshing = false;

  // ---- visão do canal atual ---------------------------------------------

  LiveChannel? viewChannel;
  List<EpgProgram> programs = const [];
  String? sourceLabel;
  bool loadingView = false;
  String? viewError;

  SavedAccount? _viewAccount;
  int _viewToken = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  int _nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<void> load() async {
    preferUser = await _db.getSetting('epg_prefer_user') == '1';
    collapsed = await _db.getSetting('epg_collapsed') == '1';
    sources = await _db.loadEpgSources();
    unawaited(_db.pruneEpg(_nowEpoch() - 6 * 3600));
  }

  Future<void> setPreferUser(bool value) async {
    preferUser = value;
    _notify();
    await _db.setSetting('epg_prefer_user', value ? '1' : '0');
    unawaited(_loadView());
  }

  Future<void> setCollapsed(bool value) async {
    collapsed = value;
    _notify();
    await _db.setSetting('epg_collapsed', value ? '1' : '0');
  }

  // ---- visão do canal ----------------------------------------------------

  /// Mostra a programação do [channel] (ou limpa, se for null).
  Future<void> showChannel(LiveChannel? channel, SavedAccount? account) {
    viewChannel = channel;
    _viewAccount = account;
    return _loadView();
  }

  Future<void> _loadView() async {
    final channel = viewChannel;
    final account = _viewAccount;
    final token = ++_viewToken;
    programs = const [];
    sourceLabel = null;
    viewError = null;
    if (channel == null || account == null) {
      loadingView = false;
      _notify();
      return;
    }
    loadingView = true;
    _notify();

    _Resolved? result;
    String? failure;
    try {
      result = await _resolve(channel, account);
    } catch (e) {
      failure = 'Falha ao carregar a programação: $e';
    }
    if (token != _viewToken || _disposed) return; // outro canal foi aberto
    programs = result?.found?.programs ?? const [];
    sourceLabel = result?.found?.label;
    viewError = result?.found == null ? (failure ?? result?.error) : null;
    loadingView = false;
    _notify();
  }

  bool _hasUpcoming(List<EpgProgram> rows, int now) =>
      rows.any((p) => p.stop > now);

  Future<_Resolved> _resolve(LiveChannel channel, SavedAccount account) async {
    String? providerError;

    Future<_Found?> fromProvider() async {
      final key = '${channel.streamId}';
      final now = _nowEpoch();
      var rows = await _db.epgPrograms(
        _providerSource,
        key,
        fromEpoch: now - _pastSeconds,
      );
      final fetchedAt = await _db.epgFetchedAt(_providerSource, key);
      final fresh = fetchedAt != null && now - fetchedAt < _providerFreshSeconds;
      if (!fresh) {
        XtreamClient? client;
        try {
          client = XtreamClient(
            server: account.server,
            username: account.username,
            password: account.password,
          );
          final fetched = await client.fetchChannelEpg(channel.streamId);
          await _db.replaceChannelPrograms(_providerSource, key, fetched, now);
          rows = await _db.epgPrograms(
            _providerSource,
            key,
            fromEpoch: now - _pastSeconds,
          );
        } on XtreamException catch (e) {
          providerError = e.message;
        } catch (e) {
          providerError = 'Falha ao buscar a programação: $e';
        } finally {
          client?.close();
        }
      }
      return _hasUpcoming(rows, now) ? _Found(rows, 'Provedor') : null;
    }

    Future<_Found?> fromUserSources() async {
      final key = channel.epgKey;
      if (key == null) return null;
      final now = _nowEpoch();
      for (final source in sources) {
        final rows = await _db.epgPrograms(
          'url:${source.id}',
          key,
          fromEpoch: now - _pastSeconds,
        );
        if (_hasUpcoming(rows, now)) return _Found(rows, source.label);
      }
      return null;
    }

    final order = preferUser
        ? [fromUserSources, fromProvider]
        : [fromProvider, fromUserSources];
    for (final step in order) {
      final found = await step();
      if (found != null) return _Resolved(found, null);
    }
    return _Resolved(null, providerError);
  }

  // ---- fontes por URL ----------------------------------------------------

  /// Devolve null se deu certo, ou a mensagem de erro de validação.
  Future<String?> addSource(String rawUrl, Set<String> wanted) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Informe um endereço http:// ou https:// válido.';
    }
    if (sources.any((s) => s.url == url)) {
      return 'Esta fonte já foi adicionada.';
    }
    await _db.insertEpgSource(url);
    sources = await _db.loadEpgSources();
    _notify();
    final added = sources.firstWhere((s) => s.url == url);
    await refreshSources([added], wanted);
    return null;
  }

  Future<void> removeSource(EpgSource source) async {
    await _db.deleteEpgSource(source.id);
    sources = await _db.loadEpgSources();
    _notify();
    unawaited(_loadView());
  }

  Future<void> refreshAll(Set<String> wanted) =>
      refreshSources(List.of(sources), wanted);

  /// Atualiza só as fontes nunca atualizadas ou com mais de 12 h.
  Future<void> refreshStale(Set<String> wanted) async {
    final now = DateTime.now();
    final stale = [
      for (final s in sources)
        if (s.updatedAt == null || now.difference(s.updatedAt!) > _staleSourceAge)
          s,
    ];
    if (stale.isEmpty) return;
    await refreshSources(stale, wanted);
  }

  Future<void> refreshSources(List<EpgSource> list, Set<String> wanted) async {
    if (refreshing || list.isEmpty) return;
    refreshing = true;
    _notify();
    try {
      for (final source in list) {
        await _refreshOne(source, wanted);
      }
      sources = await _db.loadEpgSources();
    } finally {
      refreshing = false;
      _notify();
    }
    unawaited(_loadView());
  }

  Future<void> _refreshOne(EpgSource source, Set<String> wanted) async {
    if (wanted.isEmpty) {
      await _db.updateEpgSourceStatus(source.id, {
        'error': 'Carregue o catálogo de canais antes de atualizar o EPG.',
      });
      return;
    }
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse(source.url))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw _SourceError('A fonte respondeu com erro HTTP ${response.statusCode}.');
      }
      final now = _nowEpoch();
      final rows = await compute(
        parseXmltv,
        XmltvJob(
          bytes: response.bodyBytes,
          wanted: wanted,
          fromEpoch: now - _pastSeconds,
          toEpoch: now + _futureSeconds,
        ),
      );
      await _db.replaceSourcePrograms('url:${source.id}', rows);
      await _db.updateEpgSourceStatus(source.id, {
        'updated_at': now,
        'program_count': rows.length,
        'error': rows.isEmpty
            ? 'Nenhum programa encontrado para os canais do seu catálogo. '
                'Os códigos de EPG da fonte podem não corresponder aos do provedor.'
            : null,
      });
    } on _SourceError catch (e) {
      await _db.updateEpgSourceStatus(source.id, {'error': e.message});
    } on TimeoutException {
      await _db.updateEpgSourceStatus(source.id, {
        'error': 'A fonte demorou demais para responder.',
      });
    } on SocketException {
      await _db.updateEpgSourceStatus(source.id, {
        'error': 'Não foi possível conectar à fonte.',
      });
    } on http.ClientException catch (e) {
      await _db.updateEpgSourceStatus(source.id, {
        'error': 'Falha de conexão com a fonte. (${e.message})',
      });
    } catch (e) {
      await _db.updateEpgSourceStatus(source.id, {
        'error': 'Não foi possível ler a fonte: $e',
      });
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _SourceError implements Exception {
  _SourceError(this.message);

  final String message;
}
