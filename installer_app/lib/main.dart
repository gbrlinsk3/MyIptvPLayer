import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// ---- configuração do instalador (ajuste aqui se mudar o nome do programa) ----
const appName = 'MIP';
const appFullName = 'MyIptvPlayer';
const appVersion = '1.0.0'; // mantenha igual a AppInfo.version do programa
const appExe = 'iptv_player.exe'; // nome do .exe gerado pelo `flutter build windows`
const accent = Color(0xFFC6613F);
const _uninstallKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MIP';

void main(List<String> args) {
  runApp(const SetupApp());
}

class SetupApp extends StatelessWidget {
  const SetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$appName — Instalador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          primary: accent,
        ),
        scaffoldBackgroundColor: const Color(0xFF151413),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(),
            minimumSize: const Size(120, 42),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const RoundedRectangleBorder(),
            minimumSize: const Size(100, 42),
          ),
        ),
      ),
      home: const SetupPage(),
    );
  }
}

enum _Step { welcome, options, installing, done, error }

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  _Step _step = _Step.welcome;
  late final TextEditingController _dir;
  bool _desktop = true;
  bool _launch = true;
  double _progress = 0;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final local = Platform.environment['LOCALAPPDATA'] ?? r'C:\';
    _dir = TextEditingController(text: '$local\\Programs\\$appName');
  }

  @override
  void dispose() {
    _dir.dispose();
    super.dispose();
  }

  void _set(double p, String s) {
    if (!mounted) return;
    setState(() {
      _progress = p;
      _status = s;
    });
  }

  Future<void> _ps(String script) async {
    final r = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
    );
    if (r.exitCode != 0) throw '${r.stderr}'.trim();
  }

  String _q(String s) => "'${s.replaceAll("'", "''")}'";

  Future<void> _install() async {
    setState(() => _step = _Step.installing);
    final dir = _dir.text.trim();
    try {
      if (dir.isEmpty || !dir.contains(':')) throw 'Escolha uma pasta válida.';
      _set(0.05, 'Preparando a pasta…');
      await Directory(dir).create(recursive: true);

      _set(0.15, 'Lendo os arquivos do programa…');
      final data = await rootBundle.load('assets/payload.zip');
      final tmp = File('${Directory.systemTemp.path}\\mip_payload.zip');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      _set(0.3, 'Copiando arquivos…');
      await _ps(
        'Expand-Archive -LiteralPath ${_q(tmp.path)} -DestinationPath ${_q(dir)} -Force',
      );
      await tmp.delete();

      _set(0.65, 'Criando atalhos…');
      final exe = '$dir\\$appExe';
      if (!File(exe).existsSync()) {
        throw 'O arquivo $appExe não foi encontrado depois de copiar. '
            'Confira a constante appExe do instalador.';
      }
      final programs =
          '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs';
      final shortcuts = <String>['$programs\\$appName.lnk'];
      if (_desktop) {
        shortcuts.add('${Platform.environment['USERPROFILE']}\\Desktop\\$appName.lnk');
      }
      for (final lnk in shortcuts) {
        await _ps(
          '\$s=(New-Object -ComObject WScript.Shell).CreateShortcut(${_q(lnk)});'
          '\$s.TargetPath=${_q(exe)};\$s.WorkingDirectory=${_q(dir)};'
          '\$s.Description=${_q(appFullName)};\$s.Save()',
        );
      }

      _set(0.8, 'Registrando o desinstalador…');
      final uninstall = File('$dir\\desinstalar.ps1');
      await uninstall.writeAsString('''
\$ErrorActionPreference = 'SilentlyContinue'
Get-Process | Where-Object { \$_.Path -like ${_q('$dir\\*')} } | Stop-Process -Force
Remove-Item ${_q('$programs\\$appName.lnk')} -Force
Remove-Item ${_q('${Platform.environment['USERPROFILE']}\\Desktop\\$appName.lnk')} -Force
Remove-Item -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MIP' -Recurse -Force
Start-Process cmd.exe -WindowStyle Hidden -ArgumentList '/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q "$dir"'
''');
      final reg = <List<String>>[
        ['DisplayName', 'REG_SZ', '$appName ($appFullName)'],
        ['DisplayVersion', 'REG_SZ', appVersion],
        ['Publisher', 'REG_SZ', appName],
        ['InstallLocation', 'REG_SZ', dir],
        ['DisplayIcon', 'REG_SZ', exe],
        [
          'UninstallString',
          'REG_SZ',
          'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "${uninstall.path}"',
        ],
        ['NoModify', 'REG_DWORD', '1'],
      ];
      for (final r in reg) {
        await Process.run('reg', [
          'add', _uninstallKey, '/v', r[0], '/t', r[1], '/d', r[2], '/f',
        ]);
      }

      _set(1, 'Pronto!');
      if (mounted) setState(() => _step = _Step.done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _step = _Step.error;
        });
      }
    }
  }

  Future<void> _finish() async {
    if (_launch) {
      await Process.start(
        '${_dir.text.trim()}\\$appExe',
        const [],
        workingDirectory: _dir.text.trim(),
        mode: ProcessStartMode.detached,
      );
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Lateral com a marca.
          Container(
            width: 230,
            color: const Color(0xFF1C1B19),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _Cubes(size: 96),
                const SizedBox(height: 18),
                Text(
                  appName,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  appFullName,
                  style: const TextStyle(color: Color(0xFFA3A096), fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'versão $appVersion',
                  style: const TextStyle(color: Color(0xFFA3A096), fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_step), child: _content()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_step) {
      case _Step.welcome:
        return _Page(
          title: 'Bem-vindo ao $appName',
          body: const Text(
            'Este assistente instala o MyIptvPlayer neste computador, só para o seu '
            'usuário do Windows (não pede senha de administrador).',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => setState(() => _step = _Step.options),
              child: const Text('Continuar'),
            ),
            OutlinedButton(onPressed: () => exit(0), child: const Text('Cancelar')),
          ],
        );
      case _Step.options:
        return _Page(
          title: 'Onde instalar',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _dir,
                decoration: const InputDecoration(
                  labelText: 'Pasta de instalação',
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _desktop,
                onChanged: (v) => setState(() => _desktop = v ?? true),
                title: const Text('Criar atalho na área de trabalho'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const Text(
                'Seus perfis, ajustes e biblioteca ficam fora desta pasta e não são '
                'apagados ao atualizar ou desinstalar.',
                style: TextStyle(color: Color(0xFFA3A096), fontSize: 12),
              ),
            ],
          ),
          actions: [
            FilledButton(onPressed: _install, child: const Text('Instalar')),
            OutlinedButton(
              onPressed: () => setState(() => _step = _Step.welcome),
              child: const Text('Voltar'),
            ),
          ],
        );
      case _Step.installing:
        return _Page(
          title: 'Instalando…',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 4),
              const SizedBox(height: 12),
              Text(_status, style: const TextStyle(color: Color(0xFFA3A096))),
            ],
          ),
          actions: const [],
        );
      case _Step.done:
        return _Page(
          title: 'Instalação concluída',
          body: CheckboxListTile(
            value: _launch,
            onChanged: (v) => setState(() => _launch = v ?? true),
            title: Text('Abrir o $appName agora'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          actions: [FilledButton(onPressed: _finish, child: const Text('Concluir'))],
        );
      case _Step.error:
        return _Page(
          title: 'Não foi possível instalar',
          body: SelectableText(
            _error ?? '',
            style: const TextStyle(color: Color(0xFFEF6B62)),
          ),
          actions: [
            FilledButton(
              onPressed: () => setState(() => _step = _Step.options),
              child: const Text('Tentar de novo'),
            ),
            OutlinedButton(onPressed: () => exit(0), child: const Text('Fechar')),
          ],
        );
    }
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.actions});

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        Expanded(child: SingleChildScrollView(child: body)),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        ),
      ],
    );
  }
}

