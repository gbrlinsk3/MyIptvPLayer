import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/live_highlight.dart';
import '../core/layout_metrics.dart';
import '../core/theme.dart';
import '../profiles/profiles_scope.dart';
import '../state/app_scope.dart';
import '../catalog/home_banners.dart' show BannerConfig;
import 'home/banner_manager_dialog.dart';
import 'downloads/downloads_settings_card.dart';
import 'account_xtream_card.dart';
import 'background_settings_card.dart';
import 'theme_settings_card.dart';
import 'diagnostics_card.dart';
import 'catalog_settings_card.dart';
import 'epg_settings_card.dart';
import 'personalization/preview_hover.dart';
import 'personalization/preview_pane.dart';
import 'update/update_settings_card.dart';
import 'profiles/profile_avatar.dart';
import 'profiles/profile_editor_dialog.dart';
import 'widgets/common.dart';
import 'widgets/rubber_segment.dart';
import 'widgets/smooth_scroll.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _userAgent;
  late final TextEditingController _keywords;
  int _tab = 0;

  static const int _personalization = 2;

  /// Largura da coluna de ajustes e o mínimo para a prévia caber ao lado
  /// (abaixo disso os ajustes ficam no centro, sem prévia).
  static const double _cardsWidth = 640;
  static const double _minPreview = 360;

  /// 0 = ajustes no centro; 1 = à esquerda, com a prévia ao lado.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addStatusListener((status) {
      _setMoving(status.isAnimating);
      // De volta ao centro: a prévia sai da árvore.
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
  late final Animation<double> _move = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeInOutCubic,
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _slide,
    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
  );

  /// A opção de Personalização sob o mouse.
  final ValueNotifier<CompareSpec?> _hover = ValueNotifier(null);

  /// A rolagem dos ajustes.
  ScrollController? _scroll;

  /// Verdadeiro enquanto os ajustes rolam ou deslizam: a prévia grande vira
  /// uma foto, para não ser redesenhada peça por peça a cada quadro.
  final ValueNotifier<bool> _moving = ValueNotifier(false);
  Timer? _settle;

  void _setMoving(bool moving) {
    _settle?.cancel();
    if (moving) {
      _moving.value = true;
    } else {
      // A roda gira em passos: espera um pouco para não refazer a foto a cada
      // um deles.
      _settle = Timer(const Duration(milliseconds: 600), () {
        _moving.value = false;
      });
    }
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    // As abas ficam paradas no alto: a escolhida começa do começo.
    if (_scroll?.hasClients ?? false) _scroll!.jumpTo(0);
    setState(() => _tab = tab);
    _hover.value = null;
    final open = tab == _personalization;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = open ? 1 : 0;
    } else if (open) {
      // A prévia é montada neste quadro, ainda invisível; o movimento começa
      // no seguinte, sem pular o pedaço gasto na montagem.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab == _personalization) _slide.forward();
      });
    } else {
      _slide.reverse();
    }
  }

  List<CompareSpec> _appearanceSpecs() {
    final windowsDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    return [
      for (final (pref, name) in const [
        (ThemePref.light, 'Claro'),
        (ThemePref.dark, 'Escuro'),
        (ThemePref.system, 'Sistema'),
        (ThemePref.auto, 'Automático'),
      ])
        CompareSpec(
          'aparencia.${pref.name}',
          pref == ThemePref.system || pref == ThemePref.auto
              ? 'Aparência: $name (agora: '
                  '${resolveDark(pref, platformDark: windowsDark) ? 'escuro' : 'claro'})'
              : 'Aparência: $name',
          change: (look) => look.copyWith(
            pref: pref,
            dark: resolveDark(pref, platformDark: windowsDark),
          ),
        ),
    ];
  }

  static String _widthTitle(BuildContext context, int px) {
    if (px == CatalogWidth.fill) return 'Largura do catálogo: Preenchido';
    final title = 'Largura do catálogo: $px px';
    // 68 = a barra lateral, que fica fora da coluna.
    return MediaQuery.sizeOf(context).width - 68 <= px
        ? '$title (nesta janela fica igual a Preenchido)'
        : title;
  }

  @override
  void initState() {
    super.initState();
    _userAgent = TextEditingController(text: AppScope.read(context).userAgent);
    _keywords = TextEditingController(
      text: AppScope.read(context).highlightKeywords.join(', '),
    );
  }

  @override
  void dispose() {
    _userAgent.dispose();
    _keywords.dispose();
    _slide.dispose();
    _settle?.cancel();
    _hover.dispose();
    _moving.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // O título e as abas ficam parados no centro; só os ajustes se movem.
    return PreviewHover(
      notifier: _hover,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: LayoutBuilder(builder: _body)),
        ],
      ),
    );
  }

  Widget _header() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _cardsWidth),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTA E AJUSTES',
                    style: AppFonts.title(34, spacing: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Pílula elástica que se estica até a aba escolhida.
                  RubberSegment<int>(
                    overBackdrop: true,
                    values: const [0, 1, 2],
                    labelOf: (v) =>
                        const ['Conta', 'Configurações', 'Personalização'][v],
                    iconOf: (v) => const [
                      Icons.person_outline,
                      Icons.settings_outlined,
                      Icons.palette_outlined,
                    ][v],
                    selected: _tab,
                    onChanged: _selectTab,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _body(BuildContext context, BoxConstraints box) {
    final window = MediaQuery.sizeOf(context);
    final cards = math.min(_cardsWidth, box.maxWidth);
    final centered = (box.maxWidth - cards) / 2;
    final room = Size(
      math.max(0, box.maxWidth - cards - 24),
      math.max(0, box.maxHeight - 24),
    );
    final pane = previewPaneLayout(room, window.width / window.height).width;
    final fits = pane >= _minPreview;
    // Ajustes e prévia juntos, centralizados no que sobrar.
    final left =
        fits ? math.max(0.0, (box.maxWidth - cards - pane - 24) / 2) : centered;
    final showPane = fits && (_tab == _personalization || !_slide.isDismissed);

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _move,
          builder: (context, child) => Positioned(
            left: centered + (left - centered) * _move.value,
            top: 0,
            bottom: 0,
            width: cards,
            child: child!,
          ),
          child: RepaintBoundary(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical) {
                  if (n is ScrollStartNotification) _setMoving(true);
                  if (n is ScrollEndNotification) _setMoving(false);
                }
                return false;
              },
              child: _settings(context),
            ),
          ),
        ),
        if (showPane)
          Positioned(
            left: left + cards,
            top: 0,
            bottom: 24,
            width: pane,
            child: IgnorePointer(
              ignoring: _tab != _personalization,
              child: FadeTransition(
                opacity: _reveal,
                child: SlideTransition(
                  position: _reveal.drive(
                    Tween(begin: const Offset(0.05, 0), end: Offset.zero),
                  ),
                  child: RepaintBoundary(
                    child: PreviewPane(hover: _hover, moving: _moving),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _settings(BuildContext context) {
    final c = AppScope.of(context);
    return SmoothScroll(
      builder: (_, smooth) => ListView(
        controller: _scroll = smooth,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          if (_tab == 0) ...[
          if (c.dbRecovered)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'O banco de dados local estava ilegível e foi recriado. '
                'O arquivo antigo foi guardado ao lado dele, com final ".corrupt-…".',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          const _ProfileCard(),
          const XtreamCard(),
          SectionCard(
            title: 'Sessão',
            children: [
              OutlinedButton(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    title: 'Sair da conta?',
                    message:
                        'Remove a conta e o catálogo salvos neste computador. '
                        'Você precisará entrar de novo.',
                    action: 'Sair',
                  );
                  if (ok) await c.logout();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.border),
                ),
                child: const Text('Sair'),
              ),
            ],
          ),

          ] else if (_tab == 1) ...[
          const UpdateSettingsCard(),
          SectionCard(
            title: 'Reprodução',
            children: [
              Text(
                'Formato do link do canal',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ts', label: Text('.ts')),
                  ButtonSegment(value: 'm3u8', label: Text('.m3u8')),
                ],
                selected: {c.streamExt},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    c.setStreamExt(selection.first),
              ),
              const SizedBox(height: 4),
              Text(
                'Vale a partir do próximo canal aberto. Se os canais não abrirem, teste o outro formato.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text(
                'User-Agent (opcional)',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userAgent,
                      onSubmitted: c.setUserAgent,
                      decoration: fieldDecoration(
                        hint: 'Vazio = padrão do player',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => c.setUserAgent(_userAgent.text),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
          const DownloadsSettingsCard(),
          const EpgSettingsCard(),
          const DiagnosticsCard(),
          const CatalogSettingsCard(),
          ] else ...[
          const ThemeSettingsCard(),
          SectionCard(
            title: 'Aparência',
            children: [
              HoverRange.segments(
                specs: _appearanceSpecs(),
                child: AppearanceSelector(
                  selected: c.themePref,
                  onChanged: c.setThemePref,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sistema segue o claro/escuro do Windows. Automático usa o '
                'horário do computador: claro das 9h às 17h, escuro das 17h às 9h.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const BackgroundSettingsCard(),
          SectionCard(
            title: 'Formato da interface',
            children: [
              HoverRange.segments(
                specs: [
                  CompareSpec(
                    'formato.reto',
                    'Formato: Quadrados',
                    change: (look) => look.copyWith(rounded: false),
                  ),
                  CompareSpec(
                    'formato.redondo',
                    'Formato: Arredondados',
                    change: (look) => look.copyWith(rounded: true),
                  ),
                ],
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'square',
                      icon: Icon(Icons.crop_square, size: 18),
                      label: Text('Quadrados'),
                    ),
                    ButtonSegment(
                      value: 'rounded',
                      icon: Icon(Icons.rounded_corner, size: 18),
                      label: Text('Arredondados'),
                    ),
                  ],
                  selected: {c.buttonShape},
                  onSelectionChanged: (v) => c.setButtonShape(v.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Quadrados deixa os cantos retos. Arredondados usa botões em '
                'pílula e cantos suaves.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          SectionCard(
            title: 'Tamanho da interface',
            children: [
              HoverRange.segments(
                specs: [
                  for (final p in UiSizes.percents)
                    CompareSpec(
                      'tamanho.$p',
                      'Tamanho da interface: $p %',
                      kind: CompareKind.screen,
                      change: (look) => look.copyWith(scalePercent: p),
                    ),
                ],
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in UiSizes.percents)
                      ButtonSegment(value: p, label: Text('$p %')),
                  ],
                  selected: {c.uiScalePercent},
                  onSelectionChanged: (v) => c.setUiScalePercent(v.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Amplia o programa inteiro (menus, botões, janelas). 100 % é o '
                'tamanho de antes; o padrão é ${UiSizes.defaultPercent} %. '
                'Também define quantos pôsteres cabem por linha. Em janelas '
                'maiores que 1920 × 1100, tudo cresce junto com a janela. Em '
                'janelas perto de Full HD ou maiores, a escala do Windows não '
                'é somada.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          SectionCard(
            title: 'Largura do catálogo',
            children: [
              HoverRange.segments(
                specs: [
                  for (final px in CatalogWidth.options)
                    CompareSpec(
                      'largura.$px',
                      _widthTitle(context, px),
                      kind: CompareKind.screen,
                      change: (look) => look.copyWith(catalogWidth: px),
                    ),
                ],
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final px in CatalogWidth.options)
                      ButtonSegment(
                        value: px,
                        label: Text(
                          px == CatalogWidth.fill ? 'Preenchido' : '$px px',
                        ),
                      ),
                  ],
                  selected: {c.catalogWidth},
                  onSelectionChanged: (v) => c.setCatalogWidth(v.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Largura máxima do conteúdo das telas, centralizado. '
                'Preenchido usa a janela inteira (padrão). Os pixels contam '
                'já com o tamanho da interface: a ${UiSizes.defaultPercent} %, '
                '1440 ocupa cerca de ${(1440 * UiSizes.defaultPercent / 100).round()} px '
                'numa janela de até 1920 × 1100.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          SectionCard(
            title: 'Minha biblioteca',
            children: [
              Text(
                'Ao clicar num título baixado',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              HoverRange.segments(
                specs: const [
                  CompareSpec(
                    'biblioteca.panel',
                    'Título baixado: Card',
                    kind: CompareKind.openMode,
                    openMode: 'panel',
                  ),
                  CompareSpec(
                    'biblioteca.expanded',
                    'Título baixado: Card expandido',
                    kind: CompareKind.openMode,
                    openMode: 'expanded',
                  ),
                  CompareSpec(
                    'biblioteca.player',
                    'Título baixado: Reproduzir',
                    kind: CompareKind.openMode,
                    openMode: 'player',
                  ),
                ],
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'panel', label: Text('Card')),
                    ButtonSegment(value: 'expanded', label: Text('Card expandido')),
                    ButtonSegment(value: 'player', label: Text('Reproduzir')),
                  ],
                  selected: {c.libraryOpenMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => c.setLibraryOpenMode(s.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Arquivos importados e gravações sempre abrem direto no player.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          HoverCompare(
            spec: const CompareSpec(
              'banners',
              'Banners do Início',
              kind: CompareKind.banners,
            ),
            child: SectionCard(
              title: 'Banners do Início',
              children: [
                KeyValueRow(
                  label: 'Banners',
                  value: '${c.catalog.banners.length} de ${BannerConfig.maxExtra}',
                ),
                Text(
                  '"Continue de onde parou" aparece sozinho quando há algo em '
                  'andamento e não conta nesse limite.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => showBannerManager(context),
                    child: const Text('Gerenciar banners'),
                  ),
                ),
              ],
            ),
          ),
          HoverCompare(
            spec: const CompareSpec(
              'highlights',
              'Destaques da TV ao vivo',
              kind: CompareKind.highlights,
            ),
            child: SectionCard(
              title: 'Destaques da TV ao vivo',
              children: [
                Text(
                  'Destaques da TV ao vivo',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Palavras-chave separadas por vírgula, na ordem dos banners. '
                  'Cada palavra que aparecer no nome de uma categoria vira um '
                  'banner no topo da TV ao vivo (máximo de 4). Vazio = sem banners.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keywords,
                  decoration: fieldDecoration(hint: 'Esportes, Notícias, Filmes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () =>
                          c.setHighlightKeywords(_keywords.text.split(',')),
                      child: const Text('Salvar destaques'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        _keywords.text = defaultHighlightKeywords.join(', ');
                        c.setHighlightKeywords(defaultHighlightKeywords);
                      },
                      child: const Text('Restaurar padrão'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final profiles = ProfilesScope.of(context);
    final profile = profiles.session?.profile;
    if (profile == null) return const SizedBox.shrink();
    return SectionCard(
      title: 'Perfil',
      children: [
        Row(
          children: [
            ProfileAvatar.of(profile, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                profile.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'A conta Xtream, o catálogo, as categorias ocultas, as fontes EPG e os '
          'ajustes abaixo pertencem a este perfil.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: () => showProfileEditor(
                context,
                existing: profile,
                isActive: true,
              ),
              child: const Text('Editar perfil'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => profiles.leave(),
              child: const Text('Trocar de perfil'),
            ),
          ],
        ),
      ],
    );
  }
}
