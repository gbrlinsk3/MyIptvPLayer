import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Interruptor do app, com as medidas do `Switch` do Material 3 e o formato do
/// [AppShape] (o do Flutter é sempre uma pílula, o tema não deixa mudar).
///
/// Teclado: Tab foca, Espaço ou Enter trocam. Sem [onChanged] fica desativado.
class AppSwitch extends StatefulWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double width = 52;
  static const double height = 32;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.value;
    final change = widget.onChanged;
    final enabled = change != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    final track = on ? AppColors.accent : scheme.surfaceContainerHighest;
    final edge = on ? AppColors.accent : AppColors.textMuted;
    final thumb = on ? scheme.onPrimary : AppColors.textMuted;
    final side = on ? 24.0 : 16.0;

    void toggle() => change?.call(!on);

    return Semantics(
      toggled: on,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              toggle();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? toggle : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
            // O contorno de foco fica por fora, com 2 de folga.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppShape.control,
                border: Border.all(
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                  color: _focus ? AppColors.text : Colors.transparent,
                ),
              ),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: AppSwitch.width,
                height: AppSwitch.height,
                // A borda de 2 já conta como recuo.
                padding: EdgeInsets.all(on ? 2 : 6),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: _hover && enabled
                      ? Color.alphaBlend(
                          scheme.onSurface.withValues(alpha: 0.08),
                          track,
                        )
                      : track,
                  borderRadius: AppShape.control,
                  border: Border.all(color: edge, width: 2),
                ),
                child: AnimatedContainer(
                  key: const ValueKey('app-switch-thumb'),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    color: thumb,
                    borderRadius: AppShape.control,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha com título, explicação e um [AppSwitch]; clicar em qualquer ponto dela
/// troca o valor (como o `SwitchListTile`).
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: change != null,
          onTap: change == null ? null : () => change(!value),
          title: title,
          subtitle: subtitle,
          // A linha já é o alvo do clique e do teclado.
          trailing: ExcludeFocus(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AppSwitch(value: value, onChanged: onChanged),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
