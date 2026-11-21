import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/channel_groups.dart';
import 'package:iptv_player/data/models.dart';

void main() {
  var nextId = 1;
  LiveChannel canal(String nome, {String? icon}) => LiveChannel(
        streamId: nextId++,
        name: nome,
        categoryId: '1',
        icon: icon,
      );

  group('parseChannelName', () {
    test('tira marcas finais e entre colchetes', () {
      final p = parseChannelName('A&E FHD [ALT]');
      expect(p.base, 'A&E');
      expect(p.tags, ['FHD', 'ALT']);
      expect(p.key, 'A&E');
      expect(p.label, 'FHD [ALT]');
      expect(p.alt, isTrue);
      expect(p.rank, 10);
    });

    test('marca simples no fim', () {
      expect(parseChannelName('BAND NEWS HD').base, 'BAND NEWS');
      expect(parseChannelName('Globo SP HD').base, 'Globo SP');
    });

    test('o número do nome fica', () {
      final p = parseChannelName('SPORTV 2 FHD');
      expect(p.base, 'SPORTV 2');
      expect(p.tags, ['FHD']);
    });

    test('marca no início não sai', () {
      final p = parseChannelName('HD Channel');
      expect(p.base, 'HD Channel');
      expect(p.tags, isEmpty);
    });

    test('sem marcas', () {
      final p = parseChannelName('ESPN');
      expect(p.base, 'ESPN');
      expect(p.tags, isEmpty);
      expect(p.label, 'Padrão');
      expect(p.alt, isFalse);
      expect(p.rank, 2);
    });

    test('separador antes da marca é removido', () {
      final p = parseChannelName('Canal | FHD');
      expect(p.base, 'Canal');
      expect(p.tags, ['FHD']);
    });

    test('só ALT vira Padrão [ALT]', () {
      final p = parseChannelName('Canal [ALT]');
      expect(p.label, 'Padrão [ALT]');
      expect(p.rank, 12);
    });

    test('marca entre parênteses no meio do nome', () {
      final p = parseChannelName('Canal (HD) Brasil');
      expect(p.base, 'Canal Brasil');
      expect(p.tags, ['HD']);
    });

    test('colchete que não é marca fica', () {
      expect(parseChannelName('Canal [SP]').base, 'Canal [SP]');
    });

    test('várias marcas finais, sem diferenciar maiúsculas', () {
      final p = parseChannelName('Filmes full hd hevc');
      expect(p.base, 'Filmes');
      expect(p.tags, ['FULL HD', 'HEVC']);
      expect(p.rank, 0);
    });

    test('qualidade pelo rank', () {
      expect(parseChannelName('X FHD').rank, 0);
      expect(parseChannelName('X 1080p').rank, 0);
      expect(parseChannelName('X HD').rank, 1);
      expect(parseChannelName('X').rank, 2);
      expect(parseChannelName('X HEVC').rank, 2);
      expect(parseChannelName('X 4K').rank, 3);
      expect(parseChannelName('X UHD').rank, 3);
      expect(parseChannelName('X SD').rank, 4);
      expect(parseChannelName('X HD [ALT]').rank, 11);
    });

    test('sobrescritos ² e ³', () {
      final p = parseChannelName('Premiere ²');
      expect(p.base, 'Premiere');
      expect(p.tags, ['²']);
    });

    test('a chave ignora maiúsculas e espaços duplicados', () {
      expect(parseChannelName('Globo  Sp HD').key, 'GLOBO SP');
    });
  });

  group('groupChannels', () {
    test('A&E em um grupo só, ordenado', () {
      final g = groupChannels([
        canal('A&E FHD'),
        canal('A&E FHD [ALT]'),
        canal('A&E HD'),
        canal('A&E HD [ALT]'),
      ]);
      expect(g, hasLength(1));
      expect(g.single.displayName, 'A&E');
      expect(
        [for (final v in g.single.versions) g.single.labelOf(v)],
        ['FHD', 'HD', 'FHD [ALT]', 'HD [ALT]'],
      );
      expect(g.single.primary.name, 'A&E FHD');
    });

    test('ordem FHD, HD, Padrão, 4K, SD', () {
      final g = groupChannels([
        canal('Globo SD'),
        canal('Globo 4K'),
        canal('Globo HD'),
        canal('Globo FHD'),
        canal('Globo'),
      ]);
      expect(g, hasLength(1));
      expect(
        [for (final v in g.single.versions) g.single.labelOf(v)],
        ['FHD', 'HD', 'Padrão', '4K', 'SD'],
      );
    });

    test('empate mantém a ordem original', () {
      final g = groupChannels([
        canal('Rede HD'),
        canal('Rede 720p'),
        canal('Rede HD HEVC'),
      ]);
      expect([for (final v in g.single.versions) v.name],
          ['Rede HD', 'Rede 720p', 'Rede HD HEVC']);
    });

    test('SporTV HD e SporTV 2 HD são grupos diferentes', () {
      final g = groupChannels([canal('SporTV HD'), canal('SporTV 2 HD')]);
      expect(g, hasLength(2));
      expect(g[0].displayName, 'SporTV');
      expect(g[1].displayName, 'SporTV 2');
    });

    test('grupos na ordem da primeira aparição e displayName original', () {
      final g = groupChannels([
        canal('Zeta HD'),
        canal('Alfa FHD'),
        canal('ZETA FHD'),
      ]);
      expect([for (final x in g) x.displayName], ['Zeta', 'Alfa']);
      expect(g.first.versions, hasLength(2));
      expect(g.first.primary.name, 'ZETA FHD');
    });

    test('streamId repetido é ignorado', () {
      final a = LiveChannel(streamId: 99, name: 'Canal HD', categoryId: '1');
      final b = LiveChannel(streamId: 99, name: 'Canal HD', categoryId: '1');
      final g = groupChannels([a, b]);
      expect(g.single.versions, hasLength(1));
    });

    test('icon: primeiro não vazio', () {
      final g = groupChannels([
        canal('Canal FHD', icon: ''),
        canal('Canal HD', icon: 'http://x/logo.png'),
        canal('Canal SD'),
      ]);
      expect(g.single.icon, 'http://x/logo.png');
      expect(groupChannels([canal('Sem logo')]).single.icon, isNull);
    });

    test('contains e pick', () {
      final fhd = canal('Canal FHD');
      final hd = canal('Canal HD');
      final sd = canal('Canal SD');
      final outro = canal('Outro HD');
      final grupo = groupChannels([sd, hd, fhd]).single;
      expect(grupo.contains(hd.streamId), isTrue);
      expect(grupo.contains(outro.streamId), isFalse);
      expect(grupo.pick(sd.streamId), same(sd));
      expect(grupo.pick(outro.streamId), same(fhd));
      expect(grupo.pick(null), same(fhd));
      expect(grupo.primary, same(fhd));
    });
  });
}
