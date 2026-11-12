import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/app_scope.dart';
import 'widgets/common.dart';

/// Conta Xtream: mostra o status e permite ver/editar servidor, usuário e senha.
class XtreamCard extends StatefulWidget {
  const XtreamCard({super.key});

  @override
  State<XtreamCard> createState() => _XtreamCardState();
}

class _XtreamCardState extends State<XtreamCard> {
  late final TextEditingController _server;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _showPass = false;
  bool _busy = false;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    final acc = AppScope.read(context).account;
    _server = TextEditingController(text: acc?.server ?? '');
    _user = TextEditingController(text: acc?.username ?? '');
    _pass = TextEditingController(text: acc?.password ?? '');
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final server = _server.text.trim();
    final user = _user.text.trim();
    final pass = _pass.text;
    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() {
        _error = 'Preencha servidor, usuário e senha.';
        _ok = null;
      });
      return;
    }
    if (app.changesAccountIdentity(server, user)) {
      final go = await confirmDialog(
        context,
        title: 'Trocar de conta?',
        message: 'Mudar o servidor ou o usuário apaga o catálogo, favoritos de '
            'canais e progresso salvos desta conta neste computador, e baixa '
            'tudo de novo. Os downloads e as gravações em arquivo são mantidos.',
        action: 'Trocar',
      );
      if (!go || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
    });
    final err = await app.updateCredentials(
      server: server,
      username: user,
      password: pass,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      _ok = err == null ? 'Credenciais validadas e salvas.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final info = c.info;
    final expires = info == null
        ? '—'
        : (info.expiresAt == null
            ? 'Não informado'
            : formatDateTime(info.expiresAt!));
    final connections = info == null
        ? '—'
        : '${info.activeConnections ?? '?'} em uso de ${info.maxConnections ?? '?'}';
    return SectionCard(
      title: 'Conta Xtream',
      children: [
        KeyValueRow(label: 'Status', value: info?.status ?? '—'),
        KeyValueRow(label: 'Expira em', value: expires),
        KeyValueRow(label: 'Conexões', value: connections),
        const SizedBox(height: 12),
        TextField(
          controller: _server,
          decoration: fieldDecoration(label: 'Servidor', hint: 'http://exemplo.com:8080'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _user,
          decoration: fieldDecoration(label: 'Usuário'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pass,
          obscureText: !_showPass,
          onSubmitted: (_) => _save(),
          decoration: fieldDecoration(
            label: 'Senha',
            suffixIcon: IconButton(
              tooltip: _showPass ? 'Ocultar senha' : 'Mostrar senha',
              onPressed: () => setState(() => _showPass = !_showPass),
              icon: Icon(
                _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
        if (_ok != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_ok!, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Validando…' : 'Salvar e testar'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final acc = c.account;
                      _server.text = acc?.server ?? '';
                      _user.text = acc?.username ?? '';
                      _pass.text = acc?.password ?? '';
                      setState(() {
                        _error = null;
                        _ok = null;
                      });
                    },
              child: const Text('Desfazer'),
            ),
          ],
        ),
      ],
    );
  }
}
