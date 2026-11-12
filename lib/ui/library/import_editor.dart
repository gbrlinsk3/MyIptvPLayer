import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/system_dialogs.dart';
import '../../core/theme.dart';
import '../../library/library_import.dart';
import '../../state/app_scope.dart';

/// Adiciona (ou edita) um arquivo de vídeo na biblioteca. Devolve true se salvou.
Future<bool> showImportEditor(BuildContext context, {LibraryImport? existing}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ImportEditor(existing: existing),
  );
  return saved ?? false;
}

class _ImportEditor extends StatefulWidget {
  const _ImportEditor({this.existing});

  final LibraryImport? existing;

  @override
  State<_ImportEditor> createState() => _ImportEditorState();
}

class _ImportEditorState extends State<_ImportEditor> {
  late final TextEditingController _file;
  late final TextEditingController _title;
  late final TextEditingController _year;
  late final TextEditingController _plot;
  late final TextEditingController _image;
  late final TextEditingController _backdrop;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _file = TextEditingController(text: e?.filePath ?? '');
    _title = TextEditingController(text: e?.title ?? '');
    _year = TextEditingController(text: e?.year ?? '');
    _plot = TextEditingController(text: e?.plot ?? '');
    _image = TextEditingController(text: e?.image ?? '');
    _backdrop = TextEditingController(text: e?.backdrop ?? '');
  }

  @override
  void dispose() {
    for (final c in [_file, _title, _year, _plot, _image, _backdrop]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await SystemDialogs.pickFile(
      title: 'Escolha o vídeo',
      filter: SystemDialogs.videoFilter,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _file.text = picked;
      // Sugere o título pelo nome do arquivo, sem sobrescrever o que já foi digitado.
      if (_title.text.trim().isEmpty) {
        _title.text = p.basenameWithoutExtension(picked).replaceAll(RegExp(r'[._]+'), ' ').trim();
      }
    });
  }

  Future<void> _pickImage(TextEditingController into) async {
    final picked = await SystemDialogs.pickFile(
      title: 'Escolha a imagem',
      filter: SystemDialogs.imageFilter,
    );
    if (picked != null && mounted) setState(() => into.text = picked);
  }

  String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    final path = _file.text.trim();
    final title = _title.text.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() => _error = 'Escolha um arquivo de vídeo que exista neste computador.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Dê um título.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final imports = AppScope.read(context).imports;
    final item = widget.existing ??
        LibraryImport(filePath: path, title: title);
    item
      ..filePath = path
      ..title = title
      ..year = _clean(_year)
      ..plot = _clean(_plot)
      ..image = _clean(_image)
      ..backdrop = _clean(_backdrop);
    try {
      await imports.save(item);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar: $e';
        });
      }
    }
  }

  Widget _pathField(
    TextEditingController c,
    String label,
    VoidCallback pick, {
    String? hint,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: fieldDecoration(label: label, hint: hint),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: pick, child: const Text('Escolher…')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(editing ? 'Editar item' : 'Adicionar à biblioteca'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pathField(_file, 'Arquivo de vídeo', _pickFile),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: fieldDecoration(label: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _year,
                decoration: fieldDecoration(label: 'Ano (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _plot,
                minLines: 3,
                maxLines: 6,
                decoration: fieldDecoration(label: 'Sinopse (opcional)'),
              ),
              const SizedBox(height: 12),
              _pathField(
                _image,
                'Pôster (opcional)',
                () => _pickImage(_image),
                hint: 'arquivo ou endereço https://…',
              ),
              const SizedBox(height: 12),
              _pathField(
                _backdrop,
                'Banner horizontal (opcional)',
                () => _pickImage(_backdrop),
                hint: 'arquivo ou endereço https://…',
              ),
              const SizedBox(height: 8),
              Text(
                'Este item aparece só em Minha biblioteca. O arquivo não é '
                'copiado nem alterado.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
