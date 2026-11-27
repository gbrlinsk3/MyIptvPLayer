import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/ui/theme_settings_card.dart';
import 'package:iptv_player/ui/widgets/common.dart';

void main() {
  testWidgets('Aparência: as quatro opções cabem em uma linha', (t) async {
    // Fonte do app: a de teste é bem mais larga e mediria outra coisa.
    await t.runAsync(
      () => (FontLoader('Comfortaa')
            ..addFont(
              File('assets/fonts/Comfortaa-Regular.ttf')
                  .readAsBytes()
                  .then((b) => ByteData.view(b.buffer)),
            ))
          .load(),
    );
    ThemePref? chosen;
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          // Mesma coluna de Conta e ajustes: 640 de largura e 24 de respiro.
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  SectionCard(
                    title: 'Aparência',
                    children: [
                      AppearanceSelector(
                        selected: ThemePref.dark,
                        onChanged: (v) => chosen = v,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final line = t.getSize(find.text('Claro')).height;
    for (final label in ['Escuro', 'Sistema', 'Automático']) {
      expect(t.getSize(find.text(label)).height, line, reason: label);
    }
    await t.tap(find.text('Automático'));
    expect(chosen, ThemePref.auto);
  });
}
