# MIP (MyIptvPlayer)

Player IPTV (Xtream Codes) para Windows, feito em Flutter. Reproduz TV ao vivo, filmes e séries da sua conta Xtream, com perfis, downloads, biblioteca própria e atualização automática.

- **Repositório:** https://github.com/gbrlinsk3/MyIptvPLayer (código e Releases)
- **Versão atual:** 1.0.6 (Release publicada).
- O programa **não traz conteúdo nem contas**: cada pessoa usa a própria conta Xtream.

## Instalar e atualizar

- **Instalar:** baixe `MIP-Setup-<versão>.exe` na página de [Releases](https://github.com/gbrlinsk3/MyIptvPLayer/releases) e execute. Instala em `%LOCALAPPDATA%\Programs\MIP` e cria atalhos. O `.exe` não é assinado; o SmartScreen do Windows pode avisar.
- **Atualizar:** o app procura atualização a cada abertura. Se houver, aparece um aviso no canto inferior direito com **Atualizar agora**, **Depois** e **Detalhes** (novidades da versão). Ele baixa o instalador, confere o SHA-256 e roda o instalador em modo silencioso, que fecha o app, troca os arquivos e reabre.
- **Seus dados** (perfis, bancos, ajustes, logs) ficam em `%APPDATA%`, fora da pasta do programa, e não são tocados pela atualização ou pelo desinstalador.
- Uma instalação antiga feita pelo instalador em Flutter (já descartado) pode estar em `%LOCALAPPDATA%\Programs\MIP`, a mesma pasta do Inno: instale por cima ou desinstale antes.

## O que o programa faz

**Perfis e conta**
- Vários perfis, cada um com o próprio banco, cor de destaque, ajustes e senha Xtream. Ao abrir um perfil toca uma animação de 2,5 s com os cubos da marca.
- Conta Xtream: status, expiração e conexões; edição de servidor, usuário e senha ("Salvar e testar" autentica antes de gravar).

**Início**
- Banner grande com banners menores à direita, configurável em *Conta e ajustes → Personalização → Banners do Início* (mínimo 1 banner; fontes: Filmes novos, Séries novas, Novos, Categorias, Títulos escolhidos). "Continue de onde parou" aparece só quando há algo em andamento. Troca automática a cada 12 s por título.
- **Continuar assistindo:** cartões horizontais; clicar abre o card, clicar na chamada abre o player. Série com episódio terminado mostra o próximo.

**TV ao vivo**
- Canais por categoria, EPG, banner de destaques, favoritos e **gravação** (conexão HTTP própria, arquivo `.ts` na pasta de downloads, adicionado à Minha biblioteca).

**Filmes e séries**
- Fileiras por categoria, "Ver tudo" em grade, painel lateral e **tela expandida** com sinopse, elenco, temporadas e episódios.
- Player com áudio/legenda (inclui legenda externa), retomar de onde parou, marcar como assistido, próximo episódio automático, painel de episódios e prévia na barra de tempo.
- **Favoritos** de filmes, séries e canais.

**Busca global** (barra do topo): canais, filmes e séries, com tradução PT/EN; roda em isolate.

**Minha biblioteca:** downloads (fila de um por vez, pausar/retomar, tentativa automática, verificação de espaço), arquivos próprios, gravações e histórico.

**Conta e ajustes**
- *Configurações:* Atualizações, Reprodução, Downloads, EPG, Diagnóstico (verificar e reparar histórico) e Catálogo (atualizar/limpar TV, filmes e séries).
- *Personalização:* tema (Claro, Escuro, Sistema, Automático das 9h às 17h), formato dos botões, **tamanho da interface** (100/115/130/150 %, padrão 115 %), **largura do catálogo** (1200/1440/1600 px ou Preenchido, em pixels lógicos), banners do Início e comportamento ao clicar num título baixado.

**Tamanho e proporções**
- A ampliação cobre o programa todo (menus, diálogos, barra de título), por perfil. Pôsteres por linha em monitor 2560×1440: verticais 12/11/11/9 e horizontais 6/6/5/4 (100/115/130/150 %); em janelas menores o pôster encolhe até um mínimo. Em "Preenchido" o cartão do Continuar assistindo tem no máximo 200 px e o banner ganha altura.
- Os valores ficam em `lib/core/layout_metrics.dart` (`RowMetrics`, `HeroMetrics`) e podem ser ajustados lá.

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

**Comandos:** `flutter pub get` · `flutter analyze` · `flutter test` · `flutter run -d windows`. Fontes usadas: Arial Narrow 7 (títulos) e Comfortaa (texto), em `assets/fonts/` e declaradas no `pubspec.yaml`.

**Publicar uma versão** (precisa de Flutter, Inno Setup 6 e `gh` logado):
1. Suba `AppInfo.version` e a `version:` do `pubspec.yaml` (devem ser iguais).
2. Opcional: crie `notas\<versão>.md` com `## Novos recursos`, `## Melhorias de design` e `## Correções` (itens `- texto`; modelo em `notas/MODELO.md`). Alimenta o botão "Detalhes".
3. `powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao X.Y.Z -Repo gbrlinsk3/MyIptvPLayer -Notas "O que mudou" -Publicar`

O script confere a versão, compila, gera `release\MIP-Setup-X.Y.Z.exe` e `latest.json` (com SHA-256 e detalhes) e cria a Release `vX.Y.Z`.

## O que foi verificado e o que não

- **Compilação e testes:** `flutter analyze` sem avisos e testes passando (tema, métricas de layout, ampliação da interface, animação de abertura, manifesto de atualização).
- **Confirmado em uso por você:** o atualizador (fecha, instala, reabre) e o atalho criado pelo instalador.
- **Nunca confirmado em uso real:** gravação de TV, capa aleatória das gravações (`Player.screenshot`), migração do banco 8→9, DPAPI, prévia de quadro na barra de tempo, compatibilidade de downloads/`Range` com o seu provedor.
- **Layout e animação:** os ajustes de tamanho, largura, banner e a animação de abertura foram validados por testes, mas não por uso prolongado. Nitidez de imagens a 150 %, vídeo ampliado e desempenho não foram medidos.
- Gravação por HTTP usa uma segunda conexão com o provedor; planos de uma conexão podem recusar.

## Histórico

| Versão | Principais mudanças |
|---|---|
| 1.0.6 | Corrige o perfil que não abria na 1.0.5 (o `navigatorKey` reaproveitava o Navigator da tela de perfis); "Detalhes" abre um cartão próprio |
| 1.0.5 | Animação de abertura do perfil, botão "Detalhes" no aviso de atualização e aviso no canto inferior direito |
| 1.0.4 | Botões da janela corrigidos (cópia duplicada à esquerda) e centralizados com o perfil; Continuar assistindo e banner ajustados em "Preenchido" |
| 1.0.3 | Builds 7A e 7B: banners do Início, Continuar assistindo corrigido, tema Automático, tamanho da interface, largura do catálogo, pôsteres por linha |
| 1.0.2 e anteriores | Instalador Inno Setup, atualizador, nome MIP, Conta e ajustes, segurança da senha, favoritos, histórico, legendas externas, gravação de TV |

## Pendências

- Cartões do Continuar assistindo e altura do banner: aguardam conferência visual sua (ajuste em `layout_metrics.dart`).
- `GITHUB.md` descreve o fluxo antigo de dois repositórios e está desatualizado.
