<#
.SYNOPSIS
    Vollautomatische Installation von openEMS unter Windows.

.DESCRIPTION
    Lädt das offizielle openEMS-Windows-Paket (ZIP) von GitHub Releases,
    entpackt es, richtet Python-Extensions (Wheels) ein und installiert
    optionale Pakete (scikit-rf, easyMesh4openEMS).

    Kein Quellbuild nötig – das Windows-Paket enthält fertige Binaries.

.PARAMETER InstallDir
    Zielverzeichnis (default: C:\openEMS)

.PARAMETER Python
    Python-Interpreter für die Extensions (default: python3 oder python).

.PARAMETER NoPython
    Keine Python-Extensions installieren.

.PARAMETER NoSkrf
    scikit-rf nicht installieren.

.PARAMETER NoEasyMesh
    easyMesh4openEMS nicht installieren.

.PARAMETER NoOctave
    Octave-Interface nicht einrichten.

.PARAMETER DryRun
    Nur anzeigen, was gemacht würde.

.EXAMPLE
    .\install_openems.ps1
    .\install_openems.ps1 -InstallDir D:\Tools\openEMS -NoOctave
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "C:\openEMS",
    [string]$Python = "",
    [switch]$NoPython,
    [switch]$NoSkrf,
    [switch]$NoEasyMesh,
    [switch]$NoOctave,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # schnellerer Download

# ─── Konfiguration ────────────────────────────────────────────────────────────
$RepoUrl  = "https://github.com/thliebig/openEMS-Project/releases"
$EasyMeshUrl = "https://github.com/MustafaAlchalabi/easyMesh4openEMS.git"
$Logfile  = "$env:USERPROFILE\openems_install.log"

# ─── Helfer ───────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $Logfile -Value $line
    switch ($Level) {
        "ERROR"   { Write-Host "    [ERROR] $Message" -ForegroundColor Red }
        "WARN"    { Write-Host "    [WARN]  $Message" -ForegroundColor Yellow }
        "OK"      { Write-Host "    [OK]    $Message" -ForegroundColor Green }
        default   { Write-Host "    $Message" }
    }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Block)
    Write-Host "`n==> $Name" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [dry-run] $Name"
        return
    }
    & $Block
}

# ─── 1. Administrator-Rechte prüfen ──────────────────────────────────────────
function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── 2. Python finden ─────────────────────────────────────────────────────────
function Find-Python {
    if ($Python) { return $Python }
    foreach ($cmd in @("python3", "python", "py")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            # "py" Launcher: -3 für Python 3
            if ($cmd -eq "py") { return "py -3" }
            return $cmd
        }
    }
    return $null
}

function Get-PythonVersion {
    param([string]$PyCmd)
    try {
        $out = & $PyCmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        return $out.Trim()
    } catch { return $null }
}

# ─── 3. Neueste Release-URL ermitteln ────────────────────────────────────────
function Get-OpenEMSArtifact {
    Write-Log "Ermittle neuestes openEMS-Windows-Release..."
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/thliebig/openEMS-Project/releases/latest" -UseBasicParsing
        # Asset suchen: openEMS_win*.zip
        $asset = $rel.assets | Where-Object { $_.name -like "openEMS_win*.zip" } | Select-Object -First 1
        if ($asset) {
            Write-Log "Release gefunden: $($rel.tag_name) / $($asset.name)" "OK"
            return @{ Url = $asset.browser_download_url; Name = $asset.name }
        }
        # Fallback: Seite durchsuchen
        Write-Log "Kein Asset über API gefunden – versuche Release-Seite..." "WARN"
    } catch {
        Write-Log "GitHub-API fehlgeschlagen: $_" "WARN"
    }

    # Fallback: Release-Seite parsen
    try {
        $html = Invoke-WebRequest -Uri "$RepoUrl/latest" -UseBasicParsing
        $match = [regex]::Match($html.Content, 'href="([^"]*openEMS_win[^"]*\.zip)"')
        if ($match.Success) {
            $url = $match.Groups[1].Value
            if ($url -notmatch "^http") { $url = "https://github.com$url" }
            Write-Log "Release-ZIP gefunden: $url" "OK"
            return @{ Url = $url; Name = [System.IO.Path]::GetFileName($url) }
        }
    } catch {
        Write-Log "Release-Seite fehlgeschlagen: $_" "ERROR"
    }

    return $null
}

