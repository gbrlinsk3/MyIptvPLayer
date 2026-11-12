import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../profiles/profile.dart';
import '../../profiles/profiles_scope.dart';
import 'profile_avatar.dart';
import 'profile_editor_dialog.dart';

/// Máximo de perfis (escolha de layout; ajustável aqui).
const int maxProfiles = 6;

/// Tela "Quem está assistindo?". Sem perfis, abre direto o formulário do primeiro.
class ProfilePickerPage extends StatefulWidget {
  const ProfilePickerPage({super.key});

  @override
  State<ProfilePickerPage> createState() => _ProfilePickerPageState();
}

class _ProfilePickerPageState extends State<ProfilePickerPage> {
  bool _manage = false;
  bool _askedFirst = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Primeira abertura do app: ainda não existe perfil algum.
    final c = ProfilesScope.read(context);
    if (!_askedFirst && c.profiles.isEmpty) {
      _askedFirst = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final created = await showProfileEditor(context);
        if (created != null && mounted) {
          await ProfilesScope.read(context).enter(created);
        }
      });
    }
  }

  Future<void> _add() async {
    final created = await showProfileEditor(context);
    if (created != null && mounted) {
      await ProfilesScope.read(context).enter(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ProfilesScope.of(context);
    final profiles = c.profiles;
    final canAdd = profiles.length < maxProfiles;
    final managing = _manage && profiles.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    managing ? 'Gerenciar perfis' : 'Quem está assistindo?',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 28,
                    runSpacing: 28,
                    children: [
                      for (var i = 0; i < profiles.length; i++)
                        _Entrance(
                          index: i,
                          child: _ProfileTile(
                            profile: profiles[i],
                            managing: managing,
                            onTap: c.entering
                                ? null
                                : () async {
                                    if (managing) {
                                      await showProfileEditor(
                                        context,
                                        existing: profiles[i],
                                      );
                                    } else {
                                      await c.enter(profiles[i]);
                                    }
                                  },
                          ),
                        ),
                      if (canAdd)
                        _Entrance(
                          index: profiles.length,
                          child: _AddTile(onTap: c.entering ? null : _add),
                        ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  if (profiles.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => setState(() => _manage = !_manage),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: AppShape.button,
                      ),
                      child: Text(managing ? 'Concluído' : 'Gerenciar perfis'),
                    ),
                  if (c.error != null) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        c.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  if (c.indexRecovered) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        'A lista de perfis estava ilegível e foi recriada. Perfis '
                        'encontrados em disco voltaram como "Perfil N"; edite o '
                        'nome e o avatar em Gerenciar perfis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (c.entering)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.bg.withValues(alpha: 0.4),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Entrada suave: cada cartão aparece subindo levemente, com atraso escalonado.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}

class _ProfileTile extends StatefulWidget {
  const _ProfileTile({
    required this.profile,
    required this.managing,
    required this.onTap,
  });

  final Profile profile;
  final bool managing;
  final VoidCallback? onTap;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    const size = 140.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: size + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _hover ? 1.06 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size * 0.18 + 4),
                    border: Border.all(
                      color: _hover ? p.accentColor : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      ProfileAvatar.of(p, size: size),
                      if (widget.managing)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0x73000000),
                              borderRadius: BorderRadius.circular(size * 0.18),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.edit_outlined,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _hover ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatefulWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  State<_AddTile> createState() => _AddTileState();
}

class _AddTileState extends State<_AddTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const size = 140.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: size + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _hover ? 1.06 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: _hover ? AppColors.hover : AppColors.surface,
                      borderRadius: BorderRadius.circular(size * 0.18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 44,
                      color: _hover ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Adicionar perfil',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _hover ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
