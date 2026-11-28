import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'slider_shapes.dart';

/// Paleta do app. Os valores não são `const`: mudam com o tema (claro/escuro) e
/// com a cor de destaque do perfil. Escolhas de design iniciais, fáceis de ajustar.
class AppColors {
  // ---- Liquid Glass, claro ----
  static const _lightBg = Color(0xFFFAF9F5);
  static const _lightSidebar = Color(0xFFF4F2EA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightBorder = Color(0xFFE8E6DC);
  static const _lightHover = Color(0xFFF0EEE6);
  static const _lightText = Color(0xFF1F1E1D);
  static const _lightMuted = Color(0xFF51504B);
  static const _lightDanger = Color(0xFFB3261E);

  // ---- Liquid Glass, escuro ----
  static const _darkBg = Color(0xFF151413);
  static const _darkSidebar = Color(0xFF1C1B19);
  static const _darkSurface = Color(0xFF211F1D);
  static const _darkBorder = Color(0xFF34322E);
  static const _darkHover = Color(0xFF2A2825);
  static const _darkText = Color(0xFFF1EFE8);
  static const _darkMuted = Color(0xFFA3A096);
  static const _darkDanger = Color(0xFFEF6B62);

  // ---- Minimalista: cinzas neutros, claro ----
  static const _minLightBg = Color(0xFFFFFFFF);
  static const _minLightSidebar = Color(0xFFF7F7F7);
  static const _minLightSurface = Color(0xFFF5F5F5);
  static const _minLightBorder = Color(0xFFE2E2E2);
  static const _minLightHover = Color(0xFFEBEBEB);
  static const _minLightText = Color(0xFF171717);
  static const _minLightMuted = Color(0xFF525252);

  // ---- Minimalista: cinzas neutros, escuro ----
  static const _minDarkBg = Color(0xFF0F0F0F);
  static const _minDarkSidebar = Color(0xFF161616);
  static const _minDarkSurface = Color(0xFF1A1A1A);
  static const _minDarkBorder = Color(0xFF2E2E2E);
  static const _minDarkHover = Color(0xFF262626);
  static const _minDarkText = Color(0xFFF2F2F2);
  static const _minDarkMuted = Color(0xFFA3A3A3);

  /// Cor de destaque padrão (terracota).
  static const defaultAccent = Color(0xFFC6613F);

  static bool isDark = false;

  /// Tema visual (Personalização → Tema): `false` é o Liquid Glass.
  static bool minimal = false;

  static Color bg = _lightBg;
  static Color sidebar = _lightSidebar;
  static Color surface = _lightSurface;
  static Color border = _lightBorder;
  static Color hover = _lightHover;
  static Color text = _lightText;
  static Color textMuted = _lightMuted;
  static Color danger = _lightDanger;

  /// Cor do perfil ativo: o meio da escala de tons (ver [AccentScale]).
  static Color accentBase = defaultAccent;

  /// Posição na escala: -100 (mais claro) a 100 (mais escuro); 0 é a cor do
  /// perfil.
  static int accentTone = 0;

  /// Cor de destaque em uso: [accentBase] no tom [accentTone].
  static Color accent = defaultAccent;

  /// Texto e ícones desenhados sobre [accent].
  static Color onAccent = Colors.white;

  static Color accentSoft = _soft(defaultAccent, false);

  /// Destaque usado como **texto** ou ícone sobre o fundo do tema. Quando o
  /// tom escolhido se lê pior que a cor do perfil (claro no tema claro, escuro
  /// no escuro), parte da cor do perfil; botões cheios e progresso seguem o
  /// tom. No Minimalista ainda é ajustado até 4,5:1 no fundo, na superfície e
  /// no item marcado.
  static Color get accentInk {
    final picked = contrast(accent, bg) < contrast(accentBase, bg)
        ? accentBase
        : accent;
    if (!minimal) return picked;
    return _readable(picked, [bg, surface, accentSoft], text);
  }

  /// Destaque sobre vídeo, foto ou véu escuro, que não mudam com claro/escuro.
  /// No Minimalista, um tom escuro é clareado até aparecer.
  static Color get accentOnMedia => minimal
      ? _readable(accent, const [_mediaGround], Colors.white)
      : accent;

  /// Cinza que representa o pior caso de fundo escurecido sobre a imagem.
  static const _mediaGround = Color(0xFF3A3A3A);

  /// Contraste WCAG entre duas cores opacas.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05, lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }

  /// [color] levada em direção a [toward] só até ter 4,5:1 em todos os fundos.
  static Color _readable(Color color, List<Color> grounds, Color toward) {
    var result = color;
    for (var step = 1;
        step <= 20 && grounds.any((g) => contrast(result, g) < 4.5);
        step++) {
      result = Color.lerp(color, toward, step / 20)!;
    }
    return result;
  }

  static Color _soft(Color c, bool dark) => dark
      ? Color.lerp(minimal ? _minDarkSurface : _darkSurface, c, 0.28)!
      : Color.lerp(Colors.white, c, 0.14)!;

  static void _refreshAccent() {
    accent = AccentScale.tone(accentBase, accentTone);
    onAccent = AccentScale.on(accent);
    accentSoft = _soft(accent, isDark);
  }

  /// Aplica a cor do perfil. Chamar antes de reconstruir a interface.
  static void applyAccent(Color c) {
    accentBase = c;
    _refreshAccent();
  }

  static void applyAccentTone(int tone) {
    accentTone = AccentScale.clamp(tone);
    _refreshAccent();
  }

  /// Fora de um perfil: Liquid Glass com a cor padrão, no tom original.
  static void resetProfileLook() {
    accentTone = 0;
    applyLook(minimal: false);
    applyAccent(defaultAccent);
  }

  /// Troca o tema visual. Chamar antes de reconstruir a interface.
  static void applyLook({required bool minimal}) {
    AppColors.minimal = minimal;
    applyBrightness(isDark);
  }

  /// Lê as cores de **outra** aparência sem trocar a do app (prévias em
  /// Personalização): aplica, lê e restaura no mesmo instante, antes de
  /// qualquer desenho. [read] não pode guardar nada além das cores lidas.
  static T sample<T>({
    required bool dark,
    required bool minimal,
    required int tone,
    required T Function() read,
  }) {
    final wasDark = isDark, wasMinimal = AppColors.minimal, wasTone = accentTone;
    void apply(bool d, bool m, int t) {
      AppColors.minimal = m;
      isDark = d;
      applyAccentTone(t);
      applyBrightness(d);
    }

    apply(dark, minimal, tone);
    try {
      return read();
    } finally {
      apply(wasDark, wasMinimal, wasTone);
    }
  }

  /// Troca a paleta (claro/escuro). Chamar antes de reconstruir a interface.
  static void applyBrightness(bool dark) {
    isDark = dark;
    Color pick(Color light, Color darkColor, Color minLight, Color minDark) =>
        minimal ? (dark ? minDark : minLight) : (dark ? darkColor : light);
    bg = pick(_lightBg, _darkBg, _minLightBg, _minDarkBg);
    sidebar =
        pick(_lightSidebar, _darkSidebar, _minLightSidebar, _minDarkSidebar);
    surface =
        pick(_lightSurface, _darkSurface, _minLightSurface, _minDarkSurface);
    border = pick(_lightBorder, _darkBorder, _minLightBorder, _minDarkBorder);
    hover = pick(_lightHover, _darkHover, _minLightHover, _minDarkHover);
    text = pick(_lightText, _darkText, _minLightText, _minDarkText);
    textMuted = pick(_lightMuted, _darkMuted, _minLightMuted, _minDarkMuted);
    danger = dark ? _darkDanger : _lightDanger;
    accentSoft = _soft(accent, dark);
  }
}

/// Escala da cor de destaque: do claro ao escuro, com a cor do perfil no meio.
/// Para antes do branco e do preto: em cada ponta a cor ainda tem cerca de 2:1
/// de contraste com o fundo (o claro numa ponta, o escuro na outra), para a
/// mesma escolha aparecer nos dois temas.
class AccentScale {
  static const int limit = 100;

