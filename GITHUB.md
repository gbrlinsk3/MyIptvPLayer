# Publicar o MIP no GitHub (para seus amigos instalarem e atualizarem)

> Passo a passo escrito sem testar (o assistente não acessa o seu GitHub). Os nomes de menus do GitHub podem variar um pouco.

## Por que dois repositórios
- Um repositório **privado** não pode ser baixado por quem não tem login/permissão nele, e o atualizador do app não faz login (embutir uma chave de acesso no programa a daria a qualquer um que tenha o .exe).
- Solução: **dois repositórios**.
  1. `mip` — **privado**: o código-fonte (`lib/`, `installer_app/`, README...). Só você vê.
  2. `mip-releases` — **público**, quase vazio: guarda só os arquivos prontos (instalador e atualização) e uma página de informações. Quem tem o link baixa; ninguém vê seu código.
- Limite honesto: "público" significa que qualquer pessoa que achar o endereço consegue baixar o instalador. Não aparece em buscas se você não divulgar, mas não é secreto. Como o programa não traz conteúdo/credenciais IPTV (cada pessoa usa a própria conta), o risco é baixo; ainda assim, não coloque nada pessoal lá.

## 1) Criar conta e repositórios
1. Crie uma conta em github.com (grátis).
2. **New repository** → nome `mip` → **Private** → Create.
3. **New repository** → nome `mip-releases` → **Public** → marque "Add a README" → Create.

## 2) Enviar o código para o repositório privado
Instale o Git e o GitHub CLI (`winget install Git.Git GitHub.cli`), feche e abra o terminal, e na pasta do projeto:
```
gh auth login
git init
git add .
git commit -m "MIP"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/mip.git
git push -u origin main
```
Antes, crie um arquivo `.gitignore` com pelo menos `build/`, `.dart_tool/`, `release/` e `installer_app/assets/payload.zip` (arquivos grandes gerados).

## 3) Página de informações (no repositório público)
Edite o README do `mip-releases` com: o que é o MIP, como instalar (baixar `MIP-Instalador-X.zip`, extrair, abrir `mip_setup.exe`), e que o programa se atualiza sozinho. O texto de "Como instalar" do README deste projeto pode ser copiado.

## 4) Apontar o programa para as atualizações
Em `lib/core/app_info.dart` troque:
```dart
static const defaultManifestUrl =
    'https://github.com/SEU_USUARIO/mip-releases/releases/latest/download/latest.json';
```
Assim o programa já nasce configurado e seus amigos não precisam digitar nada. (O endereço `releases/latest/download/<arquivo>` sempre aponta para a Release mais recente.)

## 5) Publicar uma versão
1. Aumente a versão em `AppInfo.version` **e** no `pubspec.yaml` (e `appVersion` em `installer_app/lib/main.dart`).
2. Na pasta do projeto, no PowerShell:
```
.\installer_app\tools\montar_instalador.ps1 -Versao 1.0.1 -Repo SEU_USUARIO/mip-releases -Notas "O que mudou" -Publicar
```
Ele compila, gera o zip + hash, o instalador e o `latest.json`, e cria a Release `v1.0.1` no `mip-releases` com os 3 arquivos. Sem `-Publicar`, ele só gera tudo em `release\` e você anexa manualmente em **Releases → Draft a new release**.

## 6) O que seus amigos fazem
- **Primeira vez:** baixam `MIP-Instalador-X.zip` na página Releases do `mip-releases`, extraem e abrem `mip_setup.exe`.
- **Depois:** só abrir o MIP. Ele procura atualização ao abrir; se houver, aparece o aviso no canto inferior esquerdo → *Atualizar agora* → baixa, confere o hash, fecha, troca os arquivos, **apaga os que a versão nova não usa mais** e reabre. Perfis e biblioteca ficam em `%APPDATA%` e não são tocados.

## Observação
O primeiro `latest.json` só existe depois da primeira Release. Antes disso o app mostra "Não foi possível procurar atualização" (só no log; a tela de abertura segue normalmente).
