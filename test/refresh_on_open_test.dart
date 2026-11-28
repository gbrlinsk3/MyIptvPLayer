import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db.dart';
import 'package:iptv_player/data/models.dart';
import 'package:iptv_player/epg/epg_controller.dart';
import 'package:iptv_player/playback/playback_controller.dart';
import 'package:iptv_player/state/app_controller.dart';

class _SemPlayer implements PlaybackController {
  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Ao abrir o perfil, os canais salvos aparecem na hora e a lista é atualizada
/// em seguida; uma resposta ruim do servidor não apaga o que já está no PC.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Os testes usam um servidor Xtream falso em localhost.
  HttpOverrides.global = null;

  late Directory pasta;
  late HttpServer servidor;
  late FutureOr<Object?> Function(String? acao, String? usuario) responder;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('mip_refresh');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => pasta.path,
        );
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((pedido) async {
      final acao = pedido.uri.queryParameters['action'];
      final corpo = acao == null
          ? {
              'user_info': {'auth': 1},
            }
          : await responder(acao, pedido.uri.queryParameters['username']);
      pedido.response.headers.contentType = ContentType.json;
      pedido.response.write(jsonEncode(corpo));
      await pedido.response.close();
    });
  });

  tearDown(() async {
    await servidor.close(force: true);
  });

  Future<(AppDatabase, AppController)> abrirPerfil() async {
    final db = await AppDatabase.open('${pasta.path}/perfil.db');
    await db.saveAccount(
      SavedAccount(
        server: 'http://127.0.0.1:${servidor.port}',
        username: 'u',
        password: 's',
      ),
    );
    await db.replaceCatalog(
      const [LiveCategory(id: '1', name: 'Antiga')],
      [LiveChannel(streamId: 10, name: 'Canal salvo', categoryId: '1')],
    );
    final app = AppController(db, _SemPlayer(), EpgController(db));
    return (db, app);
  }

  Future<void> esperar(AppController app) async {
    for (var i = 0; i < 200 && app.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(app.syncing, isFalse);
  }

  test('abre com os canais salvos e atualiza a lista em seguida', () async {
    responder = (acao, _) => acao == 'get_live_categories'
        ? [
            {'category_id': '2', 'category_name': 'Nova'},
          ]
        : [
            {'stream_id': 20, 'name': 'Canal novo', 'category_id': '2'},
          ];
    final (_, app) = await abrirPerfil();

    await app.init();
    expect(app.allChannels.single.name, 'Canal salvo');
    expect(app.syncing, isTrue, reason: 'a atualização começa sozinha');

    await esperar(app);
    expect(app.syncError, isNull);
    expect(app.allChannels.single.name, 'Canal novo');
    expect(app.categories.single.name, 'Nova');
    app.dispose();
  });

  test('lista vazia ou inválida mantém os canais salvos', () async {
    responder = (_, _) => {'erro': 'sessão expirada'};
    final (db, app) = await abrirPerfil();

    await app.init();
    await esperar(app);

    expect(app.syncError, contains('lista anterior foi mantida'));
    expect(app.allChannels.single.name, 'Canal salvo');
    expect((await db.loadChannels()).single.name, 'Canal salvo');
    app.dispose();
  });

  test('conta trocada no meio do download não recebe a lista antiga', () async {
    final segura = Completer<void>();
    responder = (acao, usuario) async {
      if (usuario == 'u') await segura.future;
      return acao == 'get_live_categories'
          ? [
              {'category_id': '2', 'category_name': 'De $usuario'},
            ]
          : [
              {
                'stream_id': 20,
                'name': 'Canal de $usuario',
                'category_id': '2',
              },
            ];
    };
    final (db, app) = await abrirPerfil();
    await app.init();

    final erro = await app.login(
      server: app.account!.server,
      username: 'outro',
      password: 's',
    );
    expect(erro, isNull);
    segura.complete();
    for (var i = 0; i < 200 && app.allChannels.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await esperar(app);

    expect(app.allChannels.single.name, 'Canal de outro');
    expect((await db.loadChannels()).single.name, 'Canal de outro');
    app.dispose();
  });

  test('troca de servidor mantém as categorias favoritas e a ordem', () async {
    // A conta nova tem as mesmas categorias com outros ids.
    responder = (acao, usuario) {
      final base = usuario == 'u' ? 0 : 10;
      if (acao == 'get_live_categories') {
        return [
          for (final (i, nome) in ['A', 'B', 'C'].indexed)
            {'category_id': '${base + i + 1}', 'category_name': nome},
        ];
      }
      if (acao == 'get_live_streams') {
        return [
          for (var i = 1; i <= 3; i++)
            {
              'stream_id': base + i,
              'name': 'Canal $i',
              'category_id': '${base + i}',
            },
        ];
      }
      return const [];
    };
    final (_, app) = await abrirPerfil();
    await app.init();
    await esperar(app);
    await app.toggleFavoriteCategory('2');
    await app.moveCategory('3', '1');
    expect([for (final c in app.drawerCategories) c.name], ['B', 'C', 'A']);

    Future<void> trocar(String usuario, {required bool manter}) async {
      expect(
        await app.login(
          server: app.account!.server,
          username: usuario,
          password: 's',
          keepData: manter,
        ),
        isNull,
      );
      for (var i = 0; i < 200 && app.allChannels.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await esperar(app);
    }

    await trocar('outro', manter: true);
    expect(app.favoriteCategories, {'12'});
    expect([for (final c in app.drawerCategories) c.name], ['B', 'C', 'A']);
    expect(app.isCategoryOpen('12'), isTrue);

    await trocar('terceiro', manter: false);
    expect(app.favoriteCategories, isEmpty);
    expect([for (final c in app.drawerCategories) c.name], ['A', 'B', 'C']);
    app.dispose();
  });

  test('servidor fora do ar mantém os canais salvos', () async {
    responder = (_, _) => const [];
    final (_, app) = await abrirPerfil();
    await servidor.close(force: true);

    await app.init();
    await esperar(app);

    expect(app.syncError, isNotNull);
    expect(app.allChannels.single.name, 'Canal salvo');
    app.dispose();
  });
}