  /// Passo do controle deslizante.
  static const int step = 10;

  /// Luminância máxima (ponta clara) e mínima (ponta escura).
  static const double _lightest = 0.45;
  static const double _darkest = 0.064;

  static int clamp(int? tone) => (tone ?? 0).clamp(-limit, limit);

  static Color lightEnd(Color base) =>
      _toward(base, Colors.white, (l) => l <= _lightest);

  static Color darkEnd(Color base) =>
      _toward(base, Colors.black, (l) => l >= _darkest);

  /// O mais perto de [target] que [base] chega sem deixar de cumprir [ok].
  static Color _toward(Color base, Color target, bool Function(double) ok) {
    // Uma cor que já nasce além do limite não anda para esse lado.
    if (!ok(base.computeLuminance())) return base;
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 20; i++) {
      final mid = (low + high) / 2;
      if (ok(Color.lerp(base, target, mid)!.computeLuminance())) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Color.lerp(base, target, low)!;
  }

  static Color tone(Color base, int tone) {
    final t = clamp(tone);
    if (t == 0) return base;
    final end = t < 0 ? lightEnd(base) : darkEnd(base);
    return Color.lerp(base, end, t.abs() / limit)!;
  }

  /// Branco enquanto der leitura (as 8 cores de perfil continuam com texto
  /// branco); em tom claro, quase preto.
  static Color on(Color color) => 1.05 / (color.computeLuminance() + 0.05) >= 2.5
      ? Colors.white
      : const Color(0xFF171717);

