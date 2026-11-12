# Como gerar o instalador (Setup.exe)

Ferramenta escolhida: **Inno Setup** (gratuita). Ela pega a pasta que o Flutter gera
e embala tudo num único `Setup.exe` com assistente de instalação, atalhos e desinstalador.

## Uma vez só
1. Baixe e instale o Inno Setup 6 em https://jrsoftware.org/isinfo.php (instalação padrão).
2. Copie a pasta `installer\` deste zip para a raiz do seu projeto (ao lado de `lib\`).

## Cada vez que quiser gerar um instalador
1. No terminal, na raiz do projeto: `flutter build windows --release`
   (cria `build\windows\x64\runner\Release\` com o app e suas DLLs).
2. Confira nessa pasta o nome do `.exe`. Se não for `iptv_player.exe`, edite a linha
   `#define MyAppExe` em `installer\iptv_player.iss`.
3. (Opcional) Mude `#define MyAppVersion` para a versão nova.
4. Abra `installer\iptv_player.iss` no Inno Setup e clique em **Build > Compile** (ou Ctrl+F9).
5. O instalador aparece em `installer\output\IPTV-Player-Setup-<versão>.exe`.

## Teste antes de distribuir
- Instale em outro usuário/computador (ou uma máquina virtual) e confira que o app abre,
  que o player de vídeo funciona e que o desinstalador remove o programa.

## Importante
- **Dados do usuário não são removidos ao desinstalar:** perfis, bancos, registros e
  configurações ficam em `AppData` (de propósito, para não perder o histórico).
- O instalador **não é assinado**: o Windows SmartScreen pode avisar "editor desconhecido".
  Assinar exige um certificado de código (pago); não faz parte desta etapa.
- Computadores sem o "Visual C++ Redistributable" podem não abrir apps Flutter. O instalador
  **não** o inclui. Se isso aparecer no seu teste, me avise.
