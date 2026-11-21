import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Texto "digitado" caractere por caractere, com cursor piscando (inspirado no
/// TextType do React Bits).
///
/// Digita uma vez ao montar; [playKey] diferente (comparado com `==`) reinicia.
/// Depois de terminar, o cursor continua piscando por [hideCursorAfter] e some
/// (`null` = pisca sempre). O espaço do texto completo (com o cursor) é
/// reservado desde o início, então o layout não pula enquanto digita; os
/// caracteres ainda não digitados ficam transparentes para a quebra de linha
/// ser a final. Com `MediaQuery.disableAnimations` mostra o texto completo, sem
/// cursor, no primeiro frame.
class TextType extends StatefulWidget {
  const TextType({
    super.key,
    required this.text,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 45),
    this.startDelay = Duration.zero,
    this.showCursor = true,
    this.cursorChar = '|',
    this.cursorBlink = const Duration(milliseconds: 530),
    this.hideCursorAfter = const Duration(milliseconds: 1500),
    this.playKey,
    this.onComplete,
  });

  final String text;
  final TextStyle? style;

  /// Tempo entre um caractere e o seguinte.
  final Duration typingSpeed;

  /// Espera antes do primeiro caractere.
  final Duration startDelay;

  final bool showCursor;
  final String cursorChar;

  /// Meio ciclo do cursor (aceso ou apagado).
  final Duration cursorBlink;

  /// Quanto o cursor continua depois de terminar de digitar. `null` = pisca sempre.
  final Duration? hideCursorAfter;

  /// Quando muda (comparado com `==`), digita de novo.
  final Object? playKey;

  /// Chamado uma vez ao terminar de digitar (também com animações desligadas).
  final VoidCallback? onComplete;

  @override
  State<TextType> createState() => _TextTypeState();
}

class _TextTypeState extends State<TextType> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  bool _semAnimacao = false;
  bool _inicializado = false;
  bool _completou = false;

  int _digitados = 0;
  bool _cursorAceso = true;

  List<String> get _chars => widget.text.characters.toList();

  void _reiniciar() {
    _ticker.stop();
    _completou = false;
    final total = _chars.length;
    if (_semAnimacao || total == 0) {
      _digitados = total;
      _cursorAceso = false;
      _completou = true;
      _avisarTermino();
      return;
    }
    _digitados = 0;
    _cursorAceso = true;
    _ticker.start();
  }

  void _avisarTermino() {
    final cb = widget.onComplete;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
  }

  void _tick(Duration decorrido) {
    final total = _chars.length;
    final passo = widget.typingSpeed.inMicroseconds;
    final us = decorrido.inMicroseconds - widget.startDelay.inMicroseconds;
    var digitados = 0;
    var aceso = true;
    var terminou = false;
    if (us > 0) {
      digitados = passo <= 0 ? total : (us ~/ passo).clamp(0, total);
    }
    if (digitados >= total) {
      digitados = total;
      final fimUs = widget.startDelay.inMicroseconds + passo * total;
      final apos = decorrido.inMicroseconds - fimUs;
      final meio = widget.cursorBlink.inMicroseconds;
      aceso = meio <= 0 || (apos ~/ meio).isEven;
      final esconder = widget.hideCursorAfter;
      if (esconder != null && apos >= esconder.inMicroseconds) {
        aceso = false;
        terminou = true;
      }
      if (!_completou) {
        _completou = true;
        _avisarTermino();
      }
    }
    if (!widget.showCursor) {
      aceso = false;
      terminou = digitados >= total;
    }
    if (digitados != _digitados || aceso != _cursorAceso) {
      setState(() {
        _digitados = digitados;
        _cursorAceso = aceso;
      });
    }
    if (terminou) _ticker.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sem = MediaQuery.disableAnimationsOf(context);
    if (!_inicializado) {
      _inicializado = true;
      _semAnimacao = sem;
      _reiniciar();
    } else if (sem != _semAnimacao) {
      _semAnimacao = sem;
      if (sem) {
        _ticker.stop();
        _digitados = _chars.length;
        _cursorAceso = false;
        if (!_completou) {
          _completou = true;
          _avisarTermino();
        }
      }
    }
  }

  @override
  void didUpdateWidget(TextType old) {
    super.didUpdateWidget(old);
    if (widget.playKey != old.playKey) {
      _reiniciar();
    } else if (widget.text != old.text) {
      final total = _chars.length;
      if (_digitados > total) _digitados = total;
      if (!_ticker.isActive && _digitados < total && !_semAnimacao) _reiniciar();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = _chars;
    final n = _digitados.clamp(0, chars.length);
    final digitado = chars.take(n).join();
    final resto = chars.skip(n).join();
    final cursor = widget.showCursor ? widget.cursorChar : '';
    const invisivel = TextStyle(color: Colors.transparent);

    final reserva = Text.rich(
      TextSpan(children: [TextSpan(text: widget.text), TextSpan(text: cursor)]),
      style: widget.style,
    );
    final visivel = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: digitado),
          TextSpan(text: cursor, style: _cursorAceso ? null : invisivel),
          TextSpan(text: resto, style: invisivel),
        ],
      ),
      style: widget.style,
    );
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: Stack(
        children: [
          Opacity(opacity: 0, child: reserva),
          Positioned.fill(child: visivel),
        ],
      ),
    );
  }
}
