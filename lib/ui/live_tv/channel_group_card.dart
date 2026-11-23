import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/channel_groups.dart';
import '../widgets/click_spark.dart';
import '../widgets/spotlight.dart';
import 'live_logo.dart';

/// Cartão de um canal agrupado, no estilo da loja Nuuvem: faixa com a
/// categoria no alto, imagem larga (logo sobre o próprio logo desfocado),
/// nome, etiquetas das versões (FHD, HD, SD...) e "Clique para assistir" embaixo;
/// o coração de favoritar fica sobre a imagem.
/// [current] marca o canal que está tocando.
class ChannelGroupCard extends StatefulWidget {
  const ChannelGroupCard({
    super.key,
    required this.group,
    required this.onTap,
    this.current = false,
    this.category,
    this.favorite = false,
    this.onToggleFavorite,
  });

  final ChannelGroup group;
  final VoidCallback onTap;
  final bool current;

  /// Nome da categoria; sem ele a faixa do alto não aparece.
  final String? category;

  final bool favorite;
  final VoidCallback? onToggleFavorite;

  static const double width = 240;

  /// Altura da faixa da categoria.
  static const double categoryHeight = 24;

  /// Altura da imagem larga.
  static const double imageHeight = 120;

  /// Altura do corpo: padding 12 + nome + etiquetas + botão (32) + padding 12.
  static const double bodyHeight = 104;

  /// Altura do cartão com a faixa da categoria.
  static const double height = categoryHeight + imageHeight + bodyHeight;

  /// Altura do cartão sem a faixa da categoria.
  static const double heightWithoutCategory = imageHeight + bodyHeight;

  /// Máximo de etiquetas mostradas; as outras viram "+N".
  static const int maxTags = 3;

  @override
  State<ChannelGroupCard> createState() => _ChannelGroupCardState();
}

class _ChannelGroupCardState extends State<ChannelGroupCard> {
  bool _hover = false;
  bool _focus = false;

  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final n = g.versions.length;
    final current = widget.current;
    final category = widget.category;
    final hasCategory = category != null && category.isNotEmpty;
    final labels = <String>[];
    for (final v in g.versions) {
      final l = g.labelOf(v).replaceAll(' [ALT]', '');
      if (!labels.contains(l)) labels.add(l);
    }
    if (labels.length == 1 && labels.first == 'Padrão') {
      labels.clear();
      if (n > 1) labels.add('$n versões');
    }
    final shown = labels.take(ChannelGroupCard.maxTags).toList();
    final extra = labels.length - shown.length;

    final bool strong = current || _focus;
    final Color borderColor = strong
        ? AppColors.accent
        : (_hover
              ? Color.lerp(AppColors.border, AppColors.text, 0.35)!
              : AppColors.border);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);

    return Semantics(
      container: true,
      button: true,
      label: '${g.displayName}, $n ${n == 1 ? 'versão' : 'versões'}',
      onTap: widget.onTap,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: ChannelGroupCard.width,
            height: hasCategory
                ? ChannelGroupCard.height
                : ChannelGroupCard.heightWithoutCategory,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: _hover && !current
                    ? const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              // A borda é desenhada por cima: mudar a espessura não mexe no
              // conteúdo.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: borderColor, width: strong ? 2 : 1),
              ),
              // Facho de luz que acompanha o mouse (pinta por cima, sem tomar
              // toques; dentro de um SpotlightGroup acende também os vizinhos).
              child: SpotlightCard(
                borderRadius: BorderRadius.circular(_radius),
                borderGlow: 0.5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_radius),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasCategory)
                        ExcludeSemantics(
                          child: SizedBox(
                            height: ChannelGroupCard.categoryHeight,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: ChannelGroupCard.imageHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ExcludeSemantics(child: _WideImage(url: g.icon)),
                            // Só o ícone, no canto da imagem.
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _FavoriteButton(
                                favorite: widget.favorite,
                                onPressed: widget.onToggleFavorite,
                                name: g.displayName,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: Text(
                                  g.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              if (shown.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ExcludeSemantics(
                                  child: SizedBox(
                                    height: _Tag.height,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.centerLeft,
                                        minWidth: 0,
                                        maxWidth: double.infinity,
                                        minHeight: _Tag.height,
                                        maxHeight: _Tag.height,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (final t in shown)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                child: _Tag(t),
                                              ),
                                            if (extra > 0) _Tag('+$extra'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              ExcludeSemantics(
                                child: Text(
                                  'Clique para assistir',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão só com o coração, sobre a imagem do cartão (alvo de 32 px).
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({
    required this.favorite,
    required this.onPressed,
    required this.name,
  });

  final bool favorite;
  final VoidCallback? onPressed;
  final String name;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  final GlobalKey _iconKey = GlobalKey();

  /// Ao favoritar (não ao desfavoritar) solta faíscas a partir do coração.
  void _alternar() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    if (!widget.favorite) {
      final ctx = _iconKey.currentContext;
      if (ctx != null) {
        ClickSpark.fromContext(
          ctx,
          shape: SparkShape.stars,
          color: AppColors.accent,
          count: 8,
          radius: 24,
        );
      }
    }
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final favorite = widget.favorite;
    final onPressed = widget.onPressed;
    final name = widget.name;
    final color = favorite ? AppColors.accent : Colors.white;
    final tip = favorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos';
    return Semantics(
      container: true,
      button: true,
      label: '$tip: $name',
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tip,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed == null ? null : _alternar,
            customBorder: const CircleBorder(),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x99000000),
              ),
              child: Icon(
                favorite ? Icons.favorite : Icons.favorite_border,
                key: _iconKey,
                size: 18,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  /// Fonte 10 x altura 1,3 + padding vertical 2 + borda 2.
  static const double height = 10 * 1.3 + 2 + 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Imagem larga: o logo (≈64 px de altura) sobre o mesmo logo ampliado,
/// desfocado e escurecido. Sem logo, ou se ele falhar, mostra o ícone de TV
/// sobre um fundo mais claro.
class _WideImage extends StatelessWidget {
  const _WideImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholderBg = ColoredBox(color: AppColors.hover);
    final placeholder = Center(
      child: Icon(Icons.live_tv, size: 32, color: AppColors.textMuted),
    );
    final u = url;
    if (u == null || u.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [placeholderBg, placeholder],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: LiveLogo(
                url: u,
                fit: BoxFit.cover,
                memCacheHeight: 64,
                fallback: placeholderBg,
              ),
            ),
          ),
        ),
        const ColoredBox(color: Color(0x73000000)),
        Center(
          child: SizedBox(
            height: 64,
            child: LiveLogo(url: u, memCacheHeight: 128, fallback: placeholder),
          ),
        ),
      ],
    );
  }
}
