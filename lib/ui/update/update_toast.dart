import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../update/app_updater.dart';
import '../widgets/cubos_logo.dart';

/// Tela de abertura enquanto o app procura atualização (no máximo ~6 s).
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CubosLogo(size: 84),
            const SizedBox(height: 20),
            Text(AppInfo.name, style: AppFonts.title(34, spacing: 4)),
            const SizedBox(height: 2),
            Text(
              AppInfo.fullName,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Procurando atualizações…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso no canto inferior esquerdo quando há atualização disponível.
class UpdateToast extends StatelessWidget {
  const UpdateToast({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppUpdater.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final show = u.available != null &&
            !u.dismissed &&
            u.state != UpdateState.idle &&
            u.state != UpdateState.checking;
        if (!show) return const SizedBox.shrink();
        final info = u.available!;
        final busy = u.state == UpdateState.downloading;
        final ready = u.state == UpdateState.ready;
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
            color: AppColors.surface,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShape.rounded ? 12 : 2),
              side: BorderSide(color: AppColors.accent),
            ),
            child: SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nova versão ${info.version} disponível',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Você está na ${AppInfo.version}.'
                      '${info.notes.isEmpty ? '' : '\n${info.notes}'}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: u.progress == 0 ? null : u.progress,
                        minHeight: 3,
                      ),
                    ],
                    if (u.state == UpdateState.error && u.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        u.error!,
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: busy
                              ? null
                              : ready
                                  ? u.installAndRestart
                                  : u.download,
                          child: Text(
                            busy
                                ? 'Baixando…'
                                : ready
                                    ? 'Instalar e reiniciar'
                                    : 'Atualizar agora',
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: busy ? null : u.dismiss,
                          child: const Text('Depois'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}
