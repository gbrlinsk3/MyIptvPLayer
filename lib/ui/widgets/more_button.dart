import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Botão de texto com setinha para baixo ("Ver tudo", "Ver catálogo").
class MoreButton extends StatelessWidget {
  const MoreButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback onPressed;

  /// Ícone antes do texto (opcional).
  final IconData? icon;

  /// Padrão: a cor do perfil puxada para o contraste do tema.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ??
            Color.lerp(
              AppColors.accent,
              dark ? Colors.white : Colors.black,
              0.38,
            ),
        shape: AppShape.button,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}
