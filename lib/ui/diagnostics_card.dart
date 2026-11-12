import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/db.dart' show DbDiagnostics, RepairReport;
import '../downloads/download_models.dart';
import '../state/app_scope.dart';
import 'widgets/common.dart';

/// Conta e ajustes → Diagnóstico: estado do banco, do catálogo, dos downloads
/// e do registro de erros, para investigar problemas sem abrir arquivos.
class DiagnosticsCard extends StatefulWidget {
  const DiagnosticsCard({super.key});

  @override
  State<DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<DiagnosticsCard> {
  Future<DbDiagnostics>? _future;
  bool _opened = false;

  void _load() {
    setState(() {
      _future = AppScope.read(context).diagnostics().catchError(
        (Object e, StackTrace st) {
          AppLog.error('diagnostico', e, st);
          Error.throwWithStackTrace(e, st);
        },
      );
    });
  }

  bool _repairing = false;

  Future<void> _repair() async {
    final app = AppScope.read(context);
    var orphans = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Reparar histórico?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Antes de mexer, o app faz uma cópia de segurança do banco '
                  'deste perfil (ao lado do arquivo, guardando as 3 mais '
                  'recentes). Depois corrige posições impossíveis (negativas ou '
                  'maiores que a duração) e remove linhas inutilizáveis do '
                  'histórico. Nada do catálogo, dos downloads nem da conta é alterado.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: orphans,
                  onChanged: (v) => setState(() => orphans = v ?? false),
                  title: const Text('Também remover o progresso de títulos que não existem mais no catálogo'),
                  subtitle: Text(
                    'Se o provedor tirar um título e depois recolocar, o '
                    'progresso dele seria perdido.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reparar'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _repairing = true);
    RepairReport? report;
    Object? error;
    try {
      report = await app.repairHistory(removeOrphans: orphans);
    } catch (e, st) {
      error = e;
      AppLog.error('historico.reparo', e, st);
    }
    if (!mounted) return;
    setState(() => _repairing = false);
    final r = report;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          r == null
              ? 'Não foi possível reparar: $error'
              : (r.changedAnything
                      ? 'Reparo concluído: ${r.fixed} corrigidos, '
                          '${r.removedInvalid} inválidos e ${r.removedOrphans} órfãos removidos.'
                      : 'Nada precisou ser corrigido.') +
                  (r.integrityOk ? '' : ' Atenção: a verificação de integridade do banco falhou.') +
                  (r.backupPath == null ? ' (cópia de segurança não foi criada)' : ''),
        ),
      ),
    );
  }

  int _fileSize(String? path) {
    if (path == null) return 0;
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  List<(String, String)> _rows(DbDiagnostics d) {
    final app = AppScope.read(context);
    final downloads = app.downloads;
    final entries = downloads.entries;
    int n(DownloadStatus s) => entries.where((e) => e.status == s).length;
    final c = d.counts;
    return [
      ('Banco do perfil', d.path),
      ('Tamanho do banco', formatBytes(d.sizeBytes)),
      ('Versão do esquema', '${d.schemaVersion}'),
      ('Verificação de integridade', d.quickCheckOk ? 'OK' : 'FALHOU'),
      ('Última atualização do catálogo', app.catalogUpdatedLabel),
      ('Canais ao vivo', '${c['live_channels'] ?? 0}'),
      ('Filmes', '${c['vod_items'] ?? 0}'),
      ('Séries', '${c['series_items'] ?? 0}'),
      ('Itens com progresso', '${c['watch_progress'] ?? 0}'),
      ('Meus arquivos (biblioteca)', '${c['library_imports'] ?? 0}'),
      (
        'Downloads',
        '${entries.length} no total · ${n(DownloadStatus.done)} concluídos · '
            '${n(DownloadStatus.downloading)} baixando · '
            '${n(DownloadStatus.queued)} na fila · '
            '${n(DownloadStatus.paused)} pausados · ${n(DownloadStatus.error)} com erro',
      ),
      (
        'Conexões do download em uso',
        '${n(DownloadStatus.downloading)} (cada download usa 1 conexão da conta)',
      ),
      ('Pasta de downloads', downloads.folder),
      ('Arquivo de log', AppLog.path ?? 'Indisponível'),
      ('Tamanho do log', formatBytes(_fileSize(AppLog.path))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Diagnóstico',
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _repairing ? null : _repair,
            icon: _repairing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_outlined, size: 18),
            label: const Text('Reparar histórico'),
          ),
        ),
        if (!_opened) ...[
          Text(
            'Mostra o estado do banco, do catálogo, dos downloads e do log. '
            'Não mostra servidor, usuário nem senha.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _opened = true;
              _load();
            },
            icon: const Icon(Icons.monitor_heart_outlined, size: 18),
            label: const Text('Verificar agora'),
          ),
        ] else
          FutureBuilder<DbDiagnostics>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                );
              }
              if (snap.hasError) {
                return Text(
                  'Não foi possível ler o banco: ${snap.error}',
                  style: TextStyle(color: AppColors.danger),
                );
              }
              final rows = _rows(snap.data!);
              final ok = snap.data!.quickCheckOk;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!ok)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'O banco deste perfil falhou na verificação. Copie o '
                        'relatório e me envie.',
                        style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                      ),
                    ),
                  for (final (k, v) in rows) KeyValueRow(label: k, value: v),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Atualizar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final text = [for (final (k, v) in rows) '$k: $v'].join('\n');
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: text));
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Relatório copiado.')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copiar relatório'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
