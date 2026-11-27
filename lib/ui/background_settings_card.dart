import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/system_dialogs.dart';
import '../core/theme.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/app_switch.dart';
import 'widgets/common.dart';

/// "Imagem de fundo" (Conta e ajustes → Personalização): o padrão é a imagem do
/// app; dá para escolher uma imagem do PC, ajustar o desfoque dela e voltar ao
/// padrão. No tema Minimalista o fundo começa liso e a imagem é opcional.
class BackgroundSettingsCard extends StatefulWidget {
  const BackgroundSettingsCard({super.key});

  @override
  State<BackgroundSettingsCard> createState() => _BackgroundSettingsCardState();
}

class _BackgroundSettingsCardState extends State<BackgroundSettingsCard> {
  bool _picking = false;
  String? _error;

  /// Nível sob o ponteiro enquanto o controle é arrastado: o fundo só é refeito
  /// ao soltar.
  int? _dragged;

  Future<void> _pick() async {
    final c = AppScope.read(context);
    setState(() {
      _picking = true;
      _error = null;
    });
    final path = await SystemDialogs.pickFile(
      title: 'Escolha a imagem de fundo',
      filter: SystemDialogs.imageFilter,
    );
    final ok = path != null && await BackdropRender.canOpen(path);
    if (ok) await c.setBackgroundImage(path);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path != null && !ok) {
        _error = 'Não foi possível abrir essa imagem. '
            'Escolha um arquivo JPG, PNG, WEBP ou BMP.';
      }
    });
  }

  static String _status(String chosen, BackdropInfo? info) {
    if (info == null) return 'Carregando…';
    if (info.origin == BackdropOrigin.chosen) {
      return 'Em uso: ${p.basename(chosen)}';
    }
    if (info.chosenFailed) {
      return 'Não foi possível abrir ${p.basename(chosen)}. '
          'Em uso: a imagem padrão.';
    }
    return 'Em uso: a imagem padrão.';
  }

  Widget _blurControl(AppController c) {
    final level = _dragged ?? c.backgroundBlur;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Desfoque: ${BackdropBlur.labels[level]}',
            style: const TextStyle(fontSize: 13),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Slider(
              value: level.toDouble(),
              max: (BackdropBlur.labels.length - 1).toDouble(),
              divisions: BackdropBlur.labels.length - 1,
              semanticFormatterCallback: (v) =>
                  'Desfoque ${BackdropBlur.labels[v.round()]}',
              onChanged: (v) => setState(() => _dragged = v.round()),
              onChangeEnd: (v) {
                setState(() => _dragged = null);
                c.setBackgroundBlur(v.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final chosen = c.backgroundImage;
    final minimalSwitch = !c.minimalTheme
        ? null
        : MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSwitch(
                    value: c.minimalBackground,
                    onChanged: c.setMinimalBackground,
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'Mostrar imagem de fundo',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (minimalSwitch != null && !c.minimalBackground) {
      return SectionCard(
        title: 'Imagem de fundo',
        children: [
          minimalSwitch,
          Text(
            'Em uso: fundo liso.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      );
    }
    return SectionCard(
      title: 'Imagem de fundo',
      children: [
        ?minimalSwitch,
        ValueListenableBuilder<BackdropInfo?>(
          valueListenable: BackdropRender.info,
          builder: (context, info, _) => Text(
            _status(chosen, info),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Aparece desfocada atrás das telas. Numa imagem do PC dá para '
          'ajustar o desfoque; mantenha o arquivo no mesmo lugar.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        if (chosen.isNotEmpty)
          ValueListenableBuilder<BackdropInfo?>(
            valueListenable: BackdropRender.info,
            // Se o arquivo não abriu, quem está na tela é a padrão (desfoque fixo).
            builder: (context, info, _) => info?.chosenFailed ?? false
                ? const SizedBox.shrink()
                : _blurControl(c),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _picking ? null : _pick,
              child: Text(
                _picking ? 'Escolhendo…' : 'Escolher imagem do PC',
              ),
            ),
            if (chosen.isNotEmpty)
              TextButton(
                onPressed: _picking
                    ? null
                    : () {
                        setState(() => _error = null);
                        c.setBackgroundImage('');
                      },
                child: const Text('Usar o padrão'),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}
