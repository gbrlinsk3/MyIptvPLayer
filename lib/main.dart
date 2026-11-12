import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_info.dart';
import 'core/app_log.dart';
import 'core/theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  // Erros do Flutter, da plataforma e de código assíncrono sem tratamento
  // passam a ser registrados em arquivo.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.error('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('plataforma', error, stack);
    return true;
  };
  MediaKit.ensureInitialized();
  // Limita a memória de imagens decodificadas (as menos usadas saem sozinhas).
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 96 << 20
    ..maximumSize = 400;

  // Barra de título do Windows oculta; a interface desenha a própria.
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1000, 620),
    center: true,
    title: AppInfo.name,
    backgroundColor: AppColors.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const IptvApp());
}
