import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'preview_data.dart';
import 'preview_hover.dart';
import 'preview_look.dart';
import 'preview_parts.dart';
import 'preview_screen.dart';

/// O quadro de baixo da prévia: a opção sob o mouse, "Agora" e "Com esta
/// opção" lado a lado.
class CompareArea extends StatelessWidget {
  const CompareArea({
    super.key,
    required this.spec,
    required this.now,
    required this.data,
    required this.window,
    required this.openMode,
    required this.backdrop,
  });

  final CompareSpec? spec;
  final PreviewLook now;
  final PreviewData data;

  /// Tamanho da janela do app, em pixels lógicos.
  final Size window;

  /// Como um título baixado abre hoje.
  final String openMode;
  final ui.Image? Function(PreviewLook look) backdrop;

  @override
  Widget build(BuildContext context) {
    final current = spec;
    if (current == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: AppShape.card,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Passe o mouse sobre uma opção para comparar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }
    final next = current.change?.call(now) ?? now;
    final single = current.kind == CompareKind.banners ||
        current.kind == CompareKind.highlights;
    final same = current.kind == CompareKind.openMode
        ? current.openMode == openMode
        : next == now;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          current.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Pane(
                  label: 'Agora',
                  child: _picture(current, now, openMode),
                ),
              ),
              if (!single) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _Pane(
                    label: same
                        ? 'Com esta opção (já em uso)'
                        : 'Com esta opção',
                    child: _picture(current, next, current.openMode ?? openMode),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _picture(CompareSpec spec, PreviewLook look, String mode) {
    final parts = PreviewParts(look);
    return switch (spec.kind) {
      CompareKind.screen => PreviewScreen(
          tab: spec.tab,
          look: look,
          data: data,
          size: previewWindowSize(window, now.scalePercent, look.scalePercent),
          backdrop: backdrop(look),
        ),
      CompareKind.pieces => _Vignette(
          size: const Size(440, 260),
          parts: parts,
          backdrop: backdrop(look),
          child: _Pieces(parts: parts, data: data),
        ),
      CompareKind.openMode => _Vignette(
          size: const Size(440, 260),
          parts: parts,
          backdrop: backdrop(look),
          child: _OpenMode(parts: parts, data: data, mode: mode),
        ),
      CompareKind.banners => _Vignette(
          size: const Size(900, 220),
          parts: parts,
          backdrop: backdrop(look),
          child: _Banners(parts: parts, data: data),
        ),
      CompareKind.highlights => _Vignette(
          size: const Size(900, 280),
          parts: parts,
          backdrop: backdrop(look),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: PreviewScreen(
              tab: PreviewTab.live,
              look: look,
              data: data,
              size: window,
            ).highlightTiles(parts),
          ),
        ),
    };
  }
}

/// Um dos lados da comparação: o nome e o desenho reduzido para caber.
class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: FittedBox(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: ClipRect(child: RepaintBoundary(child: child)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette({
    required this.size,
    required this.parts,
    required this.backdrop,
    required this.child,
  });

  final Size size;
  final PreviewParts parts;
  final ui.Image? backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
        size: size,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 13,
            color: parts.p.text,
            decoration: TextDecoration.none,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [parts.ground(backdrop), child],
          ),
        ),
      );
}

/// Barra lateral, painel com texto, botões, abas, progresso e dois pôsteres.
class _Pieces extends StatelessWidget {
  const _Pieces({required this.parts, required this.data});

  final PreviewParts parts;
  final PreviewData data;

