import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/profiles/profile.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/live_tv/live_highlight_banner.dart';
import 'package:iptv_player/ui/theme_settings_card.dart';
import 'package:iptv_player/ui/widgets/glass.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05, lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

/// Só o que o cartão "Tema" usa.
class _Fake extends ChangeNotifier implements AppController {
  @override
  bool minimalTheme = false;
  @override
  int accentTone = 0;
  final saved = <int>[];

  @override
  Future<void> setMinimalTheme(bool minimal) async {
    minimalTheme = minimal;
    AppColors.applyLook(minimal: minimal);
    notifyListeners();
  }

  @override
  void previewAccentTone(int tone) {
    accentTone = tone;
    AppColors.applyAccentTone(tone);
    notifyListeners();
  }

  @override
  Future<void> setAccentTone(int tone) async {
    previewAccentTone(tone);
    saved.add(tone);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    AppColors.resetProfileLook();
    AppColors.applyBrightness(false);
  });

  /// Fundos dos dois temas visuais, no claro e no escuro.
  List<Color> backgrounds() => [
        for (final minimal in [false, true])
          for (final dark in [false, true])
            () {
              AppColors.applyLook(minimal: minimal);
              AppColors.applyBrightness(dark);
              return AppColors.bg;
            }(),
      ];

  test('escala: a cor do perfil fica no meio e vai do claro ao escuro', () {
    for (final value in profileAccents) {
      final base = Color(value);
      expect(AccentScale.tone(base, 0), base);
      expect(AccentScale.tone(base, -100), AccentScale.lightEnd(base));
      expect(AccentScale.tone(base, 100), AccentScale.darkEnd(base));
      var before = double.infinity;
      for (var t = -100; t <= 100; t += AccentScale.step) {
        final now = AccentScale.tone(base, t).computeLuminance();
        expect(now, lessThanOrEqualTo(before), reason: '$base em $t');
        before = now;
      }
      // Há o que escolher dos dois lados.
      expect(AccentScale.lightEnd(base), isNot(base), reason: '$base');
      expect(AccentScale.darkEnd(base), isNot(base), reason: '$base');
    }
  });

  test('escala: para antes do branco e do preto e aparece nos dois temas', () {
    final grounds = backgrounds();
    for (final value in profileAccents) {
      for (var t = -100; t <= 100; t += AccentScale.step) {
        final tone = AccentScale.tone(Color(value), t);
        expect(tone, isNot(Colors.white));
        expect(tone, isNot(Colors.black));
        for (final ground in grounds) {
          expect(contrast(tone, ground), greaterThanOrEqualTo(1.9),
              reason: '$tone sobre $ground');
        }
        expect(contrast(AccentScale.on(tone), tone), greaterThanOrEqualTo(2.5),
            reason: 'texto sobre $tone');
      }
    }
  });

  test('texto sobre a cor: branco nas cores de perfil, escuro no tom claro', () {
    for (final value in profileAccents) {
      expect(AccentScale.on(Color(value)), Colors.white);
      expect(
        AccentScale.on(AccentScale.lightEnd(Color(value))),
        isNot(Colors.white),
      );
    }
  });

  test('o tom escolhido continua quando a cor do perfil muda', () {
    AppColors.applyAccent(const Color(0xFF3D6FD8));
    AppColors.applyAccentTone(-100);
    expect(AppColors.accent, AccentScale.lightEnd(const Color(0xFF3D6FD8)));
    AppColors.applyAccent(const Color(0xFF3B8F5A));
    expect(AppColors.accent, AccentScale.lightEnd(const Color(0xFF3B8F5A)));
    AppColors.applyAccentTone(500);
    expect(AppColors.accentTone, AccentScale.limit);
  });

  test('Minimalista: superfícies opacas e neutras; sair volta ao Liquid Glass',
      () {
    for (final dark in [false, true]) {
      AppColors.applyBrightness(dark);
      AppColors.applyLook(minimal: false);
      expect(AppGlass.surface.a, lessThan(1));

      AppColors.applyLook(minimal: true);
      for (final fill in [
        AppGlass.surface,
        AppGlass.dialog,
        AppGlass.fill(open: false),
        AppGlass.fill(open: true),
        AppGlass.field,
      ]) {
        expect(fill.a, 1);
      }
      expect(AppGlass.sheen.a, 0);
      for (final gray in [
        AppColors.bg,
        AppColors.surface,
        AppColors.border,
        AppColors.text,
      ]) {
        expect(gray.r, gray.g);
        expect(gray.g, gray.b);
      }
      expect(contrast(AppColors.textMuted, AppColors.surface),
          greaterThanOrEqualTo(4.5));
      final theme = buildTheme();
      expect(theme.colorScheme.onPrimary, AppColors.onAccent);
      expect(theme.colorScheme.surfaceContainerHighest, AppColors.hover);
    }
    AppColors.applyAccentTone(60);
    AppColors.resetProfileLook();
    expect(AppColors.minimal, isFalse);
    expect(AppColors.accent, AppColors.defaultAccent);
  });

  test('texto na cor de destaque nunca se lê pior que a cor do perfil', () {
    for (final value in profileAccents) {
      final base = Color(value);
      AppColors.applyAccent(base);
      for (final dark in [false, true]) {
        AppColors.applyBrightness(dark);
        final floor = contrast(base, AppColors.bg);
        for (var t = -100; t <= 100; t += AccentScale.step) {
          AppColors.applyAccentTone(t);
          expect(contrast(AppColors.accentInk, AppColors.bg),
              greaterThanOrEqualTo(floor),
              reason: '$base em $t');
        }
        // Para o lado que ganha contraste, o texto segue o tom.
        AppColors.applyAccentTone(dark ? -100 : 100);
        expect(AppColors.accentInk, AppColors.accent);
      }
    }
  });

  test('Minimalista: a cor como texto tem 4,5:1 em qualquer tom', () {
    AppColors.applyLook(minimal: true);
    for (final value in profileAccents) {
      AppColors.applyAccent(Color(value));
      for (final dark in [false, true]) {
        AppColors.applyBrightness(dark);
        for (var t = -100; t <= 100; t += AccentScale.step) {
          AppColors.applyAccentTone(t);
          for (final ground in [
            AppColors.bg,
            AppColors.surface,
            AppColors.accentSoft,
          ]) {
            expect(contrast(AppColors.accentInk, ground),
                greaterThanOrEqualTo(4.5),
                reason: 'cor $value em $t, escuro $dark, sobre $ground');
          }
        }
      }
    }
  });

  test('sobre vídeo e foto, o Minimalista clareia o tom escuro', () {
    const ground = Color(0xFF3A3A3A);
    for (final value in profileAccents) {
      AppColors.applyAccent(Color(value));
      for (var t = -100; t <= 100; t += AccentScale.step) {
        AppColors.applyAccentTone(t);
        AppColors.applyLook(minimal: true);
        expect(contrast(AppColors.accentOnMedia, ground),
            greaterThanOrEqualTo(4.5),
            reason: 'cor $value em $t');
        // O Liquid Glass fica como era.
        AppColors.applyLook(minimal: false);
        expect(AppColors.accentOnMedia, AppColors.accent);
      }
    }
  });

  test('Minimalista: o destaque da TV usa a superfície, sem degradê', () {
    for (final dark in [false, true]) {
      AppColors.applyBrightness(dark);
      AppColors.applyLook(minimal: true);
      for (final t in [0.0, 0.3, 0.55, 1.0]) {
        expect(highlightGradientAt(t), AppColors.surface);
      }
      AppColors.applyLook(minimal: false);
      expect(highlightGradientAt(0), isNot(highlightGradientAt(1)));
    }
  });

  testWidgets('trocar o tema não recria o conteúdo e desliga o desfoque',
      (tester) async {
    Widget app() => MaterialApp(
          home: Scaffold(
            body: GlassSurface(child: const TextField()),
          ),
        );
    BackdropFilter filter() => tester.widget(find.byType(BackdropFilter));

    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'abc');
    final before = tester.state(find.byType(TextField));
    expect(filter().enabled, isTrue);

    AppColors.applyLook(minimal: true);
    await tester.pumpWidget(app());
    expect(tester.state(find.byType(TextField)), same(before));
    expect(find.text('abc'), findsOneWidget);
    expect(filter().enabled, isFalse);
  });

  testWidgets('cartão Tema: troca o visual, escolhe o tom e volta à cor',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    addTearDown(fake.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppScope(controller: fake, child: const ThemeSettingsCard()),
      ),
    ));

    await tester.tap(find.text('Minimalista'));
    await tester.pumpAndSettle();
    expect(fake.minimalTheme, isTrue);

    expect(find.text('Cor de destaque: cor do perfil'), findsOneWidget);
    // Só aparece quando o tom sai do da cor do perfil.
    expect(find.text('Usar a cor do perfil'), findsNothing);

    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(slider.right - 12, slider.center.dy));
    await tester.pumpAndSettle();
    expect(fake.saved.last, AccentScale.limit);
    expect(find.text('Cor de destaque: 100 % mais escuro'), findsOneWidget);

    await tester.tap(find.text('Usar a cor do perfil'));
    await tester.pumpAndSettle();
    expect(fake.accentTone, 0);
    expect(fake.saved.last, 0);
  });
}
