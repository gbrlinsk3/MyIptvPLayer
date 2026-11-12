# Cubos — build 3D (com as etapas de estabilidade 1.2–1.8)

Player IPTV para Windows (Xtream Codes) em Flutter + media_kit (libmpv) + SQLite.

## Situação real (leia primeiro)

- **Quem escreveu o código (Claude) não consegue compilar nem rodar Flutter** no ambiente onde trabalha; nada aqui foi executado por ele. O que sabemos de funcionamento vem do **seu relato**: o `flutter analyze` rodou sem erros nas etapas anteriores, o último aviso (import repetido em `app_controller.dart`) foi corrigido, e você disse que a build com a etapa 1.6b "está funcionando corretamente". **Não foi relatado** o resultado do `flutter test`, nem do `flutter analyze` após a 1.7.
- Cada seção abaixo separa o que está **no código** do que é **inferido / não verificado**. Seções antigas (3B, 3C, 3D) descrevem a época em que foram escritas; onde algo mudou depois, há uma nota "Atualização".
- Prévias em HTML feitas durante o projeto **não são o app**.

## Estado do plano de estabilidade

Feito: 1.1 análise · 1.2 registro de erros · 1.3 testes + mover downloads · 1.4 diagnóstico · 1.5 reparar histórico · 1.6 revisão dos downloads (+1.6b riscos) · 1.7 limpeza de ajustes · 1.8 revisão deste README.
**Ainda não feito (planejado, não implementado):** favoritos de filmes/séries, tela de histórico completo, instalador `.exe`, legendas externas, e a fase de otimização medida (perfil com DevTools, busca em isolate, rebuilds, cache de imagens).

## Como atualizar

1. Feche o app. **Apague a pasta `lib\` do projeto antes** e copie a `lib\` do zip no lugar (copiar por cima mantém arquivos antigos que foram removidos, e eles dão erro no `flutter analyze` — já aconteceu com `channels_pane.dart`, `categories_pane.dart` e `player_pane.dart`). Copie também o `README.md`.
2. **Fontes (novo):** baixe do dafont **Arial Narrow 7** e **Comfortaa**, crie `assets\fonts\` no projeto e coloque os arquivos com **estes nomes**: `ArialNarrow7.ttf`, `Comfortaa-Regular.ttf`, `Comfortaa-Bold.ttf` (renomeie se vierem com outro nome). Depois, no `pubspec.yaml`, dentro de `flutter:` (junto de `assets:`), acrescente:

```yaml
  fonts:
    - family: ArialNarrow7
      fonts:
        - asset: assets/fonts/ArialNarrow7.ttf
    - family: Comfortaa
      fonts:
        - asset: assets/fonts/Comfortaa-Regular.ttf
        - asset: assets/fonts/Comfortaa-Bold.ttf
          weight: 700
