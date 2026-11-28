import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'preview_data.dart';
import 'preview_look.dart';

/// As peças das prévias. Desenham só com a [PreviewLook] recebida: nada de
/// `Theme`, `AppColors` ou desfoque ao vivo.
class PreviewParts {
  PreviewParts(this.look) : p = look.palette;

  final PreviewLook look;
  final PreviewPalette p;

  /// Quadro que ocupa o lugar de uma imagem que não está no PC.
  Widget blank({Color? color}) => ColoredBox(color: color ?? p.hover);

  /// Fundo da tela: a cor do tema e, por cima, a imagem pronta.
  Widget ground(ui.Image? backdrop) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: p.bg),
          if (backdrop != null)
            RawImage(
              image: backdrop,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
        ],
      );

  Widget panel({
    required Widget child,
    required BorderRadius radius,
    Color? fill,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fill ?? p.panelFill,
          borderRadius: radius,
          border: Border.all(color: p.edge),
        ),
        child: child,
      );

  Widget image(
    String? url, {
    required BorderRadius radius,
    BoxFit fit = BoxFit.cover,
    int cacheWidth = 240,
    Color? ground,
    EdgeInsets padding = EdgeInsets.zero,
  }) =>
      ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: ground ?? p.hover,
          child: Padding(
            padding: padding,
            child: PreviewImage(
              url: url,
              fit: fit,
              cacheWidth: cacheWidth,
              fallback: const SizedBox.expand(),
            ),
          ),
        ),
      );

  Widget text(
    String value, {
    double size = 13,
    Color? color,
    FontWeight weight = FontWeight.w400,
    int maxLines = 1,
  }) =>
      Text(
        value,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          color: color ?? p.text,
          fontWeight: weight,
        ),
      );

  Widget title(String value, double size, {Color? color}) => Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.title(size, color: color ?? p.text, spacing: 1.2),
      );

  /// Botão cheio (cor de destaque) ou de contorno.
  Widget button(String label, {IconData? icon, bool filled = false}) =>
      _pill(
        label,
        icon: icon,
        fill: filled ? p.accent : p.panelFill,
        ink: filled ? p.onAccent : p.accentInk,
        edge: filled ? p.accent : p.border,
      );

  /// Botão sobre foto ou vídeo.
  Widget mediaButton(String label, {IconData? icon}) => _pill(
        label,
        icon: icon,
        fill: const Color(0x33FFFFFF),
        ink: Colors.white,
        edge: const Color(0x55FFFFFF),
      );

  Widget _pill(
    String label, {
    required Color fill,
    required Color ink,
    required Color edge,
    IconData? icon,
  }) =>
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: look.control,
          border: Border.all(color: edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: ink),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: text(label, color: ink, weight: FontWeight.w600),
            ),
          ],
        ),
      );

  /// Abas em pílula, com a primeira marcada.
  Widget tabs(List<String> labels) => panel(
        radius: look.control,
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Container(
                height: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: i == 0
                      ? Color.alphaBlend(
                          p.accent.withValues(alpha: 0.18),
                          p.surface,
                        )
                      : null,
                  borderRadius: look.control,
                ),
                child: text(
                  labels[i],
                  color: i == 0 ? p.accentInk : p.muted,
                  weight: FontWeight.w600,
                ),
              ),
          ],
        ),
      );

  Widget progress(double value, {double height = 4, Color? track}) => ClipRRect(
        borderRadius: look.control,
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: track ?? p.line,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: ColoredBox(color: p.accent),
            ),
          ),
        ),
      );

  /// Linha de texto em bloco, para onde não há o que escrever.
  Widget bar(double width, {double height = 9}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: p.line, borderRadius: look.control),
      );

  /// Camada escura de baixo de uma imagem, para o texto branco.
  static const Decoration shadeBottom = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0xCC000000)],
      stops: [0.4, 1],
    ),
  );

  static const Decoration shadeLeft = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xE6000000), Color(0x00000000)],
      stops: [0.05, 0.75],
    ),
  );
}

/// Item [i] de [list], ou um bloco sem nome quando não há tantos.
PreviewItem itemAt(List<PreviewItem> list, int i) =>
    i < list.length ? list[i] : (name: '', image: null);
