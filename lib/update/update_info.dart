/// Dados de uma atualização publicada (manifesto JSON).
///
/// Formato do manifesto (arquivo `latest.json` no seu host, por HTTPS):
/// ```json
/// { "version": "1.0.1",
///   "url": "https://.../MIP-Setup-1.0.1.exe",
///   "sha256": "<hash SHA-256 do instalador .exe>",
///   "notes": "O que mudou",
///   "details": { "novos": ["..."], "design": ["..."], "correcoes": ["..."] } }
/// ```
/// `details` é opcional (vem de `notas\<versão>.md`, lido pelo script do
/// instalador) e alimenta o botão "Detalhes" do aviso de atualização.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    this.notes = '',
    this.details = const {},
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;

  /// Novidades por seção: `novos`, `design` e `correcoes` (listas de frases).
  final Map<String, List<String>> details;

  /// Rótulo de cada seção, na ordem em que aparecem em "Detalhes".
  static const sectionTitles = {
    'novos': 'Novos recursos',
    'design': 'Melhorias de design',
    'correcoes': 'Correções',
  };

  /// true se há alguma novidade detalhada para mostrar.
  bool get hasDetails => details.values.any((l) => l.isNotEmpty);

  static Map<String, List<String>> _parseDetails(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    for (final key in sectionTitles.keys) {
      final v = raw[key];
      // Aceita lista de textos ou um texto único (o PowerShell 5 grava uma
      // lista de 1 item como texto simples).
      final items = v is List
          ? v.whereType<String>()
          : v is String
              ? [v]
              : const <String>[];
      final list = items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (list.isNotEmpty) out[key] = list;
    }
    return out;
  }

  static UpdateInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final v = json['version'], u = json['url'], h = json['sha256'];
    if (v is! String || u is! String || h is! String) return null;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(h)) return null;
    return UpdateInfo(
      version: v.trim(),
      url: u.trim(),
      sha256: h.toLowerCase(),
      notes: json['notes'] is String ? json['notes'] as String : '',
      details: _parseDetails(json['details']),
    );
  }

  /// true se [a] é mais nova que [b] (comparação numérica por partes: 1.10 > 1.9).
  static bool isNewer(String a, String b) {
    List<int> parse(String s) => s
        .split(RegExp(r'[.+\-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final x = parse(a), y = parse(b);
    for (var i = 0; i < 4; i++) {
      final p = i < x.length ? x[i] : 0;
      final q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }
}
