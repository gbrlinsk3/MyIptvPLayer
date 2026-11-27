
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/channel_groups.dart';
import '../widgets/full_name_tooltip.dart';
import '../widgets/press_scale.dart';
import 'blurred_logo.dart';
import 'live_logo.dart';

/// Cartão de "Recentes e favoritos" da TV ao vivo, no visual do cartão do
/// "Continuar assistindo": logo sobre o próprio logo desfocado, nome e versões
/// embaixo. Fica compacto ([collapsedWidth]) e se expande ([expandedWidth])
/// quando [expanded]. Expandido, mostra no canto superior direito o coração
/// (favorito) ou o X (apenas recente) e a linha de versões; compacto, só um
/// coração pequeno como indicador de favorito.
class LiveRecentCard extends StatefulWidget {
  const LiveRecentCard({
    super.key,
    required this.group,
    required this.current,
    required this.favorite,
    required this.recent,
    required this.expanded,
    required this.onTap,
    this.onEnter,
    this.onToggleFavorite,
    this.onRemoveRecent,
  });

  final ChannelGroup group;

  /// É o canal que está tocando.
  final bool current;
  final bool favorite;
  final bool recent;

  /// Cartão aberto (largura [expandedWidth], com versões e botões).
  final bool expanded;

  /// O mouse entrou no cartão (quem controla [expanded] guarda o índice).
  final VoidCallback? onEnter;

  /// Clique no cartão: toca o canal.
  final VoidCallback onTap;

  /// Clique no coração (só aparece quando [favorite] e [expanded]).
  final VoidCallback? onToggleFavorite;

  /// Clique no X (só aparece quando é apenas recente: [recent] e não
  /// [favorite], e [expanded]).
  final VoidCallback? onRemoveRecent;

  static const double height = 144;
  static const double expandedWidth = 256;
  static const double collapsedWidth = 112;

  @override
  State<LiveRecentCard> createState() => _LiveRecentCardState();
}

class _LiveRecentCardState extends State<LiveRecentCard> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final n = g.versions.length;
    final labels = <String>[];
    for (final v in g.versions) {
      final l = g.labelOf(v).replaceAll(' [ALT]', '');
      if (!labels.contains(l)) labels.add(l);
    }
    final String? versions = (labels.isEmpty ||
            (labels.length == 1 && labels.first == 'Padrão'))
        ? null
        : labels.join(' · ');

    final bool expanded = widget.expanded;
    final bool strong = widget.current || _focus || expanded;
    final Duration dur = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    final Widget? action;
    if (!expanded) {
      // Compacto: só um indicador (sem ação) de que é favorito.
      action = widget.favorite
          ? Icon(Icons.favorite, size: 16, color: AppColors.accentOnMedia)
          : null;
    } else if (widget.favorite) {
      action = CornerButton(
        icon: Icons.favorite,
        iconColor: AppColors.accentOnMedia,
        tooltip: 'Remover dos favoritos',
        onPressed: widget.onToggleFavorite,
      );
    } else if (widget.recent) {
      action = CornerButton(
        icon: Icons.close,
        iconColor: Colors.white,
        tooltip: 'Tirar dos recentes',
        onPressed: widget.onRemoveRecent,
      );
    } else {
      action = null;
    }

    return Semantics(
      container: true,
      button: true,
      label: '${g.displayName}, $n ${n == 1 ? 'versão' : 'versões'}',
      onTap: widget.onTap,
      child: FullNameTooltip(
        fullName: g.displayName,
        shownName: shortChannelName(g.displayName),
        // O mouse em cima expande o cartão: mede na largura expandida.
        style: const TextStyle(
          fontSize: 16,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        textWidth: LiveRecentCard.expandedWidth - 28,
        verticalOffset: LiveRecentCard.height / 2 + 4,
        child: PressScale(
          child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => widget.onEnter?.call(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: dur,
                curve: Curves.easeOutCubic,
                width: expanded
                    ? LiveRecentCard.expandedWidth
                    : LiveRecentCard.collapsedWidth,
                height: LiveRecentCard.height,
                decoration: BoxDecoration(
                  borderRadius: AppShape.card,
                  border: Border.all(
                    color: strong ? AppColors.accentOnMedia : AppColors.border,
                    width: strong ? 2 : 1,
                  ),
                  boxShadow: expanded
                      ? [
                          BoxShadow(
                            color: AppColors.accentOnMedia.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: AppShape.inset(2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: _Backdrop(
                          url: g.icon,
                          expanded: expanded,
                          duration: dur,
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xCC000000)],
                            stops: [0.35, 1],
                          ),
                        ),
                      ),
                      // Os textos usam a largura disponível com reticências, então
                      // não estouram em nenhum quadro da animação de largura.
                      Positioned(
                        left: expanded ? 14 : 8,
                        right: expanded ? 14 : 8,
                        bottom: 12,
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: dur,
                                curve: Curves.easeOutCubic,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: expanded ? 16 : 13,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: Text(shortChannelName(g.displayName)),
                              ),
                              if (expanded && versions != null)
                                Text(
                                  versions,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xCCFFFFFF),
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (action != null)
                        Positioned(
                          top: expanded ? 4 : 8,
                          right: expanded ? 4 : 8,
                          child: action,
                        ),
                    ],
                  ),
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

/// Botão redondo (28 px, fundo preto translúcido) com alvo de 32 px. Usado
/// também no "Continuar assistindo" do Início.
class CornerButton extends StatelessWidget {
  const CornerButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: tooltip,
      onTap: onPressed,
      excludeSemantics: true,
      child: PressShield(
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                customBorder: AppShape.button,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: AppShape.control,
                    ),
                    child: Icon(icon, size: 16, color: iconColor),
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

/// Fundo: o logo ampliado, desfocado e escurecido, com o logo (≈56 px
/// expandido, ≈48 px compacto) acima do centro. Sem logo, ou se ele falhar,
/// mostra o ícone de TV.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.url,
    required this.expanded,
    required this.duration,
  });

  final String? url;
  final bool expanded;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bg = ColoredBox(color: AppColors.hover);
    final placeholder = Center(
      child: Icon(Icons.live_tv, size: 32, color: AppColors.textMuted),
    );
    final u = url;
    if (u == null || u.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          bg,
          Align(alignment: const Alignment(0, -0.35), child: placeholder),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        BlurredLogo(
          url: u,
          sigma: 24,
          memCacheHeight: 64,
          fallback: AppColors.hover,
        ),
        const ColoredBox(color: Color(0x73000000)),
        AnimatedPositioned(
          duration: duration,
          curve: Curves.easeOutCubic,
          top: expanded ? 22 : 28,
          left: 0,
          right: 0,
          height: expanded ? 56 : 48,
          child: LiveLogo(
            url: u,
            memCacheHeight: 112,
            fallback: placeholder,
          ),
        ),
      ],
    );
  }
}