```

   Se os arquivos não existirem, o build **falha** ao declarar a fonte; sem a declaração o app roda com a fonte padrão.
3. Se ainda não fez: `flutter pub add cached_network_image`.
4. **Testes (opcional, recomendado):** copie também a pasta `test\` do zip para a raiz do projeto (ao lado de `lib\`). Ela **não é necessária para o app rodar**; só serve para `flutter test`. Os testes usam `package:iptv_player/...`, então o campo `name:` do seu `pubspec.yaml` precisa ser `iptv_player`, e `flutter_test` deve estar em `dev_dependencies` (padrão de projetos novos). Se não quiser os testes, ignore a pasta; se der erro de nome de pacote, apague `test\` ou ajuste os imports.
5. `flutter pub get`, `flutter analyze`, `flutter test` (opcional), `flutter run -d windows`.

## O que muda nos seus dados

- O banco de **cada perfil** (`profile_<id>.db`) está hoje na **versão 6** no código e sobe sozinho na primeira abertura. As migrações só **acrescentam** tabelas/colunas: v3 filmes, séries e progresso; v4 `downloads`; v5 imagem horizontal em `downloads`; v6 `library_imports` (arquivos próprios). Conta, canais, EPG, categorias ocultas e ajustes ficam como estão.
- A tela de reparo (1.5) faz uma cópia `<banco>.backup-<ms>` antes de mexer (mantém 3).

## O que está no código (3C)

- **Tema:** escuro por padrão (também em perfis que nunca escolheram), claro ou automático em Conta e ajustes → Aparência (também no menu do perfil). Corrigido: antes o app não reagia à troca porque escutava o notificador errado.
- **Rolagem:** o Início usa rolagem simples (sem alturas estimadas) e o Catálogo só lista fileiras/categorias que têm título, para não "pular" ao subir.
- **Topo:** busca global (canais, filmes e séries; ver "Rodada: busca global com canais") à esquerda; perfil ativo à direita com menu (Conta e ajustes, trocar tema, trocar de perfil). O perfil saiu da barra lateral.
- **Barra lateral:** seções MENU / GERAL, ícone cheio no item ativo e **indicador lateral na cor de destaque do perfil**; recolhe para ícones.
- **Início:** carrossel de borda a borda: banner grande à esquerda e **dois banners menores à direita** com os próximos slides (clicar vai até eles; em janela estreita, menos de ~900 px, eles somem). Setas nos dois lados, pílulas embaixo (a atual enche em 12 s) e pausa com o mouse. Slides: 1) último assistido ("Continuar"); 2) 3 filmes novos; 3) 3 séries novas; 4) mistura de recentes, com botão "Ver catálogo"; 5) Animações das categorias marcadas em Conta e ajustes (sem marcar, não aparece). Miniaturas dentro do banner trocam o destaque.
- **Carregamento do fundo:** o pôster borrado aparece na hora (e o nítido, até a imagem horizontal chegar); a imagem horizontal tenta a versão grande do TMDB e, se falhar, o endereço original. Pedidos de detalhes ao servidor ficam limitados a 3 ao mesmo tempo (provedores costumam limitar conexões).
- **Qualidade da imagem:** o fundo usa a imagem horizontal (`backdrop_path`) do servidor; se o endereço for do TMDB (`image.tmdb.org/t/p/w300` etc.), o app pede a versão `w1280` (banner) ou `w780` (cartões). Sem imagem horizontal, usa o pôster borrado ao fundo e o pôster nítido na frente, sem esticar. **Inferido:** que o TMDB aceite esses tamanhos para o seu provedor; se a imagem não carregar, me avise.
- **Transições:** troca com fade e leve zoom, zoom lento na imagem enquanto o slide está na tela, texto que sobe e aparece, banners laterais deslizando, imagem de fundo trocando em fade quando chega do servidor (os detalhes dos slides são buscados antes).
- **Continuar assistindo:** cartões horizontais com a capa do servidor; o do mouse (ou o primeiro) se expande e mostra "Clique aqui para assistir". Depois, fileiras de pôsteres de filmes e séries recentes. Os resumos de TV ao vivo e Conta saíram do Início e estão em Conta e ajustes (canais ocultos, canal selecionado e "Abrir TV ao vivo" foram para o card de TV ao vivo).
- **Fontes:** títulos em Arial Narrow 7, texto em Comfortaa (veja "Como atualizar").
- **Botão do banner** inspirado no da ref. 5 (quadrado escuro com ícone + retângulo na cor do perfil, cantos retos, sombra colorida).

**Interpretações minhas (me corrija):** "banner conectado nas bordas" = largura total, colado ao topo, só os cantos de baixo arredondados; o "card de informações lateral" = bloco de texto à esquerda sobre a imagem; fileiras abaixo usam pôsteres (a lista do servidor não traz capas horizontais; elas só vêm ao abrir o detalhe, por isso só os cartões de "continuar" e os banners as usam); "último assistido" compara filmes e séries pela data.

## O que está no código (3D)

- **Baixar:** botão "Baixar" no painel de detalhes do filme, por episódio (ícone) e "Baixar temporada". O arquivo é o **mesmo que o provedor entrega** (`container_extension`), sem recompressão: nada de conversão no app.
- **Fila:** um download por vez (cada um usa uma conexão da sua conta Xtream). Pausar, retomar (cabeçalho HTTP `Range`; se o servidor não aceitar, recomeça do zero) e cancelar (apaga o parcial). Se o app fechar no meio, o item volta **pausado** e retoma de onde parou. Download incompleto ou sem rede vira "erro" com botão de tentar de novo.
- **Minha biblioteca** (novo item no menu): "Em andamento" (linhas com progresso, tamanho, velocidade); depois de baixar, o item vai para uma fileira de **cartões deitados 16:9**, como no catálogo: uma fileira "Filmes" e uma fileira por série (episódios), com próximo episódio automático. A imagem horizontal é guardada no download (banco versão 5); itens baixados antes dessa versão buscam a imagem no servidor e, sem ela, usam o pôster. Excluir apaga o arquivo; "Mostrar na pasta" abre o Explorer.
- **Offline:** itens baixados tocam do arquivo local; o painel de detalhes também prefere o arquivo local quando existe.
- **Pasta:** padrão `<Downloads do Windows>\IPTV Player\Filmes` e `...\Séries\<série>\Temporada NN`. Em Conta e ajustes → Downloads há "Escolher pasta" (seletor do Windows via PowerShell), "Abrir pasta" e "Digitar caminho"; vale para novos downloads, e downloads antigos podem ser movidos (1.3). *Atualização: antes desta build não havia seletor.* Excluir um perfil **não apaga** os arquivos baixados.
- Também: tooltip das miniaturas do banner na cor do perfil; corrigido o gradiente branco no topo do painel de detalhes no tema escuro; corrigido o overflow de 1 px do painel de programação recolhido.

## Player (nesta build)

- **Painel de episódios no player:** botão "Episódios" nos controles (aparece quando há mais de um item na fila, ex.: série): lista lateral com o episódio atual destacado; tocar em outro troca na hora, retomando de onde você parou, sem sair da tela cheia. Esc fecha o painel.
- **Prévia na barra de tempo:** ao passar o mouse, balão com o tempo (sempre) e uma **imagem do quadro** quando o item é um **arquivo baixado**. Em streaming só aparece o tempo: gerar imagens abriria uma segunda conexão no provedor (e, em plano de uma conexão, derrubaria a reprodução). A imagem vem de um segundo player mudo, pausado, que busca o ponto e tira uma captura; primeira prévia pode levar ~1 s.
- **Visual refinado:** título em fonte de display, gradiente inferior mais suave, barra de tempo na cor do perfil que engrossa ao passar o mouse.
- **Não verificado:** `Player.screenshot()` e o segundo player em arquivos locais do Windows (se falhar, o balão fica só com o tempo); desempenho com arquivos grandes.

## Desempenho e transições (nesta build)

- **Só o que está à vista existe:** ao abrir o app só o Início é construído. Cada página (Início, TV ao vivo, Catálogo, Biblioteca, Conta) e cada aba do Catálogo (Filmes/Séries) só é criada quando você entra; ao sair, fica viva por **6 s** (voltar logo é instantâneo) e depois é **descartada**, junto com as listas de fileiras em memória. Dentro das páginas as fileiras já eram criadas só quando entram na tela.
- **Imagens:** memória de imagens decodificadas limitada a 96 MB / 400 imagens (as menos usadas saem sozinhas); as imagens também ficam em cache em disco.
- **Barra lateral:** ao expandir, abre **por cima** do conteúdo (antes empurrava e recalculava a tela inteira a cada quadro); toque fora ou escolha um item para recolher. Esta mudança de comportamento é minha.
- **Banner do Início:** o zoom lento não refaz mais o desfoque a cada quadro.
- **Transições novas:** troca de página (fade + leve subida), busca (fade), fileiras ↔ grade da categoria ↔ busca no Catálogo, perfil → app, e painel de detalhes (fade + deslize).
- **Inferido:** a causa exata dos travamentos não foi medida (não rodei o app); estas são as causas prováveis que identifiquei no código. Se continuar travando, diga em qual tela e o que você estava fazendo.

**Inferido / não verificado (3D):** que o seu provedor aceite download direto das URLs `/movie/` e `/series/` (alguns bloqueiam ou limitam velocidade) e o cabeçalho `Range`; que `getDownloadsDirectory()` devolva a pasta Downloads no seu Windows; reprodução do arquivo local pelo media_kit com caminho do Windows; nomes de arquivo com caracteres especiais; o comportamento com plano de 1 conexão.

## Da build 3B (continua igual)

- **Menu "Catálogo"** (entre TV ao vivo e Conta e ajustes), com abas **Filmes | Séries**.
- **Fileiras por categoria, estilo Netflix:** "Continuar assistindo", "Adicionados recentemente" e uma fileira por categoria visível (com contador e "Ver tudo"). Cartões crescem de leve ao passar o mouse; setas laterais aparecem com o mouse sobre a fileira. Fileira vazia não aparece.
- **Busca** por título (a aba atual) e **"Ver tudo"** em grade.
- **Painel de detalhes** deslizante à direita: sinopse, elenco, direção, nota, ano e, nas séries, temporadas e episódios com progresso.
- **Player de filmes e séries** (tela cheia, com a barra de título): pausa, barra de progresso, ±10 s, volume, tela cheia, menu de **áudio e legenda** (faixas que o arquivo tiver). Teclas: Espaço, ←/→, ↑/↓, M, F, Esc.
- **Retomar de onde parou**, **marcar como assistido** (filmes e episódios) e **próximo episódio automático** (contagem de 8 s com "Assistir agora" e "Cancelar"). Tudo por perfil, no banco do perfil.
- **Gerenciar categorias** também para filmes e séries (ícone no topo do catálogo; mesmo painel da TV ao vivo).
- Ao abrir um filme/episódio, a **TV ao vivo é parada** (evita ocupar duas conexões do provedor).
- A lista é baixada **só ao abrir a aba** e atualizada sozinha se tiver mais de 24 h; também em Conta e ajustes (atualizar/limpar). Os títulos ficam no SQLite e são lidos aos poucos, uma fileira por vez.

## Inferido / não verificado

- 3C: nomes das fontes e arquivos acima; o desenho dos banners não foi visto rodando; `backdrop_path` existir no seu provedor; `withValues`/`toARGB32` exigem Flutter recente (3.27+); a recriação da interface na troca de tema e o visual dos dois temas não foram vistos rodando; contraste do texto sobre o banner não medido.

- Ações e campos da API (`get_vod_categories`, `get_vod_streams`, `get_series_categories`, `get_series`, `get_vod_info`, `get_series_info`) e os endereços `/movie/…` e `/series/…` seguem a convenção do Xtream; **não foram testados no seu provedor**. Se uma aba vier vazia ou com erro, me diga a mensagem.
- Se o provedor não informar data de inclusão, a fileira "Adicionados recentemente" não aparece.
- `cached_network_image` funcionar no Windows com o cache em disco: não verificado.
- Nomes de tipos do `media_kit` para faixas (`Tracks`, `AudioTrack`, `SubtitleTrack`) escritos de memória; o `flutter analyze` mostra se algo não bate.
- Fluidez com listas de dezenas de milhares de títulos: não medida.

## Escolhas minhas (me corrija)

- "Continuar assistindo" em séries mostra só séries com um episódio **começado e não terminado** (não sugere o próximo episódio quando o anterior terminou).
- Um título conta como assistido ao passar de 92% ou ao terminar.
- Busca limitada a 300 resultados; "Ver tudo" carrega até 3000 títulos da categoria.
- Fileira de categoria mostra os 40 primeiros títulos (use "Ver tudo" para o resto).

## Não implementado

Atualização (etapa 1.8): downloads, Minha biblioteca (incluindo arquivos importados), favoritos de **canais** ao vivo e o "continuar assistindo" **existem no código**. Continuam **não implementados**:
- legendas externas (o player só lista as faixas de áudio/legenda que o próprio arquivo/stream traz);
- favoritos de **filmes e séries**;
- tela de **histórico completo** (hoje só o "Continuar assistindo");
- instalador `.exe`;
- otimização medida (nunca medimos desempenho; as melhorias feitas são hipóteses baseadas no código).


## Tela expandida de filme/série (adicionada sobre a 3D)

**No código:** `lib/ui/catalog/title_details_page.dart`. Abre pelo botão "Expandir informações" no canto do painel lateral. Fundo de tela cheia (pôster borrado + imagem horizontal, tentando a versão `w1280` do TMDB e depois o endereço original), título grande, nota/ano/gênero/duração, sinopse, elenco e direção. Filme: Assistir/Continuar, Do início, Baixar, marcar como assistido. Série: botão para o próximo episódio não assistido, lista de temporadas à direita (janela larga), fileira "EPISÓDIOS" com cartões deitados, barra de progresso, baixar/marcar ao passar o mouse, "Baixar temporada" e setas laterais. Usa a mesma regra do painel (arquivo baixado tem prioridade).

**Inferido / não verificado:** como o layout se comporta em janelas pequenas, se o provedor fornece imagem horizontal (`backdrop`) e imagens de episódio, e se `w1280` existe para o seu provedor. A tela é sempre escura, também no tema claro; os botões da janela (minimizar/fechar) podem ter pouco contraste nesse caso.

Correções de análise: `catalog_page.dart` (`body` não final), `player_scrub.dart` (`_video` com ignore intencional), `library_page.dart` (`?trailing`).


## TV ao vivo no formato do catálogo (adicionada sobre a 3D)

**No código:** `lib/ui/live_tv/live_tv_page.dart` (título, busca, atualizar, gerenciar categorias; fileiras por categoria com o nome como divisor; fileira "Favoritos" no topo; "Ver tudo" abre a categoria em grade), `channel_card.dart` (cartão horizontal: logo + nome + coração de favorito), `live_player_page.dart` (clique no canal abre o player em página própria, com programação (EPG) embaixo, favoritar, canal anterior/próximo, setas ← → e Esc; tela cheia do Windows continua pelo botão/tecla F). Ao voltar, a transmissão é encerrada. Favoritos são salvos no perfil (ajuste `favorite_channels`) e zerados ao entrar com uma conta nova.

**Removido:** o layout antigo de três colunas (`channels_pane.dart`, `categories_pane.dart`, `player_pane.dart`). Os ajustes `channels_compact`/`categories_compact` foram **removidos na etapa 1.7**.

**Inferido / não verificado:** que o clique em canais com muitas categorias/canais rola sem travar (fileiras de altura fixa, mas não medi); o logo de cada canal depende do provedor (sem logo aparece um ícone de TV); o EPG reaproveita o painel antigo, só trocando o lugar.


## Banners, busca inteligente e desempenho da tela expandida (sobre a 3D)

**No código:**
- *Banners do Início*: **revertidos ao comportamento anterior** (último assistido; 3 filmes novos; 3 séries novas; adicionados recentemente; animações). A versão com "top notas" e "Recomendado para você" foi removida. Descrição da versão removida, só para histórico: 1) até 3 "continue de onde parou" diferentes (filmes e séries juntos); 2/3) "Filmes novos / Séries novas · top notas": os 3 de maior nota entre os 40 mais recentes (sem nota fica de fora; se faltar, completa com os mais novos); 4) "Recomendado para você": usa as **categorias** do que você já assistiu (as recentes pesam mais) + a nota do provedor, sem repetir o que já viu; sem histórico, volta a "Adicionados recentemente"; 5) Animações. Um título não aparece em dois banners.
- *Busca* (`catalog/smart_search.dart`): índice em memória (ids + nomes normalizados), montado na primeira busca e refeito quando o catálogo muda. Ignora acentos, hífen e pontuação; palavras em qualquer ordem; prefixos; erros leves de digitação (1 letra em palavras até 5, 2 acima); "spiderman" = "spider man". O que combina com tudo vai no resultado principal; o que combina só com parte (ou só com erro de digitação, quando há acertos exatos) vai sob o divisor "Também pode interessar" (na busca do topo e na da aba Catálogo). Os pesos são escolhas minhas.
- *Tela expandida*: abre por substituição do painel (uma só animação, só fade); o conteúdo só é montado quando a animação termina; o pôster borrado virou uma miniatura esticada (sem filtro de blur); botões de download/marcar dos episódios só existem com o mouse em cima; temporadas trocam com fade; `RepaintBoundary` nos cartões, no fundo e nas páginas do menu.

**Inferido / não verificado:** a recomendação usa a *categoria* do provedor (não o gênero real, que só vem nos detalhes), então depende de como o seu provedor organiza as categorias; a nota vem do provedor e pode estar ausente; a busca roda em Dart na thread principal (rápida em dezenas de milhares de títulos pelo que calculei, mas não medi no seu catálogo); as causas do travamento da tela expandida são hipóteses baseadas no código, não medidas.

Correção: o banner do Início voltou à lógica antiga; o fundo desfocado do banner agora usa uma miniatura esticada (sem filtro de blur). A busca inteligente e a tela expandida foram mantidas.

Busca (ajuste): a busca do topo ganhou a fileira **"Mais parecidos"** (até 10, filmes e séries juntos, ordenados por semelhança; só quem combina com tudo o que foi digitado, ou, se ninguém combinar, os parciais mais próximos). Os títulos se repetem nas fileiras de baixo, como você pediu. Palavras curtas agora toleram 1 letra de diferença com a mesma inicial ("te" por "the"). Inferido: o corte e os pesos são escolhas minhas; testei só com a lógica, não com o seu catálogo.


## Estabilidade — etapa 1.2: registro de erros em arquivo

**No código:** `lib/core/app_log.dart` (`AppLog.info/warn/error`). Grava em `logs/app.log` dentro da pasta de dados do app (a mesma dos bancos, via `getApplicationSupportDirectory`; no Windows costuma ficar em `AppData\Roaming\...` — caminho exato **inferido**, a tela de diagnóstico da etapa 1.4 vai mostrá-lo). Rotação simples: acima de 512 KB o arquivo vira `app.log.1` (guarda só o anterior). Endereços de stream (`/movie|series|live/usuario/senha/`) e `username=`/`password=` são mascarados antes de gravar. O log nunca lança erro.
- `main.dart` registra erros do Flutter (`FlutterError.onError`) e erros assíncronos sem tratamento (`PlatformDispatcher.onError`).
- Os 11 `catch (_)` do projeto agora registram o motivo (downloads, perfis, conta, detalhes do catálogo, prévia do player). Também passa a ser registrada a **falha de download** (antes só aparecia na tela do item).
- Continuam silenciosos, de propósito, os erros esperados (ex.: arquivo já apagado) — mas agora aparecem como `AVISO`.

**Não verificado:** não compilei; o caminho real do log; se `PlatformDispatcher.onError` retornando `true` esconde algum erro que antes aparecia no console (ele continua indo para o console via `debugPrint`).

**Estado do plano:** 1.1 concluída (`flutter analyze` limpo, informado por você); 1.2 entregue; próximas: 1.3 testes, 1.4 diagnóstico, 1.5 reparar histórico, 1.6 revisar downloads, 1.7 limpar ajustes, 1.8 revisar README ("Não implementado" ainda está desatualizado até lá).


## Correções pedidas após a 1.2: logs, pasta de downloads e arquivos próprios

**Sobre o log que "não apareceu":** o arquivo fica na pasta de **dados do app** (`getApplicationSupportDirectory`; no Windows costuma ser algo como `C:\Users\<você>\AppData\Roaming\...`), **não** na pasta do programa — por isso não foi achado lá. Não verifiquei o caminho exato. Agora existe **Conta e ajustes → Registro de erros** com o caminho e o botão "Abrir pasta de logs". Se depois de um erro de download o arquivo continuar ausente, me avise: aí é bug do log, não de lugar.

**Escolher pasta de downloads** (`lib/core/system_dialogs.dart`, `downloads_settings_card.dart`): botão "Escolher pasta" ao lado de "Abrir pasta", usando o seletor nativo do Windows via PowerShell (sem pacote novo). "Digitar caminho" continua existindo. **Não verificado:** o diálogo abrir na frente da janela; PowerShell disponível/liberado na sua máquina.

**Reconhecer o que o app baixou** (`DownloadsController.reconcile`): quando um download concluído não está mais no caminho gravado (ex.: você mudou de pasta e moveu os arquivos), o app procura: (1) no mesmo desenho de pastas do app (`Filmes/`, `Séries/...`) dentro da pasta atual; (2) pelo nome do arquivo, **só na própria pasta**, ou também **nas subpastas** se "Procurar também nas subpastas" estiver ligado (ajuste `download_scan_subfolders`). Roda ao abrir o perfil, ao trocar de pasta, ao ligar a opção e pelo botão "Verificar arquivos". Escolha minha: o item (1) olha as pastas `Filmes`/`Séries` mesmo com a opção desligada, para não perder o que o próprio app organizou. Arquivos que não são downloads do app **não** aparecem na biblioteca.

**Adicionar arquivo à biblioteca** (`lib/library/library_import.dart`, `ui/library/import_editor.dart`): botão "Adicionar arquivo" em Minha biblioteca abre um editor (arquivo, título, ano, sinopse, pôster e banner por arquivo ou endereço). Os itens ficam na fileira **"Meus arquivos"**, só ali; editar/tirar da biblioteca ao passar o mouse (tirar **não** apaga o arquivo). Banco passou para a versão **6** (tabela `library_imports`; só adiciona, não altera nada existente). Ids de progresso são negativos para não colidir com o catálogo, e o "Continuar assistindo" ignora esses itens. Imagens locais agora funcionam em `PosterImage`/`ChainImage`.
**Não verificado:** reprodução desses arquivos no player (o player foi feito para itens do catálogo; usa o mesmo caminho dos downloads, que funciona), e o editor em janelas pequenas.

## Etapa 1.3: testes unitários + mover downloads da pasta anterior

**Testes** (`test/`, rodam com `flutter test`; nenhum precisa do app aberto nem de internet):
- `smart_search_test.dart`: normalização ("Homem-Aranha" → "homem aranha"), ordem das palavras, erro de digitação ("homen aranha", "te last of us"), nome junto/separado ("spiderman"), acentos, categorias ocultas, extras sob "relacionados", pontuação e limite.
- `catalog_parsing_test.dart`: filmes, séries, categorias, detalhes de filme e de série (episódios em mapa e em lista), nota (limite 10, zero ignorado, `rating_5based`), itens inválidos.
- `epg_parsing_test.dart`: base64 opcional, EPG do provedor, XMLTV (fuso, entidades, CDATA, filtro de canal e de janela de tempo).
- `format_test.dart`: duração, bytes, rótulos de dia/hora.

**Não verificado:** **não consegui rodar os testes** (não há Flutter nesta máquina); os resultados esperados foram calculados lendo o código. Se algum falhar, pode ser erro do teste e não do app — cole a saída. Os testes assumem que o pacote se chama `iptv_player` (`package:iptv_player/...`) e que `flutter_test` está nas dependências de desenvolvimento do seu `pubspec.yaml` (padrão de projetos novos).

**Mover downloads para a pasta atual** (`DownloadsController.moveToCurrentFolder`, card Downloads): quando há downloads concluídos fora da pasta atual (ex.: ficaram na anterior), aparece um aviso com o botão "Mover para a pasta atual". Mantém `Filmes/` e `Séries/<série>/Temporada NN/`; **nunca sobrescreve** (se já existe no destino, pula); tenta renomear (rápido) e, entre discos diferentes, copia, confere o tamanho e só então apaga a origem; apaga as pastas vazias do desenho do app deixadas para trás; mostra andamento "x de y" e um resumo (movidos/pulados/erros). Não roda com downloads em andamento. **Não verificado:** cópia entre discos com arquivos muito grandes (o andamento é por arquivo, não por bytes), nem arquivos abertos no player durante a mudança.

## Etapa 1.4: tela de diagnóstico

**No código:** `lib/ui/diagnostics_card.dart` (card em Conta e ajustes, depois de "Registro de erros") e `AppDatabase.diagnostics()` (só leitura). Botão "Verificar agora" mostra: caminho e tamanho do banco do perfil, versão do esquema (`PRAGMA user_version`), resultado do `quick_check`, última atualização do catálogo, contagens (canais, filmes, séries, itens com progresso, meus arquivos), estado dos downloads (total, concluídos, baixando, fila, pausados, com erro), conexões em uso pelos downloads, pasta de downloads e caminho/tamanho do log. "Copiar relatório" põe o texto na área de transferência. **Não mostra** servidor, usuário nem senha, mas inclui caminhos de pastas do seu Windows.

**Limites (confirmados no código):** "conexões em uso" conta só os downloads ativos; **não** inclui o player nem a TV ao vivo, porque o app não mede isso hoje. O `quick_check` roda no momento do clique e pode demorar em bancos grandes.
**Não verificado:** não compilei; o aspecto em janelas estreitas (os rótulos longos quebram de linha).

## Etapa 1.5: reparar histórico

**No código:** `AppDatabase.repairHistory` (`lib/data/db.dart`) e botão "Reparar histórico" no card Diagnóstico. O que faz, nesta ordem:
1. **Cópia de segurança** com `VACUUM INTO` → `<banco>.backup-<data>` ao lado do arquivo do perfil (guarda as 3 mais recentes).
2. `PRAGMA integrity_check` (só informa o resultado; não conserta o arquivo).
3. Numa transação, só na tabela `watch_progress`: posição ou duração negativa → 0; posição maior que a duração → posição = duração e marca como assistido; remove linhas de tipo desconhecido e episódios sem série.
4. Opcional (caixa de seleção, desligada): remove progresso de títulos que **não existem mais no catálogo** — só se a tabela do catálogo correspondente não estiver vazia, e nunca para arquivos importados (id negativo).
Depois atualiza o Início/Continuar assistindo e mostra um resumo (corrigidos / inválidos / órfãos). A operação é registrada no log.

**Escolhas minhas (podem ser ajustadas):** o que conta como "inválido"; manter as 3 últimas cópias; a opção de órfãos desligada por padrão (um título tirado e recolocado pelo provedor perderia o progresso).
**O que NÃO faz:** não repara um arquivo de banco corrompido (isso continua sendo tratado ao abrir: o arquivo ruim vira `.corrupt-<data>` e um banco novo é criado) nem restaura cópias automaticamente — para voltar uma cópia, feche o app e troque o arquivo manualmente (posso criar um botão de restaurar, se quiser).
**Não verificado:** não compilei nem testei em um banco real; `VACUUM INTO` depende da versão do SQLite embutida (aceito a partir da 3.27, que é anterior ao sqflite_ffi atual, mas não conferi a do seu build); sem testes automáticos para o reparo (precisariam do SQLite nativo no `flutter test`).

## Etapa 1.6: revisão dos downloads

**Revisado no código (`downloads_controller.dart`) e o que mudou:**
- **Mensagens de erro:** a queda de conexão chega como `http.ClientException` ("Connection closed while receiving data", visto no seu log) e aparecia crua. Agora: "A conexão com o servidor foi interrompida."; falha ao gravar (disco cheio/permissão, `FileSystemException`) mostra o motivo do Windows.
- **Nova tentativa automática:** em falha de **rede** (tempo esgotado, sem conexão, conexão interrompida, TLS, download incompleto), o item volta para a fila e tenta de novo, retomando de onde parou (cabeçalho `Range`), depois de 5 s, 15 s, 45 s e 90 s. A contagem recomeça se a tentativa baixou algo. A tela mostra "Conexão interrompida. Nova tentativa em Ns (x/4)…". Esgotadas as tentativas, vira "erro" e o botão de retomar continua funcionando. Respostas do servidor como 403/404 **não** são repetidas (repetir não resolve). Pausar ou cancelar durante a espera cancela as tentativas. As tentativas ficam no log (`AVISO downloads.novaTentativa`).
- Já estava correto (confirmado lendo): limite de 30 s para o servidor responder e de 60 s sem dados; um download por vez; `.part` retomável após fechar o app; servidor que ignora `Range` recomeça do zero.

**Riscos que encontrei e NÃO corrigi (precisam da sua decisão):**
1. Se o servidor não informa o tamanho (sem `Content-Length`), o app não consegue saber se o arquivo veio completo: uma conexão encerrada "normalmente" pode marcar como concluído um arquivo truncado.
2. Resposta 416 com `.part` maior que o arquivo real é tratada como "já tinha tudo" e finaliza.
3. Não há checagem de espaço livre em disco antes de começar (só o erro ao gravar).
4. O download não pausa sozinho quando você abre o player; em plano de 1 conexão isso pode derrubar um dos dois (o aviso existe na tela de ajustes).

**Não verificado:** não compilei nem testei com a rede caindo de verdade; os tempos de espera são escolha minha.

**Estado do plano:** 1.1–1.6 entregues (1.3–1.6 ainda não executadas por mim); próximas: 1.7 limpar ajustes sem uso, 1.8 revisar README.

## Etapa 1.6b — Riscos dos downloads

**Implementado no código (não compilado nem executado por mim):**
- **Tamanho desconhecido:** se o servidor não envia `Content-Length`, ao fim do download o app pergunta o tamanho real (requisição `Range: bytes=0-0`) e só marca como concluído se os bytes batem; se não der para conferir, conclui e registra um aviso no log.
- **Erro 416:** o app lê o tamanho real (`Content-Range` ou a sondagem). Se for igual ao `.part`, conclui; se o `.part` for maior/diferente, apaga e recomeça do zero (registrado no log).
- **Espaço em disco:** antes de baixar, mede o espaço livre via PowerShell (`core/disk_space.dart`); se faltar (arquivo + 50 MB de margem) o download falha com mensagem clara. Se a medição não funcionar (pasta de rede, sem PowerShell), não bloqueia.
- **Pausar ao assistir:** nova opção em Configurações › Downloads, "Pausar downloads enquanto assisto" (ligada por padrão). Ao abrir filme/série pela internet ou TV ao vivo, o download ativo pausa e retoma ao sair. Arquivos locais não pausam.

**Não verificado:** compilação, o script do PowerShell de espaço livre, se o seu provedor envia `Content-Range` e aceita `Range: bytes=0-0`, e o comportamento real em planos de 1 conexão.

**Estado do plano:** 1.1–1.6 + 1.6b feitos; próximo: 1.7 (aguarda "continuar").

## Etapa 1.7: limpeza de configurações sem uso

**Identificado no código (busca por todo o `lib/`):**
- `channels_compact` / `categories_compact` (e `channelsCompact`, `categoriesCompact`, `setChannelsCompact`, `setCategoriesCompact` no `AppController`) **não eram lidos por nenhuma tela**: sobras do layout antigo da TV ao vivo. **Removidos** do código.
- `stream_ext` e `user_agent` **têm interface** (Conta: seletor ts/m3u8 e campo de User-Agent) e o player de canais usa o formato. **Mantidos.**

**Dados antigos:** as duas chaves podem continuar gravadas no banco de quem já usou o app; ficam sem efeito e inofensivas (não apaguei, para não mexer no esquema).

**Não verificado:** compilação. Rode `flutter analyze`.

**Estado do plano:** 1.1–1.7 feitos; próximo: 1.8 (revisar o README, que ainda lista downloads/biblioteca/favoritos em "Não implementado") — aguarda "continuar".

## Etapa 1.8: revisão do README

**Feito:** corrigi o título, a "Situação real" (agora separa o relato seu do que é só do código), a nota sobre a versão do banco (6), o seletor de pasta de downloads, a menção aos ajustes removidos e a seção "Não implementado". As seções antigas 3B/3C/3D foram mantidas como histórico, não reescritas.

**Não verificado:** não reli cada frase antigas das seções 3B/3C/3D contra o código; podem restar detalhes defasados (por exemplo, descrições visuais do banner). Se notar algo que não bate com o app, me diga.

**Estado do plano:** Fase 1 (estabilidade) concluída. Próximo: Fase 2 (funcionalidades) — aguarda "continuar" e a escolha do item.

## Passo A (pós-1.8): busca em lista, PT/EN, desfoque e ícones dos canais

**No código:**
- **Busca do topo** (`ui/shell/search_overlay.dart`, `search_result_card.dart`): resultados em **grade de cartões horizontais 16:9** (imagem, título, tipo · ano, nota), do mais parecido ao menos, com botões **Todos / Filmes / Séries** (com contagem). Abaixo, "Também pode interessar" com **Filmes relacionados / Séries relacionadas** no formato de fileira de antes (só os da aba escolhida). A fileira "Mais parecidos" deixou de existir: a própria lista já vem ordenada por semelhança. A busca da aba Catálogo **não mudou** (continua grade de pôsteres).
- **Imagem horizontal nos resultados:** a lista do servidor só traz o pôster; a imagem horizontal vem dos detalhes, pedida só para os cartões que aparecem na tela (máx. 3 pedidos ao mesmo tempo, guardados em memória). Enquanto não chega, ou se o título não tiver, o cartão mostra o pôster nítido sobre o pôster desfocado.
- **Português ↔ inglês** (`catalog/title_dictionary.dart`, `SmartSearch.runBilingual`): a busca roda o que você digitou e a tradução **palavra por palavra** por um dicionário local de 232 pares de palavras comuns ("o último de nós" → "last us" → acha "The Last of Us"). O resultado literal sempre vem na frente (a tradução vale 0,97 da nota). Vale para a busca do topo e para a da aba Catálogo.
- **Desfoque** (`SoftBlurBackdrop` em `poster_image.dart`): antes era uma miniatura de 40 px esticada (daí os "pixels"). Agora é a miniatura (96 px) ampliada com filtro suave + desfoque real (sigma 14) dentro de `RepaintBoundary`. Usado nos banners do Início, na tela expandida e nos cartões da busca. Para mudar a força, o parâmetro `sigma` (0 desliga o desfoque).
- **Ícone dos canais** (`channel_card.dart`): cartão 252×96 (antes 232×84); o logo agora ocupa a altura toda e **encosta na borda esquerda, no topo e embaixo**, com os cantos recortados pelo cartão.
- Testes novos em `test/smart_search_test.dart` (grupo "runBilingual").

**Não implementado (diferente do que combinamos):** "títulos originais". A lista do Xtream não traz o nome original; ele só aparece nos detalhes de cada título, então não há como usá-lo na busca sem baixar os detalhes de todo o catálogo. Fica como possibilidade futura (guardar o nome original no banco quando um título for aberto).

**Inferido / não verificado (nada foi compilado nem rodado):** se o desfoque novo mantém a fluidez dos banners (o desfoque real é caro; está em `RepaintBoundary` para ser desenhado uma vez, mas não medi — se travar, use `sigma: 0` ou me avise); se o dicionário cobre os títulos do seu catálogo (é uma lista curta, escrita à mão); se o provedor entrega imagem horizontal para a maioria dos resultados; o visual da grade em janelas estreitas; quantos pedidos de detalhes a rolagem rápida gera.

**Estado:** Passo A feito. Próximo: Passo B (banners de destaque da TV ao vivo com palavras-chave editáveis) — aguarda "continuar" e perguntas finais.

## Passo B: banners de destaque na TV ao vivo

**No código:**
- `data/live_highlight.dart` (`computeHighlights`): para cada palavra-chave, na ordem, junta as categorias **visíveis** cujo nome contém a palavra (sem acento, sem diferenciar maiúsculas) e os canais delas. Uma categoria só entra no primeiro destaque que a achar; destaque sem canal não aparece; **máximo de 4 banners**; até 60 canais por banner.
- `ui/live_tv/live_highlight_banner.dart`: banner no topo da TV ao vivo (altura 280, cantos arredondados). Um slide por palavra-chave, com setas, pílulas de navegação, e troca com fade. Em cada slide: "DESTAQUE", a palavra em letras grandes, quantidade de canais e categorias, botão **Assistir** (abre o primeiro canal com a lista do destaque) e **Ver categoria** (só quando a palavra casou com uma única categoria). No canto inferior direito, carrossel de canais (logo + nome): **5 por vez** em janela larga (≥1000 px), 4 (≥780) ou 3; as duas pontas ficam a 45% de opacidade quando há mais canais do que cabem; setas rolam de 1 em 1 (dá a volta). Clicar abre o player.
- **Fundo:** gradiente na cor de destaque do perfil (os canais não trazem imagem de fundo), como você escolheu.
- **Palavras-chave editáveis:** Conta e ajustes → card "Catálogo de TV ao vivo" → "Destaques da TV ao vivo" (lista separada por vírgula, "Salvar destaques" e "Restaurar padrão"). Padrão: Esportes, Notícias, Filmes, Séries, Infantil, Documentários. Salvo no perfil (ajuste `live_highlight_keywords`); lista vazia = sem banners.
- O banner some quando há texto na busca de canais e na tela "Ver tudo" de uma categoria. A lista de fileiras passou a usar `CustomScrollView` (banner + fileiras de altura fixa).
- Testes: `test/live_highlight_test.dart`.

**Decisões minhas (você não especificou; me corrija):** sem troca automática de slide (só manual); o filtro é "o nome da categoria **contém** a palavra"; um banner por palavra (não por categoria); categorias ocultas não entram; as pílulas ficam no topo do banner.

**Inferido / não verificado (nada foi compilado nem rodado):** se os nomes das categorias do seu provedor contêm essas palavras (provedores variam, por exemplo "SPORTS" em inglês: nesse caso edite as palavras); o visual do banner e do carrossel em janelas estreitas (os textos da esquerda podem ficar apertados); desempenho de rolagem com o banner no topo.

**Estado:** Passo B feito. Próximo: Fase 2 (favoritos de filmes/séries etc.) — aguarda "continuar".

**Correção do Passo B:** o `flutter analyze` apontou erro em `categories_pane.dart` e `channels_pane.dart`. Esses arquivos **não estão mais no zip** (foram removidos na troca do layout da TV ao vivo); eles sobraram na sua pasta por cópia por cima. Apague-os (e `player_pane.dart`, se existir) em `lib\ui\live_tv\`, ou apague a `lib\` inteira antes de copiar. O outro erro (lista `const []` sem tipo em `live_tv_page.dart`) foi corrigido no código.

## Ajustes do Passo B (após ver a tela)

**No código:**
- **Nome do canal do meio:** no banner, acima do carrossel, aparece o nome do cartão central (o que fica no meio dos visíveis) e muda ao rolar; fica sobre o degradê escuro do banner.
- **"Ver todos" no banner:** com uma única categoria, abre a categoria em grade; com várias (ex.: Esportes + PPV | Esportes), vira um menu para escolher qual categoria abrir.
- **Palavras padrão:** `Eventos` e `Destaque` agora vêm **antes** de Esportes (padrão: Eventos, Destaque, Esportes, Notícias, Filmes, Séries, Infantil, Documentários; só 4 banners aparecem). "Eventos em Destaque" cai em "Eventos". **Quem já salvou as próprias palavras em Conta e ajustes não é alterado** — use "Restaurar padrão" para pegar a nova lista.
- **Cartões de canal:** o nome ficou centralizado na vertical em relação ao logo (continua alinhado à esquerda; até 3 linhas).
- **Barra lateral:** Filmes e séries agora usa o ícone de rolo de filme (`local_movies`) e Minha biblioteca o de pasta com estrela (`folder_special`); Início e TV ao vivo não mudaram.

**Interpretações minhas (me corrija):** "texto mais centralizado" entendi como centralizado na vertical; se quiser também no centro horizontal, me diga. Os ícones são do conjunto Material do Flutter; não vi como ficam na barra.

**Não verificado:** compilação.

## Rodada pós-Passo B: mini banners, favoritos, busca, rolagem, banner do Início

**No código:**
- **Mini banners na TV ao vivo** (`live_highlight_banner.dart`, `data/live_highlight.dart`): abaixo do banner principal, **4 mini banners** (altura 92) por aba (tracinho) do banner principal; a fileira troca junto com a aba. A **aba 1 vem com as palavras HBO, Premiere, SporTV e Telecine** (as categorias do seu provedor que contêm essa palavra); as outras abas vêm vazias, com "Adicionar categoria". Mini banner preenchido: nome, quantidade de canais e até 3 logos; **clicar abre a categoria em grade** (se a palavra casar com várias categorias, abre um menu para escolher). Vazio: abre uma janela com filtro para escolher uma categoria. O "x" (com o mouse em cima) esvazia o espaço. Salvo no perfil (`live_mini_banners`, JSON). Netflix foi trocado por Telecine (você disse que Netflix não é categoria; **Telecine é palavra minha**, edite se preferir: hoje só dá para trocar escolhendo outra categoria no "+" depois de remover).
- **Favorito na TV ao vivo** (`channel_card.dart`): cartão favoritado ganha borda na cor do perfil, fundo levemente tingido e nome na cor do perfil (o coração já era).
- **Busca do topo** (`search_overlay.dart`): aba **Todos**: resultados, depois "Também pode interessar" (filmes e séries relacionados). Aba **Filmes**: filmes relacionados primeiro, depois "Resultados". Aba **Séries**: séries relacionadas primeiro, depois "Resultados". Os relacionados **nunca repetem** o que está nos resultados.
- **Rolagem do Catálogo voltando ao topo** (`catalog_page.dart`): **causa provável encontrada no código** (não medida): quando outra página era descartada, o cache de fileiras era limpo; na reconstrução seguinte do Catálogo as consultas viravam novas, a tela ficava vazia por um instante, a lista era recriada e a rolagem voltava ao topo. Agora a tela mantém os dados que já tinha enquanto recarrega.
- **Erro "BOTTOM OVERFLOWED BY 17 PIXELS" no banner do Início** (`hero_carousel.dart`): ocorria no slide "Adicionados recentemente", em que os três botões não cabiam numa linha e o texto ficava mais alto que o banner. O bloco de texto agora **reduz de tamanho** se não couber (`FittedBox`).
- **Filmes novos / Séries novas** (`catalog_controller.dart`): os 3 títulos agora são **sorteados entre os 100 mais recentes** (com imagem), como você escolheu; o sorteio é **fixo enquanto o app estiver aberto** e muda na próxima abertura. O slide "Adicionados recentemente" usa os mais recentes que não foram sorteados.
- Testes novos em `test/live_highlight_test.dart` (mini banners).

**Não verificado (nada foi compilado nem rodado):** se a correção da rolagem resolve de fato (era a causa mais provável que achei, mas pode haver outra; se continuar, me diga em que fileira e depois de quanto tempo); se o banner do Início deixou de estourar em todas as janelas; o visual dos mini banners (logos, gradiente, janela estreita); se categorias com "HBO", "Premiere", "SporTV" ou "Telecine" existem no seu provedor (se não, os espaços aparecem vazios).

**Limitações:** os mini banners só aparecem junto do banner principal (que só existe quando alguma palavra-chave de destaque casa com categorias); se só houver 1 aba, só existe a fileira da aba 1.

## Fase 2.1: favoritos de filmes e séries

**No código:**
- **Banco versão 7:** nova tabela `favorite_titles` (tipo, id do título, data). Só acrescenta; nada existente é alterado. Guarda apenas a referência; os dados vêm do catálogo (título que o provedor remover some da lista de favoritos, mas a marca continua gravada).
- **Coração nos cartões** (`ui/catalog/favorite_button.dart`): aparece ao passar o mouse nos pôsteres (fileiras, grades) e nos cartões da busca; **se o título já é favorito, o coração fica sempre visível**, preenchido na cor do perfil (decisão minha). Só o coração é redesenhado quando os favoritos mudam.
- **Detalhes:** botão de coração no painel lateral (ao lado de "expandir") e botão "Favoritar / Nos favoritos" na tela expandida, abaixo das ações.
- **Aba "Favoritos" na barra lateral** (`ui/favorites/favorites_page.dart`), entre "Filmes e séries" e "Minha biblioteca": grade de pôsteres com abas Todos / Filmes / Séries. Em "Todos": filmes primeiro, depois séries (cada grupo do mais recente ao mais antigo; **não misturei por data**). Tirar o coração tira da lista.
- **Atenção a índices:** a barra lateral agora tem 6 páginas (Início 0, TV ao vivo 1, Filmes e séries 2, **Favoritos 3**, Minha biblioteca 4, Conta 5); os botões "abrir biblioteca" dos detalhes e o atalho da conta foram ajustados.

**Não verificado (nada foi compilado nem rodado):** a migração para a versão 7 no seu banco (cria uma tabela; o app faz uma verificação de integridade ao abrir); o visual do coração sobre os pôsteres; o ícone de coração na barra lateral.

**Fora desta etapa:** favoritos na tela Início; "Minha biblioteca" (arquivos importados) não tem favoritos.

**Estado:** Fase 2.1 feita. Restam na Fase 2: histórico completo, legendas externas, instalador `.exe`.

## Fase 2.2: histórico completo (dentro de Minha biblioteca)

**No código:**
- **Onde:** em Minha biblioteca, duas abas: **Arquivos** (o que já existia) e **Histórico** (`ui/library/history_view.dart`).
- **Dados:** vêm da tabela `watch_progress` que já existia (sem mudança de banco). Ela guarda **uma linha por filme/episódio, com a última posição e a data da última vez**. Por isso o histórico mostra **só a última vez de cada um**, não um registro de cada sessão (isso exigiria uma tabela nova; não existe).
- **Lista:** agrupada por **Hoje, Ontem, Esta semana (menos de 7 dias), Este mês (menos de 30 dias), Mais antigos**; cada linha com pôster, título, episódio (ex.: "T1 · E1 — …"), tipo, status (Assistido / % assistido), data e hora e barra de progresso. Até 1000 itens. Entram filmes e episódios do catálogo com posição maior que zero ou marcados como assistidos.
- **Ações:** clicar abre os detalhes (de lá: Continuar, Do início/reassistir; para episódios abre a série); menu "⋮": abrir, **marcar como assistido / não assistido**, **remover do histórico** (apaga o progresso daquele item, então ele sai também do "Continuar assistindo"). Botão **Limpar histórico** (com confirmação) apaga o progresso de todos os filmes e episódios do catálogo; **não** apaga downloads, favoritos nem arquivos importados.
- **Fora do histórico:** arquivos importados por você (progresso deles aparece no cartão da própria biblioteca). Escolhi assim para não precisar tocar o arquivo daqui; me diga se quiser incluí-los.
- **Não incluí** (você não escolheu): abas Filmes/Séries e busca no histórico.

**Não verificado (nada foi compilado nem rodado):** o visual; o comportamento ao marcar como assistido a partir do histórico (usei uma atualização direta no banco: assistido zera a posição, não assistido mantém a posição já salva); se o título de um episódio sempre abre a série certa (usa `series_id` gravado; episódios assistidos antes de essa informação existir podem abrir o item errado ou nada).

**Estado:** Fase 2.2 feita. Restam: legendas externas e instalador `.exe`.

## Fase 2.3: legenda externa (filmes e séries)

**No código:** no player de filmes e séries (`ui/catalog/vod_player_page.dart`), o menu de áudio e legendas (ícone de legendas) ganhou **"Carregar legenda de um arquivo…"**. Abre o seletor de arquivos do Windows (mesmo mecanismo da pasta de downloads, via PowerShell; filtro `.srt .ass .ssa .vtt .sub`), carrega o arquivo pelo player (`SubtitleTrack.uri` do media_kit) e já ativa a legenda. A legenda carregada passa a aparecer na lista de legendas do próprio menu, pelo nome do arquivo. Erros vão para o registro de erros (`legenda`).

**O que não faz:** a legenda vale só para aquela reprodução (não é lembrada para a próxima vez); não busca legendas na internet; não procura sozinha um arquivo de legenda ao lado do vídeo; não há ajuste de atraso/tamanho/cor; não existe no player da TV ao vivo.

**Não verificado (nada foi compilado nem rodado):** (1) se o seu `media_kit` aceita um caminho local do Windows em `SubtitleTrack.uri` (a documentação do pacote mostra exemplo com URL; caminho local deveria funcionar via libmpv, mas não testei); (2) **acentos**: arquivos `.srt` em codificação antiga (Windows-1252) podem mostrar caracteres trocados se a libmpv do seu build não detectar a codificação sozinha; (3) o seletor de arquivos com o player em tela cheia; (4) o aviso de erro quando a legenda é inválida (o libmpv pode aceitar o arquivo sem avisar).

**Se a legenda não aparecer:** me diga o formato do arquivo e o conteúdo do `logs/app.log` (Conta e ajustes → Registro de erros).

**Estado:** Fase 2.3 feita. Resta: instalador `.exe`.

## Fase 2.4: instalador (Inno Setup)

**No código/arquivos:** pasta `installer\` com `iptv_player.iss` (script do Inno Setup) e `COMO_GERAR.md` (passo a passo). Não altera o app. O script embala a pasta `build\windows\x64\runner\Release` (gerada por `flutter build windows --release`) num `Setup.exe` que instala **só para o usuário atual** (sem pedir administrador), cria atalho no menu Iniciar e (opcional) na Área de Trabalho, tem desinstalador e usa o assistente em português do Brasil.

**Por que Inno Setup (e não MSIX):** gera um `.exe` comum, gratuito, sem certificado nem Microsoft Store. MSIX exigiria certificado e alteraria o seu `pubspec.yaml`.

**Inferido / não verificado (não gerei nem testei o instalador):** o nome do executável (`iptv_player.exe`, deduzido do nome do pacote; confira em `Release\`); a versão (`1.0.0`, ajuste); se o arquivo de idioma `BrazilianPortuguese.isl` vem na sua instalação do Inno Setup (normalmente sim; se der erro, troque a linha `[Languages]`); se as DLLs do player entram na pasta `Release` (o script copia tudo que houver lá); se o Windows pede o Visual C++ Redistributable em máquinas limpas.

**Fora do escopo:** assinatura digital (SmartScreen pode avisar), atualização automática, ícone próprio do instalador.

**Estado:** Fase 2 concluída (favoritos, histórico, legenda externa, instalador). Fase 3 (otimização medida) ainda não iniciada: exige que você meça com `flutter run --profile` e o DevTools.

## Rodada de ajustes (player, cartões de episódio, mini banners, busca)

**No código:**
- **Marcar como assistido automático** (`vod_player_page.dart`): faltando **2 min em episódios** e **10 min em filmes** (em vídeo curto, no máximo 25% do tempo) o item é marcado como assistido. A posição onde você parou **continua salva**; ela só volta ao início se o vídeo for assistido **até o fim**. Isto vale também para "Marcar como assistido" manual (detalhes e histórico), que antes zerava a posição, e `canResume` agora não depende mais de "assistido". Substitui a regra antiga de 92%.
- **Painel "Próximo episódio":** aparece faltando 2 min (só se houver próximo episódio) e fica aberto **13 s**; mexer o mouse reinicia essa espera. Depois vira uma **aba com seta (→)** na borda direita (*atualização: a aba fica no canto inferior direito durante o resto do episódio e **sobe** quando a interface aparece, para não ficar sobre os controles; o painel grande não reabre*); com o mouse em cima mostra o texto "Próximo episódio" mantendo a seta; clicar vai ao próximo. O botão de minimizar (>) do painel faz o mesmo. Quando o episódio **acaba**, o painel volta com contagem de **8 s** (botões "Assistir agora" e "Cancelar") e avança sozinho.
- **Cartões de episódio** (`title_details_page.dart`): assistidos ficam **mais escuros** (imagem e título) com o **ícone de assistido sempre visível** (no canto); com o mouse em cima, voltam os botões de baixar e de marcar/desmarcar.
- **Barra de rolagem** ao lado da sinopse na tela expandida: removida (o texto ainda rola com a roda do mouse).
- **Mini banners da TV ao vivo:** a cor de cada um segue o degradê do banner principal (1º azul, depois mais escuros). Os quadrados vazios de logos que não carregam não aparecem mais.
- **Busca:** enquanto a imagem horizontal carrega, o cartão tem **só um fundo liso** (sem pôster nem desfoque). Se o título não tiver imagem horizontal, o pôster aparece nítido no centro **só depois** de a consulta terminar.

**Interpretações minhas (me corrija):** o painel do "Próximo episódio" **não reabre** quando o mouse se mexe depois de minimizado (só a aba); o ícone de assistido no cartão fica sempre visível **só nos assistidos**.

**Não verificado (nada foi compilado nem rodado):** o comportamento do painel e da marcação num episódio real; se a retomada de itens "assistidos" aparece como esperado nos detalhes (agora mostram "Continuar" quando há posição salva); o visual dos cartões escurecidos.

## Fase 3.1: otimização da busca (foco escolhido por você)

**No código (hipóteses vindas da leitura do código; nada foi medido):**
- **Busca em isolate** (`catalog/search_worker.dart`): normalizar os nomes e comparar a digitação com todos os títulos rodava na própria interface (e agora roda duas vezes: original + tradução PT/EN, para filmes e séries). O índice é enviado uma vez ao isolate e cada busca manda só o texto. Se o isolate falhar, o app volta ao caminho antigo e registra no log (`busca.isolate`).
- **Normalização de texto** (`foldText`): antes criava uma string por letra e a normalização era feita **duas vezes** por título ao montar o índice; agora letras ASCII são copiadas direto e `joined` só é calculado quando usado.
- **Tela de resultados** (`search_overlay.dart`): listas de cada aba e fileiras de relacionados são montadas **uma vez por resultado** (antes eram recriadas a cada rebuild, o que fazia as fileiras piscarem/recarregarem); ao digitar, os resultados anteriores ficam na tela até os novos chegarem (com um indicador pequeno), e respostas antigas são descartadas.
- **Cartões** (`search_result_card.dart`): a imagem horizontal só é pedida se o cartão ficar na tela por 350 ms (rolagem rápida não gera dezenas de pedidos); sem pôster desfocado de fundo; `addAutomaticKeepAlives: false` na grade.

**Não verificado (nada foi compilado nem rodado):** se o ganho é perceptível (preciso que você meça ou me diga o que ainda trava); a troca de dados com o isolate; se o primeiro carregamento do índice ainda tem uma pausa (agora ela acontece no isolate, não na interface).

**Como medir (se ainda travar):** `flutter run --profile -d windows`, abrir o DevTools > Performance, digitar na busca e anotar quadros em vermelho; me mande o que a aba mostrar (qual widget/tempo).

## Rodada: busca global com canais, favoritos de canais, card expandido

**No código (identificado):**
- **Campos de busca removidos:** "Buscar canal" na TV ao vivo (`live_tv_page.dart`; o banner de destaques agora aparece sempre) e "Buscar filmes/Buscar séries" em Filmes e séries (`catalog_page.dart`; a grade de resultados dessa aba foi removida). A busca agora é **só a do topo**.
- **Busca do topo com canais** (`search_overlay.dart`, `app_controller.dart > searchChannels`): nova aba **Canais** (Todos · Filmes · Séries · Canais, com contagem). Em **Todos** aparecem os filmes/séries e, abaixo, uma seção "CANAIS" com até 12 cartões e o botão "Ver todos" (abre a aba Canais). A busca de canais exige **todas as palavras** no nome (sem acento/maiúscula); quem começa com a primeira palavra vem antes; limite de 300; só canais de categorias visíveis. **Não usa** o dicionário PT/EN nem tolera erro de digitação (isso é só para filmes/séries). Clicar num canal abre o player ao vivo (lista = resultados). Dica do campo: "Buscar filmes, séries e canais…".
- **Favoritos** (`favorites_page.dart`): nova aba **Canais** (cartões iguais aos da TV ao vivo). Em **Todos**: filmes e séries, depois os canais. O coração do cartão remove o canal da lista. Contador do título virou "N itens".
- **Card expandido do filme** (`title_details_page.dart`, `download_button.dart`): **Baixar** virou botão só de ícone + texto (sem borda) no **canto superior direito**; ordem dos botões: **Assistir, (Do início), Favoritar, Marcar como assistido**. Na **série**, o Favoritar continua abaixo dos botões como antes.
- **Série:** **desvanecer escuro** no lado direito (340 px, de transparente a ~88% preto), atrás da lista de temporadas e sem capturar cliques.
- **Imagens horizontais da busca mais rápidas:** o endereço da imagem horizontal de cada título agora é **guardado no banco** (nova tabela `backdrop_cache`, **banco versão 8**) sempre que os detalhes chegam; na próxima busca o cartão mostra a imagem **na hora**, sem pedir ao provedor. Para os títulos ainda desconhecidos: os 12 primeiros resultados têm os detalhes pedidos assim que a busca termina (máx. 3 por vez, como antes) e a espera por cartão caiu de 350 para 150 ms.

**Inferido / não verificado (nada foi compilado nem rodado):** que a lentidão vinha da espera pelos detalhes no provedor (é a causa que o código sugere; não medi); o ganho real (a **primeira** busca de cada título continua dependendo do provedor; as seguintes devem ser instantâneas); a migração do banco 7 → 8 (só cria uma tabela nova); o visual do fade, do botão Baixar no canto e da seção de canais; se o botão Baixar no canto superior direito não fica por baixo de algum elemento da barra de título.

**Ideia da mensagem "degrade":** não entendi se era um pedido; **não implementei nada com essa palavra** além do fade da série. Se era outro degradê (ex.: nos cartões da busca), me diga onde.

**Não implementado (só discutido):** gravação de TV ao vivo e as outras sugestões da resposta.

## Rodada: aba padrão da busca, fila de imagens, pausa durante reprodução

**No código (identificado):**
- **Aba inicial da busca** (`search_overlay.dart`, `catalog_controller.dart > activeKind`, `catalog_page.dart`): a busca abre em **Canais** quando você está em TV ao vivo; em **Filmes** ou **Séries** quando está em Filmes e séries (a aba aberta lá); em **Todos** nas outras telas (Início, Favoritos, Minha biblioteca, Conta). Vale só na hora em que a busca abre; depois você troca livremente.
- **Série:** o botão **Favoritar** ficou ao lado de Assistir (mesma linha de botões).
- **Fila de imagens horizontais da busca** (`catalog_controller.dart`): o pedido de detalhes agora tem **prioridade e cancelamento**. Cartões da busca passam na frente dos banners; um pedido que ainda não começou e cujo cartão saiu da tela (ou veio outra busca) é **cancelado**. Antes, a fila (3 por vez) ficava cheia de pedidos de buscas antigas e dos banners, por isso as imagens só apareciam depois de rolar. Causa **inferida do código**, não medida.
- **Pausa em segundo plano durante a reprodução:** enquanto a **TV ao vivo** ou um **filme/série pela internet** está aberto, a fila de detalhes **não inicia pedidos novos** (retoma ao fechar o player) e a atualização automática da lista de filmes/séries também não começa. Os **downloads** já eram pausados durante a reprodução (isso já existia). Arquivo local (baixado/importado) não aciona a pausa porque não usa internet.

**O que continua rodando durante a reprodução (identificado):** a programação (EPG) do canal que você está vendo e o próprio vídeo. Não há outros temporizadores de rede no código além desses; o carrossel do Início para sozinho porque a tela fica por baixo do player (comportamento do Flutter, não testado).

**Não verificado (nada foi compilado nem rodado):** a fila (ordem e cancelamento), se as imagens passam a aparecer sem rolar, a aba inicial em cada tela, e quanto de internet isso realmente economiza (não medi).

**Banners do Início:** a regra dos 3 "Continue de onde parou" (posições 4 e 5) foi **desfeita** porque eu tinha interpretado errado o pedido. Os banners voltaram à versão anterior (Continue, Filmes novos, Séries novas, Adicionados recentemente, Animações). O problema real (o "Continue de onde parou" aparecendo também nos banners menores da direita) ainda **não foi corrigido**: aguardando esclarecimento.

## Rodada: banners laterais, gerenciador de banners, gravação de TV, ícone

**No código (identificado):**
- **Banners menores à direita** (`hero_carousel.dart`, `catalog_controller.dart > relatedTo`): o de **cima** mostra o slide **atual + 2** (o próximo, +1, continua acessível pela seta do banner grande; com só 2 slides mostra o outro). O de **baixo** mostra um título **relacionado** ao do banner grande (mesma categoria, com imagem, diferente dele; a escolha é fixa para cada título) e **clicar abre o card expandido** desse título. Sem relacionado disponível, o espaço fica vazio.
- **Gerenciador de banners** (`ui/home/banner_manager_dialog.dart`, `catalog/home_banners.dart`; botão em *Conta → Banners do Início*, que **substitui** o antigo cartão "Banner Animações"): o 1º banner ("Continue de onde parou") é **fixo**; até **4 extras** (5 no total) com **nome editável**, ordem (subir/descer), remover, e fonte: Filmes novos, Séries novas, Novos (mistura), Continue assistindo (do 2º em diante), **Categorias** (3 sorteados das categorias marcadas) ou **Títulos escolhidos** (busca e marca até 6). Salvo no banco do perfil (ajuste `home_banners`, JSON). Na 1ª vez vem o padrão antigo (Filmes novos, Séries novas, Adicionados recentemente e, se você tinha categorias de Animações marcadas, Animações com elas). Banner sem títulos disponíveis simplesmente não aparece. "Restaurar padrão" volta a isso.
- **Gravação da TV ao vivo** (`playback_controller.dart`, `player_controls.dart`): botão vermelho na barra do player (também em tela cheia) → **gravar / pausar-continuar / parar** com o tempo gravado (e marcador "REC mm:ss" sempre visível no canto do vídeo). Usa a propriedade `stream-record` do libmpv e grava o fluxo **sem converter**, em arquivo `.ts`, na **mesma pasta dos downloads** (nome: `Canal - AAAA-MM-DD HH-mm.ts`). Recusa gravar com menos de 1 GB livre (quando o espaço consegue ser lido). **Pausar** fecha o arquivo e **continuar** abre outro (` (2)`, ` (3)`…), porque o libmpv não tem pausa de gravação. Trocar de canal, sair do player ou reconexão automática encerra o arquivo atual (na reconexão abre um novo segmento).
- **Ícone:** novo desenho minimalista (quadrado escuro, borda e "play" arredondado em vermelho) em `extras/app_icon.ico` e `extras/app_icon_preview.png`. **Dentro do programa** o logo da barra lateral usa o mesmo desenho na **cor de destaque do perfil**. O ícone do `.exe`/atalho/barra de tarefas é **fixo** (não muda com o perfil; o Windows não permite sem código nativo, que não fiz).

**O que você precisa fazer para o ícone do .exe:** copie `extras/app_icon.ico` por cima de `windows/runner/resources/app_icon.ico` do **seu** projeto (essa pasta não vai no zip) e recompile.

**Inferido / não verificado (nada foi compilado nem rodado):**
- Se o `stream-record` grava de fato o seu provedor: funciona bem com fluxo contínuo (MPEG-TS); com **HLS (.m3u8)** pode não gravar ou gerar arquivo vazio. Teste gravando ~30 s e abrindo o arquivo.
- Se o arquivo `.ts` gravado aparece em "Minha biblioteca" (depende de como ela lista extensões; não conferi).
- Gravar assistindo usa **a mesma conexão** do player (não abre uma segunda), mas a gravação **não** continua se você sair do canal ou fechar o player.
- A pausa em segundo plano de rede durante a reprodução **não** afeta a gravação (ela faz parte do fluxo do player).
- Visual dos banners menores, do gerenciador e do botão de gravação.
- A `analyze` pode apontar detalhes (ex.: `Random(_heroSeed + hashCode)`, uso de `NativePlayer` do media_kit na sua versão).

## Rodada: nome "Cubos" e logo de três cubos

**No código (identificado):**
- O nome do programa é **Cubos**: janela (`main.dart`, `app.dart`), barra lateral (`shell.dart`, "CUBOS") e instalador (`installer/iptv_player.iss`, `MyAppName`).
- A barra lateral usa o logo novo, `lib/ui/widgets/cubos_logo.dart` (`CubosLogo`): três cubos isométricos desenhados à mão com `CustomPainter`, nas cores fixas do ícone (não mudam com a cor do perfil).
- O ícone do programa é `extras/app_icon.ico` (fundo transparente), com a prévia em `extras/app_icon_preview.png`. Os três cubos são o desenho escolhido; as outras duas variações (`canto` e `play` no topo) ficaram só na conversa e não estão no projeto.

**Mantido de propósito:** a pasta padrão de downloads continua `Downloads\IPTV Player`, para não mudar o caminho de quem já baixou.

**Para aplicar o ícone do .exe:** copie `extras/app_icon.ico` por cima de `windows/runner/resources/app_icon.ico` do seu projeto e recompile. O nome do `.exe` e do pacote Flutter não foram alterados.

**Não verificado:** nada foi compilado nem rodado. Não verifiquei se "Cubos" já é usado como marca ou app. O logo na barra lateral foi desenhado por código e pode precisar de ajuste de tamanho. O ícone não foi visto em 16 px no Windows.

## Rodada: cubos com a cor do perfil, gravação refeita, sem "Continuar assistindo" no catálogo

**No código (identificado):**
- **Cubos com a cor do perfil** (`ui/widgets/cubos_logo.dart`): face de cima mais clara, lateral esquerda na cor de destaque, direita mais escura. Vale só **dentro do programa**; o ícone do `.exe` continua fixo.
- **"Continuar assistindo" removido** das abas Filmes e Séries (`catalog_page.dart`); ficam "Adicionados recentemente" e as categorias. Ele continua no Início (banner) e em Minha biblioteca.
- **Gravação refeita.** Você relatou que a gravação aparecia como ativa mas **não gerava arquivo**: o método anterior (propriedade `stream-record` do libmpv) não funcionou no seu caso; a causa exata **não foi investigada** (não consigo rodar o app). Agora a gravação usa uma **conexão HTTP própria** (`playback_controller.dart`): baixa o mesmo link do canal (se o formato do link for `.m3u8`, troca para `.ts`) direto para um arquivo `.ts` na pasta de downloads. Ao **parar**, o arquivo é **adicionado a Minha biblioteca → Arquivos** (título "Canal — gravação dd/mm hh:mm") e a mensagem mostra o caminho; se nada foi gravado, avisa. Se a conexão cair, tenta abrir outro arquivo em 2 s; se não conseguir, fica pausada com um aviso no marcador "REC".

**Pontos de atenção (inferidos, não testados):**
- É uma **segunda conexão** com o provedor (uma para assistir, outra para gravar). Se o seu plano permite só 1, o servidor pode recusar (a mensagem cita HTTP e o limite de conexões) ou derrubar o vídeo.
- O servidor precisa aceitar o link `.ts` do canal; se aceitar só `.m3u8`, a gravação falha (HLS não é suportado por esse método).
- Nada foi compilado nem rodado aqui. Teste gravando ~30 s e conferindo a pasta e a biblioteca.

**Banner menor de baixo no "Continue de onde parou":** quando o banner grande é o "Continue de onde parou", o menor de baixo mostra **outro título em andamento** (o mais recente que não seja o do banner grande) com o texto "Clique aqui para assistir"; clicar **retoma a reprodução** direto. Nos demais slides continua o título relacionado, que abre o card expandido. Se só houver um título em andamento, o espaço de baixo fica vazio. Não compilado nem rodado.

## Rodada: biblioteca com gravações, capa, abertura configurável (build 6A)

> Tudo abaixo foi **escrito mas não compilado nem executado** (sem Flutter no ambiente de desenvolvimento). Rode `flutter analyze` e teste.

**Identificado no código (implementado nesta rodada):**
- **Minha biblioteca**: gravações de TV ao vivo ficam numa seção própria (`library_imports.kind = 'recording'`). Banco passou para a **versão 9** (migração adiciona a coluna `kind`).
- **Remover item**: diálogo com *Cancelar / Tirar / Apagar arquivo*; "Apagar arquivo" pede uma segunda confirmação e, em gravações, apaga também a capa `.jpg`.
- **Capa da gravação**: frame aleatório (10–90 % do vídeo) via `video_thumb.dart` (`Player.screenshot`), gerado após parar a gravação. *Não verificado* que o `screenshot` funciona no seu ambiente.
- **Abrir arquivo da biblioteca**: Conta e ajustes → Reprodução → *Reproduzir / Card / Card expandido* (títulos baixados). Importados e gravações sempre tocam direto.
- **Série (card expandido)**: botões de texto "Marcar todos como assistidos" / "Desmarcar todos como assistido" abaixo de Assistir/Favoritos.
- **Banner de TV ao vivo**: "Ver todos" abre diálogo no estilo do programa (substitui o menu popup).
- **Gerenciar categorias**: na primeira abertura de cada tela (TV ao vivo, Filmes, Séries) o botão mostra ícone + "Desabilitar categorias"; depois só o ícone (configuração `hints_seen`).
- Dica no card "continue assistindo": banner menor de baixo mostra outro título.

**Ainda não feito (planejado):** renomear para "Lumios Play", instruções de instalação/atualização, formato dos botões, redesenho de Conta e ajustes, edição das credenciais Xtream, instalador próprio, atualizador, segurança.


## Rodada: MIP (MyIptvPlayer), botões, Conta e ajustes, atualizador, instalador, segurança (build 6B)

> **Tudo escrito sem compilar nem executar** (sem Dart/Flutter no ambiente do assistente). Rode `flutter analyze` e `flutter test`. Itens marcados *não verificado* dependem de teste no seu Windows.

### Nome
- Nome do programa: **MIP** (curto) / **MyIptvPlayer** (por extenso), em `lib/core/app_info.dart` (`AppInfo`). Usado no título da janela, barra lateral, tela de abertura, instalador. Os cubos continuam como logo.
- **Decisão minha (não confirmada):** você escreveu "deixe o nome como MIP, MyIptvPlayer"; usei MIP na interface e MyIptvPlayer onde cabe o nome completo.
- A pasta padrão de downloads passou de `IPTV Player` para `MyIptvPlayer` (só vale para quem não escolheu pasta própria; arquivos já gravados em `IPTV Player` não são movidos).
- O pacote Dart continua `iptv_player` (é o `name:` do seu pubspec, que não alterei) e o executável continua `iptv_player.exe` — o instalador usa esse nome (`appExe` em `installer_app/lib/main.dart`).

### Botões
- Padrão novo: **cantos quadrados** em todo o programa (tema global em `core/theme.dart`, `AppShape`). Em **Conta e ajustes → Personalização → Formato dos botões** dá para escolher quadrados ou arredondados (salvo por perfil, configuração `button_shape`).
- Cobre botões Filled/Elevated/Outlined/Text, SegmentedButton e os botões grandes do banner/card expandido. Botões de ícone redondos, chips e caixas de diálogo mantêm o formato próprio (*não verificado* se algum botão com `shape` fixo ficou de fora).

### Conta e ajustes
- Agora com três abas: **Conta** (perfil, Conta Xtream, sair), **Configurações** (TV ao vivo, filmes/séries, reprodução, EPG, atualizações, downloads, logs, diagnóstico) e **Personalização** (tema, formato dos botões, banners do Início, destaques da TV ao vivo).
- **Conta Xtream**: mostra status/expiração/conexões e permite **ver e editar servidor, usuário e senha** (olho para mostrar a senha). "Salvar e testar" autentica no servidor antes de gravar. Trocar só a senha mantém o catálogo; trocar servidor ou usuário pede confirmação e baixa tudo de novo (igual a novo login).

### Como instalar pela primeira vez
Duas formas (ambas *não testadas*):
1. **Instalador MIP** (visual do programa, feito em Flutter — pasta `installer_app/`):
   - No seu projeto: `.\installer_app\tools\montar_instalador.ps1 -Versao 1.0.0 -UrlBase https://seusite.com/mip`.
   - O script compila o MIP, compacta, embute no instalador e compila o instalador. Saída em `release\`: `MIP-Instalador-1.0.0.zip` (a pasta do instalador — o `.exe` precisa dos arquivos ao lado dele; **não é um .exe único**) e `MIP-1.0.0.zip` + `latest.json` (para o atualizador).
   - Para o usuário: extrair `MIP-Instalador-*.zip`, abrir `mip_setup.exe`, seguir as telas. Instala em `%LOCALAPPDATA%\Programs\MIP` sem pedir administrador, cria atalhos e registra em "Aplicativos instalados". Desinstalar: pelo Windows (roda `desinstalar.ps1`).
   - Limitações conhecidas: janela com a barra padrão do Windows (para tamanho menor edite `installer_app/windows/runner/main.cpp`, p. ex. `Size(780, 480)`); a pasta `installer_app/windows/` (runner) não vem no zip: rode `flutter create --platforms=windows .` dentro de `installer_app` uma vez.
2. **Inno Setup** (o que já funcionou): `installer/COMO_GERAR.md`; o script agora usa o nome MIP.
3. **Sem instalar**: copiar a pasta `Release` e abrir `iptv_player.exe`.

### Como atualizar
- **Automático (atualizador próprio):** a cada abertura o app mostra uma tela de carregamento "Procurando atualizações…" (até 6 s) e, se houver versão nova, um aviso no **canto inferior esquerdo** com *Atualizar agora* / *Depois*. Ao atualizar: baixa o zip (somente **https**), confere o **SHA-256** do manifesto, fecha o app, troca os arquivos e reabre. Usa PowerShell + `Expand-Archive` do Windows (*não verificado*).
- **Precisa de um endereço público (https) com o `latest.json`:** `{ "version": "1.0.1", "url": "https://.../MIP-1.0.1.zip", "sha256": "<hash>", "notes": "..." }`. Você ainda **não tem hospedagem**; até configurar, o atualizador fica desligado. Informe o endereço em Conta e ajustes → Configurações → Atualizações (ou em `AppInfo.defaultManifestUrl` antes de compilar). Opções gratuitas comuns: GitHub Releases/Pages, Cloudflare Pages, Netlify — posso preparar o passo a passo quando você escolher.
- A versão do programa vem de `AppInfo.version` (mantenha igual à `version:` do pubspec).
- **Manual:** substituir a pasta do programa pela nova (ou rodar o novo instalador). Perfis, banco e ajustes ficam em `%APPDATA%` e são mantidos.

### Segurança (o que foi feito de verdade)
- **Senha Xtream protegida** com a DPAPI do Windows (`core/secret_store.dart`, via `dart:ffi`, sem pacote extra): gravada como `dpapi:<base64>` no banco; só o mesmo usuário do Windows nesse PC decifra. Senhas antigas em texto simples migram sozinhas no próximo início. Se a DPAPI falhar, cai para texto simples e registra aviso no log. *Não verificado em execução.*
- **Atualizações**: só https e só com SHA-256 igual ao do manifesto; manifesto inválido é rejeitado (há testes em `test/update_test.dart`).
- **Logs**: já mascaravam usuário/senha em links e parâmetros (`AppLog.scrub`) — nada mudou, e a senha não é exibida na tela sem clicar no olho.
- **Não feito / limites:** servidores IPTV costumam ser `http://` (sem criptografia) e o app não pode forçar https; o `latest.json` não é assinado digitalmente (o hash protege contra download corrompido, não contra quem controla o seu host); os downloads/gravações em arquivo não são criptografados; o `.exe` não é assinado (o Windows SmartScreen pode avisar).

