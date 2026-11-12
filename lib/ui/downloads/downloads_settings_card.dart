import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/system_dialogs.dart';
import '../../core/theme.dart';
import '../../state/app_scope.dart';
import '../widgets/common.dart';

/// Conta e ajustes → Downloads: pasta de destino e espaço usado.
class DownloadsSettingsCard extends StatefulWidget {
  const DownloadsSettingsCard({super.key});

  @override
  State<DownloadsSettingsCard> createState() => _DownloadsSettingsCardState();
}

class _DownloadsSettingsCardState extends State<DownloadsSettingsCard> {
  final TextEditingController _path = TextEditingController();
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _save(String? value) async {
    final downloads = AppScope.read(context).downloads;
    try {
      await downloads.setFolder(value);
      if (mounted) {
        setState(() {
          _editing = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível usar essa pasta: $e');
    }
  }

  Future<void> _choose() async {
    final downloads = AppScope.read(context).downloads;
    final picked = await SystemDialogs.pickFolder(
      initial: downloads.folder,
      description: 'Escolha a pasta dos downloads',
    );
    if (picked != null && mounted) await _save(picked);
  }

  Future<void> _move() async {
    final downloads = AppScope.read(context).downloads;
    final list = downloads.outsideCurrentFolder;
    if (list.isEmpty) return;
    final size = list.fold<int>(0, (a, e) => a + e.doneBytes);
    final ok = await confirmDialog(
      context,
      title: 'Mover ${list.length} ${list.length == 1 ? 'arquivo' : 'arquivos'}?',
      message: 'Os downloads que estão fora de "${downloads.folder}" '
          '(${formatBytes(size)}) serão movidos para lá, mantendo as pastas '
          'Filmes e Séries. Nada é sobrescrito. Entre discos diferentes a '
          'cópia pode demorar.',
      action: 'Mover',
    );
    if (!ok || !mounted) return;

    final progress = ValueNotifier<(int, int)>((0, list.length));
    final messenger = ScaffoldMessenger.of(context);
    // Diálogo de andamento (sem fechar por toque); fechado ao terminar.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Movendo arquivos…'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: v.$2 == 0 ? null : v.$1 / v.$2,
                  color: AppColors.accent,
                  backgroundColor: AppColors.hover,
                ),
                const SizedBox(height: 10),
                Text('${v.$1} de ${v.$2}'),
              ],
            ),
          ),
        ),
      ),
    ));
    final result = await downloads.moveToCurrentFolder(
      onProgress: (done, total) => progress.value = (done, total),
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.busy
              ? 'Há downloads em andamento. Pause ou espere terminar e tente de novo.'
              : '${result.moved} movidos'
                  '${result.skipped > 0 ? ' · ${result.skipped} pulados (já existiam no destino ou sumiram)' : ''}'
                  '${result.failed > 0 ? ' · ${result.failed} com erro (veja o registro de erros)' : ''}',
        ),
      ),
    );
  }

  Future<void> _verify() async {
    final downloads = AppScope.read(context).downloads;
    final messenger = ScaffoldMessenger.of(context);
    final n = await downloads.reconcile();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'Nenhum arquivo perdido foi encontrado.'
              : '$n ${n == 1 ? 'arquivo reconhecido' : 'arquivos reconhecidos'} de novo.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.read(context).downloads;
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        return SectionCard(
          title: 'Downloads',
          children: [
            KeyValueRow(label: 'Pasta', value: downloads.folder),
            KeyValueRow(
              label: 'Baixado',
              value:
                  '${downloads.finished.length} itens · ${formatBytes(downloads.usedBytes)}',
            ),
            const SizedBox(height: 8),
            Text(
              'Os arquivos são salvos no formato original do provedor, sem '
              'recompressão. Mudar a pasta vale para novos downloads; os já '
              'baixados que você mover para a nova pasta são reconhecidos de '
              'novo. Um download usa uma conexão da sua conta: se o plano '
              'permite só uma, pause durante a reprodução.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (_editing) ...[
              TextField(
                controller: _path,
                autofocus: true,
                onSubmitted: _save,
                decoration: fieldDecoration(label: 'Nova pasta (caminho completo)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _save(_path.text),
                    child: const Text('Salvar'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _editing = false;
                      _error = null;
                    }),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _choose,
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                    label: const Text('Escolher pasta'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => downloads.openFolder(),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Abrir pasta'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _path.text = downloads.folder;
                      _editing = true;
                    }),
                    child: const Text('Digitar caminho'),
                  ),
                  TextButton(
                    onPressed: _verify,
                    child: const Text('Verificar arquivos'),
                  ),
                  if (downloads.customFolder != null)
                    TextButton(
                      onPressed: () => _save(null),
                      child: const Text('Usar a pasta padrão'),
                    ),
                ],
              ),
              if (downloads.outsideCurrentFolder.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${downloads.outsideCurrentFolder.length} '
                          '${downloads.outsideCurrentFolder.length == 1 ? 'download está' : 'downloads estão'} '
                          'fora da pasta atual (por exemplo, na pasta anterior).',
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: downloads.moving ? null : _move,
                        child: const Text('Mover para a pasta atual'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: downloads.pauseOnPlayback,
                onChanged: downloads.setPauseOnPlayback,
                title: const Text('Pausar downloads enquanto assisto'),
                subtitle: Text(
                  'Ao abrir um filme, série ou canal pela internet, o download '
                  'em andamento pausa e retoma sozinho quando você sair. Evita '
                  'estourar o limite de conexões da conta.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: downloads.scanSubfolders,
                onChanged: downloads.setScanSubfolders,
                title: const Text('Procurar também nas subpastas'),
                subtitle: Text(
                  'Ao reconhecer arquivos baixados que sumiram, olha só a pasta '
                  'escolhida (e as pastas Filmes e Séries criadas pelo app). '
                  'Ligado, olha todas as subpastas.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
