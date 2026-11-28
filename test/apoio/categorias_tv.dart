// Apoio dos testes das categorias da gaveta da TV ao vivo.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/epg/epg_controller.dart';
import 'package:iptv_player/playback/playback_controller.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/live_tv/category_section.dart';
import 'package:iptv_player/ui/live_tv/live_drawer.dart';
import 'package:iptv_player/ui/widgets/ui_scale.dart';

class _SemPlayer implements PlaybackController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const nomesPadrao = ['Abertos', 'Esportes', 'Filmes', 'Notícias'];

/// Mais categorias do que cabem na tela.
final muitasCategorias = [for (var i = 0; i < 40; i++) 'Categoria $i'];

late Directory _pasta;

/// Uma pasta nova por teste, no lugar da pasta de dados do app.
void prepararPasta() {
  setUp(() async {
    _pasta = await Directory.systemTemp.createTemp('mip_categorias');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => _pasta.path,
        );
  });
}

/// Um perfil com quatro categorias de dois canais cada.
Future<(AppDatabase, AppController)> abrir(
  WidgetTester tester, {
  List<String> nomes = nomesPadrao,
}) async {
  return (await tester.runAsync(() async {
    final db = await AppDatabase.open('${_pasta.path}/perfil.db');
    if (await db.loadAccount() == null) {
      await db.saveAccount(
        const SavedAccount(
          server: 'http://127.0.0.1:1',
          username: 'u',
          password: 's',
        ),
      );
      await db.replaceCatalog(
        [
          for (var i = 0; i < nomes.length; i++)
            LiveCategory(id: '${i + 1}', name: nomes[i]),
        ],
        [
          for (var i = 0; i < nomes.length; i++)
            for (var j = 0; j < 2; j++)
              LiveChannel(
                streamId: i * 10 + j,
                name: 'Canal ${nomes[i]} $j',
                categoryId: '${i + 1}',
              ),
        ],
      );
    }
    final app = AppController(db, _SemPlayer(), EpgController(db));
    await app.init();
    // A atualização ao abrir falha na hora (nada escuta na porta 1).
    for (var i = 0; i < 400 && app.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return (db, app);
  }))!;
}

Future<void> montar(
  WidgetTester tester,
  AppController app, {
  double escala = 1,
  Size janela = const Size(1400, 900),
  bool sobreVideo = false,
}) async {
  tester.view.physicalSize = janela;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: MaterialApp(
        builder: (context, child) => UiScale(scale: escala, child: child!),
        home: Scaffold(
          body: LiveDrawer(
            onOpen: (_, _) {},
            closable: sobreVideo,
            watchPrograms: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Os títulos de categoria, de cima para baixo.
List<String> titulos(WidgetTester tester) {
  final headers = tester
      .widgetList<CategoryHeader>(find.byType(CategoryHeader))
      .toList();
  headers.sort((a, b) {
    double y(CategoryHeader h) => tester.getTopLeft(find.byWidget(h)).dy;
    return y(a).compareTo(y(b));
  });
  return [for (final h in headers) h.title];
}

Finder titulo(String nome) =>
    find.byWidgetPredicate((w) => w is CategoryHeader && w.title == nome);

/// Clica no título, longe do coração.
Future<void> clicar(WidgetTester tester, String nome) async {
  final area = tester.getRect(titulo(nome));
  await tester.tapAt(Offset(area.right - 300, area.center.dy));
  await tester.pumpAndSettle();
}

Future<void> favoritar(WidgetTester tester, String nome) async {
  await tester.tap(
    find.descendant(of: titulo(nome), matching: find.byType(IconButton)),
  );
  await tester.pumpAndSettle();
}

/// Segura o título [nome] e solta [dy] pontos de tela abaixo. Devolve o
/// quanto a peça arrastada andou antes de soltar.
Future<double> arrastar(WidgetTester tester, String nome, double dy) async {
  final area = tester.getRect(titulo(nome));
  final inicio = Offset(area.left + 120, area.center.dy);
  final gesto = await tester.startGesture(
    inicio,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(
    CategoryHeader.holdDelay + const Duration(milliseconds: 50),
  );
  await tester.pump();
  final peca = find.byType(CategoryDragGhost);
  expect(peca, findsOneWidget);
  final antes = tester.getTopLeft(peca).dy;
  await gesto.moveTo(inicio + Offset(0, dy));
  await tester.pump();
  final andou = tester.getTopLeft(peca).dy - antes;
  await tester.pump(const Duration(milliseconds: 300));
  await gesto.up();
  await tester.pumpAndSettle();
  expect(peca, findsNothing);
  return andou;
}

Future<void> fechar(WidgetTester tester, AppController app) async {
  // Deixa as gravações terminarem antes de descartar.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  app.dispose();
}
