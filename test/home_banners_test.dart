import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/home_banners.dart';

void main() {
  test('perfil novo (sem categorias marcadas): 3 banners padrão', () {
    final d = BannerConfig.defaults(const {});
    expect([for (final b in d) b.name],
        ['Filmes novos', 'Séries novas', 'Adicionados recentemente']);
    expect([for (final b in d) b.source], [
      BannerSource.newMovies,
      BannerSource.newSeries,
      BannerSource.newMix,
    ]);
  });

  test('configuração salva vazia ou inválida cai no padrão', () {
    expect(BannerConfig.decode(''), isEmpty);
    expect(BannerConfig.decode('lixo'), isEmpty);
    expect(BannerConfig.decode('[]'), isEmpty);
  });
}
