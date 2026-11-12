import 'package:flutter/material.dart';

import 'core/app_info.dart';
import 'core/theme.dart';
import 'playback/playback_controller.dart';
import 'profiles/profiles_controller.dart';
import 'profiles/profiles_scope.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'ui/login_page.dart';
import 'ui/profiles/profile_picker_page.dart';
import 'ui/shell.dart';
import 'ui/update/update_toast.dart';
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

  @override
  void initState() {
    super.initState();
    _playback = PlaybackController();
    _profiles = ProfilesController(_playback)..load();
    WidgetsBinding.instance.addObserver(this);
    _startupUpdateCheck();
  }

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

  /// Tema "Automático": acompanha o claro/escuro do Windows.
  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  ThemeData? _theme;
  String? _themeKey;

  ThemeData _themeFor(bool dark) {
    final key = '$dark-${AppColors.accent.toARGB32()}-${AppShape.radius}';
    if (_themeKey != key) {
      _themeKey = key;
      _theme = buildTheme();
    }
    return _theme!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                [session.app.themeNotifier, session.app.shapeRevision],
              ),
              builder: (context, _) => _themed(session),
            ),
          );
        },
      ),
    );
  }

  Widget _themed(ProfileSession? session) {
    final mode = session?.app.themeMode ?? ThemeMode.dark;
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final dark =
        mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);
    // As cores são estáticas: atualiza a paleta e recria a árvore (key).
    AppColors.applyBrightness(dark);
    return MaterialApp(
      key: ValueKey(dark),
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: _themeFor(dark),
      builder: (context, child) => Stack(
        children: [
          if (child != null) Positioned.fill(child: child),
          const UpdateToast(),
        ],
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

class _Root extends StatelessWidget {
  const _Root({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    switch (controller.phase) {
      case AppPhase.booting:
        return const PlainFrame(child: _Splash());
      case AppPhase.loggedOut:
        return const PlainFrame(child: LoginPage());
      case AppPhase.ready:
        return const Shell();
    }
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
