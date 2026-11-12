import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/theme.dart';
import 'widgets/common.dart';

/// Conta e ajustes → Registro de erros: onde fica o arquivo de log.
class LogsSettingsCard extends StatelessWidget {
  const LogsSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final path = AppLog.path;
    return SectionCard(
      title: 'Registro de erros',
      children: [
        KeyValueRow(label: 'Arquivo', value: path ?? 'Indisponível'),
        const SizedBox(height: 8),
        Text(
          'Falhas (downloads, rede, banco) são anotadas aqui, com endereços e '
          'senhas mascarados. Envie este arquivo se precisar de ajuda.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: path == null ? null : AppLog.openFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Abrir pasta de logs'),
        ),
      ],
    );
  }
}
