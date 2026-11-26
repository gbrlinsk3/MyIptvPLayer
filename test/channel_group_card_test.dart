import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/channel_groups.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/ui/live_tv/channel_group_card.dart';
import 'package:iptv_player/ui/widgets/click_spark.dart';
import 'package:iptv_player/ui/widgets/spotlight.dart';

void main() {
  var id = 1;
  // Sem icon: o teste não depende de rede.
  LiveChannel canal(String nome) =>
      LiveChannel(streamId: id++, name: nome, categoryId: '1');

  Future<void> monta(
    WidgetTester tester,
    List<String> nomes, {
    bool favorite = false,
    VoidCallback? onTap,
    VoidCallback? onToggleFavorite,
  }) async {
    final g = groupChannels(nomes.map(canal)).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: ChannelGroupCard.width,
              height: ChannelGroupCard.height,
              child: ChannelGroupCard(
                group: g,
                onTap: onTap ?? () {},
                favorite: favorite,
                onToggleFavorite: onToggleFavorite,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('5 versões mostram FHD, HD, SD sem exceção', (tester) async {
    await monta(tester, [
      'Canal FHD',
      'Canal HD',
      'Canal SD',
      'Canal FHD [ALT]',
      'Canal HD [ALT]',
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('FHD'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    expect(find.text('SD'), findsOneWidget);
    expect(find.text('Padrão'), findsNothing);
  });

  testWidgets('1 versão sem marca não mostra Padrão', (tester) async {
    await monta(tester, ['Canal']);
    expect(tester.takeException(), isNull);
    expect(find.text('Padrão'), findsNothing);
  });

  testWidgets('largura do cartão é 240', (tester) async {
    await monta(tester, ['Canal FHD']);
    expect(tester.getSize(find.byType(ChannelGroupCard)).width, 240);
  });

  testWidgets('Favoritar chama onToggleFavorite e não onTap', (tester) async {
    var taps = 0;
    var favs = 0;
    await monta(
      tester,
      ['Canal FHD', 'Canal HD'],
      onTap: () => taps++,
      onToggleFavorite: () => favs++,
    );
    expect(find.byIcon(Icons.favorite), findsNothing);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(favs, 1);
    expect(taps, 0);

    await tester.tap(find.text('Canal'));
    await tester.pump();
    expect(taps, 1);
    expect(favs, 1);
  });

  testWidgets('favoritar solta faíscas; desfavoritar não', (tester) async {
    await monta(tester, ['Canal FHD'], onToggleFavorite: () {});
    expect(ClickSpark.ativas, 0);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(ClickSpark.ativas, 1);
    await tester.pumpAndSettle();
    expect(ClickSpark.ativas, 0);
    expect(tester.takeException(), isNull);

    await monta(tester, ['Canal FHD'], favorite: true, onToggleFavorite: () {});
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(ClickSpark.ativas, 0);
  });

  testWidgets('favoritar com o toque ainda chama o callback uma vez', (tester) async {
    var favs = 0;
    await monta(tester, ['Canal FHD'], onToggleFavorite: () => favs++);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    expect(favs, 1);
  });

  testWidgets('o cartão tem facho (Spotlight) que não rouba o toque', (tester) async {
    var taps = 0;
    await monta(tester, ['Canal FHD'], onTap: () => taps++);
    expect(find.byType(SpotlightCard), findsOneWidget);
    final gesto = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesto.addPointer(location: tester.getCenter(find.byType(ChannelGroupCard)));
    await tester.pump();
    await tester.tap(find.text('Canal'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorito mostra coração cheio; só ícone, sem texto de botão', (tester) async {
    await monta(tester, ['Canal FHD'], favorite: true);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.text('Favorito'), findsNothing);
    expect(find.text('Favoritar'), findsNothing);
  });

  testWidgets('nome longo usa até 3 linhas, sem estourar o cartão', (tester) async {
    const nome = '(01)   ⏰ 14:45 • Borussia Mönchengladbach x Eintracht Frankfurt am Main •';
    await monta(tester, ['$nome FHD', '$nome HD']);
    expect(tester.takeException(), isNull);
    expect(find.text('Clique para assistir'), findsNothing);
    expect(find.text('FHD'), findsOneWidget);
    final base = parseChannelName('$nome FHD').base;
    final texto = tester.widget<Text>(find.text(shortChannelName(base)));
    expect(texto.maxLines, 3);
  });

  test('shortChannelName só encurta os canais de evento', () {
    expect(
      shortChannelName('(01)   ⏰ 14:45 • Bodø/Glimt x LASK Linz •'),
      '14:45 • Bodø/Glimt x LASK Linz',
    );
    expect(shortChannelName('(10) ⏰'), '(10) ⏰');
    expect(shortChannelName('Canal (2) ⏰ HD'), 'Canal (2) ⏰ HD');
    expect(shortChannelName('Globo SP •'), 'Globo SP •');
  });

  testWidgets('o coração fica sobre a imagem, acima do corpo', (tester) async {
    await monta(tester, ['Canal FHD'], onToggleFavorite: () {});
    final cartao = tester.getTopLeft(find.byType(ChannelGroupCard));
    final coracao = tester.getCenter(find.byIcon(Icons.favorite_border));
    final dy = coracao.dy - cartao.dy;
    expect(dy, greaterThan(0));
    expect(dy, lessThan(ChannelGroupCard.imageHeight));
  });
}
