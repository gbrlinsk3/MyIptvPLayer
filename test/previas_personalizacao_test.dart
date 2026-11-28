import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_controller.dart';
import 'package:iptv_player/core/layout_metrics.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/data/live_highlight.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/downloads/downloads_controller.dart';
import 'package:iptv_player/library/library_import.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/personalization/preview_data.dart';
import 'package:iptv_player/ui/personalization/preview_hover.dart';
import 'package:iptv_player/ui/personalization/preview_look.dart';
import 'package:iptv_player/ui/personalization/preview_pane.dart';
import 'package:iptv_player/ui/personalization/preview_screen.dart';
import 'package:iptv_player/ui/widgets/app_backdrop.dart';
import 'package:iptv_player/ui/widgets/glass.dart';

class _CatalogoFalso extends ChangeNotifier implements CatalogController {
  @override
  int bannersRevision = 0;

  @override
  int progressRevision = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BaixadosFalsos extends ChangeNotifier implements DownloadsController {
  @override
  List<Never> get finished => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImportadosFalsos extends ChangeNotifier implements ImportsController {
  @override
  List<Never> get items => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AppFalso extends ChangeNotifier implements AppController {
  @override
  final _CatalogoFalso catalog = _CatalogoFalso();
  @override
  final _BaixadosFalsos downloads = _BaixadosFalsos();
  @override
  final _ImportadosFalsos imports = _ImportadosFalsos();

  @override
  ThemePref get themePref => ThemePref.light;
  @override
  bool get minimalTheme => true;
  @override
  bool get minimalBackground => false;
  @override
  int get accentTone => 0;
  @override
  String get backgroundImage => '';
  @override
  int get backgroundBlur => 2;
  @override
  int get uiScalePercent => 115;
  @override
  int get catalogWidth => CatalogWidth.fill;
  @override
  String get libraryOpenMode => 'panel';
  @override
  List<String> get highlightKeywords => const [];
  @override
  List<LiveChannel> get allChannels => const [];
  @override
  List<int> get recentChannels => const [];
  @override
  List<LiveCategory> get categories => const [];
  @override
  List<LiveHighlight> get highlights => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _look = PreviewLook(
  pref: ThemePref.light,
  dark: false,
  minimal: false,
  minimalBackground: false,
  rounded: true,
  tone: 0,
  background: '',
  blur: 2,
  scalePercent: 115,
  catalogWidth: CatalogWidth.fill,
);

final _data = PreviewData(
  banners: [
    for (var b = 0; b < 3; b++)
      (
        name: 'Banner com um nome bem comprido número $b',
        titles: [
          for (var i = 0; i < 3; i++)
            (name: 'Um título de filme muito comprido $i', image: null),
        ],
      ),
  ],
  continuing: [for (var i = 0; i < 8; i++) (name: 'Série $i', image: null)],
  movies: [for (var i = 0; i < 14; i++) (name: 'Filme $i', image: null)],
  series: [for (var i = 0; i < 14; i++) (name: 'Série $i', image: null)],
  recentChannels: [for (var i = 0; i < 14; i++) (name: 'Canal $i', image: null)],
  channelRows: [
    (
      name: 'Categoria',
      channels: [for (var i = 0; i < 14; i++) (name: 'Canal $i', image: null)],
    ),
  ],
  highlights: [
    (name: 'Esportes', channels: [(name: 'Canal de esporte', image: null)]),
  ],
  downloads: [(name: 'Filme baixado', image: null)],
);

void _janela(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('painel: prévia e comparação cabem na altura', () {
    for (final room in const [
      Size(1400, 1100),
      Size(900, 800),
      Size(500, 640),
    ]) {
      final m = previewPaneLayout(room, 16 / 9);
      expect(m.width, lessThanOrEqualTo(room.width));
      expect(m.screen, closeTo(m.width / (16 / 9), 0.001));
      // 44 das abas e dois vãos de 12.
      expect(68 + m.screen + m.compare, lessThanOrEqualTo(room.height + 0.001));
    }
  });

  test('tamanho da interface muda a janela virtual da prévia', () {
    expect(
      previewWindowSize(const Size(2000, 1000), 115, 115),
      const Size(2000, 1000),
    );
    expect(previewWindowSize(const Size(2000, 1000), 100, 150).width,
        closeTo(1333.33, 0.01));
  });

  testWidgets('as quatro abas desenham sem estourar, com e sem conteúdo',
      (tester) async {
    _janela(tester, const Size(1600, 1000));
    final looks = [
      _look,
      _look.copyWith(dark: true, minimal: true, rounded: false),
      _look.copyWith(scalePercent: 150, catalogWidth: 1200),
    ];
    for (final size in const [
      Size(2226, 1252),
      Size(1280, 800),
      Size(900, 560),
    ]) {
      for (final look in looks) {
        for (final data in [const PreviewData(), _data]) {
          for (final tab in PreviewTab.values) {
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: FittedBox(
                    child: PreviewScreen(
                      tab: tab,
                      look: look,
                      data: data,
                      size: size,
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull, reason: '$tab $size');
          }
        }
      }
    }
  });

  testWidgets('prévia não muda a paleta do app', (tester) async {
    final antes = (AppColors.isDark, AppColors.minimal, AppColors.accent);
    final outra = _look.copyWith(dark: !antes.$1, minimal: !antes.$2, tone: 60);
    expect(outra.palette.bg, isNot(_look.copyWith(dark: antes.$1).palette.bg));
    expect((AppColors.isDark, AppColors.minimal, AppColors.accent), antes);
  });

  testWidgets('painel: troca de aba e compara a opção sob o mouse',
      (tester) async {
    _janela(tester, const Size(1000, 900));
    final hover = ValueNotifier<CompareSpec?>(null);
    addTearDown(hover.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: _AppFalso(),
        child: MaterialApp(
          home: Scaffold(body: PreviewPane(hover: hover)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in PreviewTab.values) {
      expect(find.text(tab.label), findsWidgets);
    }
    expect(
      find.text('Passe o mouse sobre uma opção para comparar.'),
      findsOneWidget,
    );

    await tester.tap(find.text('TV ao vivo'));
    await tester.pumpAndSettle();
    expect(find.text('TV AO VIVO'), findsOneWidget);

    hover.value = CompareSpec(
      'formato.reto',
      'Formato: Quadrados',
      change: (l) => l.copyWith(rounded: !l.rounded),
    );
    await tester.pump();
    expect(find.text('Formato: Quadrados'), findsOneWidget);
    expect(find.text('Agora'), findsOneWidget);
    expect(find.text('Com esta opção'), findsOneWidget);

    hover.value = CompareSpec(
      'tamanho.115',
      'Tamanho da interface: 115 %',
      kind: CompareKind.screen,
      change: (l) => l.copyWith(scalePercent: 115),
    );
    await tester.pump();
    expect(find.text('Com esta opção (já em uso)'), findsOneWidget);

    for (final spec in const [
      CompareSpec('b.player', 'Reproduzir',
          kind: CompareKind.openMode, openMode: 'player'),
      CompareSpec('b.expanded', 'Expandido',
          kind: CompareKind.openMode, openMode: 'expanded'),
      CompareSpec('banners', 'Banners', kind: CompareKind.banners),
      CompareSpec('highlights', 'Destaques', kind: CompareKind.highlights),
    ]) {
      hover.value = spec;
      await tester.pump();
      expect(tester.takeException(), isNull, reason: spec.id);
      expect(
        find.text('Com esta opção'),
        spec.kind == CompareKind.openMode ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets('segmentos: a posição do mouse escolhe a opção', (tester) async {
    final hover = ValueNotifier<CompareSpec?>(null);
    addTearDown(hover.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewHover(
          notifier: hover,
          child: Center(
            child: HoverRange.segments(
              specs: const [
                CompareSpec('a', 'A'),
                CompareSpec('b', 'B'),
                CompareSpec('c', 'C'),
              ],
              child: const SizedBox(
                width: 300,
                height: 40,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
    final left = tester.getTopLeft(find.byType(ColoredBox).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final (x, id) in const [(20.0, 'a'), (150.0, 'b'), (299.0, 'c')]) {
      await mouse.moveTo(left + Offset(x, 20));
      await tester.pump();
      expect(hover.value?.id, id);
    }
    // Ao sair, a última comparação fica.
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hover.value?.id, 'c');
  });

  testWidgets('vidro sobre o fundo só desfoca ao vivo com imagem nítida',
      (tester) async {
    addTearDown(() => BackdropRender.sharp.value = false);
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: GlassSurface(overBackdrop: true, child: SizedBox(width: 40)),
    ));
    bool live() =>
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled;

    expect(live(), isFalse);
    BackdropRender.sharp.value = true;
    await tester.pump();
    expect(live(), isTrue);
  });
}