  static String label(int tone) {
    final t = clamp(tone);
    if (t == 0) return 'cor do perfil';
    return '${t.abs()} % mais ${t < 0 ? 'claro' : 'escuro'}';
  }
}

/// Tratamento da imagem de fundo das telas principais, em cada tema.
class AppBackdropStyle {
  const AppBackdropStyle._({
    required this.blurFraction,
    required this.saturation,
    required this.veil,
    required this.base,
  });

  /// Desfoque (desvio) como fração da largura da imagem.
  final double blurFraction;
  final double saturation;

  /// Camada sobre a imagem, para os textos continuarem legíveis.
  final Color veil;

  /// Cor por baixo da imagem (aparece se ela tiver transparência).
  final Color base;

  static const dark = AppBackdropStyle._(
    blurFraction: 0.0126,
    saturation: 1.15,
    veil: Color(0x9E110F0E), // 62 %
    base: AppColors._darkBg,
  );

  static const light = AppBackdropStyle._(
    blurFraction: 0.0045,
    saturation: 1.35,
    veil: Color(0x4DF7F5F0), // 30 %
    base: AppColors._lightBg,
  );

  static AppBackdropStyle of(bool isDark) => isDark ? dark : light;

  /// Clareamento das sombras usado no tema claro (canal de 0 a 255).
  static int lift(int v) =>
      (80 + 175 * math.pow(v / 255, 0.55)).round().clamp(0, 255);

  /// Contenção das partes claras no tema escuro (brilho de 0 a 255): sem ela,
  /// uma imagem clara vira cinza médio sob o véu e o texto cinza some. Branco
  /// termina em torno de 55 depois do véu (4,5:1 com `textMuted`).
  static int tame(int y) => y <= 60 ? y : (60 + (y - 60) * 0.3).round();
}

/// Vidro (acrílico) do app, usado pelo `GlassSurface`. Barra lateral recolhida:
/// só tem o fundo atrás e é bem translúcida; aberta (e os menus) fica por cima
/// do conteúdo e precisa de mais preenchimento para o texto continuar legível.
class AppGlass {
  static bool get _d => AppColors.isDark;

  /// No Minimalista não há vidro: cada medida daqui vira a versão sólida.
  static bool get _m => AppColors.minimal;

  static const Color _none = Color(0x00000000);

  static Color fill({required bool open}) => _m
      ? AppColors.surface
      : _d
          ? Color.fromRGBO(34, 31, 30, open ? 0.80 : 0.46)
          : Color.fromRGBO(255, 255, 255, open ? 0.76 : 0.18);

  static double blur({required bool open}) =>
      _m ? 0 : (_d ? 28 : (open ? 24 : 4.5));

  /// Preenchimento das barras, painéis e botões. No claro é mais fechado que
  /// o da barra recolhida para o texto cinza continuar legível.
  static Color get surface => _m
      ? AppColors.surface
      : _d
          ? const Color.fromRGBO(34, 31, 30, 0.48)
          : const Color.fromRGBO(255, 255, 255, 0.55);

  /// Diálogos, aviso de atualização e outros cartões que flutuam com bastante
  /// texto: mais fechado que o dos menus.
  static Color get dialog => _m
      ? AppColors.surface
      : _d
          ? const Color.fromRGBO(34, 31, 30, 0.86)
          : const Color.fromRGBO(255, 255, 255, 0.84);

  /// [surface] com o realce do mouse.
  static Color get surfaceHover => Color.alphaBlend(hover, surface);

  /// Campos de texto (dentro de um painel de vidro não podem ser opacos).
  static Color get field => _m
      ? AppColors.bg
      : Color.fromRGBO(255, 255, 255, _d ? 0.04 : 0.40);