# ─── Hauptablauf ──────────────────────────────────────────────────────────────
Write-Host @"

============================================================
  openEMS Windows Installer
  https://www.openems.de/
============================================================

"@ -ForegroundColor Cyan

Write-Log "Zielverzeichnis: $InstallDir"
Write-Log "Python:          $(if ($NoPython) { 'deaktiviert' } else { 'aktiv' })"
Write-Log "scikit-rf:       $(if ($NoSkrf) { 'deaktiviert' } else { 'aktiv' })"
Write-Log "easyMesh:        $(if ($NoEasyMesh) { 'deaktiviert' } else { 'aktiv' })"
Write-Log "Octave:          $(if ($NoOctave) { 'deaktiviert' } else { 'aktiv' })"

# ─── Schritt 1: Release laden ─────────────────────────────────────────────────
Invoke-Step "Lade neuestes openEMS-Windows-Paket" {
    $artifact = Get-OpenEMSArtifact
    if (-not $artifact) {
        throw "Kein openEMS-Windows-Paket gefunden. Bitte manuell laden: $RepoUrl"
    }

    $zipPath = Join-Path $env:TEMP $artifact.Name
    Write-Log "Lade $($artifact.Name) herunter..."
    Invoke-WebRequest -Uri $artifact.Url -OutFile $zipPath -UseBasicParsing
    Write-Log "Download abgeschlossen: $zipPath" "OK"
    $script:ZipPath = $zipPath
}

# ─── Schritt 2: Entpacken ─────────────────────────────────────────────────────
Invoke-Step "Entpacke nach $InstallDir" {
    if (-not $script:ZipPath) { throw "Kein ZIP-Pfad verfügbar." }

    # Temporärer Entpackort (ZIP enthält "openEMS"-Ordner)
    $tmpExtract = Join-Path $env:TEMP "openems_extract"
    if (Test-Path $tmpExtract) { Remove-Item $tmpExtract -Recurse -Force }
    Expand-Archive -Path $script:ZipPath -DestinationPath $tmpExtract -Force

    # ZIP enthält "openEMS"-Ordner → Inhalt nach InstallDir verschieben
    $inner = Join-Path $tmpExtract "openEMS"
    if (Test-Path $inner) {
        if (Test-Path $InstallDir) {
            Write-Log "Ziel existiert bereits – aktualisiere..."
            Copy-Item "$inner\*" -Destination $InstallDir -Recurse -Force
        } else {
            Move-Item $inner -Destination $InstallDir
        }
    } else {
        # Kein "openEMS"-Unterordner → alles direkt entpacken
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Copy-Item "$tmpExtract\*" -Destination $InstallDir -Recurse -Force
    }

    Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Entpackt nach $InstallDir" "OK"

    # Prüfe Binary
    $openEMSExe = Join-Path $InstallDir "openEMS.exe"
    if (Test-Path $openEMSExe) {
        Write-Log "openEMS.exe gefunden: $openEMSExe" "OK"
    } else {
        Write-Log "openEMS.exe nicht gefunden unter $InstallDir (evtl. anderer Ordnername)." "WARN"
    }
}

# ─── Schritt 3: PATH aktualisieren ────────────────────────────────────────────
Invoke-Step "Aktualisiere PATH (User)" {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
        Write-Log "PATH um $InstallDir erweitert (User). Nach Reboot/Neuanmeldung aktiv." "OK"
    } else {
        Write-Log "PATH enthält $InstallDir bereits." "OK"
    }
    # Aktuelle Session
    $env:Path += ";$InstallDir"
}

# ─── Schritt 4: Python-Extensions (Wheels) ────────────────────────────────────
$PyCmd = $null
$PyVersion = $null

