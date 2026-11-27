import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'core/app_info.dart';
import 'core/theme.dart';
import 'playback/playback_controller.dart';
import 'profiles/profiles_controller.dart';
import 'profiles/profiles_scope.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'ui/home/hero_art.dart';
import 'ui/live_tv/blurred_logo.dart';
import 'ui/login_page.dart';
import 'ui/profiles/profile_picker_page.dart';
import 'ui/shell.dart';
import 'ui/update/update_toast.dart';
import 'ui/widgets/app_backdrop.dart';
import 'ui/widgets/intro_sound.dart';
import 'ui/widgets/morph_reveal.dart';
import 'ui/widgets/profile_intro.dart';
import 'ui/widgets/rebuild_on_change.dart';
import 'ui/widgets/ui_scale.dart';
import 'ui/window/hibernator.dart';
import 'ui/window/title_bar.dart';
import 'update/app_updater.dart';

class IptvApp extends StatefulWidget {
  const IptvApp({super.key});

  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> with WidgetsBindingObserver {
  late final PlaybackController _playback;
  late final ProfilesController _profiles;
  late final Hibernator _hibernator;

  @override
  void initState() {
    super.initState();
    _playback = PlaybackController();
    _profiles = ProfilesController(_playback)..load();
    WidgetsBinding.instance.addObserver(this);
    // Minimizado: para de desenhar e, sem nada tocando ou gravando, hiberna.
    _hibernator = Hibernator(
      busy: () => _playback.isPlaying || _playback.recState != RecState.idle,
    )..attach();
    // Tema "Automático" (por horário): confere a hora de tempos em tempos e só
    // reconstrói a interface quando o claro/escuro muda de fato.
    _themeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final pref = _profiles.session?.app.themePref;
      if (pref != ThemePref.auto || !mounted) return;
      if (resolveDark(pref!, platformDark: _platformDark) != AppColors.isDark) {
        setState(() {});
      }
    });
    _startupUpdateCheck();
  }

  Timer? _themeTimer;

  bool get _platformDark =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  /// Procura atualização a cada abertura (tela de carregamento por até ~6 s).
  bool _checkingUpdate = true;

  Future<void> _startupUpdateCheck() async {
    try {
      final updater = AppUpdater.instance;
      await updater.loadConfig();
      if (updater.configured) await updater.check();
    } catch (_) {
      // O atualizador nunca deve impedir o app de abrir.
    }
    if (mounted) setState(() => _checkingUpdate = false);
  }

  /// Tema "Sistema": acompanha o claro/escuro do Windows.
  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  ThemeData? _theme;
  String? _themeKey;

  ThemeData _themeFor(bool dark) {
    final key = '$dark-${AppColors.minimal}-'
        '${AppColors.accent.toARGB32()}-${AppShape.rounded}';
    if (_themeKey != key) {
      _themeKey = key;
      _theme = buildTheme();
    }
    return _theme!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeTimer?.cancel();
    _hibernator.dispose();
    _profiles.dispose();
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfilesScope(
      controller: _profiles,
      child: ListenableBuilder(
        listenable: _profiles,
        builder: (context, _) {
          final session = _profiles.session;
          if (session == null) return _themed(null);
          // Um AppScope por perfil: trocar de perfil recria a interface inteira.
          return AppScope(
            key: ValueKey(session.profile.id),
            controller: session.app,
            // O tema tem notificador próprio; este builder é recriado a cada
            // troca de perfil, então sempre escuta o notificador do perfil atual.
            child: ListenableBuilder(
              listenable: Listenable.merge(
                [
                  session.app.themeNotifier,
                  session.app.shapeRevision,
                  session.app.lookRevision,
                  session.app.scaleNotifier,
                ],
              ),
              builder: (context, _) => _themed(session),
            ),
          );
        },
      ),
    );
  }

  Widget _themed(ProfileSession? session) {
    final dark = resolveDark(
      session?.app.themePref ?? ThemePref.dark,
      platformDark: _platformDark,
    );
    // As cores são estáticas: atualiza a paleta e recria a árvore (key).
    AppColors.applyBrightness(dark);
    return MaterialApp(
      key: ValueKey(dark),
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      // Sem a barra de rolagem padrão: a posição aparece na faixa de traços
      // da borda direita (ver ContentFrame / EdgeScrollMarks).
      scrollBehavior: MaterialScrollBehavior().copyWith(scrollbars: false),
      theme: _themeFor(dark),
      // "Tamanho da interface": tudo (telas, diálogos, botões da janela e
      // aviso de atualização) fica dentro da mesma ampliação. Antes de entrar
      // num perfil não há ajuste salvo: tamanho 100 %.
      builder: (context, child) => RebuildOnChange(
        // Valores lidos direto (sem Theme): quando mudam, redesenha tudo.
        value: (AppShape.rounded, AppColors.minimal, AppColors.accent),
        child: UiScale(
          scale: session?.app.uiScale ?? 1.0,
          child: Stack(
            children: [
              if (child != null) Positioned.fill(child: child),
              const WindowButtonsOverlay(),
              const UpdateToast(),
            ],
          ),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        child: _checkingUpdate
            ? const StartupSplash(key: ValueKey('splash'))
            : session == null
                ? const _Entry(key: ValueKey('entry'))
                : const _Root(key: ValueKey('root')),
      ),
    );
  }
}

/// Antes de entrar em um perfil: carregando, erro fatal ou "Quem está assistindo?".
class _Entry extends StatelessWidget {
  const _Entry({super.key});

