import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ui/widgets/app_backdrop.dart' show BackdropBlur;
import '../catalog/catalog_controller.dart';
import '../core/format.dart' show formatDateTime;
import '../data/db.dart';
import '../data/live_highlight.dart';
import '../data/models.dart';
import '../data/carryover_store.dart';
import '../data/catalog_models.dart' show CatalogKind, CatalogTitle, Episode;
import '../data/xtream_client.dart';
import '../downloads/downloads_controller.dart';
import '../library/library_import.dart';
import '../epg/epg_controller.dart';
import '../playback/playback_controller.dart';
import '../core/app_log.dart';
import '../core/layout_metrics.dart';
import '../core/theme.dart'
    show AccentScale, AppColors, AppShape, ThemePref;

enum AppPhase { booting, loggedOut, ready }

/// Estado único do app (conta, catálogo, busca, canal selecionado, ajustes).
class AppController extends ChangeNotifier {
  AppController(this._db, this.playback, this.epg);

  final AppDatabase _db;

  /// Dono do player; vive no nível do app para sobreviver à troca de telas.
  final PlaybackController playback;

  /// Guia de programação.
  final EpgController epg;

  /// Filmes, séries e progresso de reprodução do perfil.
  /// As mudanças do catálogo também avisam quem escuta o AppController.
  late final CatalogController catalog =
      CatalogController(_db, accountOf: () => account)
        ..addListener(notifyListeners)
        ..onCarryoverChanged = () => unawaited(reloadCarryover());

  AppPhase phase = AppPhase.booting;
  SavedAccount? account;
  AccountInfo? info;

  // Catálogo completo (inclui categorias ocultas) e o recorte visível.
  List<LiveCategory> _allCategories = const [];
  List<LiveChannel> _catalog = const [];
  List<LiveChannel> _all = const [];
  Set<String> _hiddenLive = <String>{};

  /// Categorias visíveis que têm ao menos um canal.
  List<LiveCategory> categories = const [];

  /// Todas as categorias com ao menos um canal (visíveis ou não), para o gerenciador.
  List<LiveCategory> manageableCategories = const [];

  /// Contagem de canais por categoria, só dos visíveis.
  Map<String, int> countByCategory = const {};

  /// Contagem de canais por categoria, considerando também as ocultas.
  Map<String, int> rawCountByCategory = const {};

  /// Resultado atual da busca/filtro.
  List<LiveChannel> visible = const [];

  String? selectedCategoryId;
  String query = '';
  LiveChannel? selected;

  /// Muda quando o usuário pede para reabrir o canal atual (tentar de novo).
  int playbackNonce = 0;

  bool syncing = false;
  String? syncError;
  DateTime? catalogUpdatedAt;

  /// Extensão usada na URL do stream: 'ts' ou 'm3u8'.
  String streamExt = 'ts';

  /// O que acontece ao tocar num título baixado em Minha biblioteca:
  /// 'panel' (padrão, card lateral), 'player' ou 'expanded' (card expandido).
  String libraryOpenMode = 'panel';

  /// Dicas que já foram mostradas uma vez (ex.: `live`, `movies`, `series`).
  final Set<String> _hintsSeen = {};
  bool hintPending(String key) => !_hintsSeen.contains(key);

  void markHintSeen(String key) {
    if (!_hintsSeen.add(key)) return;
    _db.setSetting('hints_seen', _hintsSeen.join(','));
  }

  Future<void> setLibraryOpenMode(String mode) async {
    libraryOpenMode = mode;
    await _db.setSetting('library_open_mode', mode);
    notifyListeners();
  }
  String userAgent = '';

  /// Palavras-chave dos banners de destaque da TV ao vivo (ordem importa).
  List<String> highlightKeywords = defaultHighlightKeywords;
  List<LiveHighlight> _highlights = const [];
  List<LiveChannel>? _hlForAll;
  List<LiveCategory>? _hlForCategories;
  List<String>? _hlForKeywords;

  /// Destaques calculados (com cache: só refaz se canais, categorias ou
  /// palavras-chave mudarem).
  List<LiveHighlight> get highlights {
    if (!identical(_hlForAll, _all) ||
        !identical(_hlForCategories, categories) ||
        !identical(_hlForKeywords, highlightKeywords)) {
      _hlForAll = _all;
      _hlForCategories = categories;
      _hlForKeywords = highlightKeywords;
      _highlights = computeHighlights(
        keywords: highlightKeywords,
        categories: categories,
        channels: _all,
      );
    }
    return _highlights;
  }

