import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';

/// Uma combinação dos ajustes de Personalização: a atual ou a de uma opção sob
/// o mouse. As prévias são desenhadas só com o que está aqui.
@immutable
class PreviewLook {
  const PreviewLook({
    required this.pref,
    required this.dark,
    required this.minimal,
    required this.minimalBackground,
    required this.rounded,
    required this.tone,
    required this.background,
    required this.blur,
    required this.scalePercent,
    required this.catalogWidth,
  });

  factory PreviewLook.of(AppController c) => PreviewLook(
        pref: c.themePref,
        dark: AppColors.isDark,
        minimal: c.minimalTheme,
        minimalBackground: c.minimalBackground,
        rounded: AppShape.rounded,
        tone: c.accentTone,
        background: c.backgroundImage,
        blur: c.backgroundBlur,
        scalePercent: c.uiScalePercent,
        catalogWidth: c.catalogWidth,
      );

  final ThemePref pref;
  final bool dark;
  final bool minimal;
  final bool minimalBackground;
  final bool rounded;
  final int tone;

  /// Imagem escolhida no PC (vazio = a do app).
  final String background;
  final int blur;
  final int scalePercent;

  /// Ver [CatalogWidth]: 0 = preenchido.
  final int catalogWidth;

  bool get showImage => !minimal || minimalBackground;

  PreviewLook copyWith({
    ThemePref? pref,
    bool? dark,
    bool? minimal,
    bool? minimalBackground,
    bool? rounded,
    int? tone,
    String? background,
    int? blur,
    int? scalePercent,
    int? catalogWidth,
  }) =>
      PreviewLook(
        pref: pref ?? this.pref,
        dark: dark ?? this.dark,
        minimal: minimal ?? this.minimal,
        minimalBackground: minimalBackground ?? this.minimalBackground,
        rounded: rounded ?? this.rounded,
        tone: tone ?? this.tone,
        background: background ?? this.background,
        blur: blur ?? this.blur,
        scalePercent: scalePercent ?? this.scalePercent,
        catalogWidth: catalogWidth ?? this.catalogWidth,
      );

  /// Canto de [value] no formato desta combinação.
  BorderRadius radius(double value) =>
      BorderRadius.circular(rounded ? value : 0);

  BorderRadius get control => radius(999);
  BorderRadius get card => radius(14);
  BorderRadius get panel => radius(22);

  PreviewPalette get palette => PreviewPalette.of(this);

  @override
  bool operator ==(Object other) =>
      other is PreviewLook &&
      other.pref == pref &&
      other.dark == dark &&
      other.minimal == minimal &&
      other.minimalBackground == minimalBackground &&
      other.rounded == rounded &&
      other.tone == tone &&
      other.background == background &&
      other.blur == blur &&
      other.scalePercent == scalePercent &&
      other.catalogWidth == catalogWidth;

  @override
  int get hashCode => Object.hash(pref, dark, minimal, minimalBackground,
      rounded, tone, background, blur, scalePercent, catalogWidth);
}

/// As cores de uma [PreviewLook], lidas da própria paleta do app. O vidro das
/// prévias não desfoca ao vivo: o fundo atrás já vem desfocado.
@immutable
class PreviewPalette {
  const PreviewPalette._({
    required this.bg,
    required this.surface,
    required this.border,
    required this.hover,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentInk,
    required this.onMedia,
    required this.barFill,
    required this.panelFill,
    required this.edge,
    required this.selected,
    required this.selectedEdge,
    required this.line,
  });

  static PreviewPalette of(PreviewLook look) => AppColors.sample(
        dark: look.dark,
        minimal: look.minimal,
        tone: look.tone,
        read: () => PreviewPalette._(
          bg: AppColors.bg,
          surface: AppColors.surface,
          border: AppColors.border,
          hover: AppColors.hover,
          text: AppColors.text,
          muted: AppColors.textMuted,
          accent: AppColors.accent,
          onAccent: AppColors.onAccent,
          accentInk: AppColors.accentInk,
          onMedia: AppColors.accentOnMedia,
          barFill: AppGlass.fill(open: false),
          panelFill: AppGlass.surface,
          edge: AppGlass.edge,
          selected: AppGlass.selected,
          selectedEdge: AppGlass.selectedEdge,
          line: AppGlass.line,
        ),
      );

  final Color bg, surface, border, hover, text, muted;
  final Color accent, onAccent, accentInk, onMedia;
  final Color barFill, panelFill, edge, selected, selectedEdge, line;
}

/// Medidas da janela como ficariam com um "Tamanho da interface": a prévia é
/// desenhada nelas e reduzida para caber.
Size previewWindowSize(Size current, int currentPercent, int percent) =>
    current * (currentPercent / percent);