### Publicação pelo GitHub (build 6D)
- Guia em `GITHUB.md`: dois repositórios (código **privado** + `mip-releases` **público** só com instalador/atualização), porque o atualizador não faz login e repositório privado não pode ser baixado por amigos sem conta. *Escrito sem testar no seu GitHub.*
- `montar_instalador.ps1` agora recebe `-Repo usuario/mip-releases` e `-Publicar` (usa `gh release create`).
- O atualizador agora **espelha** a versão nova na pasta do programa (`robocopy /MIR`): copia o que mudou e apaga arquivos que não existem mais; remove o zip/pasta temporários. Mantém `desinstalar.ps1`. *Não verificado em execução.*

### Um só repositório (build 6F)
Decisão do usuário: **um único repositório público** (`gbrlinsk3/MyIptvPLayer`) com código e Releases. `defaultManifestUrl` aponta para ele e o script é chamado com `-Repo gbrlinsk3/MyIptvPLayer`. Consequência: o código-fonte fica visível para qualquer pessoa. Não coloque senhas, links de provedores ou dados pessoais nos arquivos do repositório.

### Correções após o primeiro teste real (build 6G)
Relatado por você: (1) instalador falhava ao criar o atalho da área de trabalho; (2) "Instalar e reiniciar" fechava o app, não reabria e não aplicava a atualização; (3) na tela de criar perfil os botões da janela ficavam inutilizáveis.
- **Atalho:** o instalador usava `%USERPROFILE%\Desktop`, que não existe quando a área de trabalho está no OneDrive. Agora pergunta ao Windows o caminho real (`GetFolderPath`) para Desktop e Menu Iniciar. *Causa inferida* pela mensagem de erro (DirectoryNotFound); não confirmei se a sua Desktop está no OneDrive.
- **Atualizador:** **a causa da falha não foi identificada** (não tenho como executar). Reescrevi o script: escreve `logs/atualizacao.log` e `update_result.txt`, só passa a copiar depois de conferir o zip, **reabre o programa mesmo se der erro**, e mostra "A última atualização falhou: …" no aviso e em Configurações → Atualizações. Se falhar de novo, mande o conteúdo de `%APPDATA%\...\logs\atualizacao.log` (botão "Abrir pasta de logs" em Configurações).
- **Botões da janela:** uma cópia de minimizar/maximizar/fechar fica por cima de tudo (inclusive diálogos); some em tela cheia. *Não verificado visualmente.*

