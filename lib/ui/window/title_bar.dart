import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';

/// Barra de título própria (a do Windows fica oculta em main.dart).
/// Área livre para arrastar a janela + minimizar / maximizar / fechar.
class TitleBar extends StatefulWidget {
  /// [child] ocupa o espaço à esquerda dos botões da janela (ex.: busca e perfil);
  /// sem ele, esse espaço inteiro arrasta a janela.
  const TitleBar({super.key, this.child, this.height = 36});

  final Widget? child;
  final double height;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sync() async {
    final value = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = value);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(
            child: widget.child ??
                const DragToMoveArea(child: SizedBox.expand()),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Row(children: [
          _WindowButton(
            icon: Icons.remove,
            tooltip: 'Minimizar',
            onTap: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            iconSize: _maximized ? 13 : 14,
            tooltip: _maximized ? 'Restaurar' : 'Maximizar',
            onTap: _toggleMaximize,
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: 'Fechar',
            danger: true,
            onTap: () => windowManager.close(),
          ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 15,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color background = _hover
        ? (widget.danger ? const Color(0xFFE81123) : AppColors.hover)
        : Colors.transparent;
    final Color foreground =
        _hover && widget.danger ? Colors.white : AppColors.text;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 36,
            color: background,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Moldura para telas sem barra lateral (carregando, login, erro):
/// barra de título em cima e a tela embaixo, sobre o mesmo fundo.
class PlainFrame extends StatelessWidget {
  const PlainFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          const TitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
