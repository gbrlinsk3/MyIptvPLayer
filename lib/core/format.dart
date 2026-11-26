String _two(int n) => n.toString().padLeft(2, '0');

String formatDateTime(DateTime value) {
  final d = value.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

/// "19:30"
String formatClock(DateTime value) {
  final d = value.toLocal();
  return '${_two(d.hour)}:${_two(d.minute)}';
}

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// "Hoje", "Amanhã", "Ontem" ou "qui 05/11".
String formatDayLabel(DateTime value, DateTime now) {
  final d = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Amanhã';
  if (diff == -1) return 'Ontem';
  return '${_weekdays[d.weekday - 1]} ${_two(d.day)}/${_two(d.month)}';
}

/// "1:05:09" ou "05:09" (para barras de progresso e durações).
String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "31.458" (ponto de milhar).
String formatCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "1 canal", "1.645 canais".
String plural(int n, String one, String many) =>
    '${formatCount(n)} ${n == 1 ? one : many}';

final _clockRuntime = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})$');

/// Duração de filme para leitura: "01:52:00" vira "1 h 52 min". Texto em outro
/// formato volta como veio; vazio ou zerado vira null.
String? formatRuntime(String? label) {
  final text = label?.trim() ?? '';
  if (text.isEmpty) return null;
  final m = _clockRuntime.firstMatch(text);
  if (m == null) return text;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  if (h == 0 && min == 0) return null;
  if (h == 0) return '$min min';
  return min == 0 ? '$h h' : '$h h $min min';
}

/// "A, A, B" vira "A, B": tira nomes repetidos (sem diferenciar maiúsculas) e
/// mantém a ordem em que o provedor enviou.
String uniqueNames(String names) {
  final seen = <String>{};
  final out = [
    for (final part in names.split(','))
      if (part.trim().isNotEmpty && seen.add(part.trim().toLowerCase()))
        part.trim(),
  ];
  return out.isEmpty ? names : out.join(', ');
}

// Setas, formas, "dingbats" e emojis, com os seletores que os acompanham.
final _symbols = RegExp(
  r'[\u{2190}-\u{2BFF}\u{FE00}-\u{FE0F}\u{200D}\u{20E3}\u{1F000}-\u{1FAFF}]',
  unicode: true,
);

/// Nome de arquivo importado sem os símbolos que aparecem como quadrados. Só
/// para exibição: o arquivo e o nome salvo não mudam.
String cleanFileTitle(String title) {
  final out = title
      .replaceAll(_symbols, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return out.isEmpty ? title : out;
}

/// Tamanho em bytes para leitura humana (ex.: 1,4 GB).
String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = (i == 0 || v >= 100) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[i]}';
}