  static double get saturation => _m ? 1 : (_d ? 1.9 : 2.0);
  static Color get edge => _m
      ? AppColors.border
      : Color.fromRGBO(255, 255, 255, _d ? 0.12 : 0.75);
  static Color get sheen =>
      _m ? _none : Color.fromRGBO(255, 255, 255, _d ? 0.06 : 0.14);

  /// Contorno escuro fino por fora (só no claro).
  static Color get ring =>
      _m ? _none : Color.fromRGBO(20, 18, 16, _d ? 0 : 0.08);
  static Color get shadow => Color.fromRGBO(
        0,
        0,
        0,
        _m ? (_d ? 0.40 : 0.10) : (_d ? 0.34 : 0.22),
      );

  static Color get line => _m
      ? AppColors.border
      : (_d ? const Color(0x1FFFFFFF) : const Color(0x1A141210));

  /// Item marcado (barra lateral, menus). No Minimalista leva a cor de destaque.
  static Color get selected => _m
      ? AppColors.accentSoft
      : Color.fromRGBO(255, 255, 255, _d ? 0.14 : 0.72);
  static Color get selectedEdge => _m ? _none : line;
  static Color get hover => _m
      ? AppColors.text.withValues(alpha: 0.06)
      : Color.fromRGBO(255, 255, 255, _d ? 0.08 : 0.40);
}

/// Formato da interface (ajuste "Formato da interface" em Conta e ajustes →
/// Personalização): as medidas de canto do app saem daqui.
///
/// - Quadrado: tudo reto.
/// - Arredondado: [control] em pílula (vira círculo numa peça quadrada),
///   [card] com 14 e [panel] com 22.
///
/// Só o círculo de carregamento fica redondo nos dois formatos. Os valores são
/// estáticos: quem troca o formato redesenha a árvore inteira (ver
/// `RebuildOnChange`), e um `CustomPainter` que os use precisa comparar
/// [rounded] no `shouldRepaint`.
class AppShape {
  static bool rounded = true;

  static const double _pill = 999;
  static const double _card = 14;
  static const double _panel = 22;
  static const double _thumb = 8;

  /// Medida própria de uma peça (ex.: banner); zero no formato quadrado.
  static double r(double value) => rounded ? value : 0;

  /// Botões, campos, abas, itens de menu, chips e barras de progresso; também
  /// setas, favorito, bolinhas, interruptores e controles deslizantes.
  static double get controlRadius => r(_pill);

  /// Pôsteres, cartões, linhas, menus suspensos e avisos.
  static double get cardRadius => r(_card);

  /// Painéis, barra lateral, gavetas e diálogos.
  static double get panelRadius => r(_panel);

  static BorderRadius get control => BorderRadius.circular(controlRadius);
  static BorderRadius get card => BorderRadius.circular(cardRadius);
  static BorderRadius get panel => BorderRadius.circular(panelRadius);

  /// Miniatura pequena dentro de uma linha (capa, logo, quadro de episódio):
  /// com o raio de cartão ela viraria quase uma cápsula.
  static BorderRadius get thumb => BorderRadius.circular(r(_thumb));

  /// Recorte por dentro da borda de um cartão: o raio do cartão menos a borda.
  static BorderRadius inset(double border) =>
      BorderRadius.circular(r(_card - border));

  /// Esqueleto de carregamento: o baixo imita uma linha de texto ou um botão;
  /// o alto (ou sem altura própria), um pôster ou cartão.
  static BorderRadius skeleton(double? height) =>
      height != null && height <= 48 ? control : card;

  static RoundedRectangleBorder get button =>
      RoundedRectangleBorder(borderRadius: control);
  static RoundedRectangleBorder get cardBorder =>
      RoundedRectangleBorder(borderRadius: card);
  static RoundedRectangleBorder get panelBorder =>
      RoundedRectangleBorder(borderRadius: panel);
}

/// Fontes do app. Os arquivos .ttf ficam em assets/fonts/ (veja o README); se
/// não estiverem declarados no pubspec, o Flutter usa a fonte padrão.
class AppFonts {
  /// Texto da interface.
  static const body = 'Comfortaa';

  /// Títulos grandes (banner, seções).
  static const display = 'ArialNarrow7';

