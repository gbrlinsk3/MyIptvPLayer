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
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
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
