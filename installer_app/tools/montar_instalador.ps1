# Gera: (1) o instalador MIP-Setup, (2) o zip de atualização + hash + latest.json.
# Rode no PowerShell, na pasta do SEU projeto do MIP:
#   .\installer_app\tools\montar_instalador.ps1 -Versao 1.0.1 -Repo SEU_USUARIO/mip-releases [-Publicar]
# Com -Publicar, cria a Release no GitHub (precisa do GitHub CLI: `gh auth login` uma vez).
# Não testado (Claude não roda Windows/Flutter). Leia e ajuste se preciso.
param(
  [Parameter(Mandatory = $true)][string]$Versao,
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$Notas = '',
  [switch]$Publicar
)
$ErrorActionPreference = 'Stop'
$raiz = Get-Location
$release = Join-Path $raiz 'build\windows\x64\runner\Release'
$saida = Join-Path $raiz 'release'
New-Item -ItemType Directory -Force -Path $saida | Out-Null

Write-Host '1/4 Compilando o MIP...'
flutter build windows --release
if (-not (Test-Path $release)) { throw "Pasta Release não encontrada: $release" }

Write-Host '2/4 Compactando o programa...'
$zip = Join-Path $saida "MIP-$Versao.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()

Write-Host '3/4 Compilando o instalador...'
Copy-Item $zip (Join-Path $raiz 'installer_app\assets\payload.zip') -Force
Push-Location (Join-Path $raiz 'installer_app')
flutter pub get
flutter build windows --release
Pop-Location
$setupDir = Join-Path $raiz 'installer_app\build\windows\x64\runner\Release'
Compress-Archive -Path (Join-Path $setupDir '*') -DestinationPath (Join-Path $saida "MIP-Instalador-$Versao.zip") -Force

Write-Host '4/4 Escrevendo latest.json...'
$UrlBase = "https://github.com/$Repo/releases/download/v$Versao"
$json = @{ version = $Versao; url = "$UrlBase/MIP-$Versao.zip"; sha256 = $hash; notes = $Notas } | ConvertTo-Json
Set-Content -Path (Join-Path $saida 'latest.json') -Value $json -Encoding UTF8
Write-Host "Pronto. Arquivos em $saida"
if ($Publicar) {
  Write-Host 'Publicando no GitHub...'
  gh release create "v$Versao" `
    (Join-Path $saida "MIP-$Versao.zip") `
    (Join-Path $saida 'latest.json') `
    (Join-Path $saida "MIP-Instalador-$Versao.zip") `
    --repo $Repo --title "MIP $Versao" --notes "$Notas"
} else {
  Write-Host "Para publicar: crie a Release v$Versao em github.com/$Repo e anexe os 3 arquivos de $saida."
}
