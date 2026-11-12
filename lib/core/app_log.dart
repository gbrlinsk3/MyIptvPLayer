import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Registro de erros e avisos em arquivo local (`logs/app.log` na pasta de
/// dados do app). Nunca lança erro: se o arquivo não puder ser escrito, a
/// mensagem vai só para o console. Endereços de stream e senhas são
/// mascarados antes de gravar.
class AppLog {
  AppLog._();

  static const _maxBytes = 512 * 1024;

  static File? _file;
  static Directory? _dir;
  static Future<void> _queue = Future.value();

  /// Caminho do arquivo de log (nulo até [init] terminar).
  static String? get path => _file?.path;

  /// Pasta dos arquivos de log (nula até [init] terminar).
  static String? get folder => _dir?.path;

  /// Abre a pasta de logs no Explorer.
  static Future<void> openFolder() async {
    final d = _dir;
    if (d == null) return;
    try {
      await Process.run('explorer.exe', [d.path]);
    } catch (e) {
      debugPrint('AppLog.openFolder falhou: $e');
    }
  }

  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'logs'));
      await dir.create(recursive: true);
      _dir = dir;
      final file = File(p.join(dir.path, 'app.log'));
      // Rotação simples: guarda só o log anterior (app.log.1).
      if (await file.exists() && await file.length() > _maxBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
      }
      _file = File(p.join(dir.path, 'app.log'));
      info('app', 'Iniciado');
    } catch (e) {
      debugPrint('AppLog.init falhou: $e');
    }
  }

  static void info(String where, String message) =>
      _write('INFO', where, message);

  static void warn(String where, Object error) =>
      _write('AVISO', where, '$error');

  static void error(String where, Object error, [StackTrace? stack]) {
    final trace = stack == null ? '' : '\n${_firstLines(stack.toString(), 8)}';
    _write('ERRO', where, '$error$trace');
  }

  static String _firstLines(String s, int n) =>
      s.split('\n').take(n).join('\n');

  /// Remove credenciais de endereços e parâmetros antes de gravar.
  static String scrub(String s) => s
      .replaceAllMapped(
        RegExp(r'(://[^/\s]+/(?:movie|series|live)/)[^/\s]+/[^/\s]+/'),
        (m) => '${m[1]}***/***/',
      )
      .replaceAllMapped(
        RegExp(r'(username|password)=[^&\s]+', caseSensitive: false),
        (m) => '${m[1]}=***',
      );

  static void _write(String level, String where, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $where: '
        '${scrub(message)}\n';
    debugPrint(line.trimRight());
    final file = _file;
    if (file == null) return;
    // Fila: as gravações acontecem uma por vez, na ordem.
    _queue = _queue.then((_) async {
      try {
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // Sem como registrar o erro do registro.
      }
    });
  }
}