### Volta ao Inno Setup, como instalador e atualizador (build 6H)
Após o teste do build 6G: o instalador em Flutter ainda falhava no atalho e o atualizador por PowerShell fechava o app sem aplicar a atualização (nem reabrir). Por pedido do usuário, **voltamos ao Inno Setup**.
- **Causa do erro do atalho (identificada pela captura de tela):** o caminho "Área de Trabalho" chegou corrompido ("Ç?rea de Trabalho") ao passar texto entre o instalador e o PowerShell. O Inno não usa esse caminho.
- **A pasta `installer_app/` foi removida** (e o `analysis_options` não precisa mais excluí-la). Apague-a do seu projeto também.
- **Novo fluxo:** `installer/montar_instalador.ps1` compila o MIP, roda o Inno (`ISCC`), gera `release\MIP-Setup-<versão>.exe` + `latest.json` (com SHA-256 do `.exe`) e, com `-Publicar`, cria a Release no GitHub. Confere se `AppInfo.version` bate com `-Versao` antes de publicar.
  `powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao 1.0.3 -Repo gbrlinsk3/MyIptvPLayer -Notas "O que mudou" -Publicar`
- **Atualizador:** baixa o `MIP-Setup-<versão>.exe`, confere o SHA-256, e ao clicar *Instalar e reiniciar* roda o instalador em modo silencioso (`/SILENT /CLOSEAPPLICATIONS`) e fecha o app. O instalador apaga os arquivos antigos da pasta do programa (`[InstallDelete]`), copia os novos e reabre o MIP (`[Run]` com `Check: WizardSilent`). *Não verificado em execução.*
- **Instalação nova:** seus amigos baixam o `MIP-Setup-<versão>.exe` na Release e executam (um único arquivo). O visual é o do assistente do Inno com o ícone do MIP; um assistente 100% com o visual do programa não está mais no projeto.
- A instalação feita antes pelo instalador em Flutter fica em `%LOCALAPPDATA%\Programs\MIP`, a mesma pasta padrão do Inno; instale o novo por cima ou desinstale o antigo em "Aplicativos instalados" antes.

