import '../core/format.dart';

/// Fim de vídeo no player de filmes e séries.
///
/// O aviso de "terminou" do libmpv (`eof-reached`, que o media_kit entrega em
/// `stream.completed`) quer dizer só que **não há mais dados**: ele também chega
/// quando o servidor derruba a conexão no meio do vídeo, sem passar por
/// `stream.error`. Esta classe separa o fim de verdade do corte e, no corte,
/// segura o ponto onde parou para nada gravar por cima dele.
class VodEndGuard {
  static const _maxTolerance = Duration(seconds: 30);
  static const _minTolerance = Duration(seconds: 3);

  /// Folga para considerar que a reprodução voltou ao ponto segurado.
  static const _reachSlack = Duration(seconds: 5);

  /// Distância máxima do fim anunciado para o aviso valer: 30 s; em vídeo curto,
  /// 10% do tempo (nunca menos de 3 s).
  static Duration tolerance(Duration duration) {
    final tenth = duration ~/ 10;
    if (tenth > _maxTolerance) return _maxTolerance;
    return tenth < _minTolerance ? _minTolerance : tenth;
  }

  /// Sem duração (o vídeo nem chegou a abrir) nunca é fim de verdade.
  static bool isRealEnd(Duration position, Duration duration) =>
      duration > Duration.zero && duration - position <= tolerance(duration);

  bool _interrupted = false;
  Duration? _resumeAt;

  /// O vídeo foi cortado e o erro está na tela.
  bool get interrupted => _interrupted;

  /// Ponto a retomar enquanto a reprodução não volta até ele.
  Duration? get resumeAt => _resumeAt;

  /// Falso enquanto salvar a posição atual apagaria o ponto segurado.
  bool get canSave => _resumeAt == null;

  /// Segura [position] até a reprodução chegar nele. Um ponto já segurado tem
  /// prioridade: uma nova tentativa que não chegou lá não o rebaixa.
  void hold(Duration? position) {
    if (position != null && position > Duration.zero) _resumeAt ??= position;
  }

  /// Corte antes do fim, com a reprodução em [position].
  void interrupt(Duration position) {
    _interrupted = true;
    hold(position);
  }

  /// "Tentar de novo": devolve de onde reabrir, a partir da posição atual
  /// [current] se nada estava segurado.
  Duration retry(Duration current) {
    _interrupted = false;
    hold(current);
    return _resumeAt ?? Duration.zero;
  }

  /// Posição informada pelo player: solta o ponto quando a reprodução chega nele.
  void reached(Duration position) {
    final at = _resumeAt;
    if (_interrupted || at == null || position <= Duration.zero) return;
    if (position >= at - _reachSlack) _resumeAt = null;
  }

  /// Fim de verdade, outro episódio ou posição escolhida pelo usuário.
  void release() {
    _interrupted = false;
    _resumeAt = null;
  }
}

/// Texto do erro quando o vídeo para antes do fim. [at] é o ponto guardado,
/// [local] indica arquivo do computador e [watched], que o título já tinha
/// sido marcado como assistido por estar perto do fim.
String vodInterruptedMessage({
  required Duration? at,
  required Duration duration,
  required bool local,
  required bool watched,
}) {
  final cause = local
      ? 'O arquivo acabou antes da hora: ele pode estar incompleto ou com defeito.'
      : 'O servidor parou de enviar o vídeo.';
  if (duration <= Duration.zero) return cause;
  final point = at == null || at <= Duration.zero
      ? ''
      : ' Parou em ${formatDuration(at)} de ${formatDuration(duration)}, '
          'e esse ponto foi guardado.';
  final mark = watched ? '' : ' O título não foi marcado como assistido.';
  return '$cause$point$mark';
}
