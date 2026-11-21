import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/carousel_arrows.dart';

void main() {
  Widget app(ScrollController c, int itens) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 50,
                width: 400,
                child: ListView(
                  controller: c,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < itens; i++)
                      SizedBox(width: 100, child: Text('$i')),
                  ],
                ),
              ),
              CarouselArrow(controller: c, left: false, passo: 100),
            ],
          ),
        ),
      );

  bool habilitada(WidgetTester t) =>
      t.widget<CarouselArrowButton>(find.byType(CarouselArrowButton)).enabled;

  testWidgets('seta direita acompanha mudança de tamanho da lista',
      (t) async {
    final c = ScrollController();
    addTearDown(c.dispose);

    await t.pumpWidget(app(c, 3));
    await t.pump();
    expect(habilitada(t), isFalse);

    await t.pumpWidget(app(c, 10));
    await t.pump();
    expect(habilitada(t), isTrue);

    await t.pumpWidget(app(c, 3));
    await t.pump();
    expect(habilitada(t), isFalse);
  });
}