if (-not $NoPython) {
    Invoke-Step "Installiere Python-Extensions (CSXCAD + openEMS Wheels)" {
        $PyCmd = Find-Python
        if (-not $PyCmd) {
            Write-Log "Kein Python gefunden – Python-Extensions werden übersprungen." "WARN"
            Write-Log "Bitte Python 3 installieren: https://www.python.org/" "WARN"
            return
        }

        $PyVersion = Get-PythonVersion -PyCmd $PyCmd
        Write-Log "Python gefunden: $PyCmd (Version $PyVersion)"

        # Wheels-Verzeichnis im Paket suchen
        $whlDir = Join-Path $InstallDir "python"
        if (-not (Test-Path $whlDir)) {
            Write-Log "Kein python\-Ordner im Paket gefunden – Wheels nicht installierbar." "WARN"
            return
        }

        # Passende Wheels finden (cp3x = Python-Version)
        $cpTag = "cp$($PyVersion -replace '\.','')"
        $csxcadWhl = Get-ChildItem -Path $whlDir -Filter "CSXCAD*-$cpTag-*.whl" | Select-Object -First 1
        $openemsWhl = Get-ChildItem -Path $whlDir -Filter "openEMS*-$cpTag-*.whl" | Select-Object -First 1

        if (-not $csxcadWhl -or -not $openemsWhl) {
            Write-Log "Keine passenden Wheels für Python $PyVersion gefunden (gesucht: $cpTag)." "WARN"
            Write-Log "Verfügbare Wheels:" "WARN"
            Get-ChildItem $whlDir -Filter "*.whl" | ForEach-Object { Write-Log "  $($_.Name)" "WARN" }
            return
        }

        Write-Log "Installiere CSXCAD: $($csxcadWhl.Name)"
        & $PyCmd -m pip install $csxcadWhl.FullName --quiet
        if ($LASTEXITCODE -ne 0) { throw "CSXCAD-Wheel-Installation fehlgeschlagen." }

        Write-Log "Installiere openEMS: $($openemsWhl.Name)"
        & $PyCmd -m pip install $openemsWhl.FullName --quiet
        if ($LASTEXITCODE -ne 0) { throw "openEMS-Wheel-Installation fehlgeschlagen." }

        # CSXCAD_INSTALL_PATH setzen
        [Environment]::SetEnvironmentVariable("CSXCAD_INSTALL_PATH", $InstallDir, "User")
        $env:CSXCAD_INSTALL_PATH = $InstallDir

        # Verifikation
        & $PyCmd -c "import CSXCAD, openEMS; print('CSXCAD', CSXCAD.__version__); print('openEMS', openEMS.__version__)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python-Extensions OK." "OK"
        } else {
            Write-Log "Python-Extensions nicht importierbar (evtl. PATH/CSXCAD_INSTALL_PATH noch nicht aktiv)." "WARN"
        }
    }
}

# ─── Schritt 5: scikit-rf ─────────────────────────────────────────────────────
if (-not $NoSkrf -and -not $NoPython) {
    Invoke-Step "Installiere scikit-rf (skrf)" {
        if (-not $PyCmd) {
            $PyCmd = Find-Python
            if (-not $PyCmd) { Write-Log "Kein Python – scikit-rf übersprungen." "WARN"; return }
        }

        Write-Log "pip install scikit-rf..."
        & $PyCmd -m pip install scikit-rf --quiet
        if ($LASTEXITCODE -eq 0) {
            & $PyCmd -c "import skrf; print('scikit-rf', skrf.__version__)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "scikit-rf installiert." "OK"
            } else {
                Write-Log "scikit-rf installiert, aber Import fehlgeschlagen." "WARN"
            }
        } else {
            Write-Log "scikit-rf-Installation fehlgeschlagen." "WARN"
        }
    }
}

# ─── Schritt 6: easyMesh4openEMS ──────────────────────────────────────────────
if (-not $NoEasyMesh -and -not $NoPython) {
    Invoke-Step "Installiere easyMesh4openEMS (Auto-Mesher)" {
        if (-not $PyCmd) {
            $PyCmd = Find-Python
            if (-not $PyCmd) { Write-Log "Kein Python – easyMesh übersprungen." "WARN"; return }
        }

        # CSXCAD/openEMS müssen importierbar sein
        & $PyCmd -c "import CSXCAD, openEMS" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "CSXCAD/openEMS-Python-Extensions nicht importierbar – easyMesh-Build könnte fehlschlagen." "WARN"
        }

        $emDir = Join-Path $env:USERPROFILE "easyMesh4openEMS"
        if (Test-Path $emDir) {
            Write-Log "easyMesh-Repo existiert – aktualisiere..."
            Push-Location $emDir
            git pull 2>$null | Out-Null
            Pop-Location
        } else {
            Write-Log "Klone easyMesh4openEMS..."
            git clone $EasyMeshUrl $emDir 2>$null | Out-Null
            if (-not (Test-Path $emDir)) {
                Write-Log "Git-Clone fehlgeschlagen (ist git installiert?). easyMesh übersprungen." "WARN"
                return
            }
        }

        Write-Log "pip install . (easyMesh)..."
        Push-Location $emDir
        & $PyCmd -m pip install . --quiet
        Pop-Location

        & $PyCmd -c "import easyMesh; print('easyMesh OK')" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "easyMesh installiert." "OK"
        } else {
            Write-Log "easyMesh-Import fehlgeschlagen." "WARN"
        }
    }
}

