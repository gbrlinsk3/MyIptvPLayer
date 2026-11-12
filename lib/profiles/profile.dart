import 'package:flutter/painting.dart';

/// Perfil local: nome, avatar e cor de destaque. Os dados de cada perfil
/// (conta Xtream, catálogo, ajustes, EPG) ficam em um banco só dele.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.accent,
  });

  final int id;
  final String name;

  /// Chave do avatar embutido (por exemplo `a01`), ver [avatarKeys].
  final String avatar;

  /// Cor de destaque (valor ARGB).
  final int accent;

  Color get accentColor => Color(accent);

  String get initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  Profile copyWith({String? name, String? avatar, int? accent}) => Profile(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        accent: accent ?? this.accent,
      );
}

/// Avatares embutidos: `assets/avatars/a01.jpg` … `a20.jpg`.
final List<String> avatarKeys = [
  for (var i = 1; i <= 20; i++) 'a${i.toString().padLeft(2, '0')}',
];

String avatarAsset(String key) => 'assets/avatars/$key.jpg';

/// Cores de destaque oferecidas na criação/edição do perfil (a primeira é a padrão).
const List<int> profileAccents = [
  0xFFC6613F, // terracota
  0xFFD64545, // vermelho
  0xFFE08A1E, // laranja
  0xFF3B8F5A, // verde
  0xFF2E8CA8, // azul-petróleo
  0xFF3D6FD8, // azul
  0xFF7B5CC4, // roxo
  0xFFC4558F, // rosa
];
