import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';

/// Tira um quadro aleatório (entre 10% e 90% da duração) de um vídeo local e o
/// guarda como `.jpg` ao lado dele. Devolve o caminho, ou null se não deu.
///
/// Usa um player do media_kit só para isso (sem aparecer na tela). **Não foi
/// testado**: depende de `Player.screenshot()` na versão do media_kit do projeto.
Future<String?> generateVideoThumb(String videoPath) async {
  Player? player;
  try {
    player = Player();
    // O controlador cria a saída de vídeo, necessária para a captura.
    VideoController(player);
    await player.open(Media(videoPath), play: false);
    var duration = player.state.duration;
    for (var i = 0; i < 40 && duration == Duration.zero; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      duration = player.state.duration;
    }
    final target = duration > const Duration(seconds: 6)
        ? Duration(
            milliseconds: (duration.inMilliseconds *
                    (0.1 + math.Random().nextDouble() * 0.8))
                .round(),
          )
        : const Duration(seconds: 2);
    await player.seek(target);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final bytes = await player.screenshot(format: 'image/jpeg');
    if (bytes == null || bytes.isEmpty) return null;
    final out = p.setExtension(videoPath, '.jpg');
    await File(out).writeAsBytes(bytes, flush: true);
    return out;
  } catch (e, st) {
    AppLog.error('biblioteca.capa', e, st);
    return null;
  } finally {
    try {
      await player?.dispose();
    } catch (_) {}
  }
}