### Build 7A — bugs, Início, Conta e ajustes
Feito pelo Claude Code **com compilação**: `flutter analyze` sem avisos e `flutter test` passando (2 testes novos em `test/theme_pref_test.dart`, só do cálculo do tema). **Nada disso foi visto rodando no app** (não há conta Xtream no ambiente do Claude Code); confira na tela.

**Já existia no código e foi só ajustado** (identificado ao ler o código, não reescrevi): o gerenciador de banners (`ui/home/banner_manager_dialog.dart`), os padrões *Filmes novos / Séries novas / Adicionados recentemente* (`BannerConfig.defaults`, que usa a fonte `newMix` "Novos (filmes e séries)" — continua uma suposição minha que é isso que você chamou de "Adicionados recentemente") e o slide "Continue de onde parou" só entrando quando há algo em andamento.

**Início — banners**
- Sempre há ao menos 1 banner: "Remover" fica desativado no último e, se a lista salva vier vazia/inválida, valem os padrões. "Continue de onde parou" não conta no limite (agora de 1 a 4 banners; antes o texto falava em "5 de 5").
- Setas do banner grande só aparecem com mais de um banner.
- Banner menor de cima: saiu o "+ N títulos"; mostra os nomes dos outros títulos do banner, separados por " · " (até 2 linhas).
- Troca automática: a cada 12 s passa ao **próximo título do banner** e, depois do último, ao próximo banner. Interpretei "intervalo atual 12 s" como 12 s **por título** (um banner de 3 títulos leva 36 s; para mudar, `_interval` em `hero_carousel.dart`). A pílula do indicador agora enche ao longo dos títulos do banner; clicar numa miniatura reinicia a contagem; trocar de banner volta ao 1º título. Os detalhes de todos os títulos dos banners são pré-carregados para a troca não esperar.

