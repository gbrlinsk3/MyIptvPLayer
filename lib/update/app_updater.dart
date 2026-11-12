import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_info.dart';
import '../core/app_log.dart';
import 'sha256.dart';
import 'update_info.dart';

enum UpdateState { idle, checking, available, downloading, ready, error }

/// Atualizador próprio. Consulta um manifesto JSON por HTTPS (endereço em
/// [manifestUrl]), baixa o .zip da nova versão, confere o SHA-256 do manifesto
/// e, ao confirmar, troca os arquivos do programa e reabre.
///
/// Não há servidor definido: o endereço fica vazio até você publicar o
/// manifesto em algum lugar e informá-lo em Conta e ajustes → Configurações →
/// Atualizações (ou em [AppInfo.defaultManifestUrl]).
class AppUpdater extends ChangeNotifier {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  UpdateState state = UpdateState.idle;
  UpdateInfo? available;
  String? error;
  double progress = 0;
  bool dismissed = false;
  String manifestUrl = AppInfo.defaultManifestUrl;

  File? _config;
  File? _zip;

  bool get configured => manifestUrl.isNotEmpty;

  Future<void> loadConfig() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _config = File(p.join(dir.path, 'update_config.json'));
      if (await _config!.exists()) {
        final j = jsonDecode(await _config!.readAsString());
        if (j is Map && j['manifest_url'] is String) {
          manifestUrl = j['manifest_url'] as String;
        }
      }
    } catch (e) {
      AppLog.warn('atualizador.config', e);
    }
  }

  Future<String?> setManifestUrl(String raw) async {
    final url = raw.trim();
    if (url.isNotEmpty && !url.toLowerCase().startsWith('https://')) {
      return 'Use um endereço https:// (conexão protegida).';
    }
    manifestUrl = url;
    try {
      await _config?.writeAsString(jsonEncode({'manifest_url': url}));
    } catch (e) {
      AppLog.warn('atualizador.config', e);
    }
    notifyListeners();
    return null;
  }

  /// Consulta o manifesto. Nunca lança; falhas ficam em [error] (e no log).
  /// [timeout] limita a espera na tela de abertura.
  Future<void> check({Duration timeout = const Duration(seconds: 6)}) async {
    if (!configured) return;
    state = UpdateState.checking;
    error = null;
    notifyListeners();
    final client = http.Client();
    try {
      final res = await client
          .get(Uri.parse(manifestUrl), headers: {'Accept': 'application/json'})
          .timeout(timeout);
      if (res.statusCode != 200) {
        throw 'servidor respondeu ${res.statusCode}';
      }
      final info = UpdateInfo.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
      if (info == null) throw 'manifesto inválido';
      if (!info.url.toLowerCase().startsWith('https://')) {
        throw 'o link da atualização não é https';
      }
      if (UpdateInfo.isNewer(info.version, AppInfo.version)) {
        available = info;
        dismissed = false;
        state = UpdateState.available;
      } else {
        available = null;
        state = UpdateState.idle;
      }
    } catch (e) {
      AppLog.warn('atualizador.checar', e);
      error = 'Não foi possível procurar atualização.';
      state = UpdateState.error;
    } finally {
      client.close();
      notifyListeners();
    }
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  /// Baixa o zip, confere o hash. Em seguida [state] vira `ready`.
  Future<void> download() async {
    final info = available;
    if (info == null || state == UpdateState.downloading) return;
    state = UpdateState.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    final client = http.Client();
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, 'mip_update'));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'update.zip'));

      final req = http.Request('GET', Uri.parse(info.url));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw 'servidor respondeu ${res.statusCode}';
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      final hash = Sha256();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          hash.add(chunk);
          got += chunk.length;
          if (total > 0) {
            progress = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (hash.close() != info.sha256) {
        await file.delete();
        throw 'o arquivo baixado não confere com o hash publicado (SHA-256)';
      }
      _zip = file;
      state = UpdateState.ready;
    } catch (e) {
      AppLog.warn('atualizador.baixar', e);
      error = 'Falha ao baixar a atualização: $e';
      state = UpdateState.error;
    } finally {
      client.close();
      notifyListeners();
    }
  }

  /// Extrai o zip por cima da pasta do programa e reabre. Encerra o app.
  /// Usa o PowerShell do Windows (Expand-Archive); um script espera o app
  /// fechar antes de copiar, porque o .exe em uso não pode ser trocado.
  Future<void> installAndRestart() async {
    final zip = _zip;
    if (zip == null || !Platform.isWindows) return;
    try {
      final exe = Platform.resolvedExecutable;
      final appDir = p.dirname(exe);
      final work = p.dirname(zip.path);
      final stage = p.join(work, 'novo');
      final script = File(p.join(work, 'atualizar.ps1'));
      String q(String s) => "'${s.replaceAll("'", "''")}'";
      await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
Start-Sleep -Seconds 2
for (\$i = 0; \$i -lt 30; \$i++) {
  if (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 1
}
if (Test-Path ${q(stage)}) { Remove-Item ${q(stage)} -Recurse -Force }
Expand-Archive -LiteralPath ${q(zip.path)} -DestinationPath ${q(stage)} -Force
# Espelha a versão nova na pasta do programa: copia o que mudou e APAGA o que
# não existe mais na versão nova (arquivos inúteis). O desinstalador é mantido.
robocopy ${q(stage)} ${q(appDir)} /MIR /XF desinstalar.ps1 /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
if (\$LASTEXITCODE -ge 8) { exit 1 }
Start-Process -FilePath ${q(exe)}
# Limpeza dos arquivos temporários da atualização.
Remove-Item ${q(stage)} -Recurse -Force
Remove-Item ${q(zip.path)} -Force
''');
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
        ],
        mode: ProcessStartMode.detached,
      );
      AppLog.info('atualizador', 'Instalando ${available?.version}; reiniciando');
      exit(0);
    } catch (e) {
      AppLog.error('atualizador.instalar', e);
      error = 'Falha ao instalar a atualização: $e';
      state = UpdateState.error;
      notifyListeners();
    }
  }
}
