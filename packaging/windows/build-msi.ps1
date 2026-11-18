<#
.SYNOPSIS
    Builds ZapFast's Windows Installer (.msi) package using WiX Toolset 5.

.EXAMPLE
    .\packaging\windows\build-msi.ps1
    .\packaging\windows\build-msi.ps1 -SkipBuild
    .\packaging\windows\build-msi.ps1 -Arch arm64
#>
param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Version,
    [string]$OutDir = "dist",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $repoRoot
try {
    if (-not $Version) {
        $cargoToml = Get-Content (Join-Path $repoRoot "Cargo.toml") -Raw
        if ($cargoToml -match '(?m)^version\s*=\s*"([^"]+)"') {
            $Version = $Matches[1]
        } else {
            throw "Could not read version from Cargo.toml"
        }
    }
    $numericVersion = ($Version -split "-")[0]

    $dotnetTools = Join-Path $env:USERPROFILE ".dotnet\tools"
    if ((Test-Path $dotnetTools) -and ($env:Path -notlike "*$dotnetTools*")) {
        $env:Path += ";$dotnetTools"
    }
    if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
        throw "WiX 5 not found. Install it once with:`n  dotnet tool install --global wix --version 5.0.2`n  wix extension add --global WixToolset.Util.wixext/5.0.2"
    }

    $target = if ($Arch -eq "arm64") { "aarch64-pc-windows-msvc" } else { $null }
    if (-not $SkipBuild) {
        Write-Host "Building ZapFast $Version ($Arch, release)..."
        if ($target) {
            cargo build --locked --release --target $target
        } else {
            cargo build --locked --release
        }
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
    }

    $binaryPath = if ($target) {
        Join-Path $repoRoot "target\$target\release\zapfast.exe"
    } else {
        Join-Path $repoRoot "target\release\zapfast.exe"
    }
    if (-not (Test-Path $binaryPath)) {
        throw "Binary not found at $binaryPath. Run without -SkipBuild first."
    }

    $outRoot = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
    $payloadDir = Join-Path $outRoot "payload"
    New-Item -ItemType Directory -Force $payloadDir | Out-Null

    Copy-Item -Force $binaryPath,
        (Join-Path $repoRoot "README.md"),
        (Join-Path $repoRoot "LICENSE"),
        (Join-Path $repoRoot "THIRD-PARTY-NOTICES.md"),
        (Join-Path $PSScriptRoot "zapfast-installer.txt") $payloadDir

    $msiPath = Join-Path $outRoot "zapfast-$Version-$Arch.msi"
    if (Test-Path $msiPath) {
        Remove-Item -Force $msiPath
    }

    Write-Host "Packaging $msiPath..."
    wix build (Join-Path $PSScriptRoot "zapfast.wxs") `
        -arch $Arch `
        -ext WixToolset.Util.wixext `
        -d "Version=$numericVersion" `
        -d "SourceDir=$payloadDir" `
        -pdbtype none `
        -o $msiPath
    if ($LASTEXITCODE -ne 0) { throw "wix build failed ($LASTEXITCODE)" }

    Write-Host "Done: $msiPath"
} finally {
    Pop-Location
}
