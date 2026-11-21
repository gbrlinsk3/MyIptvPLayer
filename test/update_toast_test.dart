import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/update/app_updater.dart';
import 'package:iptv_player/update/update_info.dart';
import 'package:iptv_player/ui/update/update_toast.dart';

void main() {
  const info = UpdateInfo(version: '9.9.9', url: 'https://x/y.exe', sha256: 'abc');
  final u = AppUpdater.instance;

  Widget host() => const MaterialApp(home: Scaffold(body: UpdateToast()));

  void aviso({UpdateState state = UpdateState.available}) {
    u.available = info;
    u.dismissed = false;
    u.state = state;
  }

  tearDown(() {
    u.available = null;
    u.dismissed = false;
    u.state = UpdateState.idle;
  });

  testWidgets('mostra o pavio e some sozinho depois de 25 s (vira "Depois")', (t) async {
    aviso();
    await t.pumpWidget(host());
    expect(find.text('Nova versão 9.9.9 disponível'), findsOneWidget);
    expect(find.byKey(const ValueKey('swipe-toast-fuse')), findsOneWidget);

    await t.pump(const Duration(seconds: 24));
    expect(u.dismissed, isFalse);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(u.dismissed, isTrue);
    expect(find.text('Nova versão 9.9.9 disponível'), findsNothing);
  });

  testWidgets('arrastar para baixo dispensa', (t) async {
    aviso();
    await t.pumpWidget(host());
    await t.drag(find.text('Nova versão 9.9.9 disponível'), const Offset(0, 140));
    await t.pumpAndSettle();
    expect(u.dismissed, isTrue);
  });

  testWidgets('baixando: o tempo para e arrastar não dispensa', (t) async {
    aviso(state: UpdateState.downloading);
    await t.pumpWidget(host());
    await t.pump(const Duration(seconds: 40));
    expect(u.dismissed, isFalse);
    await t.drag(find.text('Nova versão 9.9.9 disponível'), const Offset(0, 140));
    // A barra de progresso indeterminada anima para sempre: não usa pumpAndSettle.
    await t.pump(const Duration(seconds: 1));
    expect(u.dismissed, isFalse);
    expect(find.text('Nova versão 9.9.9 disponível'), findsOneWidget);
  });
}
