import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_scope.dart';
import 'widgets/common.dart';

/// Card de Ajustes: fontes EPG por URL e a opção de preferir o EPG do usuário.
class EpgSettingsCard extends StatefulWidget {
  const EpgSettingsCard({super.key});

  @override
  State<EpgSettingsCard> createState() => _EpgSettingsCardState();
}

class _EpgSettingsCardState extends State<EpgSettingsCard> {
  final _url = TextEditingController();
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_adding) return;
    final c = AppScope.read(context);
    setState(() {
      _adding = true;
      _error = null;
    });
    final error = await c.epg.addSource(_url.text, c.epgChannelKeys);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _error = error;
      if (error == null) _url.clear();
    });
  }

  String _status(EpgSource source, bool refreshing) {
    if (source.error != null) return source.error!;
    if (source.updatedAt == null) {
      return refreshing ? 'Atualizando…' : 'Ainda não atualizada';
    }
    return 'Atualizada em ${formatDateTime(source.updatedAt!)} · '
        '${source.programCount} programas';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final epg = c.epg;

    return ListenableBuilder(
      listenable: epg,
      builder: (context, _) {
        return SectionCard(
          title: 'Guia de programação (EPG)',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preferir as suas fontes EPG para listas Xtream',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Por padrão, as listas Xtream usam a guia de programação '
                        'do seu provedor, e as suas fontes EPG só preenchem os '
                        'canais em falta. Ative esta opção para usar primeiro o '
                        'seu EPG.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(value: epg.preferUser, onChanged: epg.setPreferUser),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Fontes EPG (URL XMLTV, .xml ou .xml.gz)',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (epg.sources.isEmpty)
              Text(
                'Nenhuma fonte adicionada.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            for (final source in epg.sources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _status(source, epg.refreshing),
                            style: TextStyle(
                              fontSize: 12,
                              color: source.error != null
                                  ? AppColors.danger
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover fonte',
                      onPressed: epg.refreshing
                          ? null
                          : () => epg.removeSource(source),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    enabled: !_adding,
                    onSubmitted: (_) => _add(),
                    decoration: fieldDecoration(
                      hint: 'https://exemplo.com/guia.xml',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _adding || epg.refreshing ? null : _add,
                  child: Text(_adding ? 'Adicionando…' : 'Adicionar'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: epg.sources.isEmpty || epg.refreshing || _adding
                      ? null
                      : () => epg.refreshAll(c.epgChannelKeys),
                  child: Text(
                    epg.refreshing ? 'Atualizando…' : 'Atualizar fontes agora',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'As fontes são atualizadas sozinhas ao abrir o app quando têm mais '
              'de 12 horas. Só entram os canais do seu catálogo que tenham código '
              'de EPG informado pelo provedor.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        );
      },
    );
  }
}
