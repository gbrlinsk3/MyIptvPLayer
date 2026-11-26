import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/format.dart';
import 'package:iptv_player/ui/account_xtream_card.dart';

void main() {
  test('milhar e singular', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(5419), '5.419');
    expect(formatCount(31458), '31.458');
    expect(formatCount(1234567), '1.234.567');
    expect(plural(1, 'canal', 'canais'), '1 canal');
    expect(plural(0, 'canal', 'canais'), '0 canais');
    expect(plural(1645, 'canal', 'canais'), '1.645 canais');
  });

  test('duração do filme por extenso', () {
    expect(formatRuntime('01:52:00'), '1 h 52 min');
    expect(formatRuntime('00:52:40'), '52 min');
    expect(formatRuntime('02:00:00'), '2 h');
    expect(formatRuntime('00:00:00'), isNull);
    expect(formatRuntime(''), isNull);
    expect(formatRuntime(null), isNull);
    expect(formatRuntime('112 min'), '112 min');
  });

  test('nomes repetidos saem e a ordem fica', () {
    expect(
      uniqueNames('David O. Russell, David O. Russell, david o. russell'),
      'David O. Russell',
    );
    expect(uniqueNames('Ana, Bia, Ana,, Caio '), 'Ana, Bia, Caio');
  });

  test('nome importado sem símbolos que viram quadrado', () {
    expect(
      cleanFileTitle(
        'Super-Herói  O Filme\u25FE\uFE0F DUBLADO \u25FE\uFE0F\u{1F39E} Movie Play',
      ),
      'Super-Herói O Filme DUBLADO Movie Play',
    );
    expect(cleanFileTitle('Rocky IV (1985) · 4K'), 'Rocky IV (1985) · 4K');
    expect(cleanFileTitle('\u{1F39E}'), '\u{1F39E}');
  });

  test('estado da conta em português', () {
    expect(accountStatusLabel('Active'), 'Ativa');
    expect(accountStatusLabel('Expired'), 'Expirada');
    expect(accountStatusLabel('Outro'), 'Outro');
    expect(accountStatusLabel(null), '—');
  });
}
