$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Run-Flutter([string[]]$Arguments) {
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falha: flutter $($Arguments -join ' ')" }
}
Run-Flutter @('pub', 'get')
Run-Flutter @('analyze', '--no-fatal-infos')
Run-Flutter @('test', '--reporter', 'expanded')
Write-Host 'Análise e testes concluídos.'
