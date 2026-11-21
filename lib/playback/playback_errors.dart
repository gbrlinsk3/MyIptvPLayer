// Tratamento puro das mensagens de erro do player (sem dependência de UI).

/// True se o servidor informou `STREAM_OFFLINE` (o mpv traz a página HTML do
/// painel XUI.ONE dentro da mensagem de erro).
bool isServerOffline(String message) =>
    message.toUpperCase().contains('STREAM_OFFLINE');

/// Texto curto e sem HTML para mostrar ao usuário.
String friendlyPlaybackError(String message) {
  if (isServerOffline(message)) {
    return 'O servidor informou que o canal está fora do ar.';
  }
  var text = message;
  final lt = text.indexOf('<');
  if (lt >= 0) text = text.substring(0, lt);
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return 'Falha ao abrir a transmissão.';
  if (text.length > 200) text = '${text.substring(0, 200)}…';
  return text;
}
