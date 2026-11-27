import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_log.dart';

/// Modo hibernar.
///
/// **Minimizado, o app para de desenhar na hora.** O `window_manager` segura a
/// mensagem de minimizar do Windows e o Flutter não fica sabendo, então quem
/// avisa que a janela está escondida é esta classe. Som, gravação, downloads e
/// temporizadores continuam.
///
/// **Passado [delay] sem nada tocando nem gravando**, [asleep] fica verdadeiro
/// para a interface soltar o que ocupa memória. Ao voltar, fica falso.
class Hibernator with WindowListener, WidgetsBindingObserver {
  Hibernator({
    required this.busy,
    this.delay = const Duration(minutes: 2),
    this.retry = const Duration(seconds: 15),
  });

  /// Algo que não pode ser interrompido (TV tocando, gravação).
  final bool Function() busy;

  /// Quanto tempo minimizado até hibernar.
  final Duration delay;

  /// Com algo tocando na hora de hibernar, tenta de novo neste intervalo.
  final Duration retry;

  static final ValueNotifier<bool> asleep = ValueNotifier(false);

  /// Outros players abertos (ex.: o de filmes e séries): cada um diz se está
  /// tocando. Quem registra tira ao fechar.
  static final Set<bool Function()> holds = {};

  bool _minimized = false;
  Timer? _timer;

  void attach() {
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    _timer?.cancel();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    asleep.value = false;
  }

  @override
  void onWindowMinimize() => minimized();

  // Voltar de minimizado chega como "restaurar" ou, se a janela estava
  // maximizada, como "maximizar"; o foco cobre o resto.
  @override
  void onWindowRestore() => restored();

  @override
  void onWindowMaximize() => restored();

  @override
  void onWindowFocus() => restored();

  void minimized() {
    if (_minimized) return;
    _minimized = true;
    _tell(AppLifecycleState.hidden);
    _timer = Timer(delay, _trySleep);
  }

  void restored() {
    if (!_minimized) return;
    _minimized = false;
    _timer?.cancel();
    _tell(AppLifecycleState.resumed);
    asleep.value = false;
  }

  void _trySleep() {
    if (!_minimized) return;
    if (busy() || holds.any((playing) => playing())) {
      _timer = Timer(retry, _trySleep);
      return;
    }
    asleep.value = true;
  }

  /// A perda de foco que o Flutter recebe do Windows pode chegar depois e
  /// religar o desenho: enquanto minimizado, volta a avisar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_minimized &&
        (state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive)) {
      _tell(AppLifecycleState.hidden);
    }
  }

  /// Mesmo canal que o motor do Flutter usa para informar o estado do app.
  static void _tell(AppLifecycleState state) {
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.lifecycle.name,
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
  }
}

/// Memória que dá para devolver depois que a interface soltou as imagens.
abstract final class MemoryRelease {
  /// Teto do cache da placa de vídeo (motor do Flutter) antes de hibernar: o
  /// mesmo cálculo do motor (12 telas), nunca abaixo de uma tela 1080p.
  static int _gpuCacheBytes() {
    var pixels = 1920.0 * 1080;
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      pixels = math.max(
        pixels,
        view.physicalSize.width * view.physicalSize.height,
      );
    }
    return (pixels * 4 * 12).round();
  }

  static int? _restore;

  /// Esvazia os caches de imagem e pede ao Windows as páginas de volta.
  static Future<void> run() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _restore ??= _gpuCacheBytes();
    await _setGpuCache(0);
    // Sem quadros, as texturas descartadas ficam na fila do driver de vídeo:
    // mais dois quadros, com um intervalo, concluem os descartes.
    for (var i = 0; i < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await forceFrame();
    }
    _trimWorkingSet();
  }

  /// Minimizado não há quadros: pede um só. Falso se ele não vier em 3 s.
  static Future<bool> forceFrame() {
    final frame = WidgetsBinding.instance.endOfFrame;
    WidgetsBinding.instance.scheduleForcedFrame();
    return frame
        .then((_) => true)
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
  }

  /// Chamado ao voltar: o cache da placa recupera o tamanho de antes.
  static Future<void> wake() async {
    final bytes = _restore;
    if (bytes == null) return;
    _restore = null;
    await _setGpuCache(bytes);
  }

  static Future<void> _setGpuCache(int bytes) async {
    try {
      await SystemChannels.skia
          .invokeMethod<void>('Skia.setResourceCacheMaxBytes', bytes)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      AppLog.warn('hibernar.placa', e);
    }
  }

  static void _trimWorkingSet() {
    if (!Platform.isWindows) return;
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final currentProcess = kernel.lookupFunction<IntPtr Function(),
          int Function()>('GetCurrentProcess');
      final emptyWorkingSet = kernel.lookupFunction<Int32 Function(IntPtr),
          int Function(int)>('K32EmptyWorkingSet');
      emptyWorkingSet(currentProcess());
    } catch (e) {
      AppLog.warn('hibernar.memoria', e);
    }
  }
}
