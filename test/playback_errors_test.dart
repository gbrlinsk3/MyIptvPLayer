import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playback/playback_errors.dart';

void main() {
  const xui = 'Failed to open http://x/live/u/p/1.ts: <html><head><title>XUI.ONE'
      '</title></head><body>STREAM_OFFLINE</body></html>';

  test('HTML do XUI com STREAM_OFFLINE', () {
    expect(isServerOffline(xui), isTrue);
    expect(isServerOffline('stream_offline'), isTrue);
    expect(friendlyPlaybackError(xui),
        'O servidor informou que o canal está fora do ar.');
  });

  test('mensagem comum', () {
    expect(isServerOffline('Sem dados do servidor há 20s.'), isFalse);
    expect(friendlyPlaybackError('  Sem   dados\n do servidor. '),
        'Sem dados do servidor.');
  });

  test('HTML sem offline é cortado no primeiro <', () {
    expect(friendlyPlaybackError('Erro 502 <html><body>Bad</body></html>'),
        'Erro 502');
  });

  test('vazia ou só HTML', () {
    expect(friendlyPlaybackError(''), 'Falha ao abrir a transmissão.');
    expect(friendlyPlaybackError('<html></html>'),
        'Falha ao abrir a transmissão.');
  });

  test('limite de 200 caracteres com reticências', () {
    final out = friendlyPlaybackError('a' * 500);
    expect(out.length, 201);
    expect(out.endsWith('…'), isTrue);
  });
}
