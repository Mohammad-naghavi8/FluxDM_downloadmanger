# Rebuilds Go engine, Flutter Windows Release, and FluxDM-Setup-1.0.0.exe
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root
try {
    Write-Host "[1/3] Building Go download engine..." -ForegroundColor Cyan
    Push-Location "$Root\go_backend"
    & go build -trimpath -ldflags="-s -w -H=windowsgui" -o dm_engine.exe .
    Pop-Location

    Write-Host "[2/3] Building Flutter Windows Release..." -ForegroundColor Cyan
    & flutter build windows --release

    Write-Host "[3/3] Compiling Inno Setup installer..." -ForegroundColor Cyan
    $IsccCandidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    $Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Iscc) {
        $Cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($Cmd) { $Iscc = $Cmd.Source }
    }
    if (-not $Iscc) {
        throw "ISCC.exe (Inno Setup 6) not found. Install it via: winget install JRSoftware.InnoSetup"
    }

    & $Iscc "$PSScriptRoot\FluxDM.iss"
    Write-Host "Done! Installer generated at: $PSScriptRoot\output\FluxDM-Setup-1.0.0.exe" -ForegroundColor Green
} finally {
    Pop-Location
}