  /// Mini banners: [miniSlides] abas x [miniSlotsPerSlide] espaços (tokens em
  /// `live_highlight.dart`). Salvo no perfil como JSON (`live_mini_banners`).
  List<List<String>> miniBanners = defaultMiniBanners();

  List<LiveChannel>? _byCatFor;
  Map<String, List<LiveChannel>> _byCat = const {};

  MiniBanner? miniBannerFor(String token) {
    if (token.isEmpty) return null;
    if (!identical(_byCatFor, _all)) {
      _byCatFor = _all;
      final m = <String, List<LiveChannel>>{};
      for (final ch in _all) {
        (m[ch.categoryId] ??= []).add(ch);
      }
      _byCat = m;
    }
    return resolveMiniBanner(token, categories: categories, channelsByCategory: _byCat);
  }

  Future<void> setMiniBanner(int slide, int slot, String token) async {
    if (slide < 0 || slide >= miniBanners.length) return;
    if (slot < 0 || slot >= miniBanners[slide].length) return;
    miniBanners = [
      for (var i = 0; i < miniBanners.length; i++)
        [
          for (var j = 0; j < miniBanners[i].length; j++)
            (i == slide && j == slot) ? token : miniBanners[i][j],
        ],
    ];
    notifyListeners();
    await _db.setSetting('live_mini_banners', jsonEncode(miniBanners));
  }

