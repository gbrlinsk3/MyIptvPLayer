# Roda os testes do MIP um arquivo por vez.
#
# Por que existe: no Windows o `flutter_tester.exe` (motor do Flutter) cai de
# vez em quando com violacao de acesso (codigo -1073741819 / 0xC0000005),
# ate num projeto vazio com um teste trivial. O resultado aparece como
# "did not complete" ou "No tests were found", sem mensagem de erro. Nao e
# defeito do codigo do app (tambem aparece como "Connection closed before test
# suite loaded"). Aqui, um arquivo que terminar assim e rodado de
# novo (ate 3 tentativas); falha de verdade (com mensagem de teste) NAO e
# repetida e derruba o script.
#
# Uso (na pasta do projeto):  powershell -ExecutionPolicy Bypass -File .\tool\rodar_testes.ps1
param([int]$Tentativas = 3)
$ErrorActionPreference = 'Continue'
$arquivos = Get-ChildItem -Path 'test' -Filter '*_test.dart' | Sort-Object FullName
$falhas = @()
$repetidos = 0
foreach ($a in $arquivos) {
  $rel = 'test/' + $a.Name
  $ok = $false
  for ($t = 1; $t -le $Tentativas; $t++) {
    $saida = & flutter test $rel 2>&1 | Out-String
    $codigo = $LASTEXITCODE
    if ($codigo -eq 0 -and $saida -match 'All tests passed') { $ok = $true; break }
    $quedaDoMotor = ($saida -match 'did not complete' -or $saida -match 'No tests were found' -or $saida -match 'Connection closed before test suite loaded') -and
                    ($saida -notmatch 'Expected:' -and $saida -notmatch 'EXCEPTION CAUGHT' -and $saida -notmatch 'Test failed')
    if (-not $quedaDoMotor) { Write-Host $saida; break }
    $repetidos++
    Write-Host "  (motor de testes caiu em $rel; tentativa $t de $Tentativas)"
  }
  if ($ok) { Write-Host "ok    $rel" } else { Write-Host "FALHA $rel"; $falhas += $rel }
}
Write-Host ''
Write-Host "$($arquivos.Count) arquivos, $($falhas.Count) com falha, $repetidos repeticao(oes) por queda do motor."
if ($falhas.Count -gt 0) { exit 1 }
