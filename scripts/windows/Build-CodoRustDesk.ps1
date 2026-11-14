[CmdletBinding()]
param([string]$EnvironmentScript, [string]$SciterLibrary)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($EnvironmentScript) { . (Resolve-Path -LiteralPath $EnvironmentScript).Path }
$destination = "$repo/target/debug"
if ($SciterLibrary) { $SciterLibrary = (Resolve-Path -LiteralPath $SciterLibrary).Path }
elseif (-not (Test-Path -LiteralPath "$destination/sciter.dll")) {
    throw 'Provide -SciterLibrary pointing to the x64 sciter.dll from the SDK linked in README.md.'
}
Push-Location $repo
try {
    cargo build --locked --bin rustdesk --target-dir "$repo/target"
    if ($LASTEXITCODE -ne 0) { throw "Debug build failed: $LASTEXITCODE" }
    if ($SciterLibrary) { Copy-Item -LiteralPath $SciterLibrary -Destination "$destination/sciter.dll" -Force }
    Write-Output 'Run scripts/windows/Run-CodoRustDesk.cmd to start the Sciter debug client.'
} finally {
    Pop-Location
}