  @override
  Widget build(BuildContext context) {
    final look = parts.look;
    final p = parts.p;
    const icons = [
      Icons.home_outlined,
      Icons.live_tv_outlined,
      Icons.local_movies_outlined,
      Icons.favorite_border_rounded,
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 50,
            child: parts.panel(
              radius: look.panel,
              fill: p.barFill,
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < icons.length; i++)
                    Container(
                      height: 40,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      alignment: Alignment.center,
                      decoration: i == 0
                          ? BoxDecoration(
                              color: p.selected,
                              borderRadius: look.control,
                              border: Border.all(color: p.selectedEdge),
                            )
                          : null,
                      child: Icon(
                        icons[i],
                        size: 20,
                        color: i == 0 ? p.accentInk : p.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: parts.panel(
              radius: look.panel,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  parts.tabs(const ['Filmes', 'Séries']),
                  const SizedBox(height: 12),
                  parts.title('TÍTULO DA TELA', 24),
                  const SizedBox(height: 4),
                  parts.text('Texto de apoio das telas', color: p.muted),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Flexible(
                        child: parts.button(
                          'Assistir',
                          icon: Icons.play_arrow,
                          filled: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: parts.button('Detalhes')),
                    ],
                  ),
                  const Spacer(),
                  parts.progress(0.6, height: 5),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 2; i++)
                  SizedBox(
                    height: 110,
                    width: 78,
                    child: parts.image(
                      itemAt(data.movies, i).image,
                      radius: look.card,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ao clicar num título baixado": painel lateral, cartão grande ou player.
class _OpenMode extends StatelessWidget {
  const _OpenMode({
    required this.parts,
    required this.data,
    required this.mode,
  });

  final PreviewParts parts;
  final PreviewData data;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final look = parts.look;
    final item = itemAt(
      data.downloads.isEmpty ? data.movies : data.downloads,
      0,
    );
    Widget actions() => Row(
          children: [
            Flexible(
              child: parts.button(
                'Assistir',
                icon: Icons.play_arrow,
                filled: true,
              ),
            ),
          ],
        );
    final cards = Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < 9; i++)
            SizedBox(
              width: 124,
              height: 70,
              child: parts.image(
                itemAt(data.downloads, i).image,
                radius: look.card,
              ),
            ),
        ],
      ),
    );
    if (mode == 'player') {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            parts.image(
              item.image,
              radius: BorderRadius.zero,
              fit: BoxFit.contain,
              ground: Colors.black,
            ),
            const DecoratedBox(decoration: PreviewParts.shadeBottom),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  parts.progress(0.35, track: const Color(0x55FFFFFF)),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.replay_10, color: Colors.white, size: 24),
                      SizedBox(width: 18),
                      Icon(Icons.pause, color: Colors.white, size: 32),
                      SizedBox(width: 18),
                      Icon(Icons.forward_10, color: Colors.white, size: 24),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        cards,
        if (mode == 'panel')
          Positioned(
            top: 10,
            right: 10,
            bottom: 10,
            width: 160,
            child: parts.panel(
              radius: look.panel,
              fill: parts.p.surface,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: parts.image(item.image, radius: look.card),
                  ),
                  const SizedBox(height: 10),
                  parts.text(item.name, weight: FontWeight.w700, maxLines: 2),
                  const SizedBox(height: 8),
                  parts.bar(110),
                  const SizedBox(height: 6),
                  parts.bar(80),
                  const Spacer(),
                  actions(),
                ],
              ),
            ),
          )
        else ...[
          const ColoredBox(color: Color(0x77000000)),
          Center(
            child: SizedBox(
              width: 320,
              height: 220,
              child: parts.panel(
                radius: look.panel,
                fill: parts.p.surface,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: parts.image(item.image, radius: look.card),
                      ),
                    ),
                    const SizedBox(height: 10),
                    parts.text(item.name, weight: FontWeight.w700),
                    const SizedBox(height: 8),
                    actions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Os banners do Início como estão, com o nome de cada um.
class _Banners extends StatelessWidget {
  const _Banners({required this.parts, required this.data});

  final PreviewParts parts;
  final PreviewData data;

  @override
  Widget build(BuildContext context) {
    final count = data.banners.length.clamp(1, 5);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: parts.look.card,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    parts.image(
                      i < data.banners.length
                          ? itemAt(data.banners[i].titles, 0).image
                          : null,
                      radius: BorderRadius.zero,
                      cacheWidth: 360,
                    ),
                    const DecoratedBox(decoration: PreviewParts.shadeBottom),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: parts.text(
                        i < data.banners.length ? data.banners[i].name : '',
                        color: Colors.white,
                        weight: FontWeight.w700,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
