import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Estado vazio de uma tela ou painel: ícone em círculo, título em frase, uma
/// linha de explicação e, se houver, um único botão de ação.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;
    return _StateView(
      icon: icon,
      iconColor: AppColors.textMuted,
      title: title,
      text: text,
      button: label != null && action != null
          ? FilledButton(onPressed: action, child: Text(label))
          : null,
    );
  }
}

/// Estado de erro de uma tela ou painel: ícone de aviso em vermelho, o que
/// houve, e o botão "Tentar de novo" se [onRetry] for informado.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.text,
    this.onRetry,
    this.retryLabel = 'Tentar de novo',
  });

  final String title;
  final String text;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return _StateView(
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.danger,
      title: title,
      text: text,
      button: retry != null
          ? FilledButton(onPressed: retry, child: Text(retryLabel))
          : null,
    );
  }
}

/// Desenho comum aos dois estados (mesmas medidas e cores do protótipo).
class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
    this.button,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;
  final Widget? button;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.hover,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: iconColor),
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.45),
              ),
              if (button != null) ...[
                const SizedBox(height: 20),
                button!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
