import 'package:flutter/material.dart';

import '../data/live_highlight.dart';
import '../core/layout_metrics.dart';
import '../core/theme.dart';
import '../profiles/profiles_scope.dart';
import '../state/app_scope.dart';
import '../catalog/home_banners.dart' show BannerConfig;
import 'home/banner_manager_dialog.dart';
import 'downloads/downloads_settings_card.dart';
import 'account_xtream_card.dart';
import 'diagnostics_card.dart';
import 'catalog_settings_card.dart';
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
            const UpdateSettingsCard(),
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
            const DownloadsSettingsCard(),
            const EpgSettingsCard(),
            const DiagnosticsCard(),
            const CatalogSettingsCard(),
            ] else ...[
            SectionCard(
              title: 'Aparência',
              children: [
                SegmentedButton<ThemePref>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemePref.light,
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemePref.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                      label: Text('Escuro'),
                    ),
                    ButtonSegment(
                      value: ThemePref.system,
                      icon: Icon(Icons.desktop_windows_outlined, size: 18),
                      label: Text('Sistema'),
                    ),
                    ButtonSegment(
                      value: ThemePref.auto,
                      icon: Icon(Icons.schedule_outlined, size: 18),
                      label: Text('Automático'),
                    ),
                  ],
                  selected: {c.themePref},
                  onSelectionChanged: (v) => c.setThemePref(v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sistema segue o claro/escuro do Windows. Automático usa o '
                  'horário do computador: claro das 9h às 17h, escuro das 17h às 9h.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
              title: 'Tamanho da interface',
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in UiSizes.percents)
                      ButtonSegment(value: p, label: Text('$p %')),
                  ],
                  selected: {c.uiScalePercent},
                  onSelectionChanged: (v) => c.setUiScalePercent(v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Amplia o programa inteiro (menus, botões, janelas). 100 % é o '
                  'tamanho de antes; o padrão é ${UiSizes.defaultPercent} %. '
                  'Também define quantos pôsteres cabem por linha.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            SectionCard(
              title: 'Largura do catálogo',
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final px in CatalogWidth.options)
                      ButtonSegment(
                        value: px,
                        label: Text(
                          px == CatalogWidth.fill ? 'Preenchido' : '$px px',
                        ),
                      ),
                  ],
                  selected: {c.catalogWidth},
                  onSelectionChanged: (v) => c.setCatalogWidth(v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  'Largura máxima do conteúdo das telas, centralizado. '
                  'Preenchido usa a janela inteira (padrão). Os pixels contam '
                  'já com o tamanho da interface: a ${UiSizes.defaultPercent} %, '
                  '1440 ocupa cerca de ${(1440 * UiSizes.defaultPercent / 100).round()} px na tela.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            SectionCard(
              title: 'Minha biblioteca',
              children: [
                Text(
                  'Ao clicar num título baixado',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'panel', label: Text('Card')),
                    ButtonSegment(value: 'expanded', label: Text('Card expandido')),
                    ButtonSegment(value: 'player', label: Text('Reproduzir')),
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
              ],
            ),
            SectionCard(
              title: 'Banners do Início',
              children: [
                KeyValueRow(
                  label: 'Banners',
                  value: '${c.catalog.banners.length} de ${BannerConfig.maxExtra}',
                ),
                Text(
                  '"Continue de onde parou" aparece sozinho quando há algo em '
                  'andamento e não conta nesse limite.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
