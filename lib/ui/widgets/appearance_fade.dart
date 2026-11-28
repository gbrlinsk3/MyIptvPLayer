import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Troca de aparência sem corte: quando [look] muda, a tela como estava vira
/// uma imagem que fica por cima e esmaece sobre a tela já redesenhada. Nada é
/// recriado. Precisa ficar acima de quem redesenha (`RebuildOnChange`).
///
/// A foto é tirada em `didUpdateWidget`, antes de o quadro novo ser pintado,
/// e custa um único desenho; durante o fade só a opacidade dela muda. Com
/// `disableAnimations` a troca é direta.
class AppearanceFade extends StatefulWidget {
  const AppearanceFade({
    super.key,
    required this.owner,
    required this.look,
    required this.child,
    this.ready,
    this.skip,
  });

  /// De quem é a aparência (o perfil). Trocar de dono, ou não ter um, não
  /// esmaece: ali a tela inteira muda.
  final Object? owner;

  /// O que, ao mudar, dispara a transição.
  final Object look;

  /// Espera o que é preparado fora do quadro (a imagem de fundo).
  final Future<void> Function()? ready;

  /// `true` = trocar direto (vídeo à vista ou perfil ainda abrindo).
  final bool Function()? skip;

  final Widget child;

  static const Duration duration = Duration(milliseconds: 240);

  @override
  State<AppearanceFade> createState() => _AppearanceFadeState();
}

class _AppearanceFadeState extends State<AppearanceFade>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundary = GlobalKey();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppearanceFade.duration,
  );

  late final Animation<double> _opacity = ReverseAnimation(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  /// A tela de antes; nulo fora de uma transição.
  ui.Image? _before;
  int _round = 0;

  @override
  void didUpdateWidget(AppearanceFade old) {
    super.didUpdateWidget(old);
    if (old.look == widget.look) return;
    if (widget.owner == null || old.owner != widget.owner) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (widget.skip?.call() ?? false) return;
    _cover();
  }

  /// Fotografa o que está na tela (inclusive um fade em andamento).
  void _cover() {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final ui.Image shot;
    try {
      shot = boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      return; // sem foto, a troca é direta
    }
    _release(_before);
    _before = shot;
    _controller
      ..stop()
      ..value = 0;
    _fadeOut(++_round);
  }

  Future<void> _fadeOut(int round) async {
    final binding = WidgetsBinding.instance;
    // Um quadro para o tema novo e outro para o resto da árvore ser
    // redesenhado; só então se começa a mostrar o que há por baixo.
    await binding.endOfFrame;
    await binding.endOfFrame;
    if (widget.ready != null) {
      await widget.ready!();
      await binding.endOfFrame;
    }
    if (!mounted || round != _round) return;
    await _controller.forward().orCancel.catchError((Object _) {});
    if (!mounted || round != _round) return;
    final shot = _before;
    setState(() => _before = null);
    _release(shot);
  }

  /// Descarta depois do quadro em que o desenho deixou de usar a imagem.
  void _release(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void dispose() {
    _controller.dispose();
    _before?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final before = _before;
    return RepaintBoundary(
      key: _boundary,
      child: Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          // Camadas separadas: o fade não repinta a tela de baixo.
          RepaintBoundary(child: widget.child),
          if (before != null)
            IgnorePointer(
              child: RepaintBoundary(
                child: RawImage(
                  image: before,
                  fit: BoxFit.fill,
                  opacity: _opacity,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
