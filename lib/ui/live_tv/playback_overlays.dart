import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// Indicador de carregamento/reconexão e painel de erro sobre o vídeo.
class PlaybackOverlays extends StatelessWidget {
  const PlaybackOverlays({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final error = playback.error;
        if (error != null) {
          return _ErrorOverlay(error: error, controller: controller);
        }
        if (!playback.buffering && !playback.reconnecting) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                if (playback.reconnecting) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Reconectando…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.error, required this.controller});

  final String error;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final other = controller.streamExt == 'ts' ? 'm3u8' : 'ts';
    return Container(
      color: const Color(0xE6000000),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 28),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível reproduzir este canal',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'O app tentou reconectar sozinho algumas vezes, sem sucesso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SelectableText(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: controller.retryPlayback,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Tentar de novo'),
                ),
                OutlinedButton(
                  onPressed: () => controller.retryWithFormat(other),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: Text('Tentar como .$other'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
