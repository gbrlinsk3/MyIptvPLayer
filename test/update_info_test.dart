import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/update/update_info.dart';

void main() {
  final hash = 'a' * 64;

  test('manifesto com details: seções na ordem e itens limpos', () {
    final info = UpdateInfo.fromJson({
      'version': '1.0.5',
      'url': 'https://x/y.exe',
      'sha256': hash,
      'notes': 'curto',
      'details': {
        'correcoes': ['  Bug A  ', ''],
        'novos': ['Recurso 1', 'Recurso 2'],
        'design': 'Só um item', // PowerShell 5 grava lista de 1 item assim
        'outra': ['ignorada'],
      },
    })!;
    expect(info.hasDetails, isTrue);
    expect(info.details['novos'], ['Recurso 1', 'Recurso 2']);
    expect(info.details['design'], ['Só um item']);
    expect(info.details['correcoes'], ['Bug A']);
    expect(info.details.containsKey('outra'), isFalse);
  });

  test('manifesto antigo (sem details) continua valendo', () {
    final info = UpdateInfo.fromJson({
      'version': '1.0.4',
      'url': 'https://x/y.exe',
      'sha256': hash,
      'notes': 'texto',
    })!;
    expect(info.hasDetails, isFalse);
    expect(info.notes, 'texto');
  });
}