/// Os três cubos isométricos do programa (mesmo desenho do logo do MIP).
class _Cubes extends StatelessWidget {
  const _Cubes({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(accent);
    return CustomPaint(
      size: Size.square(size),
      painter: _CubesPainter(
        top: hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 0.9)).toColor(),
        left: accent,
        right: hsl.withLightness((hsl.lightness - 0.16).clamp(0.1, 1.0)).toColor(),
      ),
    );
  }
}

class _CubesPainter extends CustomPainter {
  const _CubesPainter({required this.top, required this.left, required this.right});

  final Color top;
  final Color left;
  final Color right;

  static const _w = 0.8660254; // cos(30°)
  static const _h = 0.5; // sin(30°)

  // Cubos na grade isométrica (x, y, z): um em cima, dois embaixo.
  static const _cubes = [
    [0, 0, 1],
    [1, 0, 0],
    [0, 1, 0],
  ];

  static Offset _proj(num x, num y, num z) =>
      Offset((x - y) * _w, (x + y) * _h - z);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final c in _cubes) {
      for (var dx = 0; dx <= 1; dx++) {
        for (var dy = 0; dy <= 1; dy++) {
          for (var dz = 0; dz <= 1; dz++) {
            final p = _proj(c[0] + dx, c[1] + dy, c[2] + dz);
            minX = math.min(minX, p.dx);
            maxX = math.max(maxX, p.dx);
            minY = math.min(minY, p.dy);
            maxY = math.max(maxY, p.dy);
          }
        }
      }
    }
    final ext = math.max(maxX - minX, maxY - minY);
    final sc = size.width * 0.92 / ext;
    final ox = size.width / 2 - (minX + maxX) / 2 * sc;
    final oy = size.height / 2 - (minY + maxY) / 2 * sc;

    Offset pt(num x, num y, num z) {
      final p = _proj(x, y, z);
      return Offset(ox + p.dx * sc, oy + p.dy * sc);
    }

    Path poly(List<Offset> pts) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }

    final sorted = [..._cubes]..sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
    for (final c in sorted) {
      final x = c[0], y = c[1], z = c[2];
      canvas.drawPath(
        poly([pt(x + 1, y, z), pt(x + 1, y + 1, z), pt(x + 1, y + 1, z + 1), pt(x + 1, y, z + 1)]),
        Paint()..color = right,
      );
      canvas.drawPath(
        poly([pt(x, y + 1, z), pt(x + 1, y + 1, z), pt(x + 1, y + 1, z + 1), pt(x, y + 1, z + 1)]),
        Paint()..color = left,
      );
      canvas.drawPath(
        poly([pt(x, y, z + 1), pt(x + 1, y, z + 1), pt(x + 1, y + 1, z + 1), pt(x, y + 1, z + 1)]),
        Paint()..color = top,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CubesPainter old) =>
      old.top != top || old.left != left || old.right != right;
}
