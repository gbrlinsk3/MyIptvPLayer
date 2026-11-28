import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/app_scope.dart';
import '../widgets/rubber_segment.dart';
import 'preview_compare.dart';
import 'preview_data.dart';
import 'preview_hover.dart';
import 'preview_look.dart';
import 'preview_screen.dart';

/// As medidas do painel para o espaço que ele tem: a prévia grande com a
/// proporção da janela e, abaixo, a comparação.
({double width, double screen, double compare}) previewPaneLayout(
  Size room,
  double aspect,
) {
  const fixed = _PreviewPaneState._tabsHeight + 2 * _PreviewPaneState._gap;
  final free = math.max(0.0, room.height - fixed);
  final compare = (free * 0.36).clamp(170.0, 300.0);
  final width = math.max(
    0.0,
    math.min(
      math.min(room.width, _PreviewPaneState._maxWidth),
      math.max(0.0, free - compare) * aspect,
    ),
  );
  return (width: width, screen: width / aspect, compare: compare);
}

/// À direita dos ajustes de Personalização: as quatro abas principais como
/// ficam com a personalização atual e, embaixo, a opção sob o mouse.
class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key, required this.hover, this.moving});

  final ValueNotifier<CompareSpec?> hover;

  /// Enquanto for verdadeiro, a prévia grande é desenhada de uma foto.
  final ValueListenable<bool>? moving;

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  static const double _tabsHeight = 44;
  static const double _gap = 12;
  static const double _maxWidth = 1200;

  PreviewTab _tab = PreviewTab.home;
  PreviewData _data = const PreviewData();
  final PreviewBackdrops _backdrops = PreviewBackdrops();

  /// Do que [_data] depende: mudou (banners ou destaques editados), relê.
  String? _loaded;

  /// A foto da prévia grande, usada só durante o movimento: parada, a tela não
  /// produz quadros, e a próxima foto já sai com as imagens que chegaram.
  final SnapshotController _snapshot = SnapshotController();

  void _onMoving() {
    _snapshot.allowSnapshotting = widget.moving?.value ?? false;
  }

  @override
  void initState() {
    super.initState();
    widget.moving?.addListener(_onMoving);
    _onMoving();
  }

  @override
  void didUpdateWidget(PreviewPane old) {
    super.didUpdateWidget(old);
    if (old.moving == widget.moving) return;
    old.moving?.removeListener(_onMoving);
    widget.moving?.addListener(_onMoving);
    _onMoving();
  }

  void _loadData(String key) {
    if (_loaded == key) return;
    _loaded = key;
    PreviewData.load(AppScope.read(context)).then((data) {
      if (mounted && _loaded == key) setState(() => _data = data);
    });
  }

  @override
  void dispose() {
    widget.moving?.removeListener(_onMoving);
    _snapshot.dispose();
    _backdrops.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    _loadData(
      '${c.catalog.bannersRevision}|${c.catalog.progressRevision}|'
      '${c.highlightKeywords.join(',')}',
    );
    final now = PreviewLook.of(c);
    final window = MediaQuery.sizeOf(context);
    final aspect = window.width / window.height;

    return LayoutBuilder(
      builder: (context, box) {
        final layout = previewPaneLayout(box.biggest, aspect);
        return ListenableBuilder(
          listenable: _backdrops,
          builder: (context, _) => Column(
            children: [
              SizedBox(
                height: _tabsHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RubberSegment<PreviewTab>(
                    overBackdrop: true,
                    values: PreviewTab.values,
                    labelOf: (t) => t.label,
                    selected: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
              ),
              const SizedBox(height: _gap),
              SizedBox(
                width: layout.width,
                height: layout.screen,
                child: _screen(now, window, c.backgroundBlur),
              ),
              const SizedBox(height: _gap),
              SizedBox(
                width: layout.width,
                height: layout.compare,
                // Só a comparação é refeita quando o mouse muda de opção.
                child: RepaintBoundary(
                  child: ValueListenableBuilder<CompareSpec?>(
                    valueListenable: widget.hover,
                    builder: (context, spec, _) => ExcludeSemantics(
                      child: IgnorePointer(
                        child: CompareArea(
                          spec: spec,
                          now: now,
                          data: _data,
                          window: window,
                          openMode: c.libraryOpenMode,
                          backdrop: (look) => _backdrops.of(
                            look,
                            currentBlur: c.backgroundBlur,
                          ),
                        ),
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

  Widget _screen(PreviewLook now, Size window, int blur) {
    final media = MediaQuery.of(context);
    // Pontos físicos por ponto lógico daqui: inclui o "Tamanho da interface",
    // que amplia a tela por fora. Sem isso a foto sai menor e embaçada.
    final pixels = math.max(
      media.devicePixelRatio,
      View.of(context).physicalSize.width / window.width,
    );
    return Semantics(
      image: true,
      label: 'Prévia da aba ${_tab.label}',
      excludeSemantics: true,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: AppShape.card,
        ),
        child: ClipRRect(
          borderRadius: AppShape.card,
          child: MediaQuery(
            data: media.copyWith(devicePixelRatio: pixels),
            child: SnapshotWidget(
              controller: _snapshot,
              mode: SnapshotMode.permissive,
              autoresize: true,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: media.disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  child: FittedBox(
                    key: ValueKey(_tab),
                    fit: BoxFit.fill,
                    child: RepaintBoundary(
                      child: PreviewScreen(
                        tab: _tab,
                        look: now,
                        data: _data,
                        size: window,
                        backdrop: _backdrops.of(now, currentBlur: blur),
                      ),
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
