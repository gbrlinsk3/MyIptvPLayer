import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Som da animação de abertura do perfil (logo surgindo, piscadas e luz do
/// projetor, nos tempos de `ProfileIntro`). O arquivo já é gravado baixo e o
/// player toca em 100 %; não há ajuste de volume no app.
class IntroSound {
  static const asset = 'asset:///assets/sounds/abertura.wav';

  Player? _player;
  StreamSubscription<bool>? _completed;

  /// Termina quando o áudio começa de fato a andar, para a animação partir
  /// junto. Falha de som nunca trava a abertura.
  Future<void> start() async {
    try {
      final player = _player = Player();
      _completed = player.stream.completed.listen((done) {
        if (done) dispose();
      });
      final moving = player.stream.position.firstWhere(
        (p) => p > Duration.zero,
      );
      moving.ignore();
      await player.open(Media(asset));
      await moving;
    } catch (e) {
      debugPrint('Abertura: sem som ($e)');
    }
  }

  /// Libera o player (ao acabar o som ou ao sair do perfil).
  void dispose() {
    final player = _player;
    _player = null;
    _completed?.cancel();
    _completed = null;
    if (player != null) unawaited(player.dispose());
  }
}
