import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../profiles/profile.dart';
import '../../profiles/profiles_scope.dart';
import '../widgets/common.dart';
import 'profile_avatar.dart';

/// Criar ou editar um perfil: nome, avatar e cor de destaque.
/// [existing] nulo = novo perfil. [isActive] = perfil aberto no momento
/// (não pode ser excluído e a cor muda na hora).
Future<Profile?> showProfileEditor(
  BuildContext context, {
  Profile? existing,
  bool isActive = false,
}) {
  return showDialog<Profile>(
    context: context,
    builder: (ctx) => _ProfileEditor(existing: existing, isActive: isActive),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.existing, required this.isActive});

  final Profile? existing;
  final bool isActive;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name;
  late String _avatar;
  late int _accent;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _avatar = p?.avatar ?? avatarKeys.first;
    _accent = p?.accent ?? profileAccents.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome ao perfil.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = ProfilesScope.read(context);
    try {
      final Profile result;
      final existing = widget.existing;
      if (existing == null) {
        result = await c.create(name, _avatar, _accent);
      } else {
        result = existing.copyWith(name: name, avatar: _avatar, accent: _accent);
        if (widget.isActive) {
          await c.updateActive(result);
        } else {
          await c.update(result);
        }
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Não foi possível salvar: $e';
        });
      }
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Excluir o perfil "${existing.name}"?',
      message:
          'Apaga neste computador a conta Xtream, o catálogo, as fontes EPG e '
          'os ajustes deste perfil. Não afeta sua conta no provedor.',
      action: 'Excluir',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final c = ProfilesScope.read(context);
    final nav = Navigator.of(context);
    await c.delete(existing);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final accent = Color(_accent);
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                editing ? 'Editar perfil' : 'Novo perfil',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: ProfileAvatar(
                              key: ValueKey(_avatar),
                              avatar: _avatar,
                              name: _name.text,
                              accent: accent,
                              size: 80,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _name,
                              enabled: !_busy,
                              autofocus: !editing,
                              maxLength: 24,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _save(),
                              decoration: fieldDecoration(label: 'Nome do perfil')
                                  .copyWith(counterText: ''),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Avatar',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final key in avatarKeys)
                            _AvatarChoice(
                              avatar: key,
                              name: _name.text,
                              accent: accent,
                              selected: key == _avatar,
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _avatar = key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Cor de destaque',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final value in profileAccents)
                            _AccentChoice(
                              color: Color(value),
                              selected: value == _accent,
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _accent = value),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (editing && !widget.isActive)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Excluir perfil'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(editing ? 'Salvar' : 'Criar perfil'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.avatar,
    required this.name,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String avatar;
  final String name;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: ProfileAvatar(
            avatar: avatar,
            name: name,
            accent: accent,
            size: 48,
          ),
        ),
      ),
    );
  }
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.text : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
