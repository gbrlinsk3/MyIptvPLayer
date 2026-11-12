; Script do Inno Setup para gerar o instalador (Setup.exe) do MIP (MyIptvPlayer).
; Passo a passo: installer\COMO_GERAR.md
; Não testado por quem escreveu (Claude não roda Windows nem Flutter).

#define MyAppName "MIP"
; Troque a versão a cada lançamento.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
; Nome do executável gerado pelo Flutter (em build\windows\x64\runner\Release).
; Confira o nome real nessa pasta; se for outro, mude aqui.
#define MyAppExe "iptv_player.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; Identifica o app para atualizações/desinstalação. Não mude depois de lançar.
AppId={{07813E83-8935-4E3C-ABF6-6BE0BE47C440}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Instala só para o usuário atual: não pede senha de administrador.
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=MIP-Setup-{#MyAppVersion}
#if FileExists(AddBackslash(SourcePath) + "..\extras\app_icon.ico")
SetupIconFile=..\extras\app_icon.ico
#elif FileExists(AddBackslash(SourcePath) + "..\windows\runner\resources\app_icon.ico")
SetupIconFile=..\windows\runner\resources\app_icon.ico
#endif
CloseApplications=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExe}

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na Área de Trabalho"; GroupDescription: "Atalhos:"

[Files]
; Copia TUDO da pasta Release (o .exe, as DLLs, incluindo a do player, e a pasta data).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[InstallDelete]
; Apaga os arquivos da versão anterior antes de copiar os novos, assim nada
; "inútil" sobra na pasta do programa. Perfis, banco e ajustes ficam em
; %APPDATA% (fora desta pasta) e não são tocados.
Type: filesandordirs; Name: "{app}\*"

[Run]
; Instalação normal: caixa "Abrir o MIP" no fim do assistente.
Filename: "{app}\{#MyAppExe}"; Description: "Abrir o {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Atualização automática (silenciosa): reabre o programa sozinho.
Filename: "{app}\{#MyAppExe}"; Flags: nowait; Check: WizardSilent
