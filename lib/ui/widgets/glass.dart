import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'app_backdrop.dart';

/// O vidro do app (o mesmo da barra lateral flutuante): desfoca o que está
/// atrás, aviva as cores e põe um preenchimento translúcido, um filete de luz
/// no topo e a borda. Barras, painéis, menus e botões usam esta casca; só os
/// valores de [AppGlass] mudam de um caso para outro.
///
/// A borda é desenhada sem recuar o conteúdo (diferente de um `Container`).
///
/// No tema Minimalista a peça é sólida: sem desfoque, e [AppGlass] já entrega
/// preenchimento opaco, sem filete de luz.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius,
    this.fill,
    this.blur,
    this.edge,
    this.edgeWidth = 1,
    this.shadow = false,
    this.halo = false,
  });

  final Widget child;

  /// Padrão: o canto de cartão ([AppShape.card]).
  final BorderRadius? radius;

  /// Padrão: [AppGlass.surface].
  final Color? fill;

  /// Padrão: o desfoque da barra lateral recolhida.
  final double? blur;

  /// Cor da borda (padrão: [AppGlass.edge]); usada no contorno de foco.
  final Color? edge;
  final double edgeWidth;

  /// Sombra para peças que flutuam sobre o conteúdo (barra lateral, menus).
  final bool shadow;

  /// Com [shadow]: sombra suave também em volta (menus), não só embaixo.
  final bool halo;

  @override
  Widget build(BuildContext context) {
    final sigma = blur ?? AppGlass.blur(open: false);
    final radius = this.radius ?? AppShape.card;
    return CustomPaint(
      painter: _GlassOutline(
        radius,
        shadow ? AppGlass.shadow : null,
        AppGlass.ring,
        halo,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // Desligado, não desfoca; a estrutura da tela continua a mesma.
          enabled: !AppColors.minimal,
          filter: ui.ImageFilter.compose(
            outer: saturationFilter(AppGlass.saturation),
            inner: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.mirror,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill ?? AppGlass.surface),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppGlass.sheen, AppGlass.sheen.withValues(alpha: 0)],
                  stops: const [0, 0.22],
                ),
              ),
              child: DecoratedBox(
                // Atrás do conteúdo: o contorno de foco de um campo fica
                // por cima dela.
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: edge ?? AppGlass.edge,
                    width: edgeWidth,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão de vidro que flutua sobre o conteúdo com bastante texto (diálogos e
/// aviso de atualização).
class GlassPane extends StatelessWidget {
  const GlassPane({
    super.key,
    required this.child,
    this.radius,
    this.edge,
  });

  final Widget child;

  /// Padrão: o canto de painel e diálogo ([AppShape.panel]).
  final BorderRadius? radius;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: radius ?? AppShape.panel,
      shadow: true,
      fill: AppGlass.dialog,
      blur: AppGlass.blur(open: true),
      edge: edge,
      // Um Material por cima do preenchimento: sem ele, o realce de listas e
      // caixas de seleção seria desenhado atrás do vidro.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// [Dialog] de vidro. Quem chama cuida do tamanho e do recuo do conteúdo.
class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, required this.child, this.insetPadding});

  final Widget child;
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      clipBehavior: Clip.none,
      child: GlassPane(child: child),
    );
  }
}

