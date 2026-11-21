import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/channel_groups.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/ui/live_tv/live_recent_card.dart';

void main() {
  var id = 1;
  // Sem icon: o teste não depende de rede.
  LiveChannel canal(String nome) =>
      LiveChannel(streamId: id++, name: nome, categoryId: '1');

  Future<void> monta(
    WidgetTester tester,
    List<String> nomes, {
    bool favorite = false,
    bool recent = true,
    bool expanded = true,
    VoidCallback? onTap,
    VoidCallback? onToggleFavorite,
    VoidCallback? onRemoveRecent,
  }) async {
    final g = groupChannels(nomes.map(canal)).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiveRecentCard(
              group: g,
              current: false,
              favorite: favorite,
              recent: recent,
              expanded: expanded,
              onTap: onTap ?? () {},
              onToggleFavorite: onToggleFavorite,
              onRemoveRecent: onRemoveRecent,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('expandido renderiza 256x144 com versões, sem exceção',
      (tester) async {
    await monta(tester, ['Canal FHD', 'Canal HD', 'Canal SD [ALT]']);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LiveRecentCard)),
        const Size(LiveRecentCard.expandedWidth, LiveRecentCard.height));
    expect(find.text('Canal'), findsOneWidget);
    expect(find.text('FHD · HD · SD'), findsOneWidget);
  });

  testWidgets('compacto renderiza 112x144 sem versões e sem X', (tester) async {
    await monta(tester, ['Canal FHD', 'Canal HD'], expanded: false);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LiveRecentCard)),
        const Size(LiveRecentCard.collapsedWidth, LiveRecentCard.height));
    expect(find.text('Canal'), findsOneWidget);
    expect(find.text('FHD · HD'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('compacto favorito mostra só o coração indicador',
      (tester) async {
    var favs = 0;
    var taps = 0;
    await monta(
      tester,
      ['Canal FHD'],
      favorite: true,
      expanded: false,
      onTap: () => taps++,
      onToggleFavorite: () => favs++,
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    // O indicador não tem ação: tocar nele toca o canal.
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(favs, 0);
    expect(taps, 1);
  });

  testWidgets('animação de compacto para expandido não estoura',
      (tester) async {
    await monta(tester, ['Canal FHD', 'Canal HD', 'Canal SD'],
        favorite: true, expanded: false);
    await monta(tester, ['Canal FHD', 'Canal HD', 'Canal SD'],
        favorite: true, expanded: true);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(find.byType(LiveRecentCard)),
        const Size(LiveRecentCard.expandedWidth, LiveRecentCard.height));
    // E de volta.
    await monta(tester, ['Canal FHD', 'Canal HD', 'Canal SD'],
        favorite: true, expanded: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(find.byType(LiveRecentCard)),
        const Size(LiveRecentCard.collapsedWidth, LiveRecentCard.height));
  });

  testWidgets('só Padrão não mostra linha de versões', (tester) async {
    await monta(tester, ['Canal']);
    expect(tester.takeException(), isNull);
    expect(find.text('Padrão'), findsNothing);
  });

  testWidgets('favorito mostra coração e não X', (tester) async {
    await monta(tester, ['Canal FHD'], favorite: true, recent: true);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('só recente mostra X e não coração', (tester) async {
    await monta(tester, ['Canal FHD'], favorite: false, recent: true);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('tocar no X chama onRemoveRecent e não onTap', (tester) async {
    var taps = 0;
    var removes = 0;
    await monta(
      tester,
      ['Canal FHD'],
      onTap: () => taps++,
      onRemoveRecent: () => removes++,
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(removes, 1);
    expect(taps, 0);
  });

  testWidgets('tocar no coração chama onToggleFavorite e não onTap',
      (tester) async {
    var taps = 0;
    var favs = 0;
    await monta(
      tester,
      ['Canal FHD'],
      favorite: true,
      onTap: () => taps++,
      onToggleFavorite: () => favs++,
    );
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(favs, 1);
    expect(taps, 0);
  });

  testWidgets('tocar no cartão chama onTap', (tester) async {
    var taps = 0;
    await monta(tester, ['Canal FHD'], onTap: () => taps++);
    await tester.tap(find.text('Canal'));
    await tester.pump();
    expect(taps, 1);
  });
}
