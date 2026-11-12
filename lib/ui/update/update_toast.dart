import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../update/app_updater.dart';
import '../../update/update_info.dart';
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

/// Aviso no canto inferior direito quando há atualização disponível.
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
          alignment: Alignment.bottomRight,
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
                        if (info.hasDetails || info.notes.isNotEmpty)
                          TextButton(
                            onPressed: () => showUpdateDetails(context, info),
                            child: const Text('Detalhes'),
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

/// "Detalhes" do aviso de atualização: novos recursos, melhorias de design e
/// correções da versão (ou o texto curto das notas, se a versão não trouxe
/// o detalhamento).
Future<void> showUpdateDetails(BuildContext context, UpdateInfo info) {
  // O aviso fica fora do Navigator (no builder do app): usa o do app.
  final nav = appNavigatorKey.currentContext;
  if (nav == null) return Future.value();
  return showDialog<void>(
    context: nav,
    builder: (context) => AlertDialog(
      title: Text('Novidades da versão ${info.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.hasDetails)
                for (final e in UpdateInfo.sectionTitles.entries)
                  if (info.details[e.key]?.isNotEmpty ?? false) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    for (final item in info.details[e.key]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(item)),
                          ],
                        ),
                      ),
                  ]
              else
                Text(info.notes),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
