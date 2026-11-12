import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/catalog_models.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/xtream_client.dart';
import 'home_banners.dart';
import 'search_worker.dart';
import 'smart_search.dart';
import '../core/app_log.dart';

/// Um banner da Home: título da faixa e 1 a 3 títulos (o primeiro é o destaque).
class _DetailsJob {
  _DetailsJob(this.key, this.kind, this.id);

  final String key;
  final CatalogKind kind;
  final int id;
  final Completer<TitleDetails?> done = Completer<TitleDetails?>();

  /// Quantos cartões/prefetchs da busca esperam por este pedido.
  int watchers = 0;

  /// Alguém que não pode cancelar (banner, painel) também espera.
  bool pinned = false;
}

class HeroSlide {
  const HeroSlide({
    required this.kicker,
    required this.titles,
    this.resume = false,
    this.opensCatalog = false,
  });

  final String kicker;
  final List<CatalogTitle> titles;

  /// Slide "continue de onde parou": o botão retoma a reprodução.
  final bool resume;

  /// O botão secundário leva à aba Catálogo.
  final bool opensCatalog;
}

/// Resultado da busca: o que mais se aproxima e, à parte, os extras.
class SearchResults {
  const SearchResults({
    this.best = const [],
    this.related = const [],
    this.scores = const {},
  });

  final List<CatalogTitle> best;
  final List<CatalogTitle> related;

  /// Pontuação por id (só vale comparar entre resultados do mesmo tipo).
  final Map<int, double> scores;

  /// Os mais parecidos de filmes e séries juntos, do melhor ao pior. Só entram
  /// os que combinam com tudo o que foi digitado; se não houver nenhum,
  /// entram os parciais mais próximos.
  static List<CatalogTitle> closest(SearchResults a, SearchResults b,
      {int limit = 10}) {
    List<(double, CatalogTitle)> rank(Iterable<(SearchResults, CatalogTitle)> it) => [
          for (final (r, t) in it) (r.scores[t.id] ?? 0, t),
        ]..sort((x, y) => y.$1.compareTo(x.$1));

    var ranked = rank([
      for (final t in a.best) (a, t),
      for (final t in b.best) (b, t),
    ]);
    if (ranked.isEmpty) {
      ranked = rank([
        for (final t in a.related) (a, t),
        for (final t in b.related) (b, t),
      ]);
      if (ranked.isNotEmpty) {
        final floor = ranked.first.$1 * 0.6;
        ranked = [for (final e in ranked) if (e.$1 >= floor) e];
      }
    }
    return [for (final e in ranked.take(limit)) e.$2];
  }

  bool get isEmpty => best.isEmpty && related.isEmpty;
}

/// Estado de uma aba do catálogo (filmes ou séries).
class CatalogSection {
  List<LiveCategory> categories = const [];
  Map<String, int> counts = const {};
  Set<String> hidden = <String>{};
  DateTime? updatedAt;
  bool syncing = false;
  String? error;

  /// Categorias com ao menos um título (visíveis ou não), para o gerenciador.
  List<LiveCategory> get manageable => [
        for (final c in categories)
          if ((counts[c.id] ?? 0) > 0) c,
      ];

  /// Categorias visíveis com ao menos um título.
  List<LiveCategory> get visibleCategories => [
        for (final c in manageable)
          if (!hidden.contains(c.id)) c,
      ];

  int get total => counts.values.fold(0, (a, b) => a + b);

  int get visibleTotal {
    var n = 0;
    counts.forEach((id, c) {
      if (!hidden.contains(id)) n += c;
    });
    return n;
  }
}

/// Filmes, séries, detalhes e progresso do perfil aberto.
///
/// Os títulos ficam no SQLite e são lidos aos poucos (uma fileira por vez);
/// nunca são carregados todos na memória.
class CatalogController extends ChangeNotifier {
  CatalogController(this._db, {required this.accountOf});

  final AppDatabase _db;
  final SavedAccount? Function() accountOf;

  final Map<CatalogKind, CatalogSection> _sections = {
    for (final k in CatalogKind.values) k: CatalogSection(),
  };

  CatalogSection section(CatalogKind kind) => _sections[kind]!;

