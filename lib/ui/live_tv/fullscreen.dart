import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../playback/playback_controller.dart';
import 'player_controls.dart';
import 'playback_overlays.dart';

bool _fullscreenOpen = false;

/// Coloca a janela em tela cheia e abre uma página só com o vídeo.
/// Sai com Esc, F, duplo clique ou pelo botão de tela cheia.
/// O player é o mesmo (o PlaybackController), então a transmissão não reinicia.
Future<void> enterVideoFullscreen(
  BuildContext context,
  PlaybackController playback,
) async {
  if (_fullscreenOpen) return;
  _fullscreenOpen = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    await windowManager.setFullScreen(true);
    await navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenPage(playback: playback),
      ),
    );
  } finally {
    await windowManager.setFullScreen(false);
    _fullscreenOpen = false;
  }
}

class FullscreenPage extends StatelessWidget {
  const FullscreenPage({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    void exit() => Navigator.of(context).pop();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): exit,
        const SingleActivator(LogicalKeyboardKey.keyF): exit,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: playback.video,
                controls: (state) => const SizedBox.shrink(),
              ),
              Positioned.fill(
                child: PlayerControls(
                  playback: playback,
                  fullscreen: true,
                  onToggleFullscreen: exit,
                ),
              ),
              Positioned.fill(child: PlaybackOverlays(playback: playback)),
            ],
          ),
        ),
      ),
    );
  }
}
