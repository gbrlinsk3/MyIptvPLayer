import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Botão principal do banner (inspirado no "Free download" da referência):
/// quadrado escuro com ícone + retângulo na cor de destaque, cantos retos e
/// sombra colorida.
class HeroPrimaryButton extends StatefulWidget {
  const HeroPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.play_arrow_rounded,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<HeroPrimaryButton> createState() => _HeroPrimaryButtonState();
}

class _HeroPrimaryButtonState extends State<HeroPrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: AppShape.borderRadius,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: _hover ? 0.55 : 0.35),
                blurRadius: _hover ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                color: const Color(0xFF1B1A19),
                child: Icon(widget.icon, color: Colors.white, size: 24),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                alignment: Alignment.center,
                color: _hover
                    ? Color.lerp(AppColors.accent, Colors.white, 0.12)
                    : AppColors.accent,
                child: Text(
                  widget.label.toUpperCase(),
                  style: AppFonts.title(16, color: Colors.white, spacing: 2.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão secundário do banner: contorno branco, cantos retos.
class HeroGhostButton extends StatefulWidget {
  const HeroGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<HeroGhostButton> createState() => _HeroGhostButtonState();
}

class _HeroGhostButtonState extends State<HeroGhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.18 : 0.08),
            borderRadius: AppShape.borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: _hover ? 0.8 : 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label.toUpperCase(),
                style: AppFonts.title(15, color: Colors.white, spacing: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