  @override
  Widget build(BuildContext context) {
    final profiles = ProfilesScope.of(context);
    if (profiles.loading) return const PlainFrame(child: _Splash());
    if (!profiles.ready) {
      return PlainFrame(
        child: _FatalScreen(error: profiles.error ?? 'Erro desconhecido'),
      );
    }
    return const PlainFrame(child: ProfilePickerPage());
  }
}

class _Root extends StatefulWidget {
  const _Root({super.key});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  // Animação de abertura ao entrar no perfil (cobre o carregamento). Ao fim da
  // cena, ela e o Início são capturados como imagens e trocados com a transição
  // "derreter" do Morph Slider (MorphReveal).
  bool _intro = true;
  bool _sceneDone = false;
  bool _morphStarted = false;
  ui.Image? _fromImage;
  ui.Image? _toImage;
  final _sceneKey = GlobalKey();
  final _pageKey = GlobalKey();
  final _introSound = IntroSound();

  /// A tela principal foi desmontada pela hibernação.
  bool _slept = false;

  @override
  void initState() {
    super.initState();
    Hibernator.asleep.addListener(_onHibernate);
  }

  @override
  void dispose() {
    Hibernator.asleep.removeListener(_onHibernate);
    _introSound.dispose();
    _fromImage?.dispose();
    _toImage?.dispose();
    super.dispose();
  }

  void _onHibernate() {
    if (!mounted) return;
    if (Hibernator.asleep.value) {
      unawaited(_sleep());
      return;
    }
    unawaited(MemoryRelease.wake());
    if (!_slept) return;
    // De volta: a mesma abertura de quando se entra no perfil cobre a tela
    // enquanto ela é montada e as imagens são lidas de novo.
    _introSound.dispose();
    setState(() {
      _slept = false;
      _intro = true;
      _sceneDone = false;
      _morphStarted = false;
    });
  }

  /// Solta a memória. A tela principal só é desmontada se estiver à vista: com
  /// algo aberto por cima (diálogo, detalhes, filme em pausa), nada se perde e
  /// saem só os caches.
  Future<void> _sleep() async {
    final controller = AppScope.read(context);
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    var unmounted = false;
    if (onTop && !_intro && controller.phase == AppPhase.ready) {
      setState(() => _slept = true);
      // Um quadro, para a tela ser de fato desmontada.
      unmounted = await MemoryRelease.forceFrame();
    }
    if (!Hibernator.asleep.value) return; // o usuário já voltou
    if (unmounted) {
      // Só com a tela fora: estas imagens são usadas direto por ela.
      HeroArt.release();
      BlurredLogo.release();
      BackdropRender.releaseCache();
      controller.catalog.trimCache();
    }
    await MemoryRelease.run();
  }

  Future<ui.Image?> _capture(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    return boundary.toImage(pixelRatio: 1.0);
  }

  /// A cena terminou e o perfil já saiu do carregamento: captura as duas telas
  /// e começa a transição. Se algo falhar, a cena só some.
  Future<void> _startMorph() async {
    _morphStarted = true;
    try {
      // Espera as imagens do Início (banners e capas) chegarem, senão a captura
      // sai com quadrados vazios: segue quando o cache de imagens para de
      // crescer por ~0,4 s (no máximo 2,2 s de espera extra).
      final cache = PaintingBinding.instance.imageCache;
      var last = cache.currentSizeBytes;
      var stable = 0;
      final waited = Stopwatch()..start();
      while (mounted &&
          waited.elapsedMilliseconds < 2200 &&
          (stable < 4 || waited.elapsedMilliseconds < 500)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final now = cache.currentSizeBytes;
        if (now == last) {
          stable++;
        } else {
          stable = 0;
          last = now;
        }
      }
      await WidgetsBinding.instance.endOfFrame;
      final from = await _capture(_sceneKey);
      final to = await _capture(_pageKey);
      if (!mounted) {
        from?.dispose();
        to?.dispose();
        return;
      }
      if (from == null || to == null) {
        from?.dispose();
        to?.dispose();
        setState(() => _intro = false);
        return;
      }
      setState(() {
        _fromImage = from;
        _toImage = to;
      });
    } catch (e) {
      debugPrint('Abertura: captura falhou ($e)');
      if (mounted) setState(() => _intro = false);
    }
  }

  void _finishMorph() {
    if (!mounted) return;
    final from = _fromImage, to = _toImage;
    setState(() {
      _intro = false;
      _fromImage = null;
      _toImage = null;
    });
    // Libera depois do quadro em que o desenho deixou de usar as imagens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      from?.dispose();
      to?.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final Widget page;
    switch (controller.phase) {
      case AppPhase.booting:
        page = const PlainFrame(child: _Splash());
      case AppPhase.loggedOut:
        page = const PlainFrame(child: LoginPage());
      case AppPhase.ready:
        page = _slept ? const SizedBox.expand() : const Shell();
    }
    if (_intro && _sceneDone && !_morphStarted && controller.phase != AppPhase.booting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startMorph();
      });
    }
    // A árvore não muda quando a animação termina (o app não é recriado).
    return Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(key: _pageKey, child: page)),
        if (_intro && _toImage == null)
          Positioned.fill(
            child: ProfileIntro(
              boundaryKey: _sceneKey,
              startSound: _introSound.start,
              onDone: () => setState(() => _sceneDone = true),
            ),
          ),
        if (_intro && _fromImage != null && _toImage != null)
          Positioned.fill(
            child: MorphReveal(
              from: _fromImage!,
              to: _toImage!,
              onDone: _finishMorph,
            ),
          ),
      ],
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _FatalScreen extends StatelessWidget {
  const _FatalScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Não foi possível iniciar o app',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$error',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
