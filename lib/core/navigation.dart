import 'package:flutter/widgets.dart';

/// Chave do Navigator principal. Serve para abrir diálogos de widgets que
/// ficam fora do Navigator (como o aviso de atualização, no `builder` do app).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
