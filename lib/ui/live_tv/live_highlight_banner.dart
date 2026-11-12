import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/live_highlight.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';

/// Cor do degradê do banner principal numa posição `t` (0 = canto azul, 1 =
/// canto escuro). Os mini banners usam a mesma função para "continuar" o
/// desvanecer do banner principal da esquerda para a direita.
Color highlightGradientAt(double t) {
  final a = Color.lerp(AppColors.bg, AppColors.accent, 0.55)!;
  final b = Color.lerp(AppColors.bg, AppColors.accent, 0.18)!;
  final c = AppColors.bg;
  t = t.clamp(0.0, 1.0);
  return t < 0.55 ? Color.lerp(a, b, t / 0.55)! : Color.lerp(b, c, (t - 0.55) / 0.45)!;
}

/// Banner de destaques da TV ao vivo: um slide por palavra-chave (máx. 4),
/// com setas e pílulas de navegação. Em cada slide, os canais da palavra
/// ficam num carrossel pequeno no canto inferior direito (5 por vez; os dois
/// das pontas ficam mais translúcidos). Fundo: gradiente na cor do perfil
/// (os canais não trazem imagem de fundo).
class LiveHighlightBanner extends StatefulWidget {
  const LiveHighlightBanner({
    super.key,
    required this.highlights,
    required this.onOpen,
    required this.onSeeCategory,
  });

  final List<LiveHighlight> highlights;

  /// Abre o player no canal, com a lista do destaque como fila.
  final void Function(LiveChannel channel, List<LiveChannel> list) onOpen;
  final ValueChanged<String> onSeeCategory;

  static const double height = 280;

  @override
  State<LiveHighlightBanner> createState() => _LiveHighlightBannerState();
}

class _LiveHighlightBannerState extends State<LiveHighlightBanner> {
  int _index = 0;

