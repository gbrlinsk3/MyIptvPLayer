import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../update/app_updater.dart';
import '../widgets/common.dart';

/// Conta e ajustes → Configurações → Atualizações.
class UpdateSettingsCard extends StatefulWidget {
  const UpdateSettingsCard({super.key});

  @override
  State<UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<UpdateSettingsCard> {
  late final TextEditingController _url =
      TextEditingController(text: AppUpdater.instance.manifestUrl);
  String? _msg;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = await AppUpdater.instance.setManifestUrl(_url.text);
    setState(() => _msg = err ?? 'Endereço salvo.');
  }

  @override
  Widget build(BuildContext context) {
    final u = AppUpdater.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final status = switch (u.state) {
          UpdateState.checking => 'Procurando…',
          UpdateState.available || UpdateState.ready || UpdateState.downloading =>
            'Nova versão ${u.available?.version} disponível',
          UpdateState.error => u.error ?? 'Erro',
          UpdateState.idle => u.configured ? 'Você está na versão mais recente' : 'Não configurado',
        };
        return SectionCard(
          title: 'Atualizações',
          children: [
            KeyValueRow(label: 'Versão instalada', value: AppInfo.version),
            KeyValueRow(label: 'Situação', value: status),
            const SizedBox(height: 12),
            Text(
              'Endereço do manifesto de atualização (https)',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              onSubmitted: (_) => _save(),
              decoration: fieldDecoration(hint: 'https://seusite.com/mip/latest.json'),
            ),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_msg!, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Salvar')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: u.state == UpdateState.checking
                      ? null
                      : () async {
                          await _save();
                          await u.check(timeout: const Duration(seconds: 15));
                        },
                  child: const Text('Procurar agora'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