**Início — Continuar assistindo**
- Bug do cartão que "voltava a ficar pequeno": ao abrir o card/player por cima, o mouse "saía" da fileira e o primeiro cartão reabria expandido. Agora o cartão clicado fica expandido enquanto o card/player está aberto (`_pinned` em `continue_strip.dart`). *Causa inferida do comportamento do `MouseRegion`; não vi o bug rodando.*
- Clicar no cartão (filme ou série) abre o **card expandido** (`showTitleDetailsPage`); clicar na chamada abre o **player** (`resumeTitle` em `play_actions.dart`). A chamada passou de "CLIQUE AQUI PARA ASSISTIR" para "CLIQUE AQUI PARA CONTINUAR ASSISTINDO", como você escreveu (reduz a fonte se não couber).
- Série cujo último episódio terminou mostra o **próximo episódio** (ex.: T1 · E8) em vez de sumir; só some quando não há próximo. Para achar o próximo é preciso baixar os detalhes da série (cache por título, espera de até 8 s; sem rede, a série fica de fora naquele carregamento). Série com episódio em andamento continua voltando nele. Se o último episódio terminado tem outro mais antigo em andamento, vale o **mais recente** dos dois. Consulta nova: `CatalogStore.seriesActivity` (SQL conferido à parte no SQLite). O banner grande "Continue de onde parou" usa a mesma lista.
- O botão "Continuar" do banner grande não mudou (série ainda abre o card lateral).
- Card de série (lateral e expandido) abre na **temporada do último episódio assistido ou começado** (`lastEpisodeSeason`). Se o último foi o final de uma temporada, abre nela mesma (não na seguinte).

