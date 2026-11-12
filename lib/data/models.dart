/// Credenciais salvas localmente (uma conta por vez nesta build).
class SavedAccount {
  const SavedAccount({
    required this.server,
    required this.username,
    required this.password,
  });

  final String server;
  final String username;
  final String password;
}

/// Dados da conta devolvidos pelo servidor na autenticação.
class AccountInfo {
  const AccountInfo({
    this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
  });

  final String? status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
}

class LiveCategory {
  const LiveCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class LiveChannel {
  LiveChannel({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.icon,
    this.epgId,
  }) : searchKey = foldText(name);

  final int streamId;
  final String name;
  final String categoryId;
  final String? icon;

  /// Código de EPG informado pelo provedor para este canal (pode não existir).
  final String? epgId;

  /// Nome em minúsculas e sem acentos, calculado uma vez para a busca.
  final String searchKey;

  /// Código de EPG em minúsculas, usado para casar com fontes XMLTV.
  String? get epgKey {
    final value = epgId?.trim().toLowerCase();
    return (value == null || value.isEmpty) ? null : value;
  }
}

/// Um programa da guia. Horários em segundos desde 1970 (UTC).
class EpgProgram {
  const EpgProgram({
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });

  final int start;
  final int stop;
  final String title;
  final String? description;

  DateTime get startTime =>
      DateTime.fromMillisecondsSinceEpoch(start * 1000);
  DateTime get stopTime => DateTime.fromMillisecondsSinceEpoch(stop * 1000);
}

/// Fonte de EPG (XMLTV) adicionada pelo usuário, por URL.
class EpgSource {
  const EpgSource({
    required this.id,
    required this.url,
    this.updatedAt,
    this.programCount = 0,
    this.error,
  });

  final int id;
  final String url;
  final DateTime? updatedAt;
  final int programCount;
  final String? error;

  /// Nome curto para exibir (o host da URL).
  String get label {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }
}

const _accented = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _plain = 'aaaaaeeeeiiiiooooouuuucn';

final Map<int, int> _foldMap = {
  for (var i = 0; i < _accented.length; i++)
    _accented.codeUnitAt(i): _plain.codeUnitAt(i),
};

/// Minúsculas + remoção dos acentos mais comuns do português/espanhol.
/// (Chamada para cada título ao montar o índice de busca: só letras fora do
/// ASCII passam pela tabela de acentos, o resto é copiado direto.)
String foldText(String input) {
  final lower = input.toLowerCase();
  final units = lower.codeUnits;
  List<int>? out;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u < 0x80) {
      out?.add(u);
      continue;
    }
    final plain = _foldMap[u];
    if (plain != null) {
      out ??= units.sublist(0, i).toList(growable: true);
      out.add(plain);
    } else {
      out?.add(u);
    }
  }
  return out == null ? lower : String.fromCharCodes(out);
}