/// [AlertDialog] de vidro, com as mesmas medidas e estilos de texto (Material
/// 3). O do Flutter não deixa pôr o desfoque atrás do próprio cartão.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassDialog(
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: DefaultTextStyle(
                style: theme.textTheme.headlineSmall!.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                child: Semantics(
                  namesRoute: true,
                  container: true,
                  child: title,
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: content,
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Estilo do [MenuAnchor] que deixa o painel do Material invisível (e sem
/// recortar a sombra): quem desenha o menu é o [GlassMenuPanel]. Use junto com
/// `clipBehavior: Clip.none`.
const glassMenuStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
  shadowColor: WidgetStatePropertyAll(Colors.transparent),
  elevation: WidgetStatePropertyAll(0),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
);

/// Painel de vidro de um menu. Listas maiores que [maxHeight] rolam por dentro
/// dele.
class GlassMenuPanel extends StatelessWidget {
  const GlassMenuPanel({
    super.key,
    required this.children,
    this.width = 208,
    this.maxHeight = 360,
  });

  final List<Widget> children;
  final double width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      shadow: true,
      halo: true,
      fill: AppGlass.fill(open: true),
      blur: AppGlass.blur(open: true),
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            // A rolagem de fora é a do MenuAnchor: esta não pode dividir o
            // controlador com ela.
            primary: false,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de um [GlassMenuPanel]. [selected] marca a opção em uso.
class GlassMenuItem extends StatelessWidget {
  const GlassMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Em pílula o item não encosta nas bordas do painel; o texto continua
    // alinhado no mesmo lugar nos dois formatos.
    final margin = AppShape.rounded ? 8.0 : 0.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Semantics(
        selected: selected,
        child: MenuItemButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16 - margin / 2),
            ),
            visualDensity: VisualDensity.standard,
            shape: WidgetStatePropertyAll(AppShape.button),
            foregroundColor: WidgetStatePropertyAll(AppColors.text),
            backgroundColor: selected
                ? WidgetStatePropertyAll(AppGlass.selected)
                : null,
            overlayColor: WidgetStatePropertyAll(AppGlass.hover),
          ),
          leadingIcon: icon == null
              ? null
              : Icon(icon, size: 18, color: AppColors.textMuted),
          trailingIcon: selected
              ? Icon(Icons.check, size: 18, color: AppColors.accentInk)
              : null,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

/// Botão que abre um menu de vidro com uma opção marcada (ex.: temporada).
/// [child] é o rótulo clicável; o menu é o [GlassMenuPanel].
class GlassMenuButton<T> extends StatefulWidget {
  const GlassMenuButton({
    super.key,
    required this.tooltip,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    required this.child,
    this.menuWidth = 200,
  });

  final double menuWidth;
  final String tooltip;
  final List<T> options;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  State<GlassMenuButton<T>> createState() => _GlassMenuButtonState<T>();
}

class _GlassMenuButtonState<T> extends State<GlassMenuButton<T>> {
  final _focus = FocusNode(debugLabel: 'menu de vidro');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      childFocusNode: _focus,
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      alignmentOffset: const Offset(0, 4),
      style: glassMenuStyle,
      menuChildren: [
        GlassMenuPanel(
          width: widget.menuWidth,
          children: [
            for (final o in widget.options)
              GlassMenuItem(
                label: widget.labelOf(o),
                selected: o == widget.selected,
                onPressed: () => widget.onSelected(o),
              ),
          ],
        ),
      ],
      builder: (context, menu, child) => Tooltip(
        message: widget.tooltip,
        child: InkWell(
          focusNode: _focus,
          borderRadius: AppShape.control,
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Contorno e sombra só por fora da peça: uma sombra comum também pintaria por
/// baixo e escureceria o vidro translúcido.
class _GlassOutline extends CustomPainter {
  const _GlassOutline(this.radius, this.shadow, this.ring, this.halo);

  final BorderRadius radius;
  final Color? shadow;
  final Color ring;
  final bool halo;

  @override
  void paint(Canvas canvas, Size size) {
    final box = radius.toRRect(Offset.zero & size);
    final shadow = this.shadow;
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(60))
        ..addRRect(box),
    );
    if (shadow != null) {
      if (halo) {
        canvas.drawRRect(
          box.inflate(2),
          Paint()
            ..color = shadow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }
      canvas.drawRRect(
        box.shift(const Offset(0, 10)),
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawRRect(box.inflate(1), Paint()..color = ring);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassOutline old) =>
      old.radius != radius ||
      old.shadow != shadow ||
      old.ring != ring ||
      old.halo != halo;
}
