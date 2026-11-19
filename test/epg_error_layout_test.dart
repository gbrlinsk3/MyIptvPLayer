import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/ui/live_tv/epg_panel.dart';

/// O erro do guia precisa caber na altura do corpo do painel expandido
/// (141 px) sem overflow, mesmo com mensagem técnica longa. 400 px é o pior
/// caso de largura; 853 px é a janela de 1280 px com a interface em 150 %.
void main() {
  final erroLongo = 'Falha ao consultar a fonte de EPG: ${'x' * 200}';

  Widget app({required double width, VoidCallback? onRetry}) {
    return MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.0),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 141,
            child: EpgErrorView(error: erroLongo, onRetry: onRetry),
          ),
        ),
      ),
    );
  }

  for (final width in [400.0, 853.0]) {
    testWidgets('EpgErrorView sem overflow com largura $width', (tester) async {
      await tester.pumpWidget(app(width: width, onRetry: () {}));
      expect(tester.takeException(), isNull);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  }

  testWidgets('sem onRetry não mostra o botão e continua sem overflow',
      (tester) async {
    await tester.pumpWidget(app(width: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Tentar de novo'), findsNothing);
  });
}