**Tema** (`core/theme.dart`: `ThemePref`, `resolveDark`)
- Claro, Escuro, **Sistema** (segue o Windows; era o antigo "Automático", o valor salvo `system` continua valendo) e **Automático** (claro das 9h às 17h, escuro das 17h às 9h, hora do computador; confere a cada 30 s e só reconstrói se mudar). O botão do menu do perfil continua alternando claro/escuro.

**Conta e ajustes**
- Configurações na ordem: Atualizações, Reprodução, Downloads, EPG, Diagnóstico, **Catálogo**.
- **Catálogo** (`ui/catalog_settings_card.dart`) une "Catálogo de TV ao vivo" e "Filmes e séries": resumo dos três e chips *TV ao vivo / Filmes / Séries* + **Atualizar selecionados**. Decisão minha: "Limpar cache" ficou em dois botões (TV; filmes e séries juntos, porque o código só limpa os dois de uma vez).
- Removido o botão "Abrir TV ao vivo".
- "Ao clicar num título baixado" foi para **Personalização → Minha biblioteca**; o padrão agora é **Card** (`panel`). Quem nunca mexeu passa a ver o Card; quem já tinha salvo outro valor mantém.
- **Registro de erros** saiu da interface (apaguei `ui/logs_settings_card.dart`); o arquivo de log continua sendo gravado por `AppLog`.

