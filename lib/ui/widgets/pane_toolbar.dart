import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Cabeçalho de 56 px dos painéis laterais: título + botão de recolher/expandir.
/// No modo compacto mostra só o botão de expandir.
/// [extra] é um botão opcional exibido antes do de recolher (só no modo expandido).
class PaneToolbar extends StatelessWidget {
  const PaneToolbar({
    super.key,
    required this.title,
    required this.compact,
    required this.onToggle,
    this.extra,
  });

  final String title;
  final bool compact;
  final VoidCallback onToggle;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: compact ? 'Expandir $title' : 'Recolher $title',
      onPressed: onToggle,
      icon: Icon(
        compact ? Icons.chevron_left : Icons.chevron_right,
        size: 20,
        color: AppColors.textMuted,
      ),
    );
    if (compact) {
      return SizedBox(height: 56, child: Center(child: button));
    }
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          ?extra,
          button,
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
