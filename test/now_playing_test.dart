import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/channel_groups.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/epg/now_playing.dart';
import 'package:iptv_player/ui/live_tv/channel_group_card.dart';
import 'package:iptv_player/ui/live_tv/now_playing_builder.dart';
import 'package:iptv_player/ui/widgets/full_name_tooltip.dart';

void main() {
  const conta = SavedAccount(server: 's', username: 'u', password: 'p');
  var agora = DateTime(2026, 1, 1, 20);
  int epoch() => agora.millisecondsSinceEpoch ~/ 1000;

  EpgProgram programa(String titulo, {int de = -600, int ate = 600}) =>
      EpgProgram(start: epoch() + de, stop: epoch() + ate, title: titulo);

  LiveChannel canal(int id, {String? epg = 'x.br'}) => LiveChannel(
    streamId: id,
    name: 'Canal $id',
    categoryId: '1',
    epgId: epg,
  );

  late List<int> pedidos;
  late List<EpgProgram> doUsuario;
  late ProviderEpgCache salvo;
  late bool preferir;
  Object? falha;

  setUp(() {
    agora = DateTime(2026, 1, 1, 20);
    pedidos = [];
    doUsuario = const [];
    salvo = (rows: const [], fresh: false);
    preferir = false;
    falha = null;
  });

  NowPlaying novo() => NowPlaying(
    userPrograms: (_) async => doUsuario,
    cached: (_) async => salvo,
    fetch: (c, _) async {
      pedidos.add(c.streamId);
      if (falha != null) throw falha!;
      return [programa('Do provedor')];
    },
    preferUser: () => preferir,
    clock: () => agora,
  );

  testWidgets('mostra o do usuário e troca pelo do provedor quando chega', (
    tester,
  ) async {
    doUsuario = [programa('Do usuário')];
    final fonte = novo();
    final e = fonte.watch([canal(1)], conta);
    await tester.pump();
    expect(e.program?.title, 'Do usuário');
    expect(pedidos, isEmpty); // espera o cartão continuar na tela
    await tester.pump(const Duration(seconds: 1));
    expect(pedidos, [1]);
    expect(e.program?.title, 'Do provedor');
    fonte.release(e);
    fonte.dispose();
  });

  testWidgets('preferindo o usuário com programa, não pede ao provedor', (
    tester,
  ) async {
    doUsuario = [programa('Do usuário')];
    preferir = true;
    final fonte = novo();
    final e = fonte.watch([canal(1)], conta);
    await tester.pump(const Duration(seconds: 1));
    expect(e.program?.title, 'Do usuário');
    expect(pedidos, isEmpty);
    fonte.release(e);
    fonte.dispose();
  });

  testWidgets('sem código de EPG, guardado ainda válido ou cartão que saiu: '
      'nenhum pedido', (tester) async {
    final fonte = novo();
    final semCodigo = fonte.watch([canal(1, epg: null)], conta);
    final rapido = fonte.watch([canal(2)], conta);
    await tester.pump();
    fonte.release(rapido);
    await tester.pump(const Duration(seconds: 1));
    salvo = (rows: [programa('Guardado')], fresh: true);
    final guardado = fonte.watch([canal(3)], conta);
    await tester.pump(const Duration(seconds: 1));
    expect(guardado.program?.title, 'Guardado');
    expect(pedidos, isEmpty);
    fonte.release(semCodigo);
    fonte.release(guardado);
    fonte.dispose();
  });

  testWidgets('depois de 3 falhas seguidas para de pedir', (tester) async {
    falha = Exception('recusado');
    final fonte = novo();
    final entradas = [
      for (var i = 1; i <= 8; i++) fonte.watch([canal(i)], conta),
    ];
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(pedidos.length, lessThanOrEqualTo(4));
    for (final e in entradas) {
      fonte.release(e);
    }
    fonte.dispose();
  });

  testWidgets('programa terminado some do cartão', (tester) async {
    doUsuario = [programa('Curto', ate: 20)];
    preferir = true;
    final fonte = novo();
    final e = fonte.watch([canal(1, epg: null)], conta);
    await tester.pump();
    expect(e.program?.title, 'Curto');
    agora = agora.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 31));
    expect(e.program, isNull);
    fonte.release(e);
    fonte.dispose();
  });

  testWidgets('cartão com programa e 3 etiquetas cabe sem estourar', (
    tester,
  ) async {
    final nome = 'Um canal de nome bem comprido que ocupa muitas linhas ' * 2;
    final g = groupChannels([
      for (final q in ['FHD', 'HD', 'SD'])
        LiveChannel(streamId: q.hashCode, name: '$nome $q', categoryId: '1'),
    ]).single;
    final noAr = EpgProgram(
      start: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 600,
      stop: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
      title: 'Um programa de título também bem comprido para cortar',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChannelGroupCard(group: g, onTap: () {}, program: noAr),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(noAr.title), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('SD'), findsOneWidget);
  });

  testWidgets('cartão inativo (gaveta fechada) não pede programação', (
    tester,
  ) async {
    final fonte = novo();
    Widget cartao({required bool ativo}) => MaterialApp(
      home: NowPlayingBuilder(
        source: fonte,
        versions: [canal(1)],
        account: conta,
        active: ativo,
        builder: (_, p) => Text(p?.title ?? 'sem programa'),
      ),
    );
    await tester.pumpWidget(cartao(ativo: false));
    await tester.pump(const Duration(seconds: 1));
    expect(pedidos, isEmpty);
    await tester.pumpWidget(cartao(ativo: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(pedidos, [1]);
    expect(find.text('Do provedor'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    fonte.dispose();
  });

  testWidgets('dica do nome não desliga a dica de um botão do cartão', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: FullNameTooltip(
            fullName: 'Curto',
            style: TextStyle(fontSize: 14),
            maxLines: 1,
            textWidth: 300,
            child: Tooltip(message: 'Favoritar', child: Icon(Icons.favorite)),
          ),
        ),
      ),
    );
    final dentro = tester.element(find.byIcon(Icons.favorite));
    expect(TooltipVisibility.of(dentro), isTrue);
  });
}