  void _go(int delta) {
    final n = widget.highlights.length;
    setState(() => _index = (_index + delta + n) % n);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.highlights;
    if (list.isEmpty) return const SizedBox.shrink();
    final i = _index.clamp(0, list.length - 1);
    final h = list[i];
    final main = Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: SizedBox(
        height: LiveHighlightBanner.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: _Slide(
                    key: ValueKey('${h.keyword}:$i'),
                    highlight: h,
                    onOpen: widget.onOpen,
                    onSeeCategory: widget.onSeeCategory,
                  ),
                ),
                if (list.length > 1) ...[
                  _NavArrow(left: true, onTap: () => _go(-1)),
                  _NavArrow(left: false, onTap: () => _go(1)),
                  Positioned(
                    top: 14,
                    right: 0,
                    left: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var k = 0; k < list.length; k++)
                          GestureDetector(
                            onTap: () => setState(() => _index = k),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 6,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: k == i ? 28 : 10,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: k == i
                                        ? AppColors.accent
                                        : const Color(0x66FFFFFF),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      children: [
        main,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _MiniRow(
              key: ValueKey('mini:$i'),
              slide: i,
              onSeeCategory: widget.onSeeCategory,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 8 : null,
      right: left ? null : 8,
      child: Center(
        child: Material(
          color: const Color(0x66000000),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                left ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatefulWidget {
  const _Slide({
    super.key,
    required this.highlight,
    required this.onOpen,
    required this.onSeeCategory,
  });

  final LiveHighlight highlight;
  final void Function(LiveChannel channel, List<LiveChannel> list) onOpen;
  final ValueChanged<String> onSeeCategory;

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> {
  int _start = 0;

  static final _outlined = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Color(0x88FFFFFF)),
  );

  @override
  Widget build(BuildContext context) {
    final h = widget.highlight;
    final channels = h.channels;
    final cats = h.categories.map((c) => c.name).join(' · ');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(AppColors.bg, AppColors.accent, 0.55)!,
            Color.lerp(AppColors.bg, AppColors.accent, 0.18)!,
            AppColors.bg,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Quantos canais cabem no carrossel: 5 em janela larga, menos em estreita.
          final visible = box.maxWidth >= 1000 ? 5 : (box.maxWidth >= 780 ? 4 : 3);
          final shown = channels.length < visible ? channels.length : visible;
          const tile = 92.0, gap = 8.0;
          final stripWidth = shown * tile + (shown - 1) * gap;
          final canScroll = channels.length > visible;
          return Stack(
            children: [
              Positioned(
                left: 40,
                bottom: 30,
                right: stripWidth + 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DESTAQUE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      h.keyword.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.title(52, color: Colors.white, spacing: 1.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${channels.length} canais · $cats',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => widget.onOpen(channels.first, channels),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Assistir'),
                        ),
                        const SizedBox(width: 10),
                        if (h.categories.length == 1)
                          OutlinedButton(
                            onPressed: () =>
                                widget.onSeeCategory(h.categories.first.id),
                            style: _outlined,
                            child: const Text('Ver todos'),
                          )
                        else
                          OutlinedButton(
                            onPressed: () async {
                              final id = await showSeeCategoryDialog(
                                context,
                                h.categories,
                              );
                              if (id != null) widget.onSeeCategory(id);
                            },
                            style: _outlined,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Ver todos'),
                                SizedBox(width: 2),
                                Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 40,
                bottom: 30,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Nome do canal do meio, sobre os cartões.
                    SizedBox(
                      width: stripWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          channels[(_start + shown ~/ 2) % channels.length].name,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 8, color: Color(0x99000000))],
                          ),
                        ),
                      ),
                    ),
                    Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canScroll)
                      _StripButton(
                        icon: Icons.chevron_left,
                        onTap: () => setState(
                          () => _start = (_start - 1 + channels.length) % channels.length,
                        ),
                      ),
                    SizedBox(
                      width: stripWidth,
                      height: tile,
                      child: Row(
                        children: [
                          for (var k = 0; k < shown; k++) ...[
                            if (k > 0) const SizedBox(width: gap),
                            Opacity(
                              // As duas pontas ficam mais translúcidas quando há mais canais.
                              opacity: canScroll && (k == 0 || k == shown - 1) ? 0.45 : 1,
                              child: _Tile(
                                channel: channels[(_start + k) % channels.length],
                                size: tile,
                                onTap: () => widget.onOpen(
                                  channels[(_start + k) % channels.length],
                                  channels,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canScroll)
                      _StripButton(
                        icon: Icons.chevron_right,
                        onTap: () => setState(
                          () => _start = (_start + 1) % channels.length,
                        ),
                      ),
                  ],
                ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: Colors.white),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.channel, required this.size, required this.onTap});

  final LiveChannel channel;
  final double size;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final url = ch.icon;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: ch.name,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.size,
            height: widget.size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xE61F1E1D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hover ? AppColors.accent : const Color(0x33FFFFFF),
                width: _hover ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: (url == null || url.isEmpty)
                        ? const Icon(Icons.tv, color: Color(0x99FFFFFF), size: 26)
                        : Image.network(
                            url,
                            fit: BoxFit.contain,
                            cacheWidth: 160,
                            errorBuilder: (context, error, stack) =>
                                const Icon(Icons.tv, color: Color(0x99FFFFFF), size: 26),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 5),
                  child: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fileira de mini banners de uma aba do banner principal. Espaço preenchido:
/// nome da categoria, quantidade de canais e alguns logos; clicar abre a
/// categoria em grade (várias categorias: menu para escolher). Espaço vazio:
/// "+" para escolher uma categoria. O "x" (com o mouse em cima) esvazia o espaço.
class _MiniRow extends StatelessWidget {
  const _MiniRow({super.key, required this.slide, required this.onSeeCategory});

  final int slide;
  final ValueChanged<String> onSeeCategory;

  static const double height = 92;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final tokens = slide < c.miniBanners.length
        ? c.miniBanners[slide]
        : List<String>.filled(miniSlotsPerSlide, '');
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var k = 0; k < miniSlotsPerSlide; k++) ...[
            if (k > 0) const SizedBox(width: 12),
            Expanded(
              child: _MiniCard(
                banner: c.miniBannerFor(tokens[k]),
                hasToken: tokens[k].isNotEmpty,
                position: (k + 0.5) / miniSlotsPerSlide,
                onSeeCategory: onSeeCategory,
                onPick: () => _pickCategory(context, slide, k),
                onClear: () => c.setMiniBanner(slide, k, ''),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context, int slide, int slot) async {
    final c = AppScope.read(context);
    final id = await showDialog<String>(
      context: context,
      builder: (context) => _CategoryPicker(
        categories: c.categories,
        counts: c.countByCategory,
      ),
    );
    if (id != null) await c.setMiniBanner(slide, slot, 'cat:$id');
  }
}

class _MiniCard extends StatefulWidget {
  const _MiniCard({
    required this.banner,
    required this.hasToken,
    required this.position,
    required this.onSeeCategory,
    required this.onPick,
    required this.onClear,
  });

  final MiniBanner? banner;
  final bool hasToken;
  /// Posição horizontal do cartão na fileira (0 a 1), para casar a cor com o
  /// degradê do banner principal.
  final double position;
  final ValueChanged<String> onSeeCategory;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  State<_MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends State<_MiniCard> {
  bool _hover = false;

  void _open(BuildContext context, MiniBanner b) {
    if (b.categories.length == 1) {
      widget.onSeeCategory(b.categories.first.id);
      return;
    }
    showSeeCategoryDialog(context, b.categories).then((id) {
      if (id != null) widget.onSeeCategory(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    final border = Border.all(
      color: _hover ? AppColors.accent : AppColors.border,
      width: _hover ? 2 : 1,
    );
    if (b == null) {
      // Vazio (ou palavra sem categoria no seu provedor): "+" para escolher.
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPick,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: border,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline, size: 22, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Adicionar categoria',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final logos = [
      for (final ch in b.channels)
        if (ch.icon != null && ch.icon!.isNotEmpty) ch.icon!,
    ].take(3).toList();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Builder(
        builder: (context) => GestureDetector(
          onTap: () => _open(context, b),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: border,
              // Mesma cor do banner principal naquela posição: o 1º fica azul e os
              // seguintes escurecem, como se o degradê continuasse.
              color: highlightGradientAt(widget.position),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.title(22, spacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b.categories.length == 1
                                    ? '${b.channels.length} canais'
                                    : '${b.channels.length} canais · ${b.categories.length} categorias',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        for (final url in logos)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 34,
                                height: 34,
                                // Sem fundo: se a imagem do logo falhar, nada aparece
                                // (antes ficava um quadrado vazio).
                                padding: const EdgeInsets.all(3),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  cacheWidth: 80,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_hover)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Remover este mini banner',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: widget.onClear,
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Escolha de uma categoria (com filtro por nome).
class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.counts});

  final List<LiveCategory> categories;
  final Map<String, int> counts;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final f = foldText(_filter.trim());
    final list = [
      for (final c in widget.categories)
        if (f.isEmpty || foldText(c.name).contains(f)) c,
    ];
    return AlertDialog(
      title: const Text('Adicionar categoria'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _filter = v),
              decoration: fieldDecoration(
                hint: 'Filtrar categorias',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma categoria encontrada.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(
                          list[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${widget.counts[list[i].id] ?? 0}',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                        onTap: () => Navigator.of(context).pop(list[i].id),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}


/// Painel "Ver todos": escolhe qual categoria abrir quando o banner reúne
/// várias. Mesmo visual dos outros diálogos do programa.
Future<String?> showSeeCategoryDialog(
  BuildContext context,
  List<LiveCategory> categories,
) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VER TODOS', style: AppFonts.title(24, spacing: 1)),
              const SizedBox(height: 4),
              Text(
                'Escolha a categoria que quer abrir.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in categories)
                      _CategoryOption(
                        name: c.name,
                        onTap: () => Navigator.of(ctx).pop(c.id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CategoryOption extends StatefulWidget {
  const _CategoryOption({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  State<_CategoryOption> createState() => _CategoryOptionState();
}

class _CategoryOptionState extends State<_CategoryOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? AppColors.accent.withValues(alpha: 0.14) : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