  List<List<String>> _loadMiniBanners(String? raw) {
    final out = defaultMiniBanners();
    if (raw == null) return out;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return out;
      for (var i = 0; i < miniSlides && i < data.length; i++) {
        final row = data[i];
        if (row is! List) continue;
        for (var j = 0; j < miniSlotsPerSlide; j++) {
          out[i][j] = j < row.length && row[j] is String ? row[j] as String : '';
        }
      }
    } catch (e) {
      AppLog.warn('tv.miniBanners', e);
    }
    return out;
  }

  Future<void> setHighlightKeywords(List<String> words) async {
    final clean = [
      for (final w in words)
        if (w.trim().isNotEmpty) w.trim(),
    ];
    highlightKeywords = clean;
    notifyListeners();
    await _db.setSetting('live_highlight_keywords', clean.join(','));
  }

  /// Canais favoritos (stream_id), salvos no perfil. O conjunto é recriado a
  /// cada mudança, então a interface compara por identidade para saber se mudou.
  Set<int> favoriteChannels = <int>{};

  static const int maxRecentChannels = 20;

  /// Últimos canais assistidos (stream_id), do mais recente para o mais
  /// antigo, no máximo [maxRecentChannels]. Salvo em `recent_live_channels`.
  /// A lista é recriada a cada mudança (comparar por identidade).
  List<int> recentChannels = const [];

  Future<void> noteRecentChannel(LiveChannel ch) async {
    final next = <int>[
      ch.streamId,
      for (final id in recentChannels)
        if (id != ch.streamId) id,
    ];
    if (next.length > maxRecentChannels) {
      next.removeRange(maxRecentChannels, next.length);
    }
    recentChannels = List.unmodifiable(next);
    notifyListeners();
    await _db.setSetting('recent_live_channels', next.join(','));
  }

  /// Tira um canal da lista de recentes (o X do cartão). Persiste e notifica.
  Future<void> removeRecentChannel(int streamId) async {
    final next = <int>[
      for (final id in recentChannels)
        if (id != streamId) id,
    ];
    recentChannels = List.unmodifiable(next);
    notifyListeners();
    await _db.setSetting('recent_live_channels', next.join(','));
  }

  /// Última versão escolhida em cada canal agrupado: {chave do grupo: stream_id}.
  /// Salvo em `live_preferred_versions` (JSON).
  Map<String, int> preferredVersions = const {};

  int? preferredVersionFor(String key) => preferredVersions[key];

  Future<void> setPreferredVersion(String key, int streamId) async {
    if (preferredVersions[key] == streamId) return;
    preferredVersions = Map.unmodifiable({...preferredVersions, key: streamId});
    notifyListeners();
    await _db.setSetting('live_preferred_versions', jsonEncode(preferredVersions));
  }

  static List<int> _parseIdList(String? raw) => List.unmodifiable([
        for (final part in (raw ?? '').split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ]);

  static Map<String, int> _parsePreferredVersions(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const {};
      return Map.unmodifiable({
        for (final e in data.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
      });
    } catch (e) {
      AppLog.warn('tv.versoes', e);
      return const {};
    }
  }

  List<LiveChannel>? _byIdFor;
  Map<int, LiveChannel> _byId = const {};

  /// Canal pelo stream_id, em todo o catálogo carregado (inclusive categorias
  /// ocultas). O mapa só é refeito quando a lista de canais muda.
  LiveChannel? liveChannelById(int id) {
    if (!identical(_byIdFor, _catalog)) {
      _byIdFor = _catalog;
      _byId = {for (final ch in _catalog) ch.streamId: ch};
    }
    return _byId[id];
  }

  /// Fila (lista de onde o canal veio) do último pedido de reprodução, usada
  /// pelos botões "canal anterior/próximo".
  List<LiveChannel> liveQueue = const [];
  bool _pendingLive = false;

  /// Pede para tocar [ch] na aba TV ao vivo: seleciona o canal, guarda a fila
  /// e troca para a aba. A página da TV consome o pedido com [takeLiveRequest].
  void requestLive(LiveChannel ch, List<LiveChannel> queue) {
    selected = ch;
    liveQueue = List.unmodifiable(queue);
    _pendingLive = true;
    shellIndex = 1;
    notifyListeners();
  }

  CatalogKind? _pendingCatalog;

  /// Abre "Filmes e séries" na aba [kind]. A página consome o pedido com
  /// [takeCatalogRequest].
  void requestCatalog(CatalogKind kind) {
    _pendingCatalog = kind;
    shellIndex = 2;
    notifyListeners();
  }

  /// A aba pedida por [requestCatalog], uma única vez.
  CatalogKind? takeCatalogRequest() {
    final kind = _pendingCatalog;
    _pendingCatalog = null;
    return kind;
  }

  /// true uma única vez por pedido de [requestLive].
  bool takeLiveRequest() {
    final pending = _pendingLive;
    _pendingLive = false;
    return pending;
  }

  /// Downloads do perfil (formato original). Não repassa avisos para este
  /// controller: o progresso muda várias vezes por segundo e só as telas de
  /// download escutam (ListenableBuilder).
  /// Repara o histórico de reprodução e atualiza a interface.
  Future<RepairReport> repairHistory({bool removeOrphans = false}) async {
    final report = await _db.repairHistory(removeOrphans: removeOrphans);
    catalog.bumpProgress();
    return report;
  }

  /// Números do banco deste perfil, para a tela de diagnóstico.
  Future<DbDiagnostics> diagnostics() => _db.diagnostics();

  late final ImportsController imports = ImportsController(_db);
  late final DownloadsController downloads = DownloadsController(
    _db,
    urlFor: (kind, id, ext) => kind == CatalogKind.movies
        ? catalog.movieUrl(id, ext)
        : catalog.episodeUrl(id, ext),
    headers: () => playbackHeaders,
  );

  /// Tema do perfil (claro, escuro, o do Windows ou por horário). Muda a
  /// interface inteira, por isso tem um notificador próprio, escutado no topo
  /// do app.
  ThemePref themePref = ThemePref.dark;
  final ValueNotifier<ThemePref> themeNotifier = ValueNotifier(ThemePref.dark);

  /// Tamanho da interface (100/115/130/150 %, padrão 115 %). Amplia o app
  /// inteiro (ver `UiScale`), por isso tem notificador próprio, como o tema.
  int uiScalePercent = UiSizes.defaultPercent;
  final ValueNotifier<int> scaleNotifier = ValueNotifier(UiSizes.defaultPercent);
  double get uiScale => uiScalePercent / 100;

  /// Largura máxima do conteúdo, em pixels lógicos (0 = preenchido).
  int catalogWidth = CatalogWidth.fill;

  /// Pôsteres por linha para o tamanho de interface atual.
  int get portraitPerRow => RowMetrics.portraitCount(uiScalePercent);
  int get landscapePerRow => RowMetrics.landscapeCount(uiScalePercent);

  Future<void> setUiScalePercent(int percent) async {
    uiScalePercent = UiSizes.normalize(percent);
    scaleNotifier.value = uiScalePercent;
    notifyListeners();
    await _db.setSetting('ui_scale', '$uiScalePercent');
  }

  Future<void> setCatalogWidth(int px) async {
    catalogWidth = CatalogWidth.normalize(px);
    notifyListeners();
    await _db.setSetting('catalog_width', '$catalogWidth');
  }

  /// O texto da busca já foi "digitado" nesta abertura de perfil (a animação
  /// toca uma vez; não é salvo). Fica aqui para não repetir ao trocar de tema.
  bool searchHintTyped = false;

  /// Página aberta e estado da barra lateral; guardados aqui para sobreviver
  /// à reconstrução da interface ao trocar de tema.
  int shellIndex = 0;
  bool sidebarCollapsed = true;

  /// A TV ao vivo está com vídeo tocando: o player ocupa a largura toda, sem a
  /// "largura do catálogo" (ver `ContentFrame`).
  bool liveFullBleed = false;

  void setLiveFullBleed(bool value) {
    if (liveFullBleed == value) return;
    liveFullBleed = value;
    notifyListeners();
  }

  void setShellIndex(int value) {
    shellIndex = value;
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarCollapsed = !sidebarCollapsed;
    notifyListeners();
  }

  /// Imagem de fundo escolhida no PC (caminho do arquivo). Vazio = padrão: a
  /// imagem do app (ver `AppBackdrop`).
  String backgroundImage = '';

  Future<void> setBackgroundImage(String path) async {
    backgroundImage = path;
    notifyListeners();
    await _db.setSetting('background_image', path);
  }

  /// Nível de desfoque da imagem escolhida (ver `BackdropBlur`).
  int backgroundBlur = BackdropBlur.standard;

  Future<void> setBackgroundBlur(int level) async {
    backgroundBlur = BackdropBlur.normalize(level);
    notifyListeners();
    await _db.setSetting('background_blur', '$backgroundBlur');
  }

  /// Formato da interface: 'rounded' (padrão) ou 'square'. O nome salvo
  /// continua `button_shape`, de quando o ajuste só valia para os botões.
  String buttonShape = 'rounded';

  /// Muda quando o formato muda (o MaterialApp recria o tema e redesenha tudo).
  final ValueNotifier<int> shapeRevision = ValueNotifier(0);

  Future<void> setButtonShape(String shape) async {
    buttonShape = shape;
    AppShape.rounded = shape != 'square';
    shapeRevision.value++;
    notifyListeners();
    await _db.setSetting('button_shape', shape);
  }

  /// "Tema": Liquid Glass (padrão) ou Minimalista.
  bool minimalTheme = false;

  /// No Minimalista, mostrar a imagem de fundo (o Liquid Glass sempre mostra).
  bool minimalBackground = false;

  /// Tom da cor de destaque na escala em volta da cor do perfil.
  int accentTone = 0;

  /// Muda quando o tema visual ou o tom mudam (o MaterialApp redesenha tudo).
  final ValueNotifier<int> lookRevision = ValueNotifier(0);

  void _applyLook() {
    AppColors.applyLook(minimal: minimalTheme);
    AppColors.applyAccentTone(accentTone);
    lookRevision.value++;
  }

  Future<void> setMinimalTheme(bool minimal) async {
    minimalTheme = minimal;
    _applyLook();
    notifyListeners();
    await _db.setSetting('ui_theme', minimal ? 'minimal' : 'glass');
  }

  Future<void> setMinimalBackground(bool show) async {
    minimalBackground = show;
    notifyListeners();
    await _db.setSetting('minimal_background', show ? '1' : '0');
  }

  /// Muda o tom na hora, sem salvar (enquanto o controle é arrastado).
  void previewAccentTone(int tone) {
    final next = AccentScale.clamp(tone);
    if (next == accentTone) return;
    accentTone = next;
    _applyLook();
    notifyListeners();
  }

  Future<void> setAccentTone(int tone) async {
    previewAccentTone(tone);
    await _db.setSetting('accent_tone', '$accentTone');
  }

  Future<void> setThemePref(ThemePref pref) async {
    themePref = pref;
    themeNotifier.value = pref;
    notifyListeners();
    await _db.setSetting('theme_mode', pref.name);
  }

  bool get dbRecovered => _db.recoveredFromCorruption;

  // Ao trocar de perfil o controller é descartado enquanto tarefas em segundo
  // plano (atualização do catálogo, por exemplo) ainda podem terminar.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    catalog.dispose();
    downloads.dispose();
    imports.dispose();
    themeNotifier.dispose();
    scaleNotifier.dispose();
    shapeRevision.dispose();
    lookRevision.dispose();
    super.dispose();
  }

  /// Total de canais visíveis (fora das categorias ocultas).
  int get totalChannels => _all.length;
  int get hiddenChannelCount => _catalog.length - _all.length;

  /// Códigos de EPG (minúsculos) de todos os canais do catálogo.
  Set<String> get epgChannelKeys => {
        for (final c in _catalog)
          if (c.epgKey != null) c.epgKey!,
      };

  String get catalogUpdatedLabel =>
      catalogUpdatedAt == null ? 'Nunca' : formatDateTime(catalogUpdatedAt!);

  // ---- inicialização -----------------------------------------------------

  Future<void> init() async {
    streamExt = await _db.getSetting('stream_ext') ?? 'ts';
    libraryOpenMode = await _db.getSetting('library_open_mode') ?? 'panel';
    _hintsSeen
      ..clear()
      ..addAll(
        (await _db.getSetting('hints_seen') ?? '').split(',').where((e) => e.isNotEmpty),
      );
    userAgent = await _db.getSetting('user_agent') ?? '';
    favoriteChannels = {
      for (final part in (await _db.getSetting('favorite_channels') ?? '').split(','))
        if (int.tryParse(part) != null) int.parse(part),
    };
    recentChannels = _parseIdList(await _db.getSetting('recent_live_channels'))
        .take(maxRecentChannels)
        .toList(growable: false);
    preferredVersions =
        _parsePreferredVersions(await _db.getSetting('live_preferred_versions'));
    final savedKeywords = await _db.getSetting('live_highlight_keywords');
    highlightKeywords = savedKeywords == null
        ? defaultHighlightKeywords
        : [
            for (final w in savedKeywords.split(','))
              if (w.trim().isNotEmpty) w.trim(),
          ];
    miniBanners = _loadMiniBanners(await _db.getSetting('live_mini_banners'));
    await downloads.load();
    await imports.load();
    final savedTheme = await _db.getSetting('theme_mode');
    themePref = ThemePref.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemePref.dark,
    );
    themeNotifier.value = themePref;
    uiScalePercent =
        UiSizes.normalize(int.tryParse(await _db.getSetting('ui_scale') ?? ''));
    scaleNotifier.value = uiScalePercent;
    catalogWidth = CatalogWidth.normalize(
      int.tryParse(await _db.getSetting('catalog_width') ?? ''),
    );
    backgroundImage = await _db.getSetting('background_image') ?? '';
    backgroundBlur = BackdropBlur.normalize(
      int.tryParse(await _db.getSetting('background_blur') ?? ''),
    );
    buttonShape = await _db.getSetting('button_shape') ?? 'rounded';
    AppShape.rounded = buttonShape != 'square';
    minimalTheme = await _db.getSetting('ui_theme') == 'minimal';
    minimalBackground = await _db.getSetting('minimal_background') == '1';
    accentTone = AccentScale.clamp(
      int.tryParse(await _db.getSetting('accent_tone') ?? ''),
    );
    _applyLook();
    final savedVolume = double.tryParse(await _db.getSetting('volume') ?? '');
    if (savedVolume != null) await playback.setVolume(savedVolume);
    await epg.load();
    account = await _db.loadAccount();
    if (account == null) {
      phase = AppPhase.loggedOut;
      notifyListeners();
      return;
    }
    _hiddenLive = await _db.loadHiddenCategories('live');
    carryover = await _db.carryover.load();
    _allCategories = await _db.loadCategories();
    _catalog = await _db.loadChannels();
    await catalog.load();
    catalogUpdatedAt =
        DateTime.tryParse(await _db.getSetting('catalog_updated_at') ?? '');
    _rebuild();
    phase = AppPhase.ready;
    notifyListeners();

    unawaited(_refreshInfo());
    if (_catalog.isEmpty) {
      unawaited(refreshCatalog());
    } else {
      unawaited(epg.refreshStale(epgChannelKeys));
    }
  }

  // ---- conta -------------------------------------------------------------

  /// Devolve null em caso de sucesso, ou a mensagem de erro para exibir.
  ///
  /// [keepData] (troca de Xtream do mesmo provedor): antes de apagar o
  /// catálogo antigo, guarda histórico, favoritos, canais favoritos e
  /// categorias ocultas pelo nome; eles são religados aos títulos do catálogo
  /// novo quando ele chega (ver `CarryoverStore`). Sem [keepData] tudo isso é
  /// apagado.
  Future<String?> login({
    required String server,
    required String username,
    required String password,
    bool keepData = false,
  }) async {
    XtreamClient? client;
    try {
      client = XtreamClient(
        server: server,
        username: username,
        password: password,
      );
      final accountInfo = await client.authenticate();
      final saved = SavedAccount(
        server: client.server,
        username: username,
        password: password,
      );
      if (keepData) {
        await _db.carryover.snapshot();
      } else {
        await _db.carryover.clear();
      }
      carryover = await _db.carryover.load();
      await _db.saveAccount(saved);
      await _db.clearCatalog();
      await _db.clearHiddenCategories();
      await _db.clearVodAndProgress();
      await _db.clearFavoriteTitles();
      catalog.reset();
      await catalog.load();
      await playback.stop();

      account = saved;
      info = accountInfo;
      _allCategories = const [];
      _catalog = const [];
      _hiddenLive = <String>{};
      favoriteChannels = <int>{};
      unawaited(_db.setSetting('favorite_channels', ''));
      // Os ids de canal são do provedor antigo: recentes e versões não valem.
      recentChannels = const [];
      preferredVersions = const {};
      liveQueue = const [];
      unawaited(_db.setSetting('recent_live_channels', ''));
      unawaited(_db.setSetting('live_preferred_versions', '{}'));
      selectedCategoryId = null;
      query = '';
      selected = null;
      catalogUpdatedAt = null;
      syncError = null;
      _rebuild();
      phase = AppPhase.ready;
      notifyListeners();

      unawaited(refreshCatalog());
      if (keepData) {
        // Filmes e séries já agora, para religar o histórico e os favoritos.
        unawaited(catalog.refresh(CatalogKind.movies));
        unawaited(catalog.refresh(CatalogKind.series));
      }
      return null;
    } on XtreamException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erro inesperado: $e';
    } finally {
      client?.close();
    }
  }

  /// Valida e grava novas credenciais Xtream. Se o servidor e o usuário
  /// continuam os mesmos, só a senha muda e o catálogo é mantido; se mudarem,
  /// o catálogo é apagado e baixado de novo (igual a um novo login).
  /// [sameAccount] diz qual dos dois casos é. Devolve null se deu certo,
  /// ou a mensagem de erro.
  Future<String?> updateCredentials({
    required String server,
    required String username,
    required String password,
    bool keepData = false,
  }) async {
    final acc = account;
    if (acc == null) return 'Sem conta salva.';
    final normalized = XtreamClient.normalizeServer(server);
    final same = normalized == acc.server && username == acc.username;
    if (!same) {
      return login(
        server: server,
        username: username,
        password: password,
        keepData: keepData,
      );
    }
    XtreamClient? client;
    try {
      client = XtreamClient(server: server, username: username, password: password);
      final accountInfo = await client.authenticate();
      final saved = SavedAccount(
        server: client.server,
        username: username,
        password: password,
      );
      await _db.saveAccount(saved);
      account = saved;
      info = accountInfo;
      notifyListeners();
      return null;
    } on XtreamException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erro inesperado: $e';
    } finally {
      client?.close();
    }
  }

  /// true se [server]/[username] diferem da conta salva (trocar apaga o catálogo).
  bool changesAccountIdentity(String server, String username) {
    final acc = account;
    if (acc == null) return false;
    return XtreamClient.normalizeServer(server) != acc.server ||
        username != acc.username;
  }

  Future<void> logout() async {
    await playback.stop();
    await _db.deleteAccountAndCatalog();
    catalog.reset();
    account = null;
    info = null;
    _allCategories = const [];
    _catalog = const [];
    _hiddenLive = <String>{};
    selectedCategoryId = null;
    query = '';
    selected = null;
    catalogUpdatedAt = null;
    syncError = null;
    _rebuild();
    phase = AppPhase.loggedOut;
    notifyListeners();
  }

  Future<void> _refreshInfo() async {
    final acc = account;
    if (acc == null) return;
    XtreamClient? client;
    try {
      client = XtreamClient(
        server: acc.server,
        username: acc.username,
        password: acc.password,
      );
      info = await client.authenticate();
      notifyListeners();
    } catch (e) {
      AppLog.warn('conta.info', e);
      // Informativo apenas: falhar aqui não impede o uso do app.
    } finally {
      client?.close();
    }
  }

  // ---- catálogo ----------------------------------------------------------

  /// Depois de baixar a TV ao vivo: religa canais favoritos e categorias
  /// ocultas guardados na troca de Xtream (se houver algo guardado).
  Future<void> _applyCarryover() async {
    try {
      if (!await _db.carryover.applyLive()) return;
      favoriteChannels = {
        for (final part in (await _db.getSetting('favorite_channels') ?? '').split(','))
          if (int.tryParse(part) != null) int.parse(part),
      };
      _hiddenLive = await _db.loadHiddenCategories('live');
      carryover = await _db.carryover.load();
    } catch (e, st) {
      AppLog.error('conta.troca.ao_vivo', e, st);
    }
  }

  // ---- dados anteriores (troca de Xtream) -----------------------------------

  /// Página "Dados anteriores" na barra lateral.
  static const carryoverPage = 6;

  /// O que ficou guardado da conta anterior sem par no catálogo novo; null ou
  /// vazio = a aba "Dados anteriores" não aparece.
  Carryover? carryover;
  int get carryoverCount => carryover?.total ?? 0;

  /// Todos os canais (inclusive de categorias ocultas).
  List<LiveChannel> get allChannels => _catalog;

  /// Todas as categorias de TV ao vivo.
  List<LiveCategory> get allLiveCategories => _allCategories;

  Future<void> reloadCarryover() async {
    carryover = await _db.carryover.load();
    if (carryoverCount == 0 && shellIndex == carryoverPage) shellIndex = 0;
    notifyListeners();
  }

  Future<void> discardCarryover(CarryGroup group, Map<String, dynamic> entry) async {
    await _db.carryover.remove(group, entry);
    await reloadCarryover();
  }

  Future<void> clearCarryover() async {
    await _db.carryover.clear();
    await reloadCarryover();
  }

  /// Religa um item do histórico ou dos favoritos a [target]. Para episódio,
  /// [target] é a série e o episódio é achado por temporada e número.
  /// Devolve null se deu certo, ou a mensagem de erro.
  Future<String?> relinkCarryoverTitle(
    CarryGroup group,
    Map<String, dynamic> entry,
    CatalogTitle target,
  ) async {
    try {
      if (group == CarryGroup.favorites) {
        if (!catalog.isFavorite(target.kind, target.id)) {
          await catalog.toggleFavorite(target);
        }
        await _db.carryover.remove(group, entry);
      } else if (entry['kind'] == 'episode') {
        final d = await catalog.details(CatalogKind.series, target.id);
        final s = entry['season'], n = entry['episode'];
        Episode? ep;
        for (final list in d.seasons.values) {
          for (final e in list) {
            if (e.season == s && e.number == n) ep = e;
          }
        }
        if (ep == null) {
          return '"${target.name}" não tem o episódio T$s E$n.';
        }
        await _db.carryover.relinkProgress(entry, itemId: ep.id, seriesId: target.id);
        catalog.bumpProgress();
      } else {
        await _db.carryover.relinkProgress(entry, itemId: target.id);
        catalog.bumpProgress();
      }
      await reloadCarryover();
      return null;
    } on XtreamException catch (e) {
      return e.message;
    } catch (e, st) {
      AppLog.error('dados_anteriores.religar', e, st);
      return 'Não foi possível religar: $e';
    }
  }

  Future<void> relinkCarryoverChannel(
    Map<String, dynamic> entry,
    LiveChannel channel,
  ) async {
    if (!isFavorite(channel.streamId)) await toggleFavorite(channel);
    await _db.carryover.remove(CarryGroup.channels, entry);
    await reloadCarryover();
  }

  /// Oculta de novo a categoria escolhida ([kindKey] = live, vod ou series).
  Future<void> relinkCarryoverCategory(
    Map<String, dynamic> entry,
    String kindKey,
    String categoryId,
  ) async {
    if (kindKey == 'live') {
      await setCategoriesVisible([categoryId], false);
    } else {
      final kind = kindKey == 'vod' ? CatalogKind.movies : CatalogKind.series;
      await catalog.setCategoriesVisible(kind, [categoryId], false);
    }
    await _db.carryover.remove(CarryGroup.hidden, entry);
    await reloadCarryover();
  }

  Future<void> refreshCatalog() async {
    final acc = account;
    if (acc == null || syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();

    XtreamClient? client;
    try {
      client = XtreamClient(
        server: acc.server,
        username: acc.username,
        password: acc.password,
      );
      final cats = await client.fetchLiveCategories();
      final chans = await client.fetchLiveChannels();
      await _db.replaceCatalog(cats, chans);
      final now = DateTime.now();
      await _db.setSetting('catalog_updated_at', now.toIso8601String());
      await _applyCarryover();

      _allCategories = cats;
      _catalog = chans;
      catalogUpdatedAt = now;
      _rebuild();
      unawaited(_refreshInfo());
      unawaited(epg.refreshStale(epgChannelKeys));
    } on XtreamException catch (e) {
      syncError = e.message;
    } catch (e) {
      syncError = 'Falha ao atualizar o catálogo: $e';
    } finally {
      client?.close();
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> clearCatalogCache() async {
    await playback.stop();
    await _db.clearCatalog();
    _allCategories = const [];
    _catalog = const [];
    selectedCategoryId = null;
    selected = null;
    catalogUpdatedAt = null;
    _rebuild();
    notifyListeners();
  }

  // ---- navegação do catálogo --------------------------------------------

  void setQuery(String value) {
    query = value;
    _applyFilter();
    notifyListeners();
  }

  /// Busca global de canais (barra do topo): todas as palavras digitadas precisam
  /// aparecer no nome (sem acento/maiúscula). Quem **começa** com a primeira
  /// palavra vem antes. Só considera canais de categorias visíveis.
  List<LiveChannel> searchChannels(String text, {int limit = 300}) {
    final words = [
      for (final w in foldText(text.trim()).split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
    ];
    if (words.isEmpty) return const [];
    final starts = <LiveChannel>[];
    final others = <LiveChannel>[];
    for (final ch in _all) {
      final key = ch.searchKey;
      var ok = true;
      for (final w in words) {
        if (!key.contains(w)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      (key.startsWith(words.first) ? starts : others).add(ch);
    }
    return [...starts, ...others].take(limit).toList(growable: false);
  }

  void selectCategory(String? id) {
    selectedCategoryId = id;
    _applyFilter();
    notifyListeners();
  }

  List<LiveChannel> _favListCache = const [];
  List<LiveChannel>? _favListForAll;
  Set<int>? _favListForSet;

  /// Canais favoritos (de categorias visíveis), na ordem da lista do provedor.
  List<LiveChannel> get favoriteChannelList {
    if (!identical(_favListForAll, _all) ||
        !identical(_favListForSet, favoriteChannels)) {
      _favListForAll = _all;
      _favListForSet = favoriteChannels;
      _favListCache = [
        for (final ch in _all)
          if (favoriteChannels.contains(ch.streamId)) ch,
      ];
    }
    return _favListCache;
  }

  bool isFavorite(int streamId) => favoriteChannels.contains(streamId);

  Future<void> toggleFavorite(LiveChannel channel) async {
    final next = {...favoriteChannels};
    if (!next.remove(channel.streamId)) next.add(channel.streamId);
    favoriteChannels = next;
    notifyListeners();
    await _db.setSetting('favorite_channels', next.join(','));
  }

  void selectChannel(LiveChannel channel) {
    selected = channel;
    notifyListeners();
  }

  // ---- gerenciar categorias ---------------------------------------------

  bool isCategoryVisible(String id) => !_hiddenLive.contains(id);

  /// Mostra ou oculta categorias da TV ao vivo. Salvo no banco; vale na hora.
  Future<void> setCategoriesVisible(Iterable<String> ids, bool visible) async {
    final list = ids.toList();
    if (visible) {
      _hiddenLive.removeAll(list);
    } else {
      _hiddenLive.addAll(list);
    }
    _rebuild();
    notifyListeners();
    await _db.setCategoriesHidden('live', list, hidden: !visible);
  }

  void _rebuild() {
    _all = _hiddenLive.isEmpty
        ? _catalog
        : [
            for (final c in _catalog)
              if (!_hiddenLive.contains(c.categoryId)) c,
          ];

    final raw = <String, int>{};
    for (final c in _catalog) {
      raw[c.categoryId] = (raw[c.categoryId] ?? 0) + 1;
    }
    rawCountByCategory = raw;
    manageableCategories = [
      for (final cat in _allCategories)
        if ((raw[cat.id] ?? 0) > 0) cat,
    ];

    final counts = <String, int>{};
    for (final c in _all) {
      counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
    }
    countByCategory = counts;
    categories = [
      for (final cat in manageableCategories)
        if (!_hiddenLive.contains(cat.id)) cat,
    ];

    if (selectedCategoryId != null &&
        !categories.any((c) => c.id == selectedCategoryId)) {
      selectedCategoryId = null;
    }
    _applyFilter();
  }

  void _applyFilter() {
    final q = foldText(query.trim());
    Iterable<LiveChannel> items = _all;
    final cat = selectedCategoryId;
    if (cat != null) items = items.where((c) => c.categoryId == cat);
    if (q.isNotEmpty) items = items.where((c) => c.searchKey.contains(q));
    visible = items.toList(growable: false);
  }

  // ---- reprodução --------------------------------------------------------

  String? streamUrlFor(LiveChannel channel) {
    final acc = account;
    if (acc == null) return null;
    final user = Uri.encodeComponent(acc.username);
    final pass = Uri.encodeComponent(acc.password);
    return '${acc.server}/live/$user/$pass/${channel.streamId}.$streamExt';
  }

  Map<String, String>? get playbackHeaders {
    final ua = userAgent.trim();
    return ua.isEmpty ? null : {'User-Agent': ua};
  }

  /// Só salva o ajuste; vale a partir do próximo canal aberto.
  Future<void> setStreamExt(String ext) async {
    streamExt = ext;
    await _db.setSetting('stream_ext', ext);
    notifyListeners();
  }

  Future<void> setUserAgent(String value) async {
    userAgent = value.trim();
    await _db.setSetting('user_agent', userAgent);
    notifyListeners();
  }

  /// Reabre o canal atual com o formato informado (usado no painel de erro).
  Future<void> retryWithFormat(String ext) async {
    streamExt = ext;
    await _db.setSetting('stream_ext', ext);
    playbackNonce++;
    notifyListeners();
  }

  void retryPlayback() {
    playbackNonce++;
    notifyListeners();
  }

  Future<void> saveVolume(double value) =>
      _db.setSetting('volume', value.toStringAsFixed(0));
}
