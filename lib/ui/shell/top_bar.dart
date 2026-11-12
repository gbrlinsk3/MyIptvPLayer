import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../profiles/profiles_scope.dart';
import '../../state/app_scope.dart';
import '../profiles/profile_avatar.dart';

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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          focusNode: focus,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar filmes, séries e canais…',
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: AppColors.accent, width: 1.4),
            ),
          ),
        );
      },
    );
  }
}

/// Perfil ativo no topo, à direita. Menu: conta e ajustes, tema e trocar de perfil.
class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.onOpenAccount});

  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final profiles = ProfilesScope.of(context);
    final profile = profiles.session?.profile;
    if (profile == null) return const SizedBox.shrink();
    final app = AppScope.of(context);
    final dark = AppColors.isDark;

    return PopupMenuButton<String>(
      tooltip: 'Perfil',
      offset: const Offset(0, 48),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      onSelected: (v) {
        switch (v) {
          case 'account':
            onOpenAccount();
          case 'theme':
            app.setThemePref(dark ? ThemePref.light : ThemePref.dark);
          case 'switch':
            profiles.leave();
        }
      },
      itemBuilder: (context) => [
        _item('account', Icons.settings_outlined, 'Conta e ajustes'),
        _item(
          'theme',
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          dark ? 'Tema claro' : 'Tema escuro',
        ),
        const PopupMenuDivider(),
        _item('switch', Icons.swap_horiz, 'Trocar de perfil'),
      ],
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
