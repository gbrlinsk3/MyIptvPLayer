import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../state/app_scope.dart';
import 'edge_scroll_marks.dart';

/// "Largura do catálogo": com uma largura fixa (1200/1440/1600 px lógicos) o
/// conteúdo das telas fica numa coluna centralizada; em "preenchido" usa a
/// largura toda. Aplicado uma vez em volta da área de páginas do `Shell`.
class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final fixed = c.catalogWidth;
    return LayoutBuilder(
      builder: (context, box) {
        // TV ao vivo com vídeo tocando: o player usa a largura toda.
        final fullBleed = c.liveFullBleed && c.shellIndex == 1;
        final framed =
            !fullBleed && fixed != CatalogWidth.fill && fixed < box.maxWidth;
        return ContentFrameLayout(
          largura: framed ? fixed.toDouble() : box.maxWidth,
          framed: framed,
          pagina: c.shellIndex,
          child: child,
        );
      },
    );
  }
}

/// Monta a coluna do conteúdo com [largura] centralizada na janela inteira.
///
/// - A roda do mouse funciona na janela toda: quando o ponteiro está fora da
///   coluna, a rolagem é reencaminhada para o centro dela.
/// - A faixa de traços na borda direita mostra a posição da página e pode ser
///   usada para rolar; ela aparece só quando a página ativa tem rolagem
///   vertical.
///
/// [pagina] identifica a tela aberta: ao trocar, a posição é zerada e a própria
/// página a informa de novo (`PaginaRolagemNotification`, enviada por
/// `lazy_pages.dart`). Notificações de páginas inativas não chegam aqui.
class ContentFrameLayout extends StatefulWidget {
  const ContentFrameLayout({
    super.key,
    required this.largura,
    required this.framed,
    required this.pagina,
    required this.child,
  });

  final double largura;
  final bool framed;
  final int pagina;
  final Widget child;

  @override
  State<ContentFrameLayout> createState() => _ContentFrameLayoutState();
}

class _ContentFrameLayoutState extends State<ContentFrameLayout> {
  final ValueNotifier<PosicaoRolagem?> _posicao = ValueNotifier(null);

  /// Menor profundidade (`ScrollNotification.depth`) vista nas notificações
  /// verticais da página atual. Rolagens em níveis mais fundos (fileiras e
  /// listas internas) são ignoradas.
  int? _profundidade;

  @override
  void didUpdateWidget(ContentFrameLayout antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.pagina != widget.pagina) {
      _profundidade = null;
      _posicao.value = null;
    }
  }

  @override
  void dispose() {
    _posicao.dispose();
    super.dispose();
  }

  bool _aoNotificar(Notification n) {
    if (n is ScrollNotification) return _registrar(n.metrics, n.depth);
    if (n is ScrollMetricsNotification) {
      return _registrar(n.metrics, n.depth);
    }
    if (n is PaginaRolagemNotification) {
      _profundidade = null;
      _posicao.value = n.posicao;
      return true;
    }
    return false;
  }

  bool _registrar(ScrollMetrics m, int profundidade) {
    if (m.axis != Axis.vertical) return false;
    final atual = _profundidade;
    if (atual == null || profundidade < atual) {
      _profundidade = profundidade;
    } else if (profundidade > atual) {
      return false;
    }
    final nova = PosicaoRolagem(
      pixels: m.pixels,
      maxScrollExtent: m.maxScrollExtent,
      viewportDimension: m.viewportDimension,
    );
    if (nova != _posicao.value) _posicao.value = nova;
    return false;
  }

  /// Roda do mouse fora da coluna: reenvia a mesma rolagem para o centro dela.
  /// Dentro da coluna a página já recebe a roda, exceto na faixa de traços
  /// quando ela está visível (a faixa bloqueia o acerto e é tratada aqui).
  void _aoRodaDoMouse(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.hasSize) return;
    final w = rb.size.width;
    final cw = widget.largura.clamp(0.0, w).toDouble();
    final esquerda = rb.localToGlobal(Offset((w - cw) / 2, 0)).dx;
    final direita = rb.localToGlobal(Offset((w + cw) / 2, 0)).dx;
    final x = e.position.dx;
    if (x >= esquerda && x <= direita) {
      final faixaVisivel = _posicao.value?.rolavel ?? false;
      final inicioFaixa =
          rb.localToGlobal(Offset(w - EdgeScrollMarks.largura, 0)).dx;
      if (!faixaVisivel || x < inicioFaixa) return;
    }
    final centroX = rb.localToGlobal(Offset(w / 2, 0)).dx;
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        timeStamp: e.timeStamp,
        kind: e.kind,
        device: e.device,
        position: Offset(centroX, e.position.dy),
        scrollDelta: e.scrollDelta,
      ),
    );
  }

  /// Rolagem vinda da faixa de traços: envia um delta ao centro da coluna.
  void _rolarPagina(double dy) {
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.hasSize) return;
    final centro =
        rb.localToGlobal(Offset(rb.size.width / 2, rb.size.height / 2));
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: centro,
        scrollDelta: Offset(0, dy),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _aoRodaDoMouse,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: widget.largura,
              height: double.infinity,
              child: ContentFrameScope(
                framed: widget.framed,
                child: NotificationListener<Notification>(
                  onNotification: _aoNotificar,
                  child: widget.child,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: EdgeScrollMarks(
                posicao: _posicao,
                aoRolar: _rolarPagina,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diz às telas se o conteúdo está numa coluna estreita (e não de borda a
/// borda): o banner do Início arredonda os cantos externos nesse caso.
class ContentFrameScope extends InheritedWidget {
  const ContentFrameScope({
    super.key,
    required this.framed,
    required super.child,
  });

  final bool framed;

  static bool framedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentFrameScope>()?.framed ??
      false;

  @override
  bool updateShouldNotify(ContentFrameScope old) => framed != old.framed;
}
