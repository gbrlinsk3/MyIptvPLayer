import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/app_scope.dart';

/// Botão "Gerenciar categorias". Na **primeira vez** que a tela correspondente
/// é aberta (uma vez para TV ao vivo, uma para Filmes, uma para Séries) mostra
/// ícone + o texto "Desabilitar categorias"; depois volta a ser só o ícone.
/// [hintKey] identifica a tela (`live`, `movies`, `series`).
class ManageCategoriesButton extends StatefulWidget {
  const ManageCategoriesButton({
    super.key,
    required this.hintKey,
    required this.onPressed,
    this.iconColor,
  });

  final String hintKey;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  State<ManageCategoriesButton> createState() => _ManageCategoriesButtonState();
}

class _ManageCategoriesButtonState extends State<ManageCategoriesButton> {
  late final bool _showLabel;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _showLabel = app.hintPending(widget.hintKey);
    // Já conta como visto: da próxima vez que a tela abrir, só o ícone.
    if (_showLabel) app.markHintSeen(widget.hintKey);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.iconColor ?? AppColors.textMuted;
    if (_showLabel) {
      return TextButton.icon(
        onPressed: widget.onPressed,
        icon: Icon(Icons.tune, size: 20, color: color),
        label: Text('Desabilitar categorias', style: TextStyle(color: color)),
      );
    }
    return IconButton(
      tooltip: 'Gerenciar categorias',
      onPressed: widget.onPressed,
      icon: Icon(Icons.tune, size: 20, color: color),
    );
  }
}
