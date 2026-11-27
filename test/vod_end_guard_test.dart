import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playback/vod_end_guard.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

void main() {
  const movie = Duration(hours: 3, minutes: 4, seconds: 50);

  group('fim de verdade ou corte', () {
    test('filme "terminado" com 14 s tocados é corte', () {
      expect(VodEndGuard.isRealEnd(s(14), movie), isFalse);
    });

    // Medido com o libmpv do app: conexão derrubada aos 10% de um vídeo de 2 min.
    test('corte aos 11,7 s de 2 min', () {
      expect(VodEndGuard.isRealEnd(s(11.72), s(120)), isFalse);
    });

    // Medido no mesmo teste, com o arquivo inteiro.
    test('fim normal chega pouco antes da duração', () {
      expect(VodEndGuard.isRealEnd(s(58.6), s(60)), isTrue);
      expect(VodEndGuard.isRealEnd(s(120), s(120)), isTrue);
      expect(VodEndGuard.isRealEnd(movie + s(2), movie), isTrue);
    });

    test('margem de 30 s em vídeo longo', () {
      expect(VodEndGuard.isRealEnd(movie - s(30), movie), isTrue);
      expect(VodEndGuard.isRealEnd(movie - s(31), movie), isFalse);
    });

    test('vídeo curto: 10% do tempo, nunca menos de 3 s', () {
      expect(VodEndGuard.tolerance(s(120)), s(12));
      expect(VodEndGuard.tolerance(s(20)), s(3));
      expect(VodEndGuard.isRealEnd(s(100), s(120)), isFalse);
    });

    test('sem duração (o vídeo não abriu) não é fim', () {
      expect(VodEndGuard.isRealEnd(Duration.zero, Duration.zero), isFalse);
    });
  });

  group('ponto guardado', () {
    test('reprodução comum salva normalmente', () {
      final end = VodEndGuard();
      end.hold(null);
      end.hold(Duration.zero);
      expect(end.canSave, isTrue);
      expect(end.interrupted, isFalse);
    });

    test('no corte guarda o ponto e trava o salvamento', () {
      final end = VodEndGuard()..interrupt(s(700));
      expect(end.interrupted, isTrue);
      expect(end.resumeAt, s(700));
      expect(end.canSave, isFalse);
      // Ajustes de posição que chegam depois do corte não soltam o ponto.
      end.reached(s(700.3));
      expect(end.canSave, isFalse);
    });

    test('tentar de novo reabre no ponto e só solta ao chegar nele', () {
      final end = VodEndGuard()..interrupt(s(700));
      // A nova abertura zera a posição do player.
      expect(end.retry(Duration.zero), s(700));
      expect(end.interrupted, isFalse);
      end.reached(Duration.zero);
      end.reached(s(0.4));
      expect(end.canSave, isFalse, reason: 'sair agora não pode gravar 0');
      end.reached(s(699.8));
      expect(end.canSave, isTrue);
      expect(end.resumeAt, isNull);
    });

    test('nova tentativa que falha sem abrir mantém o ponto', () {
      final end = VodEndGuard()..interrupt(s(700));
      end.retry(Duration.zero);
      end.interrupt(Duration.zero);
      expect(end.retry(Duration.zero), s(700));
    });

    test('novo corte antes de chegar ao ponto não o rebaixa', () {
      final end = VodEndGuard()..interrupt(s(700));
      end.retry(Duration.zero);
      end.reached(s(12));
      end.interrupt(s(12));
      expect(end.resumeAt, s(700));
    });

    test('depois de retomar, um corte mais à frente vale o novo ponto', () {
      final end = VodEndGuard()..interrupt(s(700));
      end.retry(Duration.zero);
      end.reached(s(701));
      end.interrupt(s(900));
      expect(end.resumeAt, s(900));
    });

    test('abrir de onde parou protege o ponto se o servidor falhar', () {
      final end = VodEndGuard()..hold(s(3000));
      expect(end.canSave, isFalse);
      end.interrupt(Duration.zero);
      expect(end.resumeAt, s(3000));
    });

    test('erro sem corte: tentar de novo parte da posição atual', () {
      final end = VodEndGuard();
      expect(end.retry(s(80)), s(80));
      expect(end.retry(Duration.zero), s(80));
    });

    test('fim de verdade, outro episódio ou salto do usuário soltam o ponto', () {
      final end = VodEndGuard()..interrupt(s(700));
      end.release();
      expect(end.interrupted, isFalse);
      expect(end.canSave, isTrue);
      expect(end.retry(Duration.zero), Duration.zero);
    });
  });

  group('texto do erro', () {
    test('internet: diz onde parou e que não marcou', () {
      expect(
        vodInterruptedMessage(
          at: s(14),
          duration: movie,
          local: false,
          watched: false,
        ),
        'O servidor parou de enviar o vídeo. Parou em 00:14 de 3:04:50, e esse '
        'ponto foi guardado. O título não foi marcado como assistido.',
      );
    });

    test('não nega a marca feita por estar perto do fim', () {
      final text = vodInterruptedMessage(
        at: s(1250),
        duration: s(1320),
        local: false,
        watched: true,
      );
      expect(text, isNot(contains('marcado')));
    });

    test('arquivo do computador', () {
      final text = vodInterruptedMessage(
        at: s(30),
        duration: s(600),
        local: true,
        watched: false,
      );
      expect(text, startsWith('O arquivo acabou antes da hora'));
    });

    test('sem duração mostra só a causa', () {
      expect(
        vodInterruptedMessage(
          at: s(3000),
          duration: Duration.zero,
          local: false,
          watched: false,
        ),
        'O servidor parou de enviar o vídeo.',
      );
    });
  });
}
