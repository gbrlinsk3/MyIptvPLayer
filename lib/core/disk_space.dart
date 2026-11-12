import 'dart:io';

import 'app_log.dart';
import 'system_dialogs.dart';

/// Espaço livre no disco onde está uma pasta (só Windows; usa o PowerShell).
class DiskSpace {
  DiskSpace._();

  /// Bytes livres, ou nulo se não deu para saber (pasta de rede, sem
  /// PowerShell, outro sistema...). Quem chama deve tratar nulo como "não sei".
  static Future<int?> freeBytes(String folderPath) async {
    if (!Platform.isWindows) return null;
    final path = folderPath.replaceAll("'", "''");
    final out = await SystemDialogs.powershell(
      "\$r = [System.IO.Path]::GetPathRoot('$path'); "
      "if (\$r -and -not \$r.StartsWith('\\\\')) "
      "{ (New-Object System.IO.DriveInfo(\$r)).AvailableFreeSpace }",
    );
    final n = int.tryParse(out?.trim() ?? '');
    if (n == null) AppLog.warn('disco', 'Não foi possível medir o espaço livre de $folderPath');
    return n;
  }
}
