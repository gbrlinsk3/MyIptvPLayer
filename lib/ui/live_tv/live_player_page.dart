import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../../state/app_scope.dart';

/// Pede para tocar um canal na aba TV ao vivo. Não abre rota própria: só
/// registra o pedido no [AppController] e troca para a aba; quem toca é a
/// página da TV ao vivo.
///
/// Toca o canal já selecionado se ele estiver em [channels] (por streamId);
/// senão, o primeiro da lista. [channels] também vira a fila dos botões
/// "canal anterior/próximo". Lista vazia: não faz nada.
Future<void> openLivePlayer(BuildContext context, List<LiveChannel> channels) async {
  if (channels.isEmpty) return;
  final app = AppScope.read(context);
  final selectedId = app.selected?.streamId;
  var ch = channels.first;
  if (selectedId != null) {
    for (final candidate in channels) {
      if (candidate.streamId == selectedId) {
        ch = candidate;
        break;
      }
    }
  }
  app.requestLive(ch, channels);
}
