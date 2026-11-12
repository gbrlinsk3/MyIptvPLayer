import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';

void main() {
  bool auto(int hour, [int minute = 0]) => resolveDark(
        ThemePref.auto,
        platformDark: false,
        now: DateTime(2026, 1, 1, hour, minute),
      );

  test('Automático: claro das 9h às 17h, escuro das 17h às 9h', () {
    expect(auto(8, 59), isTrue);
    expect(auto(9), isFalse);
    expect(auto(16, 59), isFalse);
    expect(auto(17), isTrue);
    expect(auto(23), isTrue);
    expect(auto(0), isTrue);
  });

  test('Claro, Escuro e Sistema', () {
    expect(resolveDark(ThemePref.light, platformDark: true), isFalse);
    expect(resolveDark(ThemePref.dark, platformDark: false), isTrue);
    expect(resolveDark(ThemePref.system, platformDark: true), isTrue);
    expect(resolveDark(ThemePref.system, platformDark: false), isFalse);
  });
}