**Não feito nesta rodada:** 7B (tamanho da interface, largura do catálogo, proporções) e 7C (botão "Detalhes" do aviso de atualização, animação de abertura do perfil). Não subi versão (`AppInfo.version` e `pubspec.yaml` intactos) nem gerei instalador.


### Build 7B — tamanho da interface, largura do catálogo e proporções
Feito pelo Claude Code **com compilação**: `flutter analyze` sem avisos e `flutter test` com 14 testes passando (6 de tamanho/colunas em `test/layout_metrics_test.dart`, 6 da ampliação em `test/ui_scale_test.dart`, 2 do tema). **Nada disso foi visto rodando no app** (sem conta Xtream no ambiente do Claude Code, e não consigo capturar a tela): confira visualmente, principalmente os tamanhos dos cartões do "Continuar assistindo".

**Decisões suas (perguntei antes de implementar)**
- Os "horizontais" são os cartões do **Continuar assistindo**; mantém **1 cartão expandido + os demais recolhidos** e o número conta todos (expandido incluído).
- Com largura fixa, o **banner do Início também** fica na coluna centralizada (em "Preenchido" continua de borda a borda).
- **Mesma quantidade por linha em qualquer janela**: o pôster se ajusta à largura (em 1080p a 100 % os pôsteres ficam menores que os de 1440p).
- Os px da largura (1200/1440/1600) são **pixels lógicos**: crescem com o tamanho da interface (a 115 %, 1440 ocupa ~1656 px na tela).

**Tamanho da interface — 100/115/130/150 % (padrão 115 %)** (`ui/widgets/ui_scale.dart`, `app.dart`)
- **Validação da ideia do plano:** `Transform.scale` solto com um tamanho lógico menor **não serve** como está: o `RenderTransform` só aceita toque dentro do próprio tamanho (reduzido), então só o canto superior esquerdo responderia — *raciocínio meu, não testei essa variante*. Usei `FittedBox(fit: fill)` com um `SizedBox` do tamanho lógico (janela ÷ escala): o `RenderFittedBox` ocupa a janela toda e converte as coordenadas no teste de acerto. **Testado em widget** (`ui_scale_test.dart`, 1,5×): toque acerta só na posição ampliada (inclusive longe do canto), hover (`MouseRegion`) acompanha, campo de texto recebe foco e texto, diálogo abre ampliado e centralizado, `MediaQuery` do filho informa o tamanho lógico, e **trocar a escala em execução não recria o app** (estado preservado: a árvore não muda nem em 100 %).
- Fica por fora do `MaterialApp.builder`: telas, diálogos, menus, **barra de título, botões da janela e aviso de atualização** ampliam juntos. Nada no código usa tamanho físico da janela (conferido por busca).
- Ajuste **por perfil** (`ui_scale` no banco do perfil), em Conta e ajustes → Personalização → "Tamanho da interface". **O padrão 115 % vale para todos os perfis**, também os que nunca mexeram (é a mudança visível ao atualizar). A tela "Quem está assistindo?" e o login ficam em 100 % (ainda não há perfil/ajuste). Valor salvo inválido volta para 115 %.
- **Não verificado em execução:** nitidez de imagens ampliadas (elas são decodificadas no tamanho lógico, então a 150 % ficam um pouco menos nítidas), vídeo (textura do `media_kit`) e janela de sugestões do teclado/IME sob ampliação; custo de desempenho (é uma única camada de transformação, sem `saveLayer`, mas não medi).

**Largura do catálogo — 1200 / 1440 / 1600 px ou Preenchido (padrão)** (`ui/widgets/content_frame.dart`, `ui/shell.dart`)
- Uma coluna centralizada envolve toda a área abaixo da barra do topo: Início, TV ao vivo, Catálogo, Favoritos, Minha biblioteca, Conta e ajustes e a busca. Em "Preenchido" nada é limitado (a margem de 24 px das fileiras é a de sempre — não criei margem maior).
- Efeitos colaterais da coluna: a barra de rolagem e a rolagem do mouse ficam dentro da coluna (não na borda da janela); o banner do Início arredonda os cantos externos (22 px) quando está na coluna estreita, e fica reto de borda a borda em "Preenchido". Ajuste em Personalização → "Largura do catálogo". Se a janela for mais estreita que a largura escolhida, vale a janela.

**Pôsteres por linha** (`core/layout_metrics.dart`: `RowMetrics`)
- Verticais (fileiras e grades "Ver tudo"/favoritos): **12 / 11 / 11 / 9** para 100 / 115 / 130 / 150 %. Horizontais (Continuar assistindo, 1 expandido incluído): **6 / 6 / 5 / 4**. Os números são seus (2560×1440, Windows a 100 %); o teste confere que no monitor de referência cabem exatamente essa quantidade e o seguinte começa fora da fileira (sem "fatia" aparecendo).
- Resultado no monitor de referência (largura lógica = 2560 ÷ escala − 68 do trilho): pôster vertical ≈ 192 / 207 / 204 / 248 px **na tela** (lógico 192 / 180 / 157 / 165); cartão do Continuar assistindo recolhido ≈ 330×440 / 327×435 / 377×503 / 446×594 px na tela (expandido 2,27× mais largo). **Esses cartões ficam bem maiores que os de hoje (150×200) e maiores que os pôsteres verticais**: é o que "6 horizontais, 1 expandido incluído" resulta; se estiver grande demais, ajuste `expandedRatio`/`heightRatio` em `RowMetrics` ou me diga o que prefere.
- Piso: pôster vertical ≥ 110 px e cartão recolhido ≥ 150 px (em janela muito estreita a fileira volta a rolar em vez de encolher mais). A grade ("Ver tudo") reduz as colunas pelo mesmo piso.
- **Não alterado:** os cartões 16:9 dos resultados da busca (`search_overlay.dart`) e as grades de canais seguem a lógica própria deles; as fileiras de pôsteres dentro da busca já usam a nova regra.

**Banner do Início em telas altas** (`HeroMetrics` + `hero_carousel.dart`)
- Altura = 40 % da altura útil (janela − 64 da barra do topo), entre 440 e 640. Em 1080p dá 440 (**igual a antes**); em 1440p maximizado a 100 % ≈ 530 px. A largura máxima dos banners da direita sobe de 420 para `420 + 1,2 × (altura − 440)` (≈ 530 px em 1440p/100 %) e passou a 30 % da largura (antes 27 %): o banner grande fica mais alto e mais estreito (≈ 1950×530 contra 2060×440). Valores escolhidos por mim a partir de "mais alto e menos comprido"; sem ver o resultado, ajuste os fatores em `HeroMetrics` se precisar.

**Não feito:** 7C (botão "Detalhes" do aviso de atualização e animação de abertura do perfil). Versão (`AppInfo.version`/`pubspec.yaml`) intacta; nenhum instalador gerado.

**Versão 1.0.3:** publicada como Release com os builds 7A e 7B.
