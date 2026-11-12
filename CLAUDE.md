# MIP (MyIptvPlayer) — contexto para o Claude Code

Player IPTV (Xtream Codes) para Windows em Flutter. Repositório: https://github.com/gbrlinsk3/MyIptvPLayer (público, código + Releases).
Responder sempre em **português**. O Claude Code local pode compilar e rodar (`flutter analyze`, `flutter test`, `flutter run -d windows`), ao contrário do assistente anterior, que **nunca compilou nada** — tudo abaixo foi escrito sem execução, exceto o que o usuário confirmou testando.

## Regras do usuário (literais)
"Não invente informações sobre o projeto. Não considere funcionalidades planejadas como funcionalidades já implementadas. Diferencie claramente o que foi identificado no código daquilo que foi apenas inferido. Não crie documentação genérica que não corresponda ao projeto real. Pergunte se necessario, gosto de ajudar na montagem de interface."
- Sempre atualizar o `README.md` a cada rodada de mudanças.
- Nunca afirmar que o usuário escreveu algo que ele não escreveu (já reclamou disso).
- Fazer perguntas quando houver ambiguidade em itens grandes.

## Stack e arquitetura (identificado no código)
- Flutter Windows desktop; `media_kit`/libmpv; SQLite via `sqflite_common_ffi`, um banco por perfil, esquema **v9** (`lib/data/db.dart`).
- Estado: `ChangeNotifier` + `InheritedNotifier` (`AppScope.read/of`). `AppController` (`lib/state/app_controller.dart`, configurações via `_db.getSetting/setSetting`), `CatalogController`, `DownloadsController`, `ImportsController`, `PlaybackController`.
- Tema: `lib/core/theme.dart` (`AppColors`, `AppFonts`, `AppShape` = formato dos botões, padrão quadrado). Nome/versão: `lib/core/app_info.dart` (`AppInfo.version` deve bater com `version:` do pubspec).
- Barra de título própria (`lib/ui/window/title_bar.dart`); `WindowButtonsOverlay` fica por cima de diálogos (em `app.dart`).
- Senha Xtream protegida com DPAPI via `dart:ffi` (`lib/core/secret_store.dart`), **sem testar em execução** até onde sei.
- Atualizador: `lib/update/` (manifesto `latest.json` por HTTPS, SHA-256, roda o instalador Inno em `/SILENT`). **Confirmado pelo usuário: funciona** (fecha, instala, reabre) e o instalador cria atalho.
- Instalador: Inno Setup (`installer/iptv_player.iss`) + `installer/montar_instalador.ps1`:
  `powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao X.Y.Z -Repo gbrlinsk3/MyIptvPLayer -Notas "..." -Publicar`
  (confere `AppInfo.version`; precisa de Flutter, Inno Setup 6 e `gh`). Dados do usuário ficam em `%APPDATA%`, fora da pasta do programa.
- O pacote Dart se chama `iptv_player` (pubspec do usuário); `AppInfo.name` = "MIP".

## Fluxo do usuário
Ele mantém o próprio `pubspec.yaml`/runner. Antes, o assistente entregava zips (`lib`, `assets`, `extras`, `test`, `installer`, README) e ele copiava por cima. Com o Claude Code, editar o projeto direto.

## Plano pendente (pedido do usuário, ainda NÃO implementado)
**7A — bugs, Início, Conta e ajustes**
- Banners do Início pré-definidos: Filmes novos, Séries novas, "Adicionados recentemente" (assumido = `BannerSource.newMix` "Novos (filmes e séries)"; não confirmado). Mínimo 1 banner; usuário pode remover/editar. Setas só com >1 banner.
- Slide fixo "Continue de onde parou": entra na lista só se ativo (há conteúdo em andamento), não removível, não conta para o mínimo.
- Banner menor de cima (direita): remover "+ N títulos"; mostrar os nomes dos outros títulos do banner (hoje em `hero_carousel.dart` ~linha 787).
- Transição automática: passar pelos 3 títulos de cada banner antes do próximo (intervalo atual 12 s).
- Continuar assistindo (Início): bug — ao clicar num item horizontal o card abre mas o item clicado volta a ficar pequeno e o primeiro fica expandido; clicar em filme/série abre o card expandido; clicar em "Clique aqui para continuar assistindo" abre o player; série com episódio terminado deve mostrar o próximo (T1 E8) em vez de sumir.
- Card de série abre na temporada do último episódio assistido.
- Tema: Claro, Escuro, Sistema, Automático (claro 9h–17h, escuro 17h–9h).
- Conta e ajustes: unir painéis "Catálogo de TV ao vivo" e "Filmes e séries" (usuário escolhe o que atualizar); remover botão "Abrir TV ao vivo"; mover "Ao clicar num título baixado" para Personalização com padrão "Card" (`libraryOpenMode` 'panel'); remover Registro de erros da interface (arquivo continua sendo gravado); ordem dos painéis em Configurações: Atualizações, Reprodução, Downloads, EPG, Diagnóstico, Catálogo (TV ao vivo/filmes/séries).

**7B — tamanho e proporções**
- Tamanho da interface 100/115/130/150 % (padrão 115 %; 100 % = o atual). Ideia: `Transform.scale` com `SizedBox` de tamanho lógico reduzido (hit-test ok) — validar.
- Largura do catálogo: 1200 / 1440 / 1600 px ou preenchido (padrão; centralizado só nas opções fixas; "preenchido" com margem leve). Vale para todas as telas de conteúdo.
- Em 1440p/Windows 100 %: banner grande mais alto e menos comprido; banners da direita maiores.
- Posters por linha (monitor 2560×1440, Windows 100 %, preenchido): 100 % → 12 verticais/6 horizontais; 115 % → 11/6; 130 % → 11/5; 150 % → 9/4. Números dados pelo usuário; não seguem proporção exata — ajustar tamanho do poster.

**7C — atualizador e animação**
- Botão "Detalhes" no aviso de atualização com novidades, melhorias de design e correções. Fonte: `notas\<versão>.md` (seções Novos recursos / Melhorias de design / Correções) lido pelo script e colocado no `latest.json`.
- Animação estilo Netflix após escolher o perfil: 4 cubos (3 aparentes) lado a lado, depois "dash" até formar o logo, então abre o app. **Pergunta em aberto:** onde fica o 4º cubo e o que é o "dash" (contorno sendo desenhado ou deslize rápido). Sugerido: ~2,5 s, pulável com clique, opção para desligar.

## Pendências/riscos conhecidos
- Gravação de TV (HTTP próprio `.ts`), capa aleatória de gravação (`Player.screenshot`) e migração do banco 8→9 nunca foram confirmadas pelo usuário em uso real.
- Pasta padrão de downloads mudou de `IPTV Player` para `MyIptvPlayer` (arquivos antigos não são movidos).
- Instalação anterior feita por um instalador Flutter descartado pode ficar em `%LOCALAPPDATA%\Programs\MIP` (mesma pasta do Inno).
