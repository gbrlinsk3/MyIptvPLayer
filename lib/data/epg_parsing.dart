import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

// ---------------------------------------------------------------------------
// EPG do provedor (API Xtream)
//
// O formato abaixo (epg_listings, start_timestamp, título em base64) segue a
// convenção Xtream que eu conheço. NÃO foi verificado no servidor do usuário.
// ---------------------------------------------------------------------------

final _base64Shape = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

/// Muitos painéis Xtream devolvem título/descrição em base64; outros, em
/// texto puro. Só aceita como base64 o que decodifica para UTF-8 válido e sem
/// caracteres de controle; caso contrário devolve o texto original.
String decodeMaybeBase64(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.length % 4 != 0 || !_base64Shape.hasMatch(text)) {
    return text;
  }
  try {
    final decoded = utf8.decode(base64.decode(text)); // estrito: pode lançar
    final hasControl = decoded.runes.any(
      (r) => r < 0x20 && r != 0x0A && r != 0x09 && r != 0x0D,
    );
    return hasControl ? text : decoded.trim();
  } on FormatException {
    return text;
  }
}

int? _localToEpoch(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}

List<EpgProgram> parseProviderEpg(Uint8List bytes) {
  Object? data;
  try {
    data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return const [];
  }
  if (data is! Map) return const [];
  final list = data['epg_listings'];
  if (list is! List) return const [];

  final out = <EpgProgram>[];
  for (final item in list) {
    if (item is! Map) continue;
    // Prefere os timestamps; se faltarem, usa as datas em texto (tratadas
    // como horário local, o que é uma suposição).
    final start = int.tryParse('${item['start_timestamp']}') ??
        _localToEpoch(item['start']?.toString());
    final stop = int.tryParse('${item['stop_timestamp']}') ??
        _localToEpoch(item['end']?.toString());
    final title = decodeMaybeBase64((item['title'] ?? '').toString());
    if (start == null || stop == null || title.isEmpty) continue;
    final description =
        decodeMaybeBase64((item['description'] ?? '').toString());
    out.add(
      EpgProgram(
        start: start,
        stop: stop,
        title: title,
        description: description.isEmpty ? null : description,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// EPG por URL (XMLTV)
// ---------------------------------------------------------------------------

/// Entrada para [parseXmltv] (roda em outro isolate).
class XmltvJob {
  const XmltvJob({
    required this.bytes,
    required this.wanted,
    required this.fromEpoch,
    required this.toEpoch,
  });

  final Uint8List bytes;

  /// Códigos de canal (minúsculos) que interessam; o resto é descartado.
  final Set<String> wanted;
  final int fromEpoch;
  final int toEpoch;
}

class XmltvRow {
  const XmltvRow({
    required this.channel,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });

  final String channel;
  final int start;
  final int stop;
  final String title;
  final String? description;
}

final _programmeRe =
    RegExp(r'<programme\b([^>]*)>(.*?)</programme>', dotAll: true);
final _channelAttr = RegExp(r'\bchannel\s*=\s*"([^"]*)"');
final _startAttr = RegExp(r'\bstart\s*=\s*"([^"]*)"');
final _stopAttr = RegExp(r'\bstop\s*=\s*"([^"]*)"');
final _titleTag = RegExp(r'<title\b[^>]*>(.*?)</title>', dotAll: true);
final _descTag = RegExp(r'<desc\b[^>]*>(.*?)</desc>', dotAll: true);
final _timeRe = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{2}:?\d{2})?',
);
final _offsetRe = RegExp(r'^([+-])(\d{2}):?(\d{2})$');
final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

/// "20261104190000 -0300" -> segundos UTC. Sem fuso, assume UTC.
int? _xmltvTime(String? raw) {
  if (raw == null) return null;
  final m = _timeRe.firstMatch(raw.trim());
  if (m == null) return null;
  final utc = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  ).millisecondsSinceEpoch ~/ 1000;
  final zone = m.group(7);
  if (zone == null) return utc;
  final z = _offsetRe.firstMatch(zone);
  if (z == null) return utc;
  final offset = (int.parse(z.group(2)!) * 3600 + int.parse(z.group(3)!) * 60) *
      (z.group(1) == '-' ? -1 : 1);
  return utc - offset;
}

String _unescape(String raw) {
  final text = raw.trim();
  if (text.startsWith('<![CDATA[') && text.endsWith(']]>')) {
    return text.substring(9, text.length - 3).trim();
  }
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_entityRe, (m) {
    final entity = m.group(1)!;
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = entity.startsWith('#x')
        ? int.tryParse(entity.substring(2), radix: 16)
        : int.tryParse(entity.substring(1));
    if (code == null || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  });
}

/// Lê um XMLTV (texto ou .gz) e devolve só os programas dos canais desejados
/// dentro da janela de tempo. Função de nível superior para rodar via compute().
///
/// Não usa um parser XML completo (seria lento e pesado com arquivos grandes):
/// varre os blocos `<programme>` com expressões regulares. Só entende atributos
/// com aspas duplas, que é o formato usual do XMLTV.
List<XmltvRow> parseXmltv(XmltvJob job) {
  var bytes = job.bytes;
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = Uint8List.fromList(gzip.decode(bytes));
  }
  final text = utf8.decode(bytes, allowMalformed: true);

  final out = <XmltvRow>[];
  for (final m in _programmeRe.allMatches(text)) {
    final attrs = m.group(1)!;
    final channel = _channelAttr.firstMatch(attrs)?.group(1)?.trim().toLowerCase();
    if (channel == null || !job.wanted.contains(channel)) continue;

    final start = _xmltvTime(_startAttr.firstMatch(attrs)?.group(1));
    final stop = _xmltvTime(_stopAttr.firstMatch(attrs)?.group(1));
    if (start == null || stop == null) continue;
    if (stop < job.fromEpoch || start > job.toEpoch) continue;

    final body = m.group(2)!;
    final titleRaw = _titleTag.firstMatch(body)?.group(1);
    if (titleRaw == null) continue;
    final title = _unescape(titleRaw);
    if (title.isEmpty) continue;
    final descRaw = _descTag.firstMatch(body)?.group(1);
    final desc = descRaw == null ? '' : _unescape(descRaw);

    out.add(
      XmltvRow(
        channel: channel,
        start: start,
        stop: stop,
        title: title,
        description: desc.isEmpty ? null : desc,
      ),
    );
  }
  return out;
}
