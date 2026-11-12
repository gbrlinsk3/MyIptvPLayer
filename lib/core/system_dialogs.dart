import 'dart:convert';
import 'dart:io';

import 'app_log.dart';

/// Diálogos nativos do Windows para escolher pasta/arquivo, sem pacote extra:
/// usa o PowerShell (System.Windows.Forms) que já vem no Windows.
/// Em outros sistemas (ou se o PowerShell falhar) devolve nulo.
class SystemDialogs {
  SystemDialogs._();

  /// Escolhe uma pasta. Nulo = cancelado ou indisponível.
  static Future<String?> pickFolder({
    String? initial,
    String description = 'Escolha a pasta',
  }) {
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$owner = New-Object System.Windows.Forms.Form
\$owner.TopMost = \$true
\$null = \$owner.Handle
\$d = New-Object System.Windows.Forms.FolderBrowserDialog
\$d.Description = '${_q(description)}'
\$d.ShowNewFolderButton = \$true
${initial == null || initial.isEmpty ? '' : "\$d.SelectedPath = '${_q(initial)}'"}
if (\$d.ShowDialog(\$owner) -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$d.SelectedPath }
\$owner.Dispose()
''';
    return _run(script);
  }

  /// Escolhe um arquivo. [filter] no formato do Windows, ex.:
  /// `Vídeos|*.mp4;*.mkv|Todos os arquivos|*.*`.
  static Future<String?> pickFile({
    String title = 'Escolha o arquivo',
    String filter = 'Todos os arquivos|*.*',
    String? initialDirectory,
  }) {
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$owner = New-Object System.Windows.Forms.Form
\$owner.TopMost = \$true
\$null = \$owner.Handle
\$d = New-Object System.Windows.Forms.OpenFileDialog
\$d.Title = '${_q(title)}'
\$d.Filter = '${_q(filter)}'
\$d.Multiselect = \$false
${initialDirectory == null || initialDirectory.isEmpty ? '' : "\$d.InitialDirectory = '${_q(initialDirectory)}'"}
if (\$d.ShowDialog(\$owner) -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$d.FileName }
\$owner.Dispose()
''';
    return _run(script);
  }

  static const videoFilter =
      'Vídeos|*.mp4;*.mkv;*.avi;*.mov;*.ts;*.m4v;*.webm;*.wmv;*.flv|Todos os arquivos|*.*';
  static const imageFilter =
      'Imagens|*.jpg;*.jpeg;*.png;*.webp;*.bmp|Todos os arquivos|*.*';

  // Aspas simples do PowerShell se escapam dobrando.
  static String _q(String s) => s.replaceAll("'", "''");

  static Future<String?> _run(String script) => powershell(script, sta: true);

  /// Roda um script do PowerShell e devolve o que ele imprimiu (nulo se falhar
  /// ou se não for Windows). `-STA` é necessário para diálogos.
  static Future<String?> powershell(String script, {bool sta = false}) async {
    if (!Platform.isWindows) return null;
    try {
      // UTF-16LE em base64: evita qualquer problema de aspas/acentos na linha de comando.
      final bytes = <int>[];
      for (final u in ('[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n$script').codeUnits) {
        bytes..add(u & 0xFF)..add(u >> 8);
      }
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', if (sta) '-STA', '-EncodedCommand', base64Encode(bytes)],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        AppLog.warn('dialogo', 'PowerShell saiu com ${result.exitCode}: ${result.stderr}');
        return null;
      }
      final out = '${result.stdout}'.trim();
      return out.isEmpty ? null : out;
    } catch (e) {
      AppLog.warn('dialogo', e);
      return null;
    }
  }
}
