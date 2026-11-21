# MIP (MyIptvPlayer)

Player IPTV (Xtream Codes) para Windows, feito em Flutter. Reproduz TV ao vivo, filmes e séries da sua conta Xtream, com perfis, downloads, biblioteca própria e atualização automática.

- **Repositório:** https://github.com/gbrlinsk3/MyIptvPLayer (código e Releases)
- **Versão atual:** 1.0.8 (Release publicada).
- O programa **não traz conteúdo nem contas**: cada pessoa usa a própria conta Xtream.

## Instalar e atualizar

- **Instalar:** baixe `MIP-Setup-<versão>.exe` na página de [Releases](https://github.com/gbrlinsk3/MyIptvPLayer/releases) e execute. Instala em `%LOCALAPPDATA%\Programs\MIP` e cria atalhos no Menu Iniciar e na Área de Trabalho chamados `MyIptvPlayer`; o executável é `MyIptvPlayer.exe` (antes era `iptv_player.exe`). Quem atualiza tem os atalhos antigos `MIP.lnk` apagados pelo instalador. O nome do app na interface (MIP), a pasta de instalação e o nome do Setup (`MIP-Setup-X.Y.Z.exe`) não mudaram. O `.exe` não é assinado; o SmartScreen do Windows pode avisar. `installer\montar_instalador.ps1` apaga `build\windows\x64\runner\Release` antes de compilar (o `flutter build` não limpa essa pasta e um `iptv_player.exe` antigo entrava no instalador).
- **Atualizar:** o app procura atualização a cada abertura. Se houver, aparece um aviso no canto inferior direito com **Atualizar agora**, **Depois** e **Detalhes** (novidades da versão). Ele baixa o instalador, confere o SHA-256 e roda o instalador em modo silencioso, que fecha o app, troca os arquivos e reabre.
- **Seus dados** (perfis, bancos, ajustes, logs) ficam em `%APPDATA%`, fora da pasta do programa, e não são tocados pela atualização ou pelo desinstalador. Com a troca do nome do executável os dados continuam no mesmo lugar (`%APPDATA%\com.example\iptv_player`), porque `ProductName` e `CompanyName` do `Runner.rc` foram mantidos.
- Uma instalação antiga feita pelo instalador em Flutter (já descartado) pode estar em `%LOCALAPPDATA%\Programs\MIP`, a mesma pasta do Inno: instale por cima ou desinstale antes.

## O que o programa faz

**Perfis e conta**
- Vários perfis, cada um com o próprio banco, cor de destaque, ajustes e senha Xtream. Ao abrir um perfil toca uma animação de 3 s com os cubos da marca.
- Conta Xtream: status, expiração e conexões; edição de servidor, usuário e senha ("Salvar e testar" autentica antes de gravar).
- **Trocar o Xtream:** ao mudar servidor ou usuário, o app pergunta se é do mesmo provedor. *Sim:* histórico (Continuar assistindo), favoritos de filmes/séries/canais e categorias ocultas são guardados pelo nome e religados ao catálogo novo quando ele chega (mesmo nome e ano; episódios por temporada e número). O que não tiver par seguro continua guardado (`account_carryover` nos ajustes) e aparece na aba temporária **Dados anteriores** (seção "TEMPORÁRIO" no fim da barra lateral, com contador na cor de destaque): abas Histórico, Favoritos, Canais e Categorias ocultas; cada item pode ser **religado** (janela com busca no catálogo atual; episódio: escolhe a série e o episódio é achado por temporada/número) ou **descartado**, e "Excluir aba" descarta tudo. A aba some quando não sobra nada. *Não:* avisa que esses dados serão apagados e pede confirmação. Código em `lib/catalog/title_matcher.dart` e `lib/data/carryover_store.dart`.

**Início**
- Banner grande com banners menores à direita, configurável em *Conta e ajustes → Personalização → Banners do Início* (mínimo 1 banner; fontes: Filmes novos, Séries novas, Novos, Categorias, Títulos escolhidos). "Continue de onde parou" aparece só quando há algo em andamento. Troca automática a cada 12 s por título.
- **Continuar assistindo:** cartões horizontais; clicar abre o card, clicar na chamada abre o player. Série com episódio terminado mostra o próximo.

**TV ao vivo**
- Tela **Cinema**: sem canal tocando, a página inicial da TV mostra no topo os banners de destaque (com os mini banners HBO/PREMIERE/SPORTV/TELECINE; entram de cima), depois a fileira "Recentes e favoritos" e todas as categorias visíveis (as ocultas não aparecem). Os destaques não são mais fileiras da gaveta. "Ver todos" do banner rola até a fileira da categoria. Nada toca ao abrir.
- **Gaveta** (canais sobre o vídeo): sem o campo "Buscar canal" (a busca do topo acha canais); no cabeçalho ficam atualizar, gerenciar categorias e fechar, à direita. Arrastável pela alça ou pelo cabeçalho com 3 encaixes: baixo (cabeçalho + "Recentes e favoritos"), médio (72% da altura) e tela cheia. Arrastar até o fundo fecha. Soltar em tela cheia com vídeo tocando encerra o vídeo e volta à página inicial da TV.
- Canais com o mesmo nome base são agrupados num cartão só, com etiquetas de versão (FHD, HD, SD, 4K, H265...; `[ALT]` some da etiqueta; até 3 etiquetas + "+N"; cartão de versão única sem marca não mostra etiqueta). O cartão das categorias tem estilo de loja (240 px): faixa com a categoria, imagem larga com o logo sobre o próprio logo desfocado, nome, etiquetas de versão e botão Favoritar/Favorito.
- **Recentes e favoritos:** cartões no estilo do Continuar assistindo (logo sobre fundo desfocado, nome e versões). Ficam compactos (112 px) e se expandem (256 px) ao passar o mouse; um fica aberto por vez (o sob o mouse, senão o canal tocando, senão o primeiro). Compacto: sem X e sem versões, com o coração só indicativo. Expandido: coração nos favoritos (clicar desfavorita e mostra o aviso "Removido dos favoritos" com Desfazer, que some em 5 s) e X nos que são só recentes (tira da lista); clicar toca direto. Vale na gaveta e na faixa sobre o vídeo. Todos os avisos (SnackBar) seguem o tema escuro (`snackBarTheme` em `lib/core/theme.dart`: flutuante, borda fina, ação na cor de destaque).
- Clicar num cartão toca o canal ocupando a área. Controles sobre o vídeo: nome e versão, favoritar, anterior/próximo (dentro da fileira de onde o canal foi aberto), Guia e menu de versão; também a faixa "Recentes e favoritos" e o botão "Todos os canais", que reabre a gaveta sobre o vídeo. Os controles somem com o mouse parado.
- Versão: abre na ordem FHD > HD > sem marca > 4K > SD, com `[ALT]` por último; lembra a última versão escolhida pelo usuário em cada canal. Se a versão falhar depois das tentativas automáticas do player, o app tenta sozinho a próxima versão do mesmo canal e avisa com uma mensagem rápida. Quando o servidor responde `STREAM_OFFLINE` o player não repete: vira erro na hora ("O servidor informou que o canal está fora do ar.") e a TV passa para a próxima versão; cada versão é tentada uma vez e, esgotadas, aparece "Canal fora do ar em todas as versões." e o painel com Tentar de novo. As mensagens de erro do player não trazem mais HTML do servidor (`lib/playback/playback_errors.dart`).
- O Guia (EPG) abre como faixa/painel sobre o vídeo. Ao sair da aba, a reprodução é encerrada após o tempo de página inativa; ao voltar, a gaveta aparece de novo.
- Atalhos de teclado (não conferidos no app): ↑ abre a gaveta, ↓ ou Esc fecha, ←/→ canal anterior/próximo, F tela cheia.
- Os traços de rolagem da borda direita ficam escondidos com vídeo tocando e voltam sem vídeo.
- O `app.log` registra cada abertura de canal com o motivo (gaveta, anterior, próximo, pedido externo, reserva, versão escolhida, repetir) e as trocas automáticas de versão.
- **Gravação** de TV: conexão HTTP própria, arquivo `.ts` na pasta de downloads, adicionado à Minha biblioteca.

**Filmes e séries**
- Fileiras por categoria, "Ver tudo" em grade, painel lateral e **tela expandida** com sinopse, elenco, temporadas e episódios.
- Player com áudio/legenda (inclui legenda externa), retomar de onde parou, marcar como assistido, próximo episódio automático, painel de episódios e prévia na barra de tempo.
- Painel "Próximo episódio" (faltando 2 min): fica 12 s aberto (pausa com o mouse em cima) e vira uma aba na cor de destaque; passar o mouse na aba reabre o painel.
- Na tela expandida da série, **Gerenciar assistidos** abre um painel com menu de temporada, "Marcar todos desta temporada" / "Remover todos desta temporada" (fixos no alto, acima de um divisor) e a lista de episódios para marcar um a um.
- **Favoritos** de filmes, séries e canais.

**Busca global** (barra do topo): canais, filmes e séries, com tradução PT/EN; roda em isolate.

**Minha biblioteca:** downloads (fila de um por vez, pausar/retomar, tentativa automática, verificação de espaço), arquivos próprios, gravações e histórico.

**Conta e ajustes**
- *Configurações:* Atualizações, Reprodução, Downloads, EPG, Diagnóstico (verificar e reparar histórico) e Catálogo (atualizar/limpar TV, filmes e séries).
- *Personalização:* tema (Claro, Escuro, Sistema, Automático das 9h às 17h), formato dos botões, **tamanho da interface** (100/115/130/150 %, padrão 115 %), **largura do catálogo** (1200/1440/1600 px ou Preenchido, em pixels lógicos), banners do Início e comportamento ao clicar num título baixado.

**Tamanho e proporções**
- A ampliação cobre o programa todo (menus, diálogos, barra de título), por perfil. Pôsteres por linha em monitor 2560×1440: verticais 12/11/11/9 e horizontais 6/6/5/4 (100/115/130/150 %); em janelas menores o pôster encolhe até um mínimo. Em "Preenchido" o cartão do Continuar assistindo tem no máximo 200 px e o banner ganha altura.
- Os valores ficam em `lib/core/layout_metrics.dart` (`RowMetrics`, `HeroMetrics`) e podem ser ajustados lá.

**Visual e estados**
- Esqueleto com brilho enquanto carregam as fileiras e grades de títulos (primeira carga do catálogo), Favoritos, o guia de programação, os detalhes de filme/série (painel lateral e tela expandida), os resultados da busca global, a lista da janela Religar, o Início (banner, Continuar assistindo e banner enquanto o catálogo baixa), a TV ao vivo e o histórico de Minha biblioteca.
- A roda do mouse rola a página em toda a largura da janela, também nas margens fora da coluna de largura fixa; no lugar da barra de rolagem há traços de navegação na borda direita da janela (`lib/ui/widgets/edge_scroll_marks.dart`), que mostram a posição e aceitam clique/arrasto. Só aparecem quando a tela ativa tem o que rolar e entram/saem com fade e deslize ao trocar de tela.
- Fileiras de títulos (e Continuar assistindo) podem ser arrastadas com o mouse; as setas ficam sempre visíveis (desativadas nas pontas) e, com largura fixa, ficam em colunas ao lado dos pôsteres, não por cima (`lib/ui/widgets/carousel_arrows.dart`). Com "Preenchido" ficam sobre as bordas da fileira.
- Abas com indicador deslizante em Favoritos, Minha biblioteca, Dados anteriores e na busca global.
- TV ao vivo: com vídeo tocando, o player usa a largura toda ao lado da barra, sem a "largura do catálogo" (`AppController.liveFullBleed`, lido por `ContentFrame`).
- Seta Sling: ao esticar, o lugar de repouso ganha um círculo só de borda e duas tangentes o ligam ao botão (correia).
- Títulos de fileira (Início, Filmes e séries, busca) e de categoria da TV ao vivo entram letra por letra (`SplitText`) só na primeira vez que cada título aparece na sessão (`RevealScope` em volta da área de páginas, em `lib/ui/shell.dart`); depois nascem prontos. Os cartões de canal da TV têm um facho de luz que acompanha o mouse e também acende os vizinhos da mesma fileira (`SpotlightCard`/`SpotlightGroup`), e **Favoritar** solta faíscas em estrela a partir do coração (só ao favoritar, não ao desfavoritar; `ClickSpark`). Sem animações no Windows (`disableAnimations`), tudo aparece direto.
- Cartão de canal da TV (estilo Nuuvem): o favoritar é só o ícone de coração no canto da imagem e o rodapé diz "Clique para assistir". No banner "Destaque" da TV, o texto segue o tema (escuro no claro) e a faixa mostra 5 cartões com o pôster do canal desfocado ao fundo; o do meio é maior (124 px, os outros 92 px) e todos têm o efeito ímã (`Magnet`). Em janela estreita (< 860 px) a faixa mostra 3 cartões.
- Volume dos players (TV ao vivo e filmes/séries): barras finas que acendem até o volume (`WakeSlider`); ao soltar, o foco volta ao player para as setas do teclado continuarem trocando canal/avançando.
- Aviso de atualização e cartão "Próximo episódio" têm um pavio que se consome (`SwipeToast`): o aviso some em 25 s (pausa durante o download e em Detalhes; sumir ou dispensar vale como "Depois" e ele volta na próxima abertura); o cartão do próximo episódio dura 12 s e depois vira aba minimizada (a contagem de 8 s ao fim do episódio continua como antes). No cartão, mexer o mouse não reinicia mais os 12 s; o pavio só pausa com o mouse em cima.
- TV ao vivo com vídeo tocando: volume e gravação ficam numa linha acima de "Recentes e favoritos" (`PlayerControlsPart.audioRec`, montada em `_bottomArea`); no canto inferior direito fica só o botão de tela cheia, maior (ícone de 36 px) e com o brilho do `ShinyText` passando por ele (`PlayerControlsPart.fullscreen`). Em tela cheia a barra continua com tudo junto (`PlayerControlsPart.all`).
- Logos/pôsteres da TV ao vivo (cartões, Recentes, banner e faixa de canais) usam `LiveLogo` (`lib/ui/live_tv/live_logo.dart`, `cached_network_image`): ficam guardados em disco e não são baixados de novo ao reabrir o app. Antes usavam `Image.network`, que só guarda na memória. O desfoque de fundo ganhou `RepaintBoundary`. Na primeira carga, a demora observada vem do servidor: o logo de "Eventos em destaque" é um PNG de ~2 MB compartilhado por 28 canais.
- Abas principais de Conta e ajustes com indicador elástico (`RubberSegment`); o contorno de foco só aparece pelo teclado.
- Barra lateral: o destaque da aba escolhida é um só e desliza da aba anterior até a nova (por baixo dos itens). Com a barra expandida, a tela muda durante o deslize; terminado o deslize a barra espera 1 s (para dar tempo de trocar de aba de novo) e fica compacta, ou fica compacta na hora se o mouse não estiver sobre ela (ou sair dela depois do deslize). Escolher outra aba reinicia a espera; clicar no logo, na setinha ou fora da barra cancela a espera. Os títulos de seção (MENU, GERAL, TEMPORÁRIO) têm altura fixa para os itens não mudarem de lugar ao abrir/fechar (`lib/ui/shell.dart`).
- Contadores com dígitos que rolam no selo de Dados anteriores e em Gerenciar assistidos.
- Estado vazio em Favoritos e em Minha biblioteca (downloads); carregando e erro desenhados no guia de programação.

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
Se, depois de trocar o nome do executável (`BINARY_NAME` em `windows/CMakeLists.txt`), o build falhar com `No target iptv_player`, apague `build\windows\x64\CMakeCache.txt` (cache gerado) e compile de novo.

**Publicar uma versão** (precisa de Flutter, Inno Setup 6 e `gh` logado):
1. Suba `AppInfo.version` e a `version:` do `pubspec.yaml` (devem ser iguais).
2. Opcional: crie `notas\<versão>.md` com `## Novos recursos`, `## Melhorias de design` e `## Correções` (itens `- texto`; modelo em `notas/MODELO.md`). Alimenta o botão "Detalhes".
3. `powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao X.Y.Z -Repo gbrlinsk3/MyIptvPLayer -Notas "O que mudou" -Publicar`

O script confere a versão, compila, gera `release\MIP-Setup-X.Y.Z.exe` e `latest.json` (com SHA-256 e detalhes) e cria a Release `vX.Y.Z`.

## O que foi verificado e o que não

- **Compilação e testes:** `flutter analyze` sem avisos e testes passando (tema, métricas de layout, ampliação da interface, animação de abertura, manifesto de atualização, banners do Início, troca de Xtream).
- **Confirmado em uso por você:** o atualizador (fecha, instala, reabre) e o atalho criado pelo instalador.
- **Nunca confirmado em uso real:** gravação de TV, capa aleatória das gravações (`Player.screenshot`), migração do banco 8→9, DPAPI, prévia de quadro na barra de tempo, compatibilidade de downloads/`Range` com o seu provedor.
- **Layout e animação:** os ajustes de tamanho, largura, banner e a animação de abertura foram validados por testes, mas não por uso prolongado. Nitidez de imagens a 150 %, vídeo ampliado e desempenho não foram medidos.
- Gravação por HTTP usa uma segunda conexão com o provedor; planos de uma conexão podem recusar.

## Histórico

| Versão | Principais mudanças |
|---|---|
| 1.0.8 | Esqueleto de carregamento com brilho, abas com indicador deslizante (Favoritos, Minha biblioteca, Dados anteriores e busca), contadores com dígitos que rolam (Dados anteriores e Gerenciar assistidos), estados vazio (Favoritos, Minha biblioteca), carregando (Favoritos, guia) e erro (guia) desenhados; aviso de atualização com botões que cabem no cartão |
| 1.0.7 | Tela expandida da série: "Gerenciar assistidos" (painel por temporada); aviso de atualização com botões que quebram de linha |
| 1.0.6 | Troca de Xtream mantendo dados (mesmo provedor) e aba temporária "Dados anteriores"; painel Próximo episódio (12 s, aba na cor de destaque); botões do card embaixo da imagem; dicas e hover dos botões da janela redesenhados; animação de abertura sem onda |
| 1.0.5 | Animação de abertura do perfil, botão "Detalhes" no aviso de atualização e aviso no canto inferior direito |
| 1.0.4 | Botões da janela corrigidos (cópia duplicada à esquerda) e centralizados com o perfil; Continuar assistindo e banner ajustados em "Preenchido" |
| 1.0.3 | Builds 7A e 7B: banners do Início, Continuar assistindo corrigido, tema Automático, tamanho da interface, largura do catálogo, pôsteres por linha |
| 1.0.2 e anteriores | Instalador Inno Setup, atualizador, nome MIP, Conta e ajustes, segurança da senha, favoritos, histórico, legendas externas, gravação de TV |

## Pendências

- Troca de Xtream e aba "Dados anteriores" não testadas com um provedor real: só testes automáticos do banco e do casamento e uma simulação com catálogo fictício (telas renderizadas em teste, não no app aberto). O painel "Gerenciar assistidos" passou no `flutter analyze`, mas não foi aberto nem visto na tela.
- As telas novas da 1.0.8 (esqueleto com brilho, abas deslizantes, contadores e estados vazio/carregando/erro) foram conferidas no app aberto só em parte (abas deslizantes, contador de assistidos, guia de programação carregado); esqueleto com brilho, estados vazios e o erro do guia (coberto só por teste de layout) não foram vistos na tela.
- Os esqueletos novos (detalhes, busca, Religar, Início, TV ao vivo e histórico) passaram no `flutter analyze` e no `flutter test`, mas ainda não foram vistos com o app aberto.
- Traços de navegação, rolagem da roda nas margens, arraste das fileiras e setas fixas: conferidos no app aberto só em modo "Preenchido" (traços na borda e setas visíveis); arraste com o mouse, clique curto abrindo o cartão, roda do mouse nas margens e as colunas laterais com largura fixa (1200/1440/1600) passaram só em testes automáticos ou não foram vistos. A lista antiga de canais não é mais usada na TV (o `ChannelRow` de `channel_card.dart` foi mantido sem uso).
- TV ao vivo nova (tela Cinema), primeira rodada: **conferido no app aberto** (2026-11-20, perfil real com 1645 canais): gaveta com as fileiras, agrupamento de versões, abrir canal pelo cartão, controles sobre o vídeo e some com mouse parado, Guia sobre o vídeo, favoritar e desfazer, próximo, troca automática de versão (A&E HD com `STREAM_OFFLINE` passou para A&E FHD em cerca de 32 s, ainda com as 5 tentativas), sair da aba e voltar com a gaveta de novo, traços de rolagem escondidos com vídeo e de volta sem vídeo; o erro "Null check operator used on a null value" das setas de carrossel foi corrigido (0 erros no log depois). **Não conferido no app:** atalhos de teclado, abrir canal por Favoritos e pela busca global, escolher a versão no menu e ver a escolha lembrada depois de reiniciar, largura fixa 1200/1440/1600 na TV (a TV sempre usa a largura total) e gravação na tela nova.
- TV ao vivo, segunda rodada (2026-11-20): **conferido no app aberto:** cabeçalho da gaveta à direita sem busca; banners no topo da página inicial da TV; cartões novos nas categorias e nos recentes; tocar pelo cartão; faixa de recentes sobre o vídeo com cartões novos; arrastar do médio e soltar perto volta ao médio; arrastar até o topo encerra o vídeo e mostra a página inicial com banners; arrastar para baixo encaixa no baixo mostrando Recentes; o botão Favoritar do cartão vira "Favorito" e o canal aparece com coração em Recentes e favoritos; clicar no coração remove dos favoritos e mostra o aviso com Desfazer, que restaurou; o X tirou um canal que era só recente; "Ver todos" do banner Eventos rolou a gaveta até a fileira da categoria; o build gera `MyIptvPlayer.exe` e o app abriu com os dados do perfil.
- TV ao vivo, terceira rodada (2026-11-20): **conferido no app instalado:** o cartão de Recentes e favoritos sob o mouse expandiu. Troca de versão: a versão HD de A&E falhou com "Failed to recognize file format" depois de cerca de 30 s (tentativas normais) e o app trocou sozinho para FHD, que tocou (log: "Versão HD (208147) falhou ...; tentando FHD" e "motivo: reserva"). **Não conferido no app:** a regra `STREAM_OFFLINE` (nesta rodada o servidor não respondeu `STREAM_OFFLINE`; segue coberta só pelos testes de `playback_errors`) e o aviso "Canal fora do ar em todas as versões."; o visual do aviso "Removido dos favoritos / Desfazer" depois da correção (some em 5 s e segue o tema escuro; antes ficava preso porque no Flutter 3.47 um SnackBar com ação persiste por padrão); a seta do carrossel que agora se atualiza quando a lista muda de tamanho (conferido só pelo teste `test/carousel_arrow_test.dart`); a animação de entrada dos banners (só o estado final foi visto).
- Instalador 1.0.8, geração local: `montar_instalador.ps1` sem `-Publicar` gerou `installer\output\MIP-Setup-1.0.8.exe` (cópia em `release\teste_local\`); `release\MIP-Setup-1.0.8.exe` e `release\latest.json` continuam iguais aos publicados. **Conferido:** instalado por cima em `%LOCALAPPDATA%\Programs\MIP`; o atalho da Área de Trabalho `MyIptvPlayer.lnk` e o do Menu Iniciar `MyIptvPlayer\MyIptvPlayer.lnk` apontam para `MyIptvPlayer.exe`; o `MIP.lnk` antigo da Área de Trabalho foi removido; a desinstalação ficou registrada como "MIP versão 1.0.8"; o app instalado abriu com os dados do perfil. A pasta do Menu Iniciar se chama `MyIptvPlayer` (o `.iss` usa `DefaultGroupName` MIP, mas o Inno reaproveita o grupo da instalação anterior). **Problema achado e corrigido:** o instalador levou também o `iptv_player.exe` antigo que sobrava em `build\windows\x64\runner\Release`; o script agora apaga essa pasta antes de compilar. **Não conferido:** o instalador não foi regerado nem reinstalado depois dessa correção; na instalação atual o `iptv_player.exe` velho continua na pasta do programa até a próxima instalação (o `[InstallDelete]` limpa `{app}`).
- Limitações conhecidas da TV nova: os cartões não mostram "agora no ar" (o EPG vem só do canal aberto); a edição dos mini banners de destaque da TV ficou sem interface; o `ChannelRow` ficou no código sem uso (`live_highlight_banner.dart` voltou a ser usado, com os mini banners no banner); uma troca espontânea de canal (A&E virou HBO 2 durante "Reconectando…") foi vista uma vez, antes do log novo, e não se repetiu; a troca para a próxima versão ainda espera as 5 tentativas do player (cerca de 30 s) nos erros que não são `STREAM_OFFLINE`.
- `flutter test -j 1` passou inteiro na última verificação, mas às vezes um arquivo diferente falha com "did not complete" / "loading [E]" e passa ao rodar de novo ou sozinho; causa não identificada.
- Futuro decidido (não implementado): suporte a controle/teclado virtual e app de celular pela rede Wi‑Fi local. Descartado: ping/sinal dos canais e atualizar a TV ao abrir o programa.
