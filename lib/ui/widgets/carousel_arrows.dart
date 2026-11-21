import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Estado e comando de um carrossel horizontal ligado a um [ScrollController].
class CarouselScroller {
  const CarouselScroller(this.controller);

  final ScrollController controller;

  // Só lê offset/extensão quando a posição já tem dimensões; antes do primeiro
  // layout acessá-los causa "Null check operator used on a null value".
  bool get _ready =>
      controller.hasClients &&
      controller.positions.length == 1 &&
      controller.position.hasContentDimensions &&
      controller.position.hasPixels;

  bool get canScrollLeft => _ready && controller.offset > 0.5;

  bool get canScrollRight =>
      _ready && controller.offset < controller.position.maxScrollExtent - 0.5;

  /// Há conteúdo fora da tela. Sem isso não faz sentido mostrar setas.
  bool get scrollable => _ready && controller.position.maxScrollExtent > 0;

  /// Rola [delta] pixels com animação curta, limitada às pontas.
  void scrollBy(double delta) {
    if (!_ready) return;
    final max = controller.position.maxScrollExtent;
    final target = (controller.offset + delta).clamp(0.0, max).toDouble();
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Botão circular de seta de carrossel: fundo da superfície, borda fina e
/// sempre visível. Sem [enabled] fica apagado e não responde ao toque.
class CarouselArrowButton extends StatelessWidget {
  const CarouselArrowButton({
    super.key,
    required this.left,
    required this.enabled,
    required this.onTap,
  });

  static const double size = 36;

  final bool left;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = left ? 'Anterior' : 'Próximos';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: AppColors.surface,
          shape: CircleBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: AppColors.hover,
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                left ? Icons.chevron_left : Icons.chevron_right,
                size: 22,
                color: enabled
                    ? AppColors.text
                    : AppColors.text.withAlpha(90),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seta fixa de um carrossel. Acompanha o [controller] (ativa ou não conforme
/// há o que rolar para aquele lado) e rola [passo] pixels a cada clique.
class CarouselArrow extends StatefulWidget {
  const CarouselArrow({
    super.key,
    required this.controller,
    required this.left,
    required this.passo,
  });

  final ScrollController controller;
  final bool left;
  final double passo;

  @override
  State<CarouselArrow> createState() => _CarouselArrowState();
}

class _CarouselArrowState extends State<CarouselArrow> {
  // Último estado desenhado; só reconstrói quando muda.
  bool? _ativa;

  bool _calcular() {
    final carrossel = CarouselScroller(widget.controller);
    return widget.left ? carrossel.canScrollLeft : carrossel.canScrollRight;
  }

  // O pai reconstrói esta seta quando a lista muda de tamanho; a extensão
  // máxima só é atualizada no layout, então relê depois do quadro.
  void _reler() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _calcular() != _ativa) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_mudou);
    // O controlador só fica preso à lista depois do primeiro quadro: relê então.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CarouselArrow antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.controller != widget.controller) {
      antigo.controller.removeListener(_mudou);
      widget.controller.addListener(_mudou);
    }
    _reler();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final carrossel = CarouselScroller(widget.controller);
    final ativa = _calcular();
    _ativa = ativa;
    return CarouselArrowButton(
      left: widget.left,
      enabled: ativa,
      onTap: () =>
          carrossel.scrollBy(widget.left ? -widget.passo : widget.passo),
    );
  }
}

/// Deixa um carrossel de conteúdo ser arrastado com o mouse, além do toque.
/// O arraste só começa com movimento: um clique curto continua sendo clique e
/// abre o cartão, porque o movimento faz o reconhecedor de arraste ganhar a
/// disputa de gestos. Enquanto o botão está apertado o cursor vira "mão fechada".
class CarouselDragArea extends StatefulWidget {
  const CarouselDragArea({super.key, required this.child});

  final Widget child;

  @override
  State<CarouselDragArea> createState() => _CarouselDragAreaState();
}

class _CarouselDragAreaState extends State<CarouselDragArea> {
  bool _pressionado = false;

  void _definir(bool valor) {
    if (_pressionado != valor) setState(() => _pressionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        scrollbars: false,
      ),
      child: MouseRegion(
        cursor: _pressionado
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: Listener(
          onPointerDown: (e) {
            if (e.kind == PointerDeviceKind.mouse) _definir(true);
          },
          onPointerUp: (_) => _definir(false),
          onPointerCancel: (_) => _definir(false),
          child: widget.child,
        ),
      ),
    );
  }
}