  static TextStyle title(double size, {Color? color, double spacing = 0.5}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: spacing,
        height: 1.05,
        color: color ?? AppColors.text,
      );
}

ThemeData buildTheme() {
  final dark = AppColors.isDark;
  var scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    outline: AppColors.border,
  );
  // O Material tinge os cinzas com a cor de destaque; no Minimalista eles são
  // neutros.
  if (AppColors.minimal) {
    scheme = scheme.copyWith(
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.bg,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surface,
      surfaceContainerHighest: AppColors.hover,
      onSurfaceVariant: AppColors.textMuted,
      outlineVariant: AppColors.border,
      secondaryContainer: AppColors.accentSoft,
      onSecondaryContainer: AppColors.text,
    );
  }

  // Cor da ação do aviso: o destaque, clareado/escurecido até ter contraste
  // mínimo de 4,5:1 sobre o fundo do aviso.
  final snackBg = AppColors.surface;
  double contraste(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  var snackAction = AppColors.accent;
  for (var i = 1; i <= 10 && contraste(snackAction, snackBg) < 4.5; i++) {
    snackAction = Color.lerp(
      AppColors.accent,
      dark ? Colors.white : Colors.black,
      i * 0.1,
    )!;
  }

  // Só muda o texto dos botões quando o tom perderia leitura.
  final ink =
      AppColors.accentInk == AppColors.accent ? null : AppColors.accentInk;

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: AppShape.button),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: AppShape.button),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: AppShape.button,
        foregroundColor: ink,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: AppShape.button,
        foregroundColor: ink,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: AppShape.button),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: AppShape.button),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: AppShape.button,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(shape: AppShape.button),
    ),
    chipTheme: ChipThemeData(shape: AppShape.button),
    checkboxTheme: CheckboxThemeData(shape: AppShape.button),
    listTileTheme: ListTileThemeData(shape: AppShape.cardBorder),
    cardTheme: CardThemeData(shape: AppShape.cardBorder),
    popupMenuTheme: PopupMenuThemeData(shape: AppShape.cardBorder),
    menuTheme: MenuThemeData(
      style: MenuStyle(shape: WidgetStatePropertyAll(AppShape.cardBorder)),
    ),
    dialogTheme: DialogThemeData(shape: AppShape.panelBorder),
    bottomSheetTheme: BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShape.panelRadius),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      borderRadius: AppShape.control,
    ),
    sliderTheme: SliderThemeData(
      thumbShape: const AppSliderThumbShape(),
      overlayShape: const AppSliderOverlayShape(),
      trackShape: AppShape.rounded
          ? const RoundedRectSliderTrackShape()
          : const RectangularSliderTrackShape(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: snackBg,
      contentTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.text,
        fontSize: 13.5,
      ),
      actionTextColor: snackAction,
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.card,
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    // Caixas de dica ("Adicionar aos favoritos"...): cartão escuro com borda
    // fina, sempre legível (também no tema claro).
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 3),
      verticalOffset: 22,
      preferBelow: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF2202024),
        borderRadius: AppShape.card,
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );
}

/// Decoração padrão dos campos de texto (definida aqui, e não no tema, para
/// não depender de classes de tema que mudam entre versões do Flutter).
InputDecoration fieldDecoration({
  String? label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  // Campo de várias linhas: em pílula viraria uma cápsula alta.
  bool multiline = false,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: multiline ? AppShape.card : AppShape.control,
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: AppGlass.field,
    // Na pílula o texto precisa de mais folga para não encostar na curva.
    contentPadding: EdgeInsets.symmetric(
      horizontal: AppShape.rounded && !multiline ? 18 : 12,
      vertical: 12,
    ),
    border: border(AppColors.border),
    enabledBorder: border(AppColors.border),
    focusedBorder: border(AppColors.accent),
  );
}

/// Escolha de tema do perfil. `system` segue o claro/escuro do Windows;
/// `auto` é por horário: claro das 9h às 17h, escuro das 17h às 9h.
enum ThemePref { light, dark, system, auto }

/// Se o tema efetivo é escuro para a escolha [pref] (usa [now] só no `auto`).
bool resolveDark(ThemePref pref, {required bool platformDark, DateTime? now}) {
  switch (pref) {
    case ThemePref.light:
      return false;
    case ThemePref.dark:
      return true;
    case ThemePref.system:
      return platformDark;
    case ThemePref.auto:
      final h = (now ?? DateTime.now()).hour;
      return h < 9 || h >= 17;
  }
}

/// Sombra de textos escritos direto sobre o vídeo: mantém a leitura em imagem
/// clara sem escurecer o vídeo.
const List<Shadow> videoTextShadows = [
  Shadow(color: Color(0xE6000000), blurRadius: 3, offset: Offset(0, 1)),
  Shadow(color: Color(0x99000000), blurRadius: 10),
];