# ─── Schritt 7: Octave-Interface (optional) ───────────────────────────────────
if (-not $NoOctave) {
    Invoke-Step "Octave-Interface (optional)" {
        # Prüfe ob Octave installiert ist
        $octaveCmd = Get-Command "octave" -ErrorAction SilentlyContinue
        if (-not $octaveCmd) {
            # Standard-Installationspfad prüfen
            $octavePaths = @(
                "C:\Program Files\GNU Octave\Octave*\bin\octave.exe",
                "C:\Program Files\Octave*\bin\octave.exe"
            )
            foreach ($p in $octavePaths) {
                $found = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) { $octaveCmd = $found; break }
            }
        }

        if (-not $octaveCmd) {
            Write-Log "Octave nicht gefunden." "WARN"
            Write-Log "Octave optional: https://octave.org/download – danach CSXCAD-Octave-Pfad manuell einrichten." "WARN"
            return
        }

        # OCTAVE_PATH setzen
        $octavePkgDir = Join-Path $InstallDir "share\openEMS\octave"
        if (Test-Path $octavePkgDir) {
            [Environment]::SetEnvironmentVariable("OCTAVE_PATH", "$octavePkgDir", "User")
            $env:OCTAVE_PATH = $octavePkgDir
            Write-Log "OCTAVE_PATH gesetzt: $octavePkgDir" "OK"
        } else {
            Write-Log "Kein Octave-Paketverzeichnis gefunden: $octavePkgDir" "WARN"
        }
    }
}

# ─── Abschluss: Verifikation ──────────────────────────────────────────────────
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  Installation abgeschlossen" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$checks = @()

# openEMS Binary
$openEMSExe = Join-Path $InstallDir "openEMS.exe"
if (Test-Path $openEMSExe) {
    Write-Log "openEMS.exe: $openEMSExe" "OK"
    $checks += "openEMS"
} else {
    Write-Log "openEMS.exe nicht gefunden." "WARN"
}

# AppCSXCAD
$appExe = Join-Path $InstallDir "AppCSXCAD.exe"
if (Test-Path $appExe) {
    Write-Log "AppCSXCAD.exe: $appExe" "OK"
    $checks += "AppCSXCAD"
}

# Python
if (-not $NoPython -and $PyCmd) {
    & $PyCmd -c "import CSXCAD, openEMS" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Python-Extensions (CSXCAD + openEMS): OK" "OK"
        $checks += "Python"
    }
}

# scikit-rf
if (-not $NoSkrf -and $PyCmd) {
    & $PyCmd -c "import skrf" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "scikit-rf: OK" "OK"
        $checks += "scikit-rf"
    }
}

# easyMesh
if (-not $NoEasyMesh -and $PyCmd) {
    & $PyCmd -c "import easyMesh" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "easyMesh: OK" "OK"
        $checks += "easyMesh"
    }
}

Write-Host "`nNächste Schritte:" -ForegroundColor Yellow
Write-Host "  1. Neues Terminal öffnen (PATH/Env-Variablen aktivieren)"
Write-Host "  2. Test:  openEMS.exe   (sollte Versionsbanner ausgeben)"
Write-Host "  3. Test:  python -c `"import CSXCAD, openEMS`""
Write-Host "  4. AppCSXCAD.exe für 3D-Visualisierung nutzen"
Write-Host "`nLogfile: $Logfile"
Write-Host "Installiert: $($checks -join ', ')`n"
