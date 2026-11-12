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
            child: WindowButtons(maximized: _maximized, onToggleMaximize: _toggleMaximize),
          ),
        ],
      ),
    );
  }
}

/// Minimizar / maximizar / fechar. [tooltips] = false quando não há Overlay
/// acima (a cópia flutuante fica fora do Navigator).
class WindowButtons extends StatelessWidget {
  const WindowButtons({
    super.key,
    required this.maximized,
    required this.onToggleMaximize,
    this.tooltips = true,
  });

  final bool maximized;
  final VoidCallback onToggleMaximize;
  final bool tooltips;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _WindowButton(
        icon: Icons.remove,
        tooltip: 'Minimizar',
        tooltips: tooltips,
        onTap: () => windowManager.minimize(),
      ),
      _WindowButton(
        icon: maximized ? Icons.filter_none : Icons.crop_square,
        iconSize: maximized ? 13 : 14,
        tooltip: maximized ? 'Restaurar' : 'Maximizar',
        tooltips: tooltips,
        onTap: onToggleMaximize,
      ),
      _WindowButton(
        icon: Icons.close,
        tooltip: 'Fechar',
        tooltips: tooltips,
        danger: true,
        onTap: () => windowManager.close(),
      ),
    ]);
  }
}

/// Cópia dos botões da janela por cima de tudo (inclusive de caixas de diálogo
/// e painéis modais), para a janela continuar controlável com um diálogo
/// aberto. Some em tela cheia (quando a barra de título também some).
class WindowButtonsOverlay extends StatefulWidget {
  const WindowButtonsOverlay({super.key});

  @override
  State<WindowButtonsOverlay> createState() => _WindowButtonsOverlayState();
}

class _WindowButtonsOverlayState extends State<WindowButtonsOverlay>
    with WindowListener {
  bool _maximized = false;
  bool _full = false;

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
    final m = await windowManager.isMaximized();
    final f = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _maximized = m;
        _full = f;
      });
    }
  }

  @override
  void onWindowMaximize() => _sync();
  @override
  void onWindowUnmaximize() => _sync();
  @override
  void onWindowEnterFullScreen() => _sync();
  @override
  void onWindowLeaveFullScreen() => _sync();

  Future<void> _toggle() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_full) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topRight,
      child: WindowButtons(
        maximized: _maximized,
        onToggleMaximize: _toggle,
        tooltips: false,
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
    this.tooltips = true,
  });

  final bool tooltips;

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
    final button = MouseRegion(
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
      );
    return widget.tooltips
        ? Tooltip(message: widget.tooltip, child: button)
        : button;
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
