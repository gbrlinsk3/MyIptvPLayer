import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/animated_content.dart';
import 'package:iptv_player/ui/widgets/shiny_text.dart';
import 'package:iptv_player/ui/widgets/split_text.dart';
import 'package:iptv_player/ui/widgets/text_type.dart';

Widget _app(Widget child, {bool semAnimacao = false, double largura = 600}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: semAnimacao),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: largura, child: child),
        ),
      ),
    ),
  );
}

const _estilo = TextStyle(fontSize: 24, color: Colors.black);

void main() {
  group('SplitText', () {
    testWidgets('termina mostrando o texto, com o mesmo tamanho de um Text igual', (t) async {
      await t.pumpWidget(_app(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SplitText(text: 'Filmes e séries', style: _estilo, maxLines: 1),
          Text('Filmes e séries', style: _estilo, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      )));
      final split = find.byType(SplitText);
      final tamanhoDuranteAnimacao = t.getSize(split);
      await t.pump(const Duration(milliseconds: 200));
      expect(t.getSize(split), tamanhoDuranteAnimacao);
      await t.pumpAndSettle();
      expect(find.text('Filmes e séries'), findsNWidgets(2));
      expect(t.getSize(split), t.getSize(find.byType(Text).last));
      expect(t.getSize(split), tamanhoDuranteAnimacao);
    });

    testWidgets('com revealId num RevealScope toca só na primeira vez do id', (t) async {
      Widget build({required bool mostrar, Object id = 'a'}) => _app(RevealScope(
            child: mostrar ? SplitText(text: 'Olá', style: _estilo, revealId: id) : const SizedBox(),
          ));
      await t.pumpWidget(build(mostrar: true));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();

      // Remonta com o mesmo id: já nasce pronto.
      await t.pumpWidget(build(mostrar: false));
      await t.pumpWidget(build(mostrar: true));
      expect(t.hasRunningAnimations, isFalse);
      expect(find.text('Olá'), findsOneWidget);

      // Outro id anima.
      await t.pumpWidget(build(mostrar: false));
      await t.pumpWidget(build(mostrar: true, id: 'b'));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
    });

    testWidgets('playKey diferente toca de novo', (t) async {
      Widget build(int k) => _app(SplitText(text: 'Olá', style: _estilo, playKey: k));
      await t.pumpWidget(build(1));
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
      await t.pumpWidget(build(2));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      expect(find.text('Olá'), findsOneWidget);
    });

    testWidgets('texto que não cabe não estoura nem muda de tamanho', (t) async {
      await t.pumpWidget(_app(
        const SplitText(text: 'Um título bem comprido que não cabe numa linha só', style: _estilo, maxLines: 1),
        largura: 200,
      ));
      final inicial = t.getSize(find.byType(SplitText));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.getSize(find.byType(SplitText)), inicial);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(SplitText)), inicial);
    });

    testWidgets('disableAnimations mostra o final no primeiro frame', (t) async {
      await t.pumpWidget(_app(const SplitText(text: 'Olá', style: _estilo), semAnimacao: true));
      expect(find.text('Olá'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('TextType', () {
    testWidgets('chega ao texto completo e chama onComplete', (t) async {
      var completou = 0;
      await t.pumpWidget(_app(TextType(
        text: 'Olá, mundo',
        style: _estilo,
        onComplete: () => completou++,
      )));
      final tamanho = t.getSize(find.byType(TextType));
      // No começo ainda não digitou nada visível.
      expect(_visivel(t), isNot(contains('Olá')));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.getSize(find.byType(TextType)), tamanho);
      expect(completou, 0);
      await t.pump(const Duration(milliseconds: 600));
      expect(_visivel(t), startsWith('Olá, mundo'));
      expect(completou, 1);
      // O cursor some depois de hideCursorAfter e o ticker para.
      await t.pump(const Duration(milliseconds: 2000));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isFalse);
      expect(completou, 1);
      expect(t.getSize(find.byType(TextType)), tamanho);
    });

    testWidgets('playKey reinicia a digitação', (t) async {
      Widget build(int k) => _app(TextType(text: 'abc', style: _estilo, playKey: k, hideCursorAfter: Duration.zero));
      await t.pumpWidget(build(1));
      await t.pump(const Duration(milliseconds: 1));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 50));
      expect(_visivel(t), startsWith('abc'));
      await t.pumpWidget(build(2));
      await t.pump(const Duration(milliseconds: 1));
      expect(_visivel(t), isNot(startsWith('abc')));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 50));
      expect(_visivel(t), startsWith('abc'));
    });

    testWidgets('hideCursorAfter nulo continua piscando', (t) async {
      await t.pumpWidget(_app(TextType(text: 'a', style: _estilo, hideCursorAfter: null)));
      await t.pump(const Duration(milliseconds: 1));
      await t.pump(const Duration(seconds: 5));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpWidget(const SizedBox()); // desmonta: o ticker é liberado
    });

    testWidgets('disableAnimations mostra o texto completo no primeiro frame e avisa o fim', (t) async {
      var completou = 0;
      await t.pumpWidget(_app(
        TextType(text: 'Olá, mundo', style: _estilo, onComplete: () => completou++),
        semAnimacao: true,
      ));
      expect(_visivel(t), startsWith('Olá, mundo'));
      expect(t.hasRunningAnimations, isFalse);
      await t.pump();
      expect(completou, 1);
    });
  });

  group('ShinyText', () {
    testWidgets('active true anima e active false para o ticker', (t) async {
      Widget build(bool ativo) => _app(ShinyText(text: 'Atualizar', style: _estilo, active: ativo));
      await t.pumpWidget(build(true));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpWidget(build(false));
      await t.pump();
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Atualizar'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(build(true));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.hasRunningAnimations, isTrue);
    });

    testWidgets('disableAnimations deixa o texto normal', (t) async {
      await t.pumpWidget(_app(const ShinyText(text: 'Atualizar', style: _estilo), semAnimacao: true));
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Atualizar'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('respeita maxLines e overflow', (t) async {
      await t.pumpWidget(_app(
        const ShinyText(
          text: 'Um texto bem comprido que não cabe',
          style: _estilo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        largura: 150,
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(ShinyText)).height, lessThan(40));
    });
  });
}

/// Texto que o usuário vê agora: só os trechos não transparentes do Text.rich
/// visível (o último Text da árvore do TextType).
String _visivel(WidgetTester t) {
  final texto = t.widgetList<RichText>(find.descendant(of: find.byType(TextType), matching: find.byType(RichText))).last;
  final buf = StringBuffer();
  texto.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      final cor = span.style?.color;
      if (cor != Colors.transparent) buf.write(span.text);
    }
    return true;
  });
  return buf.toString();
}
