import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'app_log.dart';

/// Protege segredos (a senha Xtream) com a DPAPI do Windows: só o mesmo usuário
/// do Windows, neste computador, consegue ler o valor gravado no banco.
/// Usa `dart:ffi` direto (sem pacote extra). Se a DPAPI falhar, o valor é
/// gravado sem proteção e o aviso vai para o log (o app não trava por isso).
class SecretStore {
  SecretStore._();

  static const _prefix = 'dpapi:';

  static bool isProtected(String stored) => stored.startsWith(_prefix);

  /// Devolve `dpapi:<base64>` ou o próprio [plain] se a proteção não estiver
  /// disponível (fora do Windows ou erro).
  static String protect(String plain) {
    if (!Platform.isWindows || plain.isEmpty) return plain;
    try {
      final out = _crypt(utf8.encode(plain), protect: true);
      return '$_prefix${base64Encode(out)}';
    } catch (e) {
      AppLog.warn('segredo.proteger', e);
      return plain;
    }
  }

  /// Aceita tanto valores protegidos quanto texto simples antigo.
  static String reveal(String stored) {
    if (!isProtected(stored)) return stored;
    try {
      final data = base64Decode(stored.substring(_prefix.length));
      return utf8.decode(_crypt(data, protect: false));
    } catch (e) {
      AppLog.warn('segredo.revelar', e);
      return '';
    }
  }

  static List<int> _crypt(List<int> input, {required bool protect}) {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final crt = DynamicLibrary.open('msvcrt.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');

    final malloc = crt.lookupFunction<Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)>('malloc');
    final free = crt.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    final localFree = kernel.lookupFunction<Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)>('LocalFree');

    final fn = crypt32.lookupFunction<
        Int32 Function(Pointer<_Blob>, Pointer<Void>, Pointer<_Blob>,
            Pointer<Void>, Pointer<Void>, Uint32, Pointer<_Blob>),
        int Function(Pointer<_Blob>, Pointer<Void>, Pointer<_Blob>,
            Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>)>(
      protect ? 'CryptProtectData' : 'CryptUnprotectData',
    );

    final buf = malloc(input.isEmpty ? 1 : input.length).cast<Uint8>();
    final inBlob = malloc(sizeOf<_Blob>()).cast<_Blob>();
    final outBlob = malloc(sizeOf<_Blob>()).cast<_Blob>();
    try {
      buf.asTypedList(input.length).setAll(0, input);
      inBlob.ref
        ..cbData = input.length
        ..pbData = buf;
      outBlob.ref
        ..cbData = 0
        ..pbData = nullptr.cast<Uint8>();
      // Flag 0x1 = CRYPTPROTECT_UI_FORBIDDEN (nunca abre janela).
      final ok = fn(inBlob, nullptr, nullptr, nullptr, nullptr, 1, outBlob);
      if (ok == 0) throw StateError('DPAPI falhou');
      final result = List<int>.from(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );
      localFree(outBlob.ref.pbData.cast<Void>());
      return result;
    } finally {
      free(buf.cast<Void>());
      free(inBlob.cast<Void>());
      free(outBlob.cast<Void>());
    }
  }
}

/// DATA_BLOB do Windows: { DWORD cbData; BYTE* pbData; }.
final class _Blob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}
