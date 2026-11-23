# MIP (MyIptvPlayer)

Player IPTV (Xtream Codes) para Windows, feito em Flutter. Reproduz TV ao vivo, filmes e séries da sua conta Xtream, com perfis, downloads, biblioteca própria e atualização automática.

- **Repositório:** https://github.com/gbrlinsk3/MyIptvPLayer (código e Releases)
- **Versão atual:** 1.0.10.
- O programa **não traz conteúdo nem contas**: cada pessoa usa a própria conta Xtream.

## Instalar e atualizar

- **Instalar:** baixe `MIP-Setup-<versão>.exe` na página de [Releases](https://github.com/gbrlinsk3/MyIptvPLayer/releases) e execute. Instala em `%LOCALAPPDATA%\Programs\MIP` e cria atalhos no Menu Iniciar e na Área de Trabalho chamados `MyIptvPlayer`; o executável é `MyIptvPlayer.exe` (antes era `iptv_player.exe`). Quem atualiza tem os atalhos antigos `MIP.lnk` apagados pelo instalador. O nome do app na interface (MIP), a pasta de instalação e o nome do Setup (`MIP-Setup-X.Y.Z.exe`) não mudaram. O `.exe` não é assinado; o SmartScreen do Windows pode avisar. `installer\montar_instalador.ps1` apaga `build\windows\x64\runner\Release` antes de compilar (o `flutter build` não limpa essa pasta e um `iptv_player.exe` antigo entrava no instalador).
- **Atualizar:** o app procura atualização a cada abertura. Se houver, aparece um aviso no canto inferior direito com **Atualizar agora**, **Depois** e **Detalhes** (novidades da versão). Ele baixa o instalador, confere o SHA-256 e roda o instalador em modo silencioso, que fecha o app, troca os arquivos e reabre.
- **Seus dados** (perfis, bancos, ajustes, logs) ficam em `%APPDATA%`, fora da pasta do programa, e não são tocados pela atualização ou pelo desinstalador. Com a troca do nome do executável os dados continuam no mesmo lugar (`%APPDATA%\com.example\iptv_player`), porque `ProductName` e `CompanyName` do `Runner.rc` foram mantidos.
- Uma instalação antiga feita pelo instalador em Flutter (já descartado) pode estar em `%LOCALAPPDATA%\Programs\MIP`, a mesma pasta do Inno: instale por cima ou desinstale antes.

## O que o programa faz

**Perfis e conta**
- Vários perfis, cada um com o próprio banco, cor de destaque, ajustes e senha Xtream.
- Dados da conta (status, expiração, conexões) e troca de servidor mantendo histórico, favoritos e categorias ocultas quando é o mesmo provedor.
- Temas Claro, Escuro, Sistema e Automático; tamanho da interface e largura do catálogo ajustáveis.

**Início, filmes e séries**
- Banners configuráveis, "Continuar assistindo", busca, favoritos e categorias que você pode ocultar.
- Página do título com elenco, episódios por temporada, marcar como assistido e "Gerenciar assistidos".
- Player com legendas, episódio seguinte e faixa de episódios sobre o vídeo.

**TV ao vivo**
- Tela estilo cinema: vídeo em tela cheia, gaveta de canais agrupados por nome (versões FHD/HD/SD), recentes e favoritos, guia de programação (EPG) e gravação.

**Downloads e biblioteca**
- Fila de downloads com pausa e retomada, biblioteca própria.

## Dados e segurança

- Banco SQLite por perfil, esquema **v9** (`lib/data/db.dart`); migrações só acrescentam tabelas e colunas. A tela de reparo faz cópia `.backup-<ms>` antes de mexer.
- Senha Xtream protegida com DPAPI do Windows (`lib/core/secret_store.dart`); senhas antigas migram sozinhas.
- Atualizações: só https e só com SHA-256 igual ao do manifesto. Logs mascaram usuário e senha (`AppLog.scrub`) e ficam em `logs/app.log`, na pasta de dados.
- **Limites:** servidores IPTV costumam ser `http://` (o app não pode forçar https); o `latest.json` não é assinado (o hash protege de download corrompido, não de quem controla o repositório); downloads e gravações não são criptografados. O repositório é público: não coloque senhas, links de provedores ou dados pessoais nele.
- A pasta padrão de downloads é `Downloads\MyIptvPlayer` (antes `IPTV Player`; arquivos antigos não são movidos).

## Desenvolvimento

**Stack:** Flutter (Windows), `media_kit`/libmpv, `sqflite_common_ffi`, `window_manager`, `cached_network_image`. Pacote Dart `iptv_player`; nome na interface "MIP" (`lib/core/app_info.dart`).

**Estrutura**
- `lib/state/` controladores (`AppController`, `PlaybackController`...) com `ChangeNotifier` + `InheritedNotifier` (`AppScope`)
- `lib/catalog/`, `lib/data/`, `lib/downloads/`, `lib/epg/`, `lib/library/`, `lib/playback/`, `lib/profiles/` — dados e regras
- `lib/ui/` — telas e widgets; `lib/core/` — tema, métricas de layout, log, segredos
- `lib/update/` — atualizador; `installer/` — Inno Setup e script de publicação; `test/` — testes

**Comandos:** `flutter pub get` · `flutter analyze` · `flutter test` · `flutter run -d windows`. No Windows o `flutter_tester.exe` cai de vez em quando (violação de acesso `0xC0000005`), até num projeto vazio, e o teste aparece como "did not complete", "No tests were found" ou "Connection closed before test suite loaded"; para a suíte completa use `powershell -ExecutionPolicy Bypass -File .	oolodar_testes.ps1`, que roda um arquivo por vez e repete só os que caírem assim (falha de teste de verdade não é repetida). Fontes usadas: Arial Narrow 7 (títulos) e Comfortaa (texto), em `assets/fonts/` e declaradas no `pubspec.yaml`.
Se, depois de trocar o nome do executável (`BINARY_NAME` em `windows/CMakeLists.txt`), o build falhar com `No target iptv_player`, apague `build\windows\x64\CMakeCache.txt` (cache gerado) e compile de novo.

**Publicar uma versão** (precisa de Flutter, Inno Setup 6 e `gh` logado):
1. Suba `AppInfo.version` e a `version:` do `pubspec.yaml` (devem ser iguais).
2. Opcional: crie `notas\<versão>.md` com `## Novos recursos`, `## Melhorias de design` e `## Correções` (itens `- texto`; modelo em `notas/MODELO.md`). Alimenta o botão "Detalhes".
3. `powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao X.Y.Z -Repo gbrlinsk3/MyIptvPLayer -Notas "O que mudou" -Publicar`

O script confere a versão, compila, gera `release\MIP-Setup-X.Y.Z.exe` e `latest.json` (com SHA-256 e detalhes) e cria a Release `vX.Y.Z`.

## Pendências e histórico de mudanças

O detalhamento de cada mudança e das pendências fica em `HISTORICO_DE_MUDANCAS.md`, arquivo local que não vai para o repositório.
