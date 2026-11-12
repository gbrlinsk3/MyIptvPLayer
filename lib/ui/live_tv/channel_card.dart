import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';

/// Fileira de canais de uma categoria: título como divisor e cartões
/// horizontais (ícone + nome) rolando para o lado, como no catálogo.
class ChannelRow extends StatefulWidget {
  const ChannelRow({
    super.key,
    required this.label,
    required this.channels,
    required this.onOpen,
    this.onSeeAll,
  });

  final String label;
  final List<LiveChannel> channels;
  final ValueChanged<LiveChannel> onOpen;
  final VoidCallback? onSeeAll;

  /// Altura fixa da fileira (título + cartões + folgas). Fixa de propósito:
  /// alturas variáveis faziam a rolagem "pular" antes.
  static const double extent = 40 + ChannelCard.height + 24 + 20;

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  final ScrollController _scroll = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    const itemWidth = ChannelCard.width + 12;
    final list = widget.channels;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.title(22, spacing: 1.2),
                    ),
                  ),
                  Text(
                    '${list.length}',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  if (widget.onSeeAll != null)
                    TextButton(
                      onPressed: widget.onSeeAll,
                      child: const Text('Ver tudo'),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: ChannelCard.height + 24,
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemExtent: itemWidth,
                  // Folga em cima e embaixo: o cartão cresce ao passar o mouse.
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChannelCard(
                      channel: list[i],
                      onTap: () => widget.onOpen(list[i]),
                    ),
                  ),
                ),
                if (_hover && list.length > 4) ...[
                  _Arrow(left: true, onTap: () => _scrollBy(-itemWidth * 3)),
                  _Arrow(left: false, onTap: () => _scrollBy(itemWidth * 3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 4 : null,
      right: left ? null : 4,
      child: Center(
        child: Material(
          color: const Color(0xCC1F1E1D),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                left ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão horizontal de um canal: logo à esquerda, nome ao lado e coração
/// de favorito (aparece ao passar o mouse; fica fixo se for favorito).
class ChannelCard extends StatefulWidget {
  const ChannelCard({super.key, required this.channel, required this.onTap});

  final LiveChannel channel;
  final VoidCallback onTap;

  static const double width = 252;
  static const double height = 96;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final ch = widget.channel;
    final fav = c.isFavorite(ch.streamId);
    final playing = c.selected?.streamId == ch.streamId;
    final highlight = _hover || playing || fav;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.03 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: ChannelCard.height,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Favorito: fundo levemente tingido na cor de destaque do perfil.
              color: fav
                  ? Color.lerp(AppColors.surface, AppColors.accent, 0.14)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight ? AppColors.accent : AppColors.border,
                width: highlight ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Logo(url: ch.icon),
                const SizedBox(width: 12),
                Expanded(
                  // Texto centralizado na vertical em relação ao logo.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ch.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: (playing || fav) ? AppColors.accent : AppColors.text,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: (_hover || fav)
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: fav
                              ? 'Remover dos favoritos'
                              : 'Adicionar aos favoritos',
                          onPressed: () => c.toggleFavorite(ch),
                          icon: Icon(
                            fav ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: fav ? AppColors.accent : AppColors.textMuted,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(Icons.tv, size: 28, color: AppColors.textMuted);
    // Ocupa a altura toda do cartão: encosta na borda esquerda, no topo e embaixo
    // (o cartão recorta os cantos arredondados).
    return Container(
      width: ChannelCard.height,
      padding: const EdgeInsets.all(10),
      color: AppColors.hover,
      alignment: Alignment.center,
      child: (url == null || url!.isEmpty)
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.contain,
              cacheWidth: 160,
              errorBuilder: (context, error, stack) => placeholder,
            ),
    );
  }
}