  /// Muda quando o progresso de reprodução foi alterado (atualiza fileiras).
  int progressRevision = 0;

  static const _staleAfter = Duration(hours: 24);

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_workerFuture != null) unawaited(_workerFuture!.then((w) => w.dispose(), onError: (Object _) {}));
    super.dispose();
  }

  // ---- carregar do banco -----------------------------------------------------

  // ---- favoritos (filmes e séries) ------------------------------------------

  /// Muda a cada alteração; os corações escutam só isto (não a tela toda).
  final ValueNotifier<int> favoritesRevision = ValueNotifier(0);
  Set<String> _favorites = {};

  bool isFavorite(CatalogKind kind, int id) => _favorites.contains('${kind.key}:$id');

  Future<void> _loadFavorites() async {
    _favorites = await _db.catalog.favoriteKeys();
    favoritesRevision.value++;
  }

  Future<void> toggleFavorite(CatalogTitle title) async {
    final on = !isFavorite(title.kind, title.id);
    _favorites = {..._favorites};
    final key = '${title.kind.key}:${title.id}';
    on ? _favorites.add(key) : _favorites.remove(key);
    favoritesRevision.value++; // atualiza na hora; grava em seguida
    try {
      await _db.catalog.setFavorite(title.kind, title.id, on);
    } catch (e, st) {
      AppLog.error('favoritos', e, st);
      await _loadFavorites(); // volta ao que está gravado
    }
  }

  Future<List<CatalogTitle>> favoriteTitles(CatalogKind kind) =>
      _db.catalog.favoriteTitles(kind);

  // ---- imagens horizontais (busca) --------------------------------------------

  /// Aba aberta em Filmes e séries (a busca do topo usa para escolher a aba
  /// inicial). Só informativo: mudar não reconstrói nada.
  CatalogKind activeKind = CatalogKind.movies;

  /// `<tipo>:<id>` -> endereço da imagem horizontal, guardado no banco do perfil
  /// sempre que os detalhes de um título chegam. A busca usa isto para mostrar
  /// a imagem na hora, sem pedir nada ao provedor.
  Map<String, String> _backdrops = {};

  String? cachedBackdrop(CatalogKind kind, int id) => _backdrops['${kind.key}:$id'];

  void _rememberBackdrop(CatalogKind kind, int id, String? url) {
    if (url == null || url.isEmpty) return;
    final key = '${kind.key}:$id';
    if (_backdrops[key] == url) return;
    _backdrops[key] = url;
    _db.catalog.putBackdrop(kind, id, url).catchError((Object e, StackTrace st) {
      AppLog.error('catalogo.backdrop', e, st);
    });
  }

  /// Chaves dos pedidos de "prefetch" da busca ainda guardados.
  final Set<String> _prefetchKeys = {};

  /// Pede (em segundo plano) os detalhes dos primeiros títulos que ainda não
  /// têm imagem horizontal guardada. Pedidos do prefetch anterior que ainda não
  /// começaram são cancelados.
  void prefetchBackdrops(Iterable<CatalogTitle> titles, {int max = 12}) {
    cancelPrefetch();
    var n = 0;
    for (final t in titles) {
      if (n >= max) break;
      if (cachedBackdrop(t.kind, t.id) != null) continue;
      n++;
      _prefetchKeys.add('${t.kind.key}:${t.id}');
      requestBackdrop(t.kind, t.id);
    }
  }

  void cancelPrefetch() {
    for (final key in _prefetchKeys) {
      _release(key);
    }
    _prefetchKeys.clear();
  }

  Future<void> load() async {
    await _loadFavorites();
    try {
      _backdrops = await _db.catalog.backdropCache();
    } catch (e, st) {
      AppLog.error('catalogo.backdrop.carregar', e, st);
    }
    for (final kind in CatalogKind.values) {
      final s = section(kind);
      s.categories = await _db.catalog.loadCategories(kind);
      s.counts = await _db.catalog.counts(kind);
      s.hidden = await _db.loadHiddenCategories(kind.key);
      s.updatedAt = DateTime.tryParse(
        await _db.getSetting('${kind.key}_updated_at') ?? '',
      );
    }
    final animRaw = await _db.getSetting('animation_categories') ?? '';
    animationCategories = {
      for (final k in animRaw.split('|'))
        if (k.length > 2 && (k.startsWith('m:') || k.startsWith('s:'))) k,
    };
    final rawBanners = await _db.getSetting('home_banners');
    banners = rawBanners == null
        ? BannerConfig.defaults(animationCategories)
        : BannerConfig.decode(rawBanners);
    _invalidate();
    notifyListeners();
  }

  /// Esquece tudo da memória (troca de conta ou saída).
  void reset() {
    for (final kind in CatalogKind.values) {
      _sections[kind] = CatalogSection();
    }
    _details.clear();
    _dropPending();
    _detailsOrNull.clear();
    _prefetchKeys.clear();
    _backdrops = {};
    _invalidate();
    notifyListeners();
  }

  // ---- baixar do servidor -------------------------------------------------------

  /// Chamado ao abrir a aba: baixa se nunca foi baixado ou se está velho.
  Future<void> ensureFresh(CatalogKind kind) async {
    final s = section(kind);
    // Durante uma reprodução pela internet não baixa listas grandes.
    if (s.syncing || accountOf() == null || playbackActive) return;
    final updated = s.updatedAt;
    final stale =
        updated == null || DateTime.now().difference(updated) > _staleAfter;
    if (stale && (s.error == null || updated == null)) {
      await refresh(kind);
    }
  }

  Future<void> refresh(CatalogKind kind) async {
    final acc = accountOf();
    final s = section(kind);
    if (acc == null || s.syncing) return;
    s.syncing = true;
    s.error = null;
    notifyListeners();

    XtreamClient? client;
    try {
      client = XtreamClient(
        server: acc.server,
        username: acc.username,
        password: acc.password,
      );
      final cats = await client.fetchCategories(kind);
      final titles = await client.fetchTitles(kind);
      await _db.catalog.replaceCatalog(kind, cats, titles);
      final now = DateTime.now();
      await _db.setSetting('${kind.key}_updated_at', now.toIso8601String());
      s.categories = cats;
      s.counts = await _db.catalog.counts(kind);
      s.updatedAt = now;
      _invalidate();
    } on XtreamException catch (e) {
      s.error = e.message;
    } catch (e) {
      s.error = 'Falha ao atualizar ${kind.label.toLowerCase()}: $e';
    } finally {
      client?.close();
      s.syncing = false;
      notifyListeners();
    }
  }

  /// Apaga filmes e séries salvos (o progresso é mantido).
  Future<void> clearCache() async {
    for (final kind in CatalogKind.values) {
      await _db.catalog.clearKind(kind);
      await _db.deleteSetting('${kind.key}_updated_at');
      final s = section(kind);
      s.categories = const [];
      s.counts = const {};
      s.updatedAt = null;
      s.error = null;
    }
    _details.clear();
    _invalidate();
    notifyListeners();
  }

  // ---- fileiras, busca e "ver tudo" --------------------------------------------

  // Resultados de fileiras ficam em cache (futuros) para a lista rolar sem
  // consultar o banco de novo a cada reconstrução.
  final Map<String, Future<List<CatalogTitle>>> _rows = {};

  void _invalidate() {
    _rows.clear();
    _searchIndex.clear();
    _workerIndex.clear(); // o isolate recebe o índice de novo na próxima busca
    _slides = null;
  }

  /// Libera listas em memória das fileiras (voltam do SQLite quando precisar).
  /// Chamado quando uma página é descartada depois de 6 s fora de vista.
  void trimCache() => _rows.clear();

  Future<List<HeroSlide>>? _slides;
  final int _heroSeed = DateTime.now().millisecondsSinceEpoch;

  /// Banners da Home (até 5, na ordem): último assistido, filmes novos, séries
  /// novas, mistura recente (leva ao catálogo) e animações das categorias que
  /// o usuário marcou. Slides sem títulos são omitidos. Sorteios ficam fixos
  /// até o catálogo ou o progresso mudar.
  Future<List<HeroSlide>> heroSlides() => _slides ??= _buildSlides();

  bool _hasImage(CatalogTitle t) => (t.image ?? '').startsWith('http');

  /// Recentes com imagem; se o provedor não informa a data de inclusão, usa a
  /// primeira categoria visível.
  Future<List<CatalogTitle>> _fresh(CatalogKind kind) async {
    // Os 100 mais recentes (a fileira "Adicionados recentemente" usa só 40).
    var list = (await _db.catalog.recent(kind, section(kind).hidden, limit: 100))
        .where(_hasImage)
        .toList();
    if (list.isEmpty) {
      for (final c in section(kind).visibleCategories) {
        if ((section(kind).counts[c.id] ?? 0) == 0) continue;
        list = (await rowTitles(kind, c.id)).where(_hasImage).toList();
        if (list.isNotEmpty) break;
      }
    }
    return list;
  }

  Future<List<HeroSlide>> _buildSlides() async {
    final slides = <HeroSlide>[];

    CatalogTitle? last;
    for (final kind in CatalogKind.values) {
      final cont = await continueTitles(kind);
      if (cont.isEmpty) continue;
      if (last == null || (cont.first.updatedAt ?? 0) > (last.updatedAt ?? 0)) {
        last = cont.first;
      }
    }
    if (last != null) {
      slides.add(HeroSlide(
        kicker: 'Continue de onde parou',
        titles: [last],
        resume: true,
      ));
    }

    // "Filmes novos" / "Séries novas": 3 sorteados entre os 100 mais recentes.
    // O sorteio usa uma semente fixa por abertura do app: fica igual enquanto o
    // app estiver aberto e muda na próxima vez.
    final movies = await _fresh(CatalogKind.movies);
    final series = await _fresh(CatalogKind.series);
    final rnd = Random(_heroSeed);
    final movieShuffle = [...movies]..shuffle(rnd);
    final seriesShuffle = [...series]..shuffle(rnd);
    final moviePick = movieShuffle.take(3).toList();
    final seriesPick = seriesShuffle.take(3).toList();
    // Mistura: os mais recentes que não foram sorteados, alternando filmes e séries.
    final mix = <CatalogTitle>[];
    final m = [for (final t in movies) if (!moviePick.contains(t)) t];
    final se = [for (final t in series) if (!seriesPick.contains(t)) t];
    for (var i = 0; mix.length < 3 && (i < m.length || i < se.length); i++) {
      if (i < m.length) mix.add(m[i]);
      if (mix.length < 3 && i < se.length) mix.add(se[i]);
    }

    // Os demais banners seguem a lista configurada em "Banners do Início".
    final more = [
      for (final t in await continueAll())
        if (last == null || t.kind != last.kind || t.id != last.id) t,
    ];
    for (final cfg in banners.take(BannerConfig.maxExtra)) {
      List<CatalogTitle> picks = const [];
      var opensCatalog = false;
      var resume = false;
      switch (cfg.source) {
        case BannerSource.newMovies:
          picks = moviePick;
        case BannerSource.newSeries:
          picks = seriesPick;
        case BannerSource.newMix:
          picks = mix;
          opensCatalog = true;
        case BannerSource.continueMore:
          picks = more.take(3).toList();
          resume = true;
        case BannerSource.categories:
          final pool = <CatalogTitle>[];
          for (final key in cfg.categories) {
            final kind =
                key.startsWith('m:') ? CatalogKind.movies : CatalogKind.series;
            final id = key.substring(2);
            if (!isVisible(kind, id)) continue;
            pool.addAll((await rowTitles(kind, id)).where(_hasImage));
          }
          pool.shuffle(Random(_heroSeed + cfg.name.hashCode));
          picks = pool.take(3).toList();
        case BannerSource.titles:
          final found = <String, CatalogTitle>{};
          for (final kind in CatalogKind.values) {
            final ids = [
              for (final r in cfg.titles)
                if (r.kind == kind) r.id,
            ];
            for (final t in await _db.catalog.titlesByIds(kind, ids)) {
              found['${kind.key}:${t.id}'] = t;
            }
          }
          picks = [
            for (final r in cfg.titles)
              ?found['${r.kind.key}:${r.id}'],
          ];
      }
      if (picks.isEmpty) continue;
      slides.add(HeroSlide(
        kicker: cfg.name,
        titles: picks,
        resume: resume,
        opensCatalog: opensCatalog,
      ));
    }
    return slides;
  }

  /// Banners do Início depois do fixo "Continue de onde parou" (até 4).
  List<BannerConfig> banners = [];
  int bannersRevision = 0;

  Future<void> setBanners(List<BannerConfig> value) async {
    banners = [for (final b in value.take(BannerConfig.maxExtra)) b.copy()];
    bannersRevision++;
    _slides = null;
    await _db.setSetting('home_banners', BannerConfig.encode(banners));
    notifyListeners();
  }

  /// Categorias (legado: só usadas para montar o padrão na 1ª vez) no formato `m:<id>` (filmes) ou `s:<id>`.
  Set<String> animationCategories = {};

  Future<void> setAnimationCategories(Set<String> value) async {
    animationCategories = value;
    _slides = null;
    await _db.setSetting('animation_categories', value.join('|'));
    notifyListeners();
  }

  Future<List<CatalogTitle>> rowTitles(CatalogKind kind, String categoryId) {
    return _rows.putIfAbsent(
      '${kind.key}:c:$categoryId',
      () => _db.catalog.titles(kind, categoryId, limit: 40),
    );
  }

  /// Um título do catálogo pelo id (null se não existir mais).
  Future<CatalogTitle?> titleById(CatalogKind kind, int id) async {
    final list = await _db.catalog.titlesByIds(kind, [id]);
    return list.isEmpty ? null : list.first;
  }

  /// Um título da mesma categoria de [t] (com imagem, diferente dele), para o
  /// banner menor "Relacionado" do Início. A escolha é fixa para cada título.
  Future<CatalogTitle?> relatedTo(CatalogTitle t) async {
    final rows = await rowTitles(t.kind, t.categoryId);
    final pool = [
      for (final x in rows)
        if (x.id != t.id && _hasImage(x)) x,
    ];
    if (pool.isEmpty) return null;
    return pool[(t.id * 31 + 7) % pool.length];
  }

  Future<List<CatalogTitle>> recentTitles(CatalogKind kind) {
    return _rows.putIfAbsent(
      '${kind.key}:recent',
      () => _db.catalog.recent(kind, section(kind).hidden),
    );
  }

  Future<List<CatalogTitle>> continueTitles(CatalogKind kind) {
    return _rows.putIfAbsent(
      '${kind.key}:continue:$progressRevision',
      () => _db.catalog.continueWatching(kind),
    );
  }

  /// Filmes e séries em andamento juntos, do mais recente para o mais antigo.
  Future<List<CatalogTitle>> continueAll() {
    return _rows.putIfAbsent('all:continue:$progressRevision', () async {
      final lists = [
        for (final k in CatalogKind.values) ...await continueTitles(k),
      ];
      lists.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
      return lists.take(12).toList();
    });
  }

  Future<List<CatalogTitle>> allTitles(CatalogKind kind, String categoryId) {
    return _db.catalog.titles(kind, categoryId, limit: 3000);
  }

  // Índice de busca em memória (só ids e nomes normalizados), montado na
  // primeira busca e refeito quando o catálogo muda.
  final Map<CatalogKind, Future<List<SearchEntry>>> _searchIndex = {};

  // A busca roda num isolate (ver search_worker.dart). Se ele falhar por qualquer
  // motivo, cai no caminho antigo, na própria interface.
  Future<SearchWorker>? _workerFuture;
  bool _workerBroken = false;
  final Map<CatalogKind, Future<void>> _workerIndex = {};

  Future<SearchHits> _searchHits(CatalogKind kind, String query) async {
    if (!_workerBroken) {
      try {
        final worker = await (_workerFuture ??= SearchWorker.start());
        await (_workerIndex[kind] ??= () async {
          final raw = await _db.catalog.searchIndexRaw(kind);
          await worker.load(
            kind.key,
            ids: raw.ids,
            categories: raw.cats,
            keys: raw.keys,
            ratings: raw.ratings,
          );
        }());
        return await worker.query(kind.key, query, section(kind).hidden);
      } catch (e, st) {
        _workerBroken = true;
        AppLog.error('busca.isolate', e, st);
      }
    }
    final index = await (_searchIndex[kind] ??= _db.catalog.searchIndex(kind));
    return SmartSearch.runBilingual(index, query, hidden: section(kind).hidden);
  }

  Future<SearchResults> search(CatalogKind kind, String query) async {
    final hits = await _searchHits(kind, query);
    final best = await _db.catalog.titlesByIds(kind, hits.best);
    final related = await _db.catalog.titlesByIds(kind, hits.related);
    return SearchResults(best: best, related: related, scores: hits.scores);
  }

  // ---- gerenciar categorias --------------------------------------------------------

  bool isVisible(CatalogKind kind, String id) =>
      !section(kind).hidden.contains(id);

  Future<void> setCategoriesVisible(
    CatalogKind kind,
    Iterable<String> ids,
    bool visible,
  ) async {
    final list = ids.toList();
    final s = section(kind);
    if (visible) {
      s.hidden.removeAll(list);
    } else {
      s.hidden.addAll(list);
    }
    _rows.remove('${kind.key}:recent');
    notifyListeners();
    await _db.setCategoriesHidden(kind.key, list, hidden: !visible);
  }

  // ---- detalhes -------------------------------------------------------------------

  final Map<String, Future<TitleDetails>> _details = {};

  /// Detalhes do servidor (sinopse, elenco, episódios). Em caso de falha o
  /// cache é descartado para tentar de novo na próxima abertura.
  Future<TitleDetails> details(CatalogKind kind, int id) {
    final key = '${kind.key}:$id';
    return _details.putIfAbsent(key, () async {
      final acc = accountOf();
      if (acc == null) throw XtreamException('Sem conta.');
      final client = XtreamClient(
        server: acc.server,
        username: acc.username,
        password: acc.password,
      );
      try {
        final d = kind == CatalogKind.movies
            ? await client.fetchMovieInfo(id)
            : await client.fetchSeriesInfo(id);
        _rememberBackdrop(kind, id, d.backdrop);
        return d;
      } catch (e, st) {
        AppLog.error('catalogo.detalhes ${kind.key}:$id', e, st);
        _details.remove(key);
        rethrow;
      } finally {
        client.close();
      }
    });
  }

  final Map<String, Future<TitleDetails?>> _detailsOrNull = {};

  // ---- fila de detalhes em segundo plano ------------------------------------
  //
  // Provedores IPTV costumam limitar conexões simultâneas: no máximo 3 pedidos
  // de detalhes ao mesmo tempo. A fila tem três regras:
  //  1. quem está na tela da busca ([requestBackdrop]) passa na frente dos
  //     banners; dentro de cada grupo vale a ordem de chegada;
  //  2. pedido da busca que ainda não começou e perdeu todos os interessados
  //     (o cartão saiu da tela ou veio outra busca) é **cancelado**: não gasta
  //     internet nem atrasa os próximos;
  //  3. **durante uma reprodução pela internet nada novo começa** (ver
  //     [beginPlayback]); a fila continua de onde parou ao voltar.
  final Map<String, _DetailsJob> _pending = {};
  int _running = 0;
  int _playing = 0;

  /// Há uma reprodução (TV ao vivo ou filme/série pela internet) aberta.
  bool get playbackActive => _playing > 0;

  void beginPlayback() => _playing++;

  void endPlayback() {
    if (_playing > 0) _playing--;
    if (_playing == 0) _pump();
  }

  void _pump() {
    while (_running < 3 && !playbackActive && _pending.isNotEmpty) {
      final job = _pending.values.firstWhere(
        (j) => j.watchers > 0,
        orElse: () => _pending.values.first,
      );
      _pending.remove(job.key);
      _running++;
      details(job.kind, job.id)
          .then<TitleDetails?>((d) => d)
          .catchError((Object _) {
        _detailsOrNull.remove(job.key);
        return null;
      }).then((d) {
        _running--;
        job.done.complete(d);
        _pump();
      });
    }
  }

  _DetailsJob _enqueue(CatalogKind kind, int id) {
    final key = '${kind.key}:$id';
    final job = _DetailsJob(key, kind, id);
    _pending[key] = job;
    _detailsOrNull[key] = job.done.future;
    _pump();
    return job;
  }

  /// Dá o pedido por perdido: quem ainda esperava recebe null.
  void _dropPending() {
    for (final j in _pending.values) {
      j.done.complete(null);
    }
    _pending.clear();
  }

  void _release(String key) {
    final job = _pending[key];
    if (job == null) return; // já começou (ou terminou): nada a cancelar
    if (job.watchers > 0) job.watchers--;
    if (job.watchers == 0 && !job.pinned) {
      _pending.remove(key);
      _detailsOrNull.remove(key);
      job.done.complete(null);
    }
  }

  /// Como [details], mas devolve null em caso de erro (para imagens de fundo
  /// que podem cair no pôster). Fica em cache por título. O pedido não é
  /// cancelável (banners do Início, painel, biblioteca).
  Future<TitleDetails?> detailsOrNull(CatalogKind kind, int id) {
    final key = '${kind.key}:$id';
    final existing = _detailsOrNull[key];
    if (existing != null) {
      _pending[key]?.pinned = true;
      return existing;
    }
    final job = _enqueue(kind, id)..pinned = true;
    return job.done.future;
  }

  /// Pedido **cancelável** da busca: quem pede deve chamar [releaseBackdrop]
  /// quando o cartão sair da tela.
  Future<TitleDetails?> requestBackdrop(CatalogKind kind, int id) {
    final key = '${kind.key}:$id';
    final existing = _detailsOrNull[key];
    if (existing != null) {
      _pending[key]?.watchers++;
      return existing;
    }
    final job = _enqueue(kind, id)..watchers = 1;
    return job.done.future;
  }

  void releaseBackdrop(CatalogKind kind, int id) => _release('${kind.key}:$id');

  // ---- endereços de reprodução ----------------------------------------------------

  String? movieUrl(int streamId, String ext) {
    final acc = accountOf();
    if (acc == null) return null;
    final user = Uri.encodeComponent(acc.username);
    final pass = Uri.encodeComponent(acc.password);
    return '${acc.server}/movie/$user/$pass/$streamId.$ext';
  }

  String? episodeUrl(int episodeId, String ext) {
    final acc = accountOf();
    if (acc == null) return null;
    final user = Uri.encodeComponent(acc.username);
    final pass = Uri.encodeComponent(acc.password);
    return '${acc.server}/series/$user/$pass/$episodeId.$ext';
  }

  // ---- progresso --------------------------------------------------------------------

  Future<WatchProgress?> progressOf(PlayItem item) =>
      _db.catalog.progress(item.kind.progressKind, item.id);

  Future<WatchProgress?> movieProgress(int streamId) =>
      _db.catalog.progress(CatalogKind.movies.progressKind, streamId);

  Future<Map<int, WatchProgress>> episodeProgress(int seriesId) =>
      _db.catalog.episodeProgress(seriesId);

  Future<void> saveProgress(
    PlayItem item, {
    required int positionMs,
    required int durationMs,
    required bool watched,
  }) {
    return _db.catalog.saveProgress(
      item,
      positionMs: positionMs,
      durationMs: durationMs,
      watched: watched,
    );
  }

  Future<void> setWatched(PlayItem item, bool watched) async {
    await _db.catalog.setWatched(item, watched);
    bumpProgress();
  }

  // ---- histórico --------------------------------------------------------------

  Future<List<HistoryRow>> history() => _db.catalog.history();

  Future<void> setHistoryWatched(HistoryRow row, bool watched) async {
    await _db.catalog.setHistoryWatched(row, watched);
    bumpProgress();
  }

  Future<void> removeHistory(HistoryRow row) async {
    await _db.catalog.removeHistory(row);
    bumpProgress();
  }

  Future<int> clearHistory() async {
    final n = await _db.catalog.clearHistory();
    bumpProgress();
    return n;
  }

  /// Avisa a interface que o progresso mudou (ex.: ao fechar o player).
  void bumpProgress() {
    progressRevision++;
    _slides = null;
    notifyListeners();
  }
}
