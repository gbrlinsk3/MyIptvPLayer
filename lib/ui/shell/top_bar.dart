import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../profiles/profiles_scope.dart';
import '../../state/app_scope.dart';
import '../profiles/profile_avatar.dart';
import '../widgets/glass.dart';
import '../widgets/text_type.dart';
import '../window/title_bar.dart';

/// Conteúdo do topo: busca global à esquerda, área de arrastar a janela e o
/// perfil ativo à direita (com menu). Os botões da janela ficam no TitleBar.
class TopBarContent extends StatelessWidget {
  const TopBarContent({
    super.key,
    required this.search,
    required this.focus,
    required this.onQuery,
    required this.onOpenAccount,
  });

  final TextEditingController search;
  final FocusNode focus;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 8, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SizedBox(
                  width: 440,
                  child: _SearchField(
                    controller: search,
                    focus: focus,
                    onChanged: onQuery,
                  ),
                ),
              ),
              const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              _ProfileMenu(onOpenAccount: onOpenAccount),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  static const _dica = 'Buscar filmes, séries e canais…';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final hintStyle = TextStyle(color: AppColors.textMuted, fontSize: 14);
    // A dica é "digitada" uma vez por abertura de perfil; depois fica fixa.
    final Widget dica = app.searchHintTyped
        ? Text(_dica, style: hintStyle, maxLines: 1)
        : TextType(
            text: _dica,
            style: hintStyle,
            startDelay: const Duration(milliseconds: 600),
            typingSpeed: const Duration(milliseconds: 40),
            onComplete: () => app.searchHintTyped = true,
          );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final radius = AppShape.control;
        // A borda de repouso é a do vidro; o campo só desenha a de foco.
        final semBorda = OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        );
        // No tema claro, sobre o banner em tela cheia, o vidro fecha mais
        // para a dica cinza continuar legível.
        return ValueListenableBuilder<bool>(
          valueListenable: WindowChrome.overMedia,
          builder: (context, overMedia, field) => GlassSurface(
            group: GlassGroups.bars,
            radius: radius,
            fill: overMedia && !AppColors.isDark ? AppGlass.dialog : null,
            child: field!,
          ),
          child: TextField(
            controller: controller,
            focusNode: focus,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hint: dica,
              isDense: true,
              filled: true,
              fillColor: Colors.transparent,
              hoverColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: AppColors.textMuted,
              ),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              border: semBorda,
              enabledBorder: semBorda,
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: AppColors.accent, width: 1.4),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Perfil ativo no topo, à direita. Menu: conta e ajustes, tema e trocar de
/// perfil. É um [MenuAnchor] (e não um PopupMenuButton) para o painel poder ser
/// de vidro, desfocando o conteúdo que fica atrás dele.
class _ProfileMenu extends StatefulWidget {
  const _ProfileMenu({required this.onOpenAccount});

  final VoidCallback onOpenAccount;

  @override
  State<_ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends State<_ProfileMenu> {
  final _focus = FocusNode(debugLabel: 'menu do perfil');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ProfilesScope.of(context);
    final profile = profiles.session?.profile;
    if (profile == null) return const SizedBox.shrink();
    final app = AppScope.of(context);
    final dark = AppColors.isDark;

    return MenuAnchor(
      childFocusNode: _focus,
      consumeOutsideTap: true,
      // O painel é o próprio vidro: o do Material fica invisível e não recorta
      // a sombra.
      clipBehavior: Clip.none,
      alignmentOffset: const Offset(0, 4),
      style: glassMenuStyle,
      menuChildren: [
        GlassMenuPanel(
          children: [
            GlassMenuItem(
              icon: Icons.settings_outlined,
              label: 'Conta e ajustes',
              onPressed: widget.onOpenAccount,
            ),
            GlassMenuItem(
              icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              label: dark ? 'Tema claro' : 'Tema escuro',
              onPressed: () => app.setThemePref(
                dark ? ThemePref.light : ThemePref.dark,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppGlass.line),
            ),
            GlassMenuItem(
              icon: Icons.swap_horiz,
              label: 'Trocar de perfil',
              onPressed: profiles.leave,
            ),
          ],
        ),
      ],
      builder: (context, menu, child) => Tooltip(
        message: 'Perfil',
        child: InkWell(
          focusNode: _focus,
          borderRadius: AppShape.control,
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent, width: 2),
              ),
              child: ProfileAvatar.of(profile, size: 32),
            ),
            const SizedBox(width: 10),
            // Sobre o banner em tela cheia, nome e seta ficam brancos.
            ValueListenableBuilder<bool>(
              valueListenable: WindowChrome.overMedia,
              builder: (context, overMedia, _) {
                final shadows = overMedia
                    ? const [Shadow(color: Color(0xCC000000), blurRadius: 6)]
                    : null;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: overMedia ? Colors.white : null,
                          shadows: shadows,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: overMedia ? Colors.white : AppColors.textMuted,
                      shadows: shadows,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
