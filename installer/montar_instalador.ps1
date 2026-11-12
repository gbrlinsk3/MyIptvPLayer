# Gera o instalador do MIP (Inno Setup) + latest.json para o atualizador
# e, com -Publicar, cria a Release no GitHub.
# Rode na pasta do projeto:
#   powershell -ExecutionPolicy Bypass -File .\installer\montar_instalador.ps1 -Versao 1.0.3 -Repo gbrlinsk3/MyIptvPLayer -Notas "O que mudou" -Publicar
# Requisitos: Flutter, Inno Setup 6 e (para -Publicar) GitHub CLI com `gh auth login`.
# Não testado (o assistente não roda Windows).
param(
  [Parameter(Mandatory = $true)][string]$Versao,
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$Notas = '',
  [switch]$Publicar
)
$ErrorActionPreference = 'Stop'
$raiz = Get-Location

# Evita publicar com versão errada dentro do programa.
$info = Get-Content (Join-Path $raiz 'lib\core\app_info.dart') -Raw
if ($info -notmatch "version = '$([regex]::Escape($Versao))'") {
  throw "lib\core\app_info.dart não está na versão $Versao. Mude AppInfo.version (e a version: do pubspec.yaml) antes."
}

# Localiza o compilador do Inno Setup.
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 não encontrado. Instale em https://jrsoftware.org/isinfo.php' }

Write-Host '1/3 Compilando o MIP...'
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build falhou' }

Write-Host '2/3 Gerando o instalador...'
& $iscc "/DMyAppVersion=$Versao" (Join-Path $raiz 'installer\iptv_player.iss')
if ($LASTEXITCODE -ne 0) { throw 'ISCC falhou' }
$saida = Join-Path $raiz 'release'
New-Item -ItemType Directory -Force -Path $saida | Out-Null
$setup = Join-Path $saida "MIP-Setup-$Versao.exe"
Copy-Item (Join-Path $raiz "installer\output\MIP-Setup-$Versao.exe") $setup -Force
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()

Write-Host '3/3 Escrevendo latest.json...'
$url = "https://github.com/$Repo/releases/download/v$Versao/MIP-Setup-$Versao.exe"
$json = @{ version = $Versao; url = $url; sha256 = $hash; notes = $Notas } | ConvertTo-Json
Set-Content -Path (Join-Path $saida 'latest.json') -Value $json -Encoding UTF8
Write-Host "Pronto: $setup"

if ($Publicar) {
  Write-Host 'Publicando no GitHub...'
  gh release create "v$Versao" $setup (Join-Path $saida 'latest.json') `
    --repo $Repo --title "MIP $Versao" --notes "$Notas"
} else {
  Write-Host "Para publicar: crie a Release v$Versao em github.com/$Repo e anexe $setup e latest.json."
}
