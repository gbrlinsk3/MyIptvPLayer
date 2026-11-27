import '../../data/catalog_models.dart';

/// Tamanho do bloco das fileiras de recentes.
const int recentPageSize = 40;

/// Um bloco de títulos. [lidos] é quantas linhas o banco devolveu, antes de
/// qualquer filtro: menos que [recentPageSize] quer dizer que acabou.
typedef TitlePage = ({List<CatalogTitle> titles, int lidos});

/// Busca o bloco que começa em [offset].
typedef TitlePageLoader = Future<TitlePage> Function(int offset);

/// Fileira sem fim: o primeiro bloco chega pronto e os próximos são buscados
/// aos poucos. Depois do último, a lista recomeça no primeiro título.
class EndlessTitles {
  final List<CatalogTitle> _extras = [];
  int _offset = recentPageSize;
  bool _busy = false;
  bool _ended = false;

  /// Não há mais blocos para buscar.
  bool get ended => _ended;

  int loaded(List<CatalogTitle> first) => first.length + _extras.length;

  /// Título da posição [i]; depois do fim, [i] dá a volta.
  CatalogTitle at(List<CatalogTitle> first, int i) {
    final n = _ended ? i % loaded(first) : i;
    return n < first.length ? first[n] : _extras[n - first.length];
  }

  /// Busca o próximo bloco. Devolve `true` se algo mudou. Pedidos repetidos
  /// enquanto um está em curso são ignorados.
  Future<bool> more(TitlePageLoader load) async {
    if (_busy || _ended) return false;
    _busy = true;
    try {
      // shortcut: paginação por OFFSET; trocar por chave (added, position) se
      // ficar lenta em catálogos muito grandes.
      final page = await load(_offset);
      _offset += recentPageSize;
      _extras.addAll(page.titles);
      _ended = page.lidos < recentPageSize;
      return true;
    } finally {
      _busy = false;
    }
  }
}
