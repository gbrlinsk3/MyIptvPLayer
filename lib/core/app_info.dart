/// Identidade do programa em um só lugar.
class AppInfo {
  /// Nome curto, mostrado na barra lateral e no título da janela.
  static const name = 'MIP';

  /// Nome por extenso.
  static const fullName = 'MyIptvPlayer';

  /// Versão atual. Precisa acompanhar a `version:` do pubspec.yaml
  /// (o atualizador compara este valor com o publicado).
  static const version = '1.0.0';

  /// Endereço (https) do manifesto de atualização. Vazio = sem atualizador até
  /// ser informado em Conta e ajustes → Configurações → Atualizações.
  static const defaultManifestUrl = '';

  /// Pasta padrão de downloads/gravações dentro de "Vídeos".
  static const downloadsFolder = 'MyIptvPlayer';
}
