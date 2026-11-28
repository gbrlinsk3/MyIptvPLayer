import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/shell/lazy_pages.dart';
import 'package:iptv_player/ui/widgets/animated_content.dart';
import 'package:iptv_player/ui/widgets/split_text.dart';

class _Pagina extends StatefulWidget {
  const _Pagina(this.vida);

  final List<String> vida;

  @override
  State<_Pagina> createState() => _PaginaState();
}

class _PaginaState extends State<_Pagina> {
  @override
  void initState() {
    super.initState();
    widget.vida.add('montou');
  }

  @override
  void dispose() {
    widget.vida.add('saiu');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SplitText(text: 'Categoria', revealId: 'categoria');
}

/// Página pré-carregada na abertura: montada escondida, sai sozinha e não gasta
/// as entradas animadas da primeira abertura.
void main() {
  late List<String> vida;

  Widget app(int aba, {ValueNotifier<bool>? segura}) => MaterialApp(
    home: RevealScope(
      child: LazyPages(
        index: aba,
        warm: const {1},
        warmHold: segura,
        revealFirstOpen: const {1},
        builders: [(_) => const SizedBox(), (_) => _Pagina(vida)],
      ),
    ),
  );

  setUp(() => vida = []);

  testWidgets('monta escondida depois da abertura e sai sozinha', (
    tester,
  ) async {
    await tester.pumpWidget(app(0));
    expect(vida, isEmpty, reason: 'o primeiro quadro é da página aberta');

    await tester.pump(LazyPages.warmDelay);
    await tester.pump();
    expect(vida, ['montou']);
    expect(find.byType(_Pagina), findsNothing, reason: 'fora da tela');
    expect(find.byType(_Pagina, skipOffstage: false), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(vida, ['montou', 'saiu']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('aberta em seguida, entra como na primeira vez', (tester) async {
    await tester.pumpWidget(app(0));
    await tester.pump(LazyPages.warmDelay);
    await tester.pump();

    await tester.pumpWidget(app(1));
    expect(vida.where((e) => e == 'montou'), hasLength(2));
    expect(find.byType(_Pagina), findsOneWidget);
    // A entrada da primeira abertura continua guardada para agora.
    final entrada = tester.widget<AnimatedContent>(
      find.byType(AnimatedContent),
    );
    expect(entrada.duration, greaterThan(Duration.zero));
    final escopo = RevealScope.maybeOf(tester.element(find.byType(_Pagina)))!;
    expect(escopo.jaRevelado('categoria'), isTrue);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(_Pagina), findsOneWidget, reason: 'aberta não sai');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('espera a animação de abertura sair para montar', (tester) async {
    final abertura = ValueNotifier(true);
    await tester.pumpWidget(app(0, segura: abertura));
    await tester.pump(const Duration(seconds: 5));
    expect(vida, isEmpty, reason: 'a abertura ainda está na tela');

    abertura.value = false;
    await tester.pump();
    expect(vida, isEmpty, reason: 'a espera conta a partir daqui');
    await tester.pump(LazyPages.warmDelay);
    await tester.pump();
    expect(vida, ['montou']);

    // Uma vez só: voltar a segurar e liberar não monta de novo.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    abertura.value = true;
    abertura.value = false;
    await tester.pump(const Duration(seconds: 2));
    expect(vida, ['montou', 'saiu']);
    await tester.pumpWidget(const SizedBox());
    abertura.dispose();
  });

  testWidgets('escondida não gasta a revelação do título', (tester) async {
    await tester.pumpWidget(app(0));
    await tester.pump(LazyPages.warmDelay);
    await tester.pump();
    final escopo = RevealScope.maybeOf(
      tester.element(find.byType(_Pagina, skipOffstage: false)),
    )!;
    expect(escopo.jaRevelado('categoria'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
