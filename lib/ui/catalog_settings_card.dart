import 'package:flutter/material.dart';

import '../catalog/catalog_controller.dart' show CatalogSection;
import '../core/format.dart';
import '../core/theme.dart';
import '../data/catalog_models.dart';
import '../state/app_scope.dart';
import 'widgets/common.dart';

/// Conta e ajustes → Configurações → Catálogo: resumo de TV ao vivo, filmes e
/// séries num painel só. O usuário marca o que quer atualizar.
class CatalogSettingsCard extends StatefulWidget {
  const CatalogSettingsCard({super.key});

  @override
  State<CatalogSettingsCard> createState() => _CatalogSettingsCardState();
}

class _CatalogSettingsCardState extends State<CatalogSettingsCard> {
  bool _live = true;
  bool _movies = true;
  bool _series = true;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final catalog = c.catalog;
    final movies = catalog.section(CatalogKind.movies);
    final series = catalog.section(CatalogKind.series);
    final busy = c.syncing || movies.syncing || series.syncing;
    final none = !_live && !_movies && !_series;

    String vodValue(CatalogSection s) => s.total == 0
        ? 'Ainda não baixados'
        : '${s.total} títulos (atualizado em '
            '${s.updatedAt == null ? '—' : formatDateTime(s.updatedAt!)})';

    Widget error(String? message) => message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          );

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        );

    return SectionCard(
      title: 'Catálogo',
      children: [
        heading('TV AO VIVO'),
        KeyValueRow(label: 'Canais', value: '${c.totalChannels}'),
        if (c.hiddenChannelCount > 0)
          KeyValueRow(label: 'Canais ocultos', value: '${c.hiddenChannelCount}'),
        KeyValueRow(
          label: 'Categorias',
          value: '${c.categories.length} visíveis (com ao menos um canal)',
        ),
        KeyValueRow(label: 'Atualizado em', value: c.catalogUpdatedLabel),
        error(c.syncError),
        heading('FILMES'),
        KeyValueRow(label: 'Filmes', value: vodValue(movies)),
        error(movies.error),
        heading('SÉRIES'),
        KeyValueRow(label: 'Séries', value: vodValue(series)),
        error(series.error),
        const SizedBox(height: 16),
        Text(
          'O que atualizar',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('TV ao vivo'),
              selected: _live,
              onSelected: (v) => setState(() => _live = v),
            ),
            FilterChip(
              label: const Text('Filmes'),
              selected: _movies,
              onSelected: (v) => setState(() => _movies = v),
            ),
            FilterChip(
              label: const Text('Séries'),
              selected: _series,
              onSelected: (v) => setState(() => _series = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: busy || none
                  ? null
                  : () async {
                      if (_live) await c.refreshCatalog();
                      if (_movies) await catalog.refresh(CatalogKind.movies);
                      if (_series) await catalog.refresh(CatalogKind.series);
                    },
              child: Text(busy ? 'Atualizando…' : 'Atualizar selecionados'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Limpar cache da TV ao vivo?',
                        message:
                            'Remove apenas os canais e categorias salvos neste computador. '
                            'A conta é mantida e o catálogo pode ser baixado de novo.',
                        action: 'Limpar',
                      );
                      if (ok) await c.clearCatalogCache();
                    },
              child: const Text('Limpar cache da TV'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Limpar filmes e séries salvos?',
                        message:
                            'Remove só as listas de filmes e séries guardadas neste '
                            'computador. O progresso de reprodução é mantido e as '
                            'listas podem ser baixadas de novo.',
                        action: 'Limpar',
                      );
                      if (ok) await catalog.clearCache();
                    },
              child: const Text('Limpar cache de filmes e séries'),
            ),
          ],
        ),
      ],
    );
  }
}
