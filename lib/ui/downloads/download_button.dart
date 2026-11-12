import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../downloads/download_models.dart';
import '../../state/app_scope.dart';

/// Botão "Baixar" de um filme ou episódio. Muda conforme o estado: baixar,
/// na fila, baixando (pausa ao tocar), pausado/erro (retoma ao tocar) e baixado.
/// [compact] = só o ícone (linhas de episódio). [textStyle] = botão só de
/// ícone + texto, sem borda, para cima de imagens escuras (card de filme).
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.request,
    this.compact = false,
    this.textStyle = false,
    this.onOpenLibrary,
  });

  final DownloadRequest request;
  final bool compact;
  final bool textStyle;

  /// Chamado ao tocar em "Baixado" (ex.: fechar o painel e abrir a biblioteca).
  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final downloads = app.downloads;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final e = downloads.entryFor(request.kind, request.itemId);
        final pct = e?.fraction == null ? '' : ' ${(e!.fraction! * 100).round()}%';

        IconData icon = Icons.download_outlined;
        String label = 'Baixar';
        String tip = 'Baixar no formato original';
        VoidCallback action = () => downloads.enqueue(request);
        double? ring;
        var accent = false;

        if (e != null) {
          switch (e.status) {
            case DownloadStatus.queued:
              icon = Icons.schedule;
              label = 'Na fila';
              tip = 'Na fila — toque para pausar';
              action = () => downloads.pause(e);
            case DownloadStatus.downloading:
              icon = Icons.pause;
              label = 'Baixando$pct';
              tip = 'Baixando${e.totalBytes > 0 ? ' (${formatBytes(e.doneBytes)} de ${formatBytes(e.totalBytes)})' : ''} — toque para pausar';
              ring = e.fraction;
              action = () => downloads.pause(e);
            case DownloadStatus.paused:
              icon = Icons.play_arrow;
              label = 'Pausado$pct';
              tip = 'Pausado — toque para retomar';
              action = () => downloads.resume(e);
            case DownloadStatus.error:
              icon = Icons.refresh;
              label = 'Tentar de novo';
              tip = e.error ?? 'Erro no download — toque para tentar de novo';
              action = () => downloads.resume(e);
            case DownloadStatus.done:
              icon = Icons.download_done;
              label = 'Baixado';
              tip = 'Baixado — ver na biblioteca';
              accent = true;
              action = onOpenLibrary ?? () {};
          }
        }

        final color = accent ? AppColors.accent : AppColors.textMuted;
        final isActive = e?.status == DownloadStatus.downloading;

        final Widget iconWidget = SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isActive)
                CircularProgressIndicator(
                  value: ring,
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              Icon(icon, size: isActive ? 12 : 18, color: color),
            ],
          ),
        );

        if (compact) {
          return IconButton(
            tooltip: tip,
            onPressed: action,
            icon: iconWidget,
          );
        }
        if (textStyle) {
          final Widget light = SizedBox(
            width: 20,
            height: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isActive)
                  CircularProgressIndicator(
                    value: ring,
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                Icon(
                  icon,
                  size: isActive ? 12 : 18,
                  color: accent ? AppColors.accent : Colors.white,
                ),
              ],
            ),
          );
          return Tooltip(
            message: tip,
            child: TextButton.icon(
              onPressed: action,
              icon: light,
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: accent ? AppColors.accent : Colors.white,
              ),
            ),
          );
        }
        return Tooltip(
          message: tip,
          child: OutlinedButton.icon(
            onPressed: action,
            icon: iconWidget,
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent ? AppColors.accent : AppColors.text,
              side: BorderSide(
                color: accent ? AppColors.accent : AppColors.border,
              ),
            ),
          ),
        );
      },
    );
  }
}
