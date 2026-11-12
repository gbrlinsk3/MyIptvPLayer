import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../profiles/profiles_scope.dart';
import '../state/app_scope.dart';
import 'profiles/profile_avatar.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_server.text.trim().isEmpty ||
        _user.text.trim().isEmpty ||
        _pass.text.isEmpty) {
      setState(() => _error = 'Preencha servidor, usuário e senha.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await AppScope.read(context).login(
      server: _server.text,
      username: _user.text.trim(),
      password: _pass.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recovered = AppScope.of(context).dbRecovered;
    final profile = ProfilesScope.of(context).session?.profile;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (profile != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProfileAvatar.of(profile, size: 44),
                        const SizedBox(width: 12),
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Entrar',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use os dados de acesso Xtream Codes do seu provedor. A conta fica salva só neste perfil.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                if (recovered) ...[
                  const SizedBox(height: 16),
                  Text(
                    'O banco de dados local estava ilegível e foi recriado. '
                    'O arquivo antigo foi guardado ao lado dele, com final ".corrupt-…".',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _server,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: fieldDecoration(
                    label: 'Servidor',
                    hint: 'http://servidor.com:8080',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: fieldDecoration(label: 'Usuário'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  enabled: !_busy,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: fieldDecoration(
                    label: 'Senha',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: AppShape.button,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Entrar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ProfilesScope.read(context).leave(),
                  child: const Text('Trocar de perfil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
