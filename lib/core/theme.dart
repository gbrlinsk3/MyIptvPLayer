import 'package:flutter/material.dart';

/// Paleta do app. Os valores não são `const`: mudam com o tema (claro/escuro) e
/// com a cor de destaque do perfil. Escolhas de design iniciais, fáceis de ajustar.
class AppColors {
  // ---- tema claro ----
  static const _lightBg = Color(0xFFFAF9F5);
  static const _lightSidebar = Color(0xFFF4F2EA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightBorder = Color(0xFFE8E6DC);
  static const _lightHover = Color(0xFFF0EEE6);
  static const _lightText = Color(0xFF1F1E1D);
  static const _lightMuted = Color(0xFF6F6E69);
  static const _lightDanger = Color(0xFFB3261E);

  // ---- tema escuro ----
  static const _darkBg = Color(0xFF151413);
  static const _darkSidebar = Color(0xFF1C1B19);
  static const _darkSurface = Color(0xFF211F1D);
  static const _darkBorder = Color(0xFF34322E);
  static const _darkHover = Color(0xFF2A2825);
  static const _darkText = Color(0xFFF1EFE8);
  static const _darkMuted = Color(0xFFA3A096);
  static const _darkDanger = Color(0xFFEF6B62);

  /// Cor de destaque padrão (terracota).
  static const defaultAccent = Color(0xFFC6613F);

  static bool isDark = false;

  static Color bg = _lightBg;
  static Color sidebar = _lightSidebar;
  static Color surface = _lightSurface;
  static Color border = _lightBorder;
  static Color hover = _lightHover;
  static Color text = _lightText;
  static Color textMuted = _lightMuted;
  static Color danger = _lightDanger;

  /// Cor de destaque do perfil ativo.
  static Color accent = defaultAccent;
  static Color accentSoft = _soft(defaultAccent, false);

  static Color _soft(Color c, bool dark) =>
      dark ? Color.lerp(_darkSurface, c, 0.28)! : Color.lerp(Colors.white, c, 0.14)!;

  /// Aplica a cor do perfil. Chamar antes de reconstruir a interface.
  static void applyAccent(Color c) {
    accent = c;
    accentSoft = _soft(c, isDark);
  }

  static void resetAccent() => applyAccent(defaultAccent);

  /// Troca a paleta (claro/escuro). Chamar antes de reconstruir a interface.
  static void applyBrightness(bool dark) {
    isDark = dark;
    bg = dark ? _darkBg : _lightBg;
    sidebar = dark ? _darkSidebar : _lightSidebar;
    surface = dark ? _darkSurface : _lightSurface;
    border = dark ? _darkBorder : _lightBorder;
    hover = dark ? _darkHover : _lightHover;
    text = dark ? _darkText : _lightText;
    textMuted = dark ? _darkMuted : _lightMuted;
    danger = dark ? _darkDanger : _lightDanger;
    accentSoft = _soft(accent, dark);
  }
}

/// Fontes do app. Os arquivos .ttf ficam em assets/fonts/ (veja o README); se
/// não estiverem declarados no pubspec, o Flutter usa a fonte padrão.
/// Formato dos botões: `radius` 0 = cantos quadrados (padrão), 8 = arredondados.
/// Definido pelo ajuste "Formato dos botões" em Conta e ajustes → Personalização.
class AppShape {
  static double radius = 0;
  static bool get rounded => radius > 0;

  static RoundedRectangleBorder get button =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  static BorderRadius get borderRadius => BorderRadius.circular(radius);
}

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
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    outline: AppColors.border,
  );

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
      style: OutlinedButton.styleFrom(shape: AppShape.button),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: AppShape.button),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: AppShape.button),
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    // Caixas de dica ("Adicionar aos favoritos"...): cartão escuro com borda
    // fina e cantos arredondados, sempre legível (também no tema claro).
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 3),
      verticalOffset: 22,
      preferBelow: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF2202024),
        borderRadius: BorderRadius.circular(8),
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
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
