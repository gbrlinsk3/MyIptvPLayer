import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/play_actions.dart';
import '../catalog/poster_image.dart';

/// "Continuar assistindo": cartões horizontais (capa do servidor) que se
/// expandem ao passar o mouse e mostram "Clique aqui para assistir".
/// Sem mouse em cima, o primeiro fica expandido.
class ContinueStrip extends StatefulWidget {
  const ContinueStrip({super.key, required this.future});

  final Future<List<CatalogTitle>> future;

  @override
  State<ContinueStrip> createState() => _ContinueStripState();
}

class _ContinueStripState extends State<ContinueStrip> {
  int? _hover;

  static const _height = 200.0 + 28; // folga para sombra e borda
  static const _collapsed = 150.0;
  static const _expanded = 340.0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CatalogTitle>>(
      future: widget.future,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        final open = _hover ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'CONTINUAR ASSISTINDO',
                  style: AppFonts.title(22, spacing: 1.2),
                ),
              ),
              SizedBox(
                height: _height,
                child: MouseRegion(
                  onExit: (_) => setState(() => _hover = null),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    itemCount: list.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _ContinueCard(
                        title: list[i],
                        width: i == open ? _expanded : _collapsed,
                        expanded: i == open,
                        onEnter: () => setState(() => _hover = i),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.title,
    required this.width,
    required this.expanded,
    required this.onEnter,
  });

  final CatalogTitle title;
  final double width;
  final bool expanded;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final progress = title.progress;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(),
      child: GestureDetector(
        onTap: () => watchTitle(context, title),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: expanded ? AppColors.accent : AppColors.border,
              width: expanded ? 2 : 1,
            ),
            boxShadow: expanded
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: FutureBuilder<TitleDetails?>(
              future: catalog.detailsOrNull(title.kind, title.id),
              builder: (context, snap) => Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    url: tmdbSize(snap.data?.backdrop, 'w780') ?? title.image,
                    name: title.name,
                    cacheWidth: 700,
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
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: progress != null ? 18 : 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.name,
                          maxLines: expanded ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (title.subtitle != null && expanded)
                          Text(
                            title.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 11,
                            ),
                          ),
                        if (expanded) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'CLIQUE AQUI PARA ASSISTIR',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: AppFonts.title(
                                    13,
                                    color: Colors.white,
                                    spacing: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: const Color(0x66000000),
                        color: AppColors.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
