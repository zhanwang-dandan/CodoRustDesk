[CmdletBinding()]
param(
    [string]$EnvironmentScript,
    [string]$OutputDirectory,
    [string]$ShortSourcePath,
    [string]$Python = 'python',
    [switch]$PackageOnly
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($EnvironmentScript) { . (Resolve-Path -LiteralPath $EnvironmentScript).Path }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'target/windows-packages' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$buildRepo = $repo
if ($ShortSourcePath) {
    $ShortSourcePath = [IO.Path]::GetFullPath($ShortSourcePath)
    if (-not (Test-Path -LiteralPath $ShortSourcePath)) {
        New-Item -ItemType Junction -Path $ShortSourcePath -Target $repo | Out-Null
    }
    if ((Get-FileHash "$ShortSourcePath/Cargo.toml").Hash -ne (Get-FileHash "$repo/Cargo.toml").Hash) {
        throw 'ShortSourcePath does not point to this repository.'
    }
    $buildRepo = $ShortSourcePath
}
$version = [regex]::Match((Get-Content "$repo/Cargo.toml" -Raw), '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $version) { throw 'Cannot read the application version from Cargo.toml.' }
$name = "CodoRustDesk-$version-windows-x64-Flutter"
$bundle = Join-Path $OutputDirectory "$name-Release"
if (Test-Path -LiteralPath $bundle) { throw "Bundle already exists; choose a fresh OutputDirectory: $bundle" }

function Assert-Command([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}

function Restore-PluginJunctions {
    $plugins = Get-Content "$buildRepo/flutter/.flutter-plugins-dependencies" -Raw | ConvertFrom-Json
    foreach ($platformName in @('windows', 'linux')) {
        $linkRoot = "$buildRepo/flutter/$platformName/flutter/ephemeral/.plugin_symlinks"
        New-Item -ItemType Directory -Force $linkRoot | Out-Null
        foreach ($plugin in $plugins.plugins.$platformName) {
            $linkPath = Join-Path $linkRoot $plugin.name
            if (-not (Test-Path -LiteralPath $linkPath)) {
                New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
            }
        }
    }
}

Push-Location $buildRepo
try {
    if (-not $PackageOnly) {
        foreach ($bridge in @('src/bridge_generated.rs', 'src/bridge_generated.io.rs',
                'flutter/lib/generated_bridge.dart', 'flutter/lib/generated_bridge.freezed.dart')) {
            if (-not (Test-Path -LiteralPath "$buildRepo/$bridge")) {
                throw "Missing CI bridge artifact: $bridge. See scripts/windows/README.md."
            }
        }
        $flutterVersion = flutter --version --machine | ConvertFrom-Json
        Assert-Command 'Flutter version check'
        if ($flutterVersion.frameworkVersion -ne '3.24.5') { throw 'This x64 build requires Flutter 3.24.5.' }
        if (-not $env:FLUTTER_ROOT) {
            $env:FLUTTER_ROOT = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
        }
        cargo build --locked --release --lib --features flutter --target-dir "$buildRepo/target"
        Assert-Command 'Rust Flutter library build'
        cargo build --locked --release -p dylib_virtual_display --target-dir "$buildRepo/target"
        Assert-Command 'Virtual display library build'
        Set-Location "$buildRepo/flutter"
        $pubOutput = flutter pub get 2>&1
        $pubExit = $LASTEXITCODE
        $pubOutput | Write-Host
        if ($pubExit -ne 0) {
            if (($pubOutput | Out-String) -notmatch 'requires symlink support') {
                throw "flutter pub get failed with exit code $pubExit"
            }
            Restore-PluginJunctions
            flutter pub get
            Assert-Command 'Flutter dependency setup'
        }
        Restore-PluginJunctions
        $engine = "$env:FLUTTER_ROOT/bin/cache/artifacts/engine"
        $ephemeral = "$buildRepo/flutter/windows/flutter/ephemeral"
        New-Item -ItemType Directory -Force "$ephemeral/cpp_client_wrapper" | Out-Null
        Copy-Item "$engine/windows-x64/cpp_client_wrapper/*" "$ephemeral/cpp_client_wrapper" -Recurse -Force
        Get-ChildItem "$engine/windows-x64-release" -File |
            Where-Object Extension -In @('.h', '.dll', '.lib') |
            Copy-Item -Destination $ephemeral -Force
        Copy-Item "$engine/windows-x64/icudtl.dat" $ephemeral -Force
        $env:CMAKE_BUILD_PARALLEL_LEVEL = '2'
        $env:_CL_ = '/MP1'
        flutter build windows --release --no-pub
        Assert-Command 'Flutter Windows build'
    }

    $release = "$buildRepo/flutter/build/windows/x64/runner/Release"
    foreach ($required in @("$release/rustdesk.exe", "$release/librustdesk.dll", "$release/data/app.so",
            "$buildRepo/target/release/dylib_virtual_display.dll")) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing Release output: $required" }
    }
    New-Item -ItemType Directory -Force $bundle | Out-Null
    Copy-Item "$release/*" $bundle -Recurse -Force
    Copy-Item "$buildRepo/target/release/dylib_virtual_display.dll" $bundle
    Copy-Item "$repo/LICENCE" "$bundle/LICENCE.txt"
    Copy-Item "$PSScriptRoot/PORTABLE-README.txt" "$bundle/README.txt"
    if ($env:FLUTTER_ROOT) {
        Copy-Item "$env:FLUTTER_ROOT/bin/cache/artifacts/engine/windows-x64-release/license.windows_flutter.md" "$bundle/FLUTTER-ENGINE-LICENSE.md"
    } else {
        throw 'FLUTTER_ROOT must be set to include the engine license when packaging.'
    }
    $sourceCommit = git -C $repo rev-parse HEAD
    Assert-Command 'Source revision lookup'
    [ordered]@{ version = $version; source_commit = $sourceCommit; features = @('flutter', 'use_dasp');
        architecture = 'x86_64-pc-windows-msvc'; signed = $false } |
        ConvertTo-Json | Set-Content "$bundle/BUILD-INFO.json" -Encoding utf8
    $metadata = "$repo/libs/portable/app_metadata.toml"
    $oldMetadata = if (Test-Path -LiteralPath $metadata) { [IO.File]::ReadAllBytes($metadata) } else { $null }
    try {
        & $Python "$repo/libs/portable/generate.py" -f $bundle -o "$repo/libs/portable" -e rustdesk.exe -l 9
        Assert-Command 'Portable EXE packaging'
        $target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { "$repo/target" }
        $portable = Join-Path $OutputDirectory "$name-portable.exe"
        Copy-Item "$target/release/rustdesk-portable-packer.exe" $portable
    } finally {
        if ($null -ne $oldMetadata) { [IO.File]::WriteAllBytes($metadata, [byte[]]$oldMetadata) }
        elseif (Test-Path -LiteralPath $metadata) { Remove-Item -LiteralPath $metadata }
    }
    $zip = Join-Path $OutputDirectory "$name-Release.zip"
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip
    $hashLines = foreach ($artifact in @($portable, $zip)) {
        $hash = Get-FileHash -LiteralPath $artifact -Algorithm SHA256
        "$($hash.Hash.ToLower())  $([IO.Path]::GetFileName($artifact))"
    }
    $hashLines | Set-Content (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding utf8
    Get-Item $portable, $zip
} finally {
    Pop-Location
}
