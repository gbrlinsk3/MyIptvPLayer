import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../update/app_updater.dart';
import '../../update/update_info.dart';
import '../widgets/cubos_logo.dart';
import '../widgets/glass.dart';
import '../widgets/swipe_toast.dart';

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
class UpdateToast extends StatefulWidget {
  const UpdateToast({super.key});

  @override
  State<UpdateToast> createState() => _UpdateToastState();
}

class _UpdateToastState extends State<UpdateToast> {
  // "Detalhes" aberto. O aviso fica fora do Navigator (no builder do app), por
  // isso as novidades aparecem num cartão próprio, não num showDialog.
  bool _details = false;

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
        // Botões de texto mais justos: os três cabem numa linha.
        final compact = TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        );
        // Arrastar para baixo ou deixar o pavio de 25 s acabar equivale a
        // "Depois": o aviso volta na próxima abertura do programa. O tempo para
        // com o mouse em cima, baixando e com "Detalhes" aberto; mudar a etapa
        // (por exemplo, baixado) recomeça a contagem.
        final toast = Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SwipeToast(
            lifetime: const Duration(seconds: 25),
            paused: busy || _details,
            dismissible: !busy,
            restartKey: u.state,
            onDismiss: u.dismiss,
            child: GlassPane(
              radius: AppShape.card,
              edge: AppColors.accent,
              child: SizedBox(
                width: 400,
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
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
                          TextButton(
                            style: compact,
                            onPressed: busy ? null : u.dismiss,
                            child: const Text('Depois'),
                          ),
                          if (info.hasDetails || info.notes.isNotEmpty)
                            TextButton(
                              style: compact,
                              onPressed: () => setState(() => _details = true),
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
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_details)
              _UpdateDetails(
                info: info,
                onClose: () => setState(() => _details = false),
              ),
            toast,
          ],
        );
      },
    );
  }
}

/// "Detalhes" do aviso de atualização: novos recursos, melhorias de design e
/// correções da versão (ou o texto curto das notas, se a versão não trouxe
/// o detalhamento). Cartão central com fundo escurecido; clicar fora fecha.
class _UpdateDetails extends StatelessWidget {
  const _UpdateDetails({required this.info, required this.onClose});

  final UpdateInfo info;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const ColoredBox(color: Color(0x99000000)),
        ),
        Center(
          child: GlassPane(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Novidades da versão ${info.version}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (info.hasDetails)
                              for (final e in UpdateInfo.sectionTitles.entries)
                                if (info.details[e.key]?.isNotEmpty ?? false) ...[
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 8, bottom: 6),
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        color: AppColors.accentInk,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  for (final item in info.details[e.key]!)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onClose,
                        child: const Text('Fechar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
