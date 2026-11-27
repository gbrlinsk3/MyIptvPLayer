import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/profiles/profile_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('o índice de perfis guarda o formato do último perfil usado', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('mip_perfis_');
    addTearDown(() => dir.delete(recursive: true));

    // Índice criado antes desta versão: só a tabela de perfis.
    final antigo = await databaseFactoryFfi.openDatabase(
      '${dir.path}${Platform.pathSeparator}profiles.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE profiles ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
          'avatar TEXT NOT NULL, accent INTEGER NOT NULL, '
          'created_at INTEGER NOT NULL)',
        ),
      ),
    );
    await antigo.insert('profiles', {
      'name': 'Ana',
      'avatar': 'a01',
      'accent': 0xFFC6613F,
      'created_at': 0,
    });
    await antigo.close();

    var store = await ProfileStore.open(directory: dir);
    expect(store.recovered, isFalse);
    expect((await store.list()).single.name, 'Ana');
    expect(await store.appSetting('last_button_shape'), isNull);
    await store.setAppSetting('last_button_shape', 'square');
    await store.setAppSetting('last_button_shape', 'rounded');
    await store.close();

    store = await ProfileStore.open(directory: dir);
    expect(await store.appSetting('last_button_shape'), 'rounded');
    await store.close();
  });
}
