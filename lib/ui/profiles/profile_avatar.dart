import 'package:flutter/material.dart';

import '../../profiles/profile.dart';

/// Avatar quadrado de cantos arredondados. Se a imagem embutida não existir
/// (por exemplo, `assets/avatars/` não declarado no pubspec), mostra a inicial
/// do nome sobre a cor do perfil.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatar,
    required this.name,
    required this.accent,
    required this.size,
  });

  factory ProfileAvatar.of(Profile p, {Key? key, required double size}) =>
      ProfileAvatar(
        key: key,
        avatar: p.avatar,
        name: p.name,
        accent: p.accentColor,
        size: size,
      );

  final String avatar;
  final String name;
  final Color accent;
  final double size;

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.18);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          avatarAsset(avatar),
          fit: BoxFit.cover,
          cacheWidth: (size * 2).round(),
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => ColoredBox(
            color: accent,
            child: Center(
              child: Text(
                _initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
