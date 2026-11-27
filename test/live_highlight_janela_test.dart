import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/live_highlight.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/live_tv/live_highlight_banner.dart';

Future<void> _fonte(String familia, String caminho) => (FontLoader(familia)
      ..addFont(
        File(caminho).readAsBytes().then((b) => ByteData.view(b.buffer)),
      ))
    .load();

/// A linha de atalhos sob o banner lê o controller; aqui, tudo vazio.
class _AppFalso extends ChangeNotifier implements AppController {
  @override
  List<List<String>> get miniBanners => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('destaque da TV não estoura em janela', (t) async {
    // Fontes do app: a de teste é bem mais larga e mediria outra coisa.
    await t.runAsync(() async {
      await _fonte('Comfortaa', 'assets/fonts/Comfortaa-Regular.ttf');
      await _fonte('ArialNarrow7', 'assets/fonts/ArialNarrow7.ttf');
    });
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final destaque = LiveHighlight(
      keyword: 'eventos',
      categories: const [
        LiveCategory(id: '1', name: 'EVENTOS EM DESTAQUE'),
        LiveCategory(id: '2', name: 'EVENTOS PPV'),
      ],
      channels: [
        for (var i = 0; i < 12; i++)
          LiveChannel(streamId: i, name: '17:00 Jogo $i', categoryId: '1'),
      ],
    );
    for (final largura in [880.0, 960.0, 1038.0, 1108.0, 1180.0, 1600.0]) {
      t.view.physicalSize = Size(largura, 700);
      await t.pumpWidget(
        AppScope(
          controller: _AppFalso(),
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Comfortaa'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LiveHighlightBanner(
                  highlights: [destaque],
                  onOpen: (_, _) {},
                  onSeeCategory: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull, reason: 'largura $largura');
      expect(find.text('Ver todos'), findsOneWidget);
    }
  });
}
