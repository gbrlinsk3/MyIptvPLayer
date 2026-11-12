import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/catalog_models.dart';
import '../data/live_highlight.dart';
import '../core/theme.dart';
import '../profiles/profiles_scope.dart';
import '../state/app_scope.dart';
import 'home/banner_manager_dialog.dart';
import 'downloads/downloads_settings_card.dart';
import 'account_xtream_card.dart';
import 'diagnostics_card.dart';
import 'logs_settings_card.dart';
import 'epg_settings_card.dart';
import 'update/update_settings_card.dart';
import 'profiles/profile_avatar.dart';
import 'profiles/profile_editor_dialog.dart';
import 'widgets/common.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final TextEditingController _userAgent;
  late final TextEditingController _keywords;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _userAgent = TextEditingController(text: AppScope.read(context).userAgent);
    _keywords = TextEditingController(
      text: AppScope.read(context).highlightKeywords.join(', '),
    );
  }

  @override
  void dispose() {
    _userAgent.dispose();
    _keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Conta e ajustes',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.person_outline, size: 18),
                    label: Text('Conta'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.settings_outlined, size: 18),
                    label: Text('Configurações'),
                  ),
                  ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.palette_outlined, size: 18),
                    label: Text('Personalização'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
            if (_tab == 0) ...[
            if (c.dbRecovered)
              Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'O banco de dados local estava ilegível e foi recriado. '
                  'O arquivo antigo foi guardado ao lado dele, com final ".corrupt-…".',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            const _ProfileCard(),
            const XtreamCard(),
            SectionCard(
              title: 'Sessão',
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Sair da conta?',
                      message:
                          'Remove a conta e o catálogo salvos neste computador. '
                          'Você precisará entrar de novo.',
                      action: 'Sair',
                    );
                    if (ok) await c.logout();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.border),
                  ),
                  child: const Text('Sair'),
                ),
              ],
            ),

            ] else if (_tab == 1) ...[
            SectionCard(
              title: 'Catálogo de TV ao vivo',
              children: [
                KeyValueRow(label: 'Canais', value: '${c.totalChannels}'),
                if (c.hiddenChannelCount > 0)
                  KeyValueRow(
                    label: 'Canais ocultos',
                    value: '${c.hiddenChannelCount}',
                  ),
                KeyValueRow(
                  label: 'Canal selecionado',
                  value: c.selected?.name ?? 'Nenhum',
                ),
                KeyValueRow(
                  label: 'Categorias',
                  value:
                      '${c.categories.length} visíveis (com ao menos um canal)',
                ),
                KeyValueRow(
                  label: 'Atualizado em',
                  value: c.catalogUpdatedLabel,
                ),
                if (c.syncError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      c.syncError!,
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => c.setShellIndex(1),
                      child: const Text('Abrir TV ao vivo'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: c.syncing ? null : c.refreshCatalog,
                      child: Text(c.syncing ? 'Atualizando…' : 'Atualizar agora'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: c.syncing
                          ? null
                          : () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Limpar cache do catálogo?',
                                message:
                                    'Remove apenas os canais e categorias salvos neste computador. '
                                    'A conta é mantida e o catálogo pode ser baixado de novo.',
                                action: 'Limpar',
                              );
                              if (ok) await c.clearCatalogCache();
                            },
                      child: const Text('Limpar cache'),
                    ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'Filmes e séries',
              children: [
                for (final kind in CatalogKind.values) ...[
                  KeyValueRow(
                    label: kind.label,
                    value: c.catalog.section(kind).total == 0
                        ? 'Ainda não baixados'
                        : '${c.catalog.section(kind).total} títulos (atualizado em '
                            '${c.catalog.section(kind).updatedAt == null ? '—' : formatDateTime(c.catalog.section(kind).updatedAt!)})',
                  ),
                  if (c.catalog.section(kind).error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        c.catalog.section(kind).error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: c.catalog.section(CatalogKind.movies).syncing ||
                              c.catalog.section(CatalogKind.series).syncing
                          ? null
                          : () async {
                              await c.catalog.refresh(CatalogKind.movies);
                              await c.catalog.refresh(CatalogKind.series);
                            },
                      child: const Text('Atualizar agora'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Limpar filmes e séries salvos?',
                          message:
                              'Remove só as listas de filmes e séries guardadas neste '
                              'computador. O progresso de reprodução é mantido e as '
                              'listas podem ser baixadas de novo.',
                          action: 'Limpar',
                        );
                        if (ok) await c.catalog.clearCache();
                      },
                      child: const Text('Limpar cache'),
                    ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'Reprodução',
              children: [
                Text(
                  'Formato do link do canal',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ts', label: Text('.ts')),
                    ButtonSegment(value: 'm3u8', label: Text('.m3u8')),
                  ],
                  selected: {c.streamExt},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      c.setStreamExt(selection.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vale a partir do próximo canal aberto. Se os canais não abrirem, teste o outro formato.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ao clicar num título baixado na Minha biblioteca',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'player', label: Text('Reproduzir')),
                    ButtonSegment(value: 'panel', label: Text('Card')),
                    ButtonSegment(value: 'expanded', label: Text('Card expandido')),
                  ],
                  selected: {c.libraryOpenMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => c.setLibraryOpenMode(s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Arquivos importados e gravações sempre abrem direto no player.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  'User-Agent (opcional)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _userAgent,
                        onSubmitted: c.setUserAgent,
                        decoration: fieldDecoration(
                          hint: 'Vazio = padrão do player',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => c.setUserAgent(_userAgent.text),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ],
            ),
            const EpgSettingsCard(),
            const UpdateSettingsCard(),
            const DownloadsSettingsCard(),
            const LogsSettingsCard(),
            const DiagnosticsCard(),
            ] else ...[
            SectionCard(
              title: 'Aparência',
              children: [
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text('Escuro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      label: Text('Automático'),
                    ),
                  ],
                  selected: {c.themeMode},
                  onSelectionChanged: (v) => c.setThemeMode(v.first),
                ),
              ],
            ),
            SectionCard(
              title: 'Formato dos botões',
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'square',
                      icon: Icon(Icons.crop_square, size: 18),
                      label: Text('Quadrados'),
                    ),
                    ButtonSegment(
                      value: 'rounded',
                      icon: Icon(Icons.rounded_corner, size: 18),
                      label: Text('Arredondados'),
                    ),
                  ],
                  selected: {c.buttonShape},
                  onSelectionChanged: (v) => c.setButtonShape(v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vale para os botões de todo o programa.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            SectionCard(
              title: 'Banners do Início',
              children: [
                KeyValueRow(
                  label: 'Banners',
                  value: '${1 + c.catalog.banners.length} de 5',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => showBannerManager(context),
                    child: const Text('Gerenciar banners'),
                  ),
                ),
              ],
            ),
            SectionCard(
              title: 'Destaques da TV ao vivo',
              children: [
                Text(
                  'Destaques da TV ao vivo',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Palavras-chave separadas por vírgula, na ordem dos banners. '
                  'Cada palavra que aparecer no nome de uma categoria vira um '
                  'banner no topo da TV ao vivo (máximo de 4). Vazio = sem banners.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keywords,
                  decoration: fieldDecoration(hint: 'Esportes, Notícias, Filmes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () =>
                          c.setHighlightKeywords(_keywords.text.split(',')),
                      child: const Text('Salvar destaques'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        _keywords.text = defaultHighlightKeywords.join(', ');
                        c.setHighlightKeywords(defaultHighlightKeywords);
                      },
                      child: const Text('Restaurar padrão'),
                    ),
                  ],
                ),
              ],
            ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final profiles = ProfilesScope.of(context);
    final profile = profiles.session?.profile;
    if (profile == null) return const SizedBox.shrink();
    return SectionCard(
      title: 'Perfil',
      children: [
        Row(
          children: [
            ProfileAvatar.of(profile, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                profile.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'A conta Xtream, o catálogo, as categorias ocultas, as fontes EPG e os '
          'ajustes abaixo pertencem a este perfil.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: () => showProfileEditor(
                context,
                existing: profile,
                isActive: true,
              ),
              child: const Text('Editar perfil'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => profiles.leave(),
              child: const Text('Trocar de perfil'),
            ),
          ],
        ),
      ],
    );
  }
}
