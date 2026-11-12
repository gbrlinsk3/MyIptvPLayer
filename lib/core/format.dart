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
