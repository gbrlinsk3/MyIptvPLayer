import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'personalization/preview_hover.dart';
import 'widgets/common.dart';

/// "Tema" (Conta e ajustes → Personalização): o visual (Liquid Glass ou
/// Minimalista) e o tom da cor de destaque. Claro/escuro fica em "Aparência".
class ThemeSettingsCard extends StatelessWidget {
  const ThemeSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return SectionCard(
      title: 'Tema',
      children: [
        HoverRange.segments(
          specs: [
            CompareSpec(
              'tema.vidro',
              'Tema: Liquid Glass',
              change: (look) => look.copyWith(minimal: false),
            ),
            CompareSpec(
              'tema.minimo',
              'Tema: Minimalista',
              change: (look) => look.copyWith(minimal: true),
            ),
          ],
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.blur_on, size: 18),
                label: Text('Liquid Glass'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.layers_outlined, size: 18),
                label: Text('Minimalista'),
              ),
            ],
            selected: {c.minimalTheme},
            onSelectionChanged: (v) => c.setMinimalTheme(v.first),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Liquid Glass usa vidro desfocado sobre a imagem de fundo. '
          'Minimalista usa superfícies lisas e neutras, com a cor de destaque '
          'nos botões, na seleção e no progresso.',
          style: muted,
        ),
        const SizedBox(height: 16),
        _AccentScaleControl(c),
        const SizedBox(height: 4),
        Text(
          'A escala parte da cor do perfil, no meio, e vale nos dois temas. '
          'Ela para antes do branco e do preto, para a cor continuar visível. '
          'Para trocar a cor do meio, edite o perfil.',
          style: muted,
        ),
      ],
    );
  }
}

class _AccentScaleControl extends StatelessWidget {
  const _AccentScaleControl(this.c);

  final AppController c;

  static const double _width = 360;

  static CompareSpec _toneSpec(int tone) => CompareSpec(
        'tom.$tone',
        'Cor de destaque: ${AccentScale.label(tone)}',
        change: (look) => look.copyWith(tone: tone),
      );

  @override
  Widget build(BuildContext context) {
    final base = AppColors.accentBase;
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _width),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cor de destaque: ${AccentScale.label(c.accentTone)}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 14,
              trackShape: _ScaleTrackShape(
                [AccentScale.lightEnd(base), base, AccentScale.darkEnd(base)],
                AppShape.rounded,
              ),
              thumbShape: _ScaleThumbShape(
                color: AppColors.accent,
                ring: AppColors.text,
                gap: AppColors.bg,
                rounded: AppShape.rounded,
              ),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              overlayColor: AppColors.accent.withValues(alpha: 0.18),
            ),
            child: HoverRange(
              // A trilha do controle começa depois desta margem.
              inset: 24,
              specAt: (f) => _toneSpec(
                ((2 * f - 1) * AccentScale.limit / AccentScale.step).round() *
                    AccentScale.step,
              ),
              child: Slider(
                value: c.accentTone.toDouble(),
                min: -AccentScale.limit.toDouble(),
                max: AccentScale.limit.toDouble(),
                divisions: 2 * AccentScale.limit ~/ AccentScale.step,
                semanticFormatterCallback: (v) =>
                    'Cor de destaque: ${AccentScale.label(v.round())}',
                onChanged: (v) => c.previewAccentTone(v.round()),
                onChangeEnd: (v) => c.setAccentTone(v.round()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mais claro', style: muted),
                Text('Mais escuro', style: muted),
              ],
            ),
          ),
          // Abaixo do controle: ao aparecer, ele não sai do lugar.
          if (c.accentTone != 0)
            Align(
              alignment: Alignment.centerLeft,
              child: HoverCompare(
                spec: _toneSpec(0),
                child: TextButton(
                  onPressed: () => c.setAccentTone(0),
                  child: const Text('Usar a cor do perfil'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Trilho com a própria escala: claro, cor do perfil no meio e escuro.
class _ScaleTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _ScaleTrackShape(this.colors, this.rounded);

  final List<Color> colors;
  final bool rounded;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(rounded ? rect.height / 2 : 0),
      ),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }
}

/// Botão com anel: aparece sobre qualquer ponto da escala, que tem a mesma cor
/// do miolo.
class _ScaleThumbShape extends SliderComponentShape {
  const _ScaleThumbShape({
    required this.color,
    required this.ring,
    required this.gap,
    required this.rounded,
  });

  final Color color;
  final Color ring;
  final Color gap;
  final bool rounded;

  static const double _radius = 12;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    void shape(double radius, Color color) {
      final paint = Paint()..color = color;
      if (rounded) {
        context.canvas.drawCircle(center, radius, paint);
      } else {
        context.canvas.drawRect(
          Rect.fromCircle(center: center, radius: radius),
          paint,
        );
      }
    }

    shape(_radius, ring);
    shape(_radius - 2, gap);
    shape(_radius - 4, color);
  }
}

/// "Aparência": Claro, Escuro, Sistema ou Automático.
class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ThemePref selected;
  final ValueChanged<ThemePref> onChanged;

  /// Ícone e texto juntos no rótulo: com o `icon:` do [ButtonSegment] o Flutter
  /// impõe o próprio respiro lateral (12 e 16), e "Automático" quebra em duas
  /// linhas nos quatro segmentos iguais desta coluna.
  static ButtonSegment<ThemePref> _segment(
    ThemePref value,
    IconData icon,
    String text,
  ) =>
      ButtonSegment(
        value: value,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemePref>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      segments: [
        _segment(ThemePref.light, Icons.light_mode_outlined, 'Claro'),
        _segment(ThemePref.dark, Icons.dark_mode_outlined, 'Escuro'),
        _segment(ThemePref.system, Icons.desktop_windows_outlined, 'Sistema'),
        _segment(ThemePref.auto, Icons.schedule_outlined, 'Automático'),
      ],
      selected: {selected},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}
