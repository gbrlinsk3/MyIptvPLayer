import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/live_tv/blurred_logo.dart';

/// Sem endereço http não há o que baixar: o widget segue o caminho da cor de
/// reserva, que passa pelo mesmo desenho único e pelo mesmo guardado.
Widget _cards(int count, {Color? fallback, double width = 360}) => MaterialApp(
      home: Wrap(
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(
              width: width,
              height: 180,
              child: BlurredLogo(url: '', sigma: 24, fallback: fallback),
            ),
        ],
      ),
    );

void main() {
  tearDown(BlurredLogo.release);

  testWidgets('desenha uma vez e reaproveita entre cartões iguais',
      (tester) async {
    await tester.pumpWidget(_cards(2, fallback: Colors.grey));

    expect(find.byType(RawImage), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(BlurredLogo.cached, 1);

    // A imagem é 4x menor que a área: sigma 24 na tela vira 6 nela.
    final image = tester.widget<RawImage>(find.byType(RawImage).first).image!;
    expect((image.width, image.height), (90, 46));
  });

  testWidgets('um cartão crescendo só redesenha a cada passo de 8 px',
      (tester) async {
    for (final width in [360.0, 361.0, 362.0, 363.0]) {
      await tester.pumpWidget(
        _cards(1, fallback: Colors.grey, width: width),
      );
    }
    expect(BlurredLogo.cached, 1);
  });

  testWidgets('sem cor de reserva não desenha nada', (tester) async {
    await tester.pumpWidget(_cards(1));

    expect(find.byType(RawImage), findsNothing);
    expect(BlurredLogo.cached, 0);
  });

  testWidgets('a hibernação solta as imagens guardadas', (tester) async {
    await tester.pumpWidget(_cards(1, fallback: Colors.grey));
    await tester.pumpWidget(const SizedBox());

    BlurredLogo.release();

    expect(BlurredLogo.cached, 0);
  });
}
