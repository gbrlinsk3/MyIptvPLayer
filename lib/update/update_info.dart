/// Dados de uma atualização publicada (manifesto JSON).
///
/// Formato do manifesto (arquivo `latest.json` no seu host, por HTTPS):
/// ```json
/// { "version": "1.0.1",
///   "url": "https://.../MIP-1.0.1.zip",
///   "sha256": "<hash hexadecimal do zip>",
///   "notes": "O que mudou" }
/// ```
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    this.notes = '',
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;

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
