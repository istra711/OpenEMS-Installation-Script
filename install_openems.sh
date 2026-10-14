#!/usr/bin/env bash
#
# install_openems.sh - Vollautomatische Installation von openEMS
# (open Electromagnetic Magnetic Simulator, https://www.openems.de/)
#
# Baut CSXCAD + openEMS from Source via das offizielle update_openEMS.sh,
# inkl. aller Abhängigkeiten (Compiler, VTK, CGAL, Boost, HDF5, TinyXML, Qt, ...).
#
# Unterstützt: Debian/Ubuntu, Fedora/RHEL/Alma, Arch, Alpine, Void, macOS (Homebrew), FreeBSD.
# Nutzung:      sudo ./install_openems.sh [Optionen]
#
set -euo pipefail

# ─── Konfiguration / Defaults ────────────────────────────────────────────────
REPO_URL="https://github.com/thliebig/openEMS-Project.git"
DEFAULT_PREFIX="$HOME/opt/openEMS"
PREFIX="$DEFAULT_PREFIX"
SRC_DIR="$HOME/openEMS-Project"
WITH_PYTHON=1
WITH_CTB=1
WITH_GUI=1
WITH_OCTAVE=1
WITH_EASYMESH=1
WITH_SKRF=1
WITH_HYP2MAT=0
WITH_MPI=0
NJOBS="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) )"
UPDATE_EXISTING=0
SKIP_DEP_CHECK=0
DRY_RUN=0
LOG_FILE="$HOME/openems_install.log"

usage() {
    cat <<EOF
Usage: $0 [options]

Optionen:
  --prefix DIR       Installationsverzeichnis (default: $DEFAULT_PREFIX)
  --src-dir DIR      Verzeichnis für den Quellcode-Clone (default: $SRC_DIR)
  --no-python        Keine Python-Extensions bauen
  --no-ctb           Keine Circuit-Toolbox (CTB) bauen
  --no-gui           AppCSXCAD-GUI deaktivieren (headless, z.B. Server)
  --no-octave        Octave nicht installieren
  --no-easymesh      easyMesh4openEMS (Auto-Mesher) nicht installieren
  --no-skrf          scikit-rf (RF-Bibliothek) nicht installieren
  --with-hyp2mat     hyp2mat aktivieren (HyperLynx-PCB-Import, veraltet)
  --with-MPI         MPI-Unterstützung aktivieren
  --njobs N          Anzahl paralleler Build-Jobs (default: $NJOBS)
  --update           Bestehende Installation aktualisieren (git pull + rebuild)
  --skip-dep-check   Automatische Dependency-Prüfung überspringen
  --dry-run          Nur anzeigen, was gemacht würde, nichts ausführen
  -h, --help         Diese Hilfe anzeigen

Beispiele:
  sudo $0                                   # Volle Installation nach ~/opt/openEMS
  sudo $0 --prefix /opt/openEMS --no-gui    # Nach /opt, headless
  sudo $0 --update                          # Vorhandene Installation updaten
EOF
}

# ─── Argumente parsen ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)       PREFIX="$2"; shift 2 ;;
        --src-dir)      SRC_DIR="$2"; shift 2 ;;
        --no-python)    WITH_PYTHON=0; shift ;;
        --no-ctb)       WITH_CTB=0; shift ;;
        --no-gui)       WITH_GUI=0; shift ;;
        --no-octave)    WITH_OCTAVE=0; shift ;;
        --no-easymesh)  WITH_EASYMESH=0; shift ;;
        --no-skrf)      WITH_SKRF=0; shift ;;
        --with-hyp2mat) WITH_HYP2MAT=1; shift ;;
        --with-MPI)     WITH_MPI=1; shift ;;
        --njobs)        NJOBS="$2"; shift 2 ;;
        --update)       UPDATE_EXISTING=1; shift ;;
        --skip-dep-check) SKIP_DEP_CHECK=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "Unbekannte Option: $1"; usage; exit 1 ;;
    esac
done

# ─── Helfer ──────────────────────────────────────────────────────────────────
log()  { echo -e "\n==> $*"; }
info() { echo "    $*"; }
warn() { echo "    [WARN] $*" >&2; }
die()  { echo "    [ERROR] $*" >&2; exit 1; }

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "    [dry-run] $*"
    else
        "$@" 2>&1 | tee -a "$LOG_FILE"
        return "${PIPESTATUS[0]}"
    fi
}

# Root-Rechte prüfen (nur für Dependency-Installation nötig, Build läuft als User)
require_root_for_deps() {
    if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
    if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif [[ $EUID -ne 0 ]]; then
        die "Root-Rechte oder sudo benötigt, um Abhängigkeiten zu installieren."
    else
        SUDO=""
    fi
}

# ─── OS-Detection ────────────────────────────────────────────────────────────
detect_os() {
    OS_ID="unknown"
    OS_ID_LIKE=""
    PKG_MGR="unknown"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS_ID="macos"
        PKG_MGR="brew"
        return
    fi

    if [[ "$(uname -s)" == "FreeBSD" ]]; then
        OS_ID="freebsd"
        PKG_MGR="pkg"
        return
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
    fi

    if command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    elif command -v xbps-install >/dev/null 2>&1; then
        PKG_MGR="xbps"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MGR="zypper"
    fi
}

# ─── Dependency-Installation ─────────────────────────────────────────────────
# Installiert minimale Bootstrap-Abhängigkeiten (git, cmake, compiler),
# damit wir das Repo klonen können. Danach übernimmt das offizielle
# scripts/install_deps.sh die restlichen Pakete.
install_bootstrap_deps() {
    log "Installiere Bootstrap-Abhängigkeiten (git, cmake, compiler)..."
    require_root_for_deps

    case "$PKG_MGR" in
        apt)
            run $SUDO apt-get update -y
            run $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
                git cmake build-essential ca-certificates curl wget \
                python3 python3-pip python3-venv
            ;;
        dnf)
            run $SUDO dnf install -y git cmake gcc gcc-c++ make \
                python3 python3-pip ca-certificates curl wget
            # EPEL für某些 Pakete (CGAL, VTK) auf RHEL/Alma
            if [[ "$OS_ID" == "rhel" || "$OS_ID" == "centos" || "$OS_ID" == "almalinux" || "$OS_ID" == "rocky" ]]; then
                run $SUDO dnf install -y epel-release || warn "epel-release fehlt, evtl. manuell aktivieren"
                run $SUDO dnf config-manager --set-enabled crb 2>/dev/null || \
                run $SUDO dnf config-manager --set-enabled powertools 2>/dev/null || true
            fi
            ;;
        pacman)
            run $SUDO pacman -Sy --noconfirm git cmake base-devel python python-pip \
                curl wget ca-certificates
            ;;
        apk)
            run $SUDO apk add --no-cache bash git cmake build-base \
                python3 py3-pip curl wget ca-certificates
            ;;
        xbps)
            run $SUDO xbps-install -Sy git cmake base-devel \
                python3 python3-pip curl wget ca-certificates
            ;;
        zypper)
            run $SUDO zypper --non-interactive refresh
            run $SUDO zypper --non-interactive install git cmake gcc-c++ make \
                python3 python3-pip curl wget ca-certificates
            ;;
        brew)
            run brew update
            run brew install git cmake python
            ;;
        pkg)
            run $SUDO pkg install -y git cmake bash python3
            ;;
        *)
            warn "Unbekannter Paketmanager. Bitte git+cmake manuell installieren."
            ;;
    esac
}

# Installiert Octave (Matlab-kompatible Scripting-Sprache für openEMS).
# Empfohlen von der offiziellen Doku als optionales Interface.
install_octave() {
    if [[ $WITH_OCTAVE -eq 0 ]]; then
        info "Octave-Installation übersprungen (--no-octave)."
        return 0
    fi

    # Prüfe ob Octave bereits vorhanden
    if command -v octave >/dev/null 2>&1; then
        info "Octave bereits installiert: $(octave --version 2>/dev/null | head -n 1)"
        return 0
    fi

    log "Installiere Octave..."
    require_root_for_deps

    case "$PKG_MGR" in
        apt)
            run $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y octave liboctave-dev
            ;;
        dnf)
            run $SUDO dnf install -y octave
            ;;
        pacman)
            run $SUDO pacman -S --noconfirm --needed octave
            ;;
        apk)
            run $SUDO apk add --no-cache octave
            ;;
        xbps)
            run $SUDO xbps-install -Sy octave
            ;;
        zypper)
            run $SUDO zypper --non-interactive install octave
            ;;
        brew)
            run brew install octave
            ;;
        pkg)
            run $SUDO pkg install -y octave
            ;;
        *)
            warn "Unbekannter Paketmanager – Octave nicht automatisch installierbar."
            warn "Bitte manuell installieren: https://octave.org/"
            return 0
            ;;
    esac

    if command -v octave >/dev/null 2>&1; then
        info "Octave installiert: $(octave --version 2>/dev/null | head -n 1)"
    else
        warn "Octave-Installation fehlgeschlagen oder nicht im PATH."
    fi
}

# Installiert easyMesh4openEMS (automatischer Mesher für openEMS/CSXCAD).
# Baut auf den Python-Extensions von CSXCAD/openEMS auf → nach Build ausführen.
install_easymesh() {
    if [[ $WITH_EASYMESH -eq 0 ]]; then
        info "easyMesh-Installation übersprungen (--no-easymesh)."
        return 0
    fi

    if [[ $WITH_PYTHON -eq 0 ]]; then
        warn "easyMesh benötigt Python-Extensions – wird übersprungen (--no-python gesetzt)."
        return 0
    fi

    log "Installiere easyMesh4openEMS (Auto-Mesher)..."

    local easymesh_url="https://github.com/MustafaAlchalabi/easyMesh4openEMS.git"
    local easymesh_dir="$HOME/easyMesh4openEMS"

    # Repo klonen / updaten
    if [[ -d "$easymesh_dir/.git" ]]; then
        info "easyMesh-Repo existiert bereits – aktualisiere..."
        (cd "$easymesh_dir" && run git pull)
    else
        run git clone "$easymesh_url" "$easymesh_dir"
    fi

    # Python-Umgebung wählen: venv von openEMS bevorzugen
    local pip_cmd="pip3"
    local py_cmd="python3"
    if [[ -f "$PREFIX/venv/bin/pip" ]]; then
        pip_cmd="$PREFIX/venv/bin/pip"
        py_cmd="$PREFIX/venv/bin/python"
        info "Installiere in openEMS-venv: $PREFIX/venv"
    else
        warn "Kein openEMS-venv gefunden – installiere in System-Python."
    fi

    # CSXCAD/openEMS-Bindings müssen importierbar sein, sonst scheitert der Build von easyMesh
    if ! (cd / && "$py_cmd" -c "import CSXCAD, openEMS" 2>/dev/null); then
        warn "CSXCAD/openEMS-Python-Extensions nicht importierbar – easyMesh-Build könnte fehlschlagen."
        warn "Stelle sicher, dass openEMS mit --python gebaut wurde und das venv aktiv ist."
    fi

    # easyMesh installieren (nicht aus PyPI, nur lokal)
    (cd "$easymesh_dir" && run "$pip_cmd" install .)

    # Verifikation
    if (cd / && "$py_cmd" -c "import easyMesh; print('easyMesh', easyMesh.__version__ if hasattr(easyMesh, '__version__') else 'OK')" 2>/dev/null); then
        info "easyMesh erfolgreich installiert."
    else
        warn "easyMesh-Import fehlgeschlagen – ggf. venv manuell aktivieren und erneut testen."
    fi
}

# Installiert scikit-rf (skrf) – RF/Microwave-Signalanalyse-Bibliothek für Python.
# Wird für Netzwerkanalyse (S-Parameter etc.) in openEMS-Workflows benötigt.
install_skrf() {
    if [[ $WITH_SKRF -eq 0 ]]; then
        info "scikit-rf-Installation übersprungen (--no-skrf)."
        return 0
    fi

    if [[ $WITH_PYTHON -eq 0 ]]; then
        warn "scikit-rf benötigt Python – wird übersprungen (--no-python gesetzt)."
        return 0
    fi

    log "Installiere scikit-rf (skrf)..."

    # Python-Umgebung wählen: venv von openEMS bevorzugen
    local pip_cmd="pip3"
    local py_cmd="python3"
    if [[ -f "$PREFIX/venv/bin/pip" ]]; then
        pip_cmd="$PREFIX/venv/bin/pip"
        py_cmd="$PREFIX/venv/bin/python"
        info "Installiere in openEMS-venv: $PREFIX/venv"
    else
        warn "Kein openEMS-venv gefunden – installiere in System-Python."
    fi

    # scikit-rf installieren (PyPI)
    run "$pip_cmd" install scikit-rf

    # Verifikation
    if (cd / && "$py_cmd" -c "import skrf; print('scikit-rf', skrf.__version__)" 2>/dev/null); then
        info "scikit-rf erfolgreich installiert."
    else
        warn "scikit-rf-Import fehlgeschlagen – ggf. venv manuell aktivieren und erneut testen."
    fi
}

# Versucht das offizielle scripts/install_deps.sh zu nutzen (empfohlen).
# Fällt auf manuelle Paketlisten zurück, falls nicht verfügbar.
install_full_deps() {
    log "Installiere vollständige Build-Abhängigkeiten..."

    local dep_args="--auto"
    [[ $WITH_PYTHON -eq 1 ]] && dep_args+=" --python"
    [[ $WITH_CTB -eq 1 ]] && dep_args+=" --with-ctb"
    [[ $WITH_GUI -eq 0 ]] && dep_args+=" --disable-gui"

    if [[ -x "$SRC_DIR/scripts/install_deps.sh" ]]; then
        info "Nutze offizielles scripts/install_deps.sh $dep_args"
        (cd "$SRC_DIR" && run ./scripts/install_deps.sh $dep_args)
        return
    fi

    warn "scripts/install_deps.sh nicht gefunden – nutze manuelle Paketlisten."
    require_root_for_deps

    case "$PKG_MGR" in
        apt)
            local apt_pkgs=(
                build-essential cmake git libhdf5-dev libvtk9-dev
                libboost-all-dev libcgal-dev libtinyxml-dev
                libgmp-dev libmpfr-dev
            )
            [[ $WITH_GUI -eq 1 ]] && apt_pkgs+=(qtbase5-dev libvtk9-qt-dev)
            [[ $WITH_PYTHON -eq 1 ]] && apt_pkgs+=(python3-dev python3-pip python3-venv)
            run $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${apt_pkgs[@]}"
            # Qt6-Kompatibilitätsmodul auf neueren Ubuntu-Versionen
            run $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y qt6-5compat-dev 2>/dev/null || true
            ;;
        dnf)
            local dnf_pkgs=(
                gcc gcc-c++ cmake git boost-devel tinyxml-devel
                hdf5-devel vtk-devel CGAL-devel gmp-devel mpfr-devel
            )
            [[ $WITH_GUI -eq 1 ]] && dnf_pkgs+=(vtk-qt)
            [[ $WITH_PYTHON -eq 1 ]] && dnf_pkgs+=(python3-devel python3-pip)
            run $SUDO dnf install -y "${dnf_pkgs[@]}"
            ;;
        pacman)
            run $SUDO pacman -S --noconfirm --needed \
                gcc cmake git boost tinyxml hdf5 cgal vtk gmp mpfr \
                qt5-base ninja
            ;;
        apk)
            run $SUDO apk add --no-cache \
                boost-dev tinyxml-dev hdf5-dev cgal-dev vtk-dev gmp-dev mpfr-dev
            ;;
        xbps)
            run $SUDO xbps-install -Sy -- \
                hdf5-devel boost-devel cgal-devel tinyxml-devel vtk-devel
            ;;
        brew)
            run brew install cmake boost hdf5 cgal vtk qt5compat || true
            # TinyXML wird von update_openEMS.sh automatisch gebaut
            ;;
        pkg)
            run $SUDO pkg install -y boost-libs tinyxml vtk9 hdf5 cgal qt5 || true
            ;;
    esac
}

# ─── Repo klonen / updaten ───────────────────────────────────────────────────
clone_or_update_repo() {
    if [[ $UPDATE_EXISTING -eq 1 && -d "$SRC_DIR/.git" ]]; then
        log "Aktualisiere bestehendes Repository in $SRC_DIR ..."
        (cd "$SRC_DIR" && run git pull --recurse-submodules && run git submodule update --init --recursive)
    elif [[ -d "$SRC_DIR/.git" ]]; then
        log "Repository existiert bereits in $SRC_DIR – überspringe Clone."
        (cd "$SRC_DIR" && run git submodule update --init --recursive)
    else
        log "Klone openEMS-Project nach $SRC_DIR ..."
        run git clone --recursive "$REPO_URL" "$SRC_DIR"
        # Tiefer Clone nötig für "git describe" (Versionierung im Build)
        (cd "$SRC_DIR" && run git fetch --unshallow || true)
    fi
}

# ─── Build & Install ─────────────────────────────────────────────────────────
build_and_install() {
    log "Baue und installiere openEMS nach $PREFIX ..."
    mkdir -p "$PREFIX" 2>/dev/null || $SUDO mkdir -p "$PREFIX"

    local build_args=("$PREFIX")
    [[ $WITH_PYTHON -eq 1 ]]    && build_args+=("--python")
    [[ $WITH_CTB -eq 1 ]]       && build_args+=("--with-CTB")
    [[ $WITH_GUI -eq 0 ]]       && build_args+=("--disable-GUI")
    [[ $WITH_HYP2MAT -eq 1 ]]   && build_args+=("--with-hyp2mat")
    [[ $WITH_MPI -eq 1 ]]       && build_args+=("--with-MPI")
    [[ $SKIP_DEP_CHECK -eq 1 ]] && build_args+=("--skip-dep-check")
    build_args+=("--njobs=$NJOBS")

    info "Build-Argumente: ${build_args[*]}"
    (cd "$SRC_DIR" && run ./update_openEMS.sh "${build_args[@]}")
}

# ─── PATH & Umgebung einrichten ──────────────────────────────────────────────
setup_environment() {
    log "Richte PATH und Umgebungsvariablen ein..."

    local path_line="export PATH=\"$PREFIX/bin:\$PATH\""
    local profiles=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
    local shell_rc

    # Passende RC-Datei wählen
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        shell_rc="$HOME/.bashrc"
    else
        shell_rc="$HOME/.profile"
    fi

    # PATH-Zeile hinzufügen (idempotent)
    if ! grep -qsF "$path_line" "$shell_rc" 2>/dev/null; then
        {
            echo ""
            echo "# openEMS (install_openems.sh)"
            echo "$path_line"
        } >> "$shell_rc"
        info "PATH-Eintrag zu $shell_rc hinzugefügt."
    else
        info "PATH-Eintrag existiert bereits in $shell_rc."
    fi

    # Aktuelle Shell aktualisieren
    export PATH="$PREFIX/bin:$PATH"

    # Octave-Pfad einrichten (falls Octave installiert)
    if command -v octave >/dev/null 2>&1 && [[ $WITH_CTB -eq 1 ]]; then
        info "Octave erkannt – CSXCAD-Octave-Interface wird beim nächsten Octave-Start automatisch genutzt."
        # Für Octave muss der Pfad in ~/.octave_env oder über OCTAVE_PATH gesetzt werden
        local octave_path_line="export OCTAVE_PATH=\"\$OCTAVE_PATH:$PREFIX/share/openEMS/octave\""
        if ! grep -qsF "OCTAVE_PATH" "$shell_rc" 2>/dev/null; then
            echo "$octave_path_line" >> "$shell_rc"
        fi
    fi

    # Python venv aktivieren (falls gebaut)
    if [[ $WITH_PYTHON -eq 1 && -f "$PREFIX/venv/bin/activate" ]]; then
        info "Python venv gefunden unter $PREFIX/venv – Activierung in README/Next-Steps."
    fi
}

# ─── Verifikation ────────────────────────────────────────────────────────────
verify_installation() {
    log "Verifiziere Installation..."

    local ok=0

    # 1. openEMS Binary
    if command -v openEMS >/dev/null 2>&1; then
        info "openEMS Binary gefunden: $(command -v openEMS)"
        openEMS --version 2>&1 | head -n 3 || true
        ok=$((ok+1))
    elif [[ -x "$PREFIX/bin/openEMS" ]]; then
        info "openEMS Binary: $PREFIX/bin/openEMS"
        "$PREFIX/bin/openEMS" --version 2>&1 | head -n 3 || true
        ok=$((ok+1))
    else
        warn "openEMS Binary nicht gefunden."
    fi

    # 2. AppCSXCAD (optional)
    if [[ $WITH_GUI -eq 1 ]]; then
        if command -v AppCSXCAD >/dev/null 2>&1 || [[ -x "$PREFIX/bin/AppCSXCAD" ]]; then
            info "AppCSXCAD gefunden."
            ok=$((ok+1))
        else
            warn "AppCSXCAD nicht gefunden (kann bei --no-gui oder fehlendem VTK/Qt auftreten)."
        fi
    fi

    # 3. Python-Extensions
    if [[ $WITH_PYTHON -eq 1 ]]; then
        local py_test="import CSXCAD, openEMS; print('CSXCAD', CSXCAD.__version__); print('openEMS', openEMS.__version__)"
        if [[ -f "$PREFIX/venv/bin/python" ]]; then
            if (cd / && "$PREFIX/venv/bin/python" -c "$py_test" 2>/dev/null); then
                info "Python-Extensions OK (venv)."
                ok=$((ok+1))
            else
                warn "Python-Extensions-Test fehlgeschlagen (venv)."
            fi
        elif command -v python3 >/dev/null 2>&1; then
            if (cd / && python3 -c "$py_test" 2>/dev/null); then
                info "Python-Extensions OK (system)."
                ok=$((ok+1))
            else
                warn "Python-Extensions nicht importierbar."
            fi
        fi
    fi

    # 4. Octave-Interface (optional, nur wenn Octave da)
    if command -v octave >/dev/null 2>&1 && [[ $WITH_CTB -eq 1 ]]; then
        if octave --eval "InitCSX" >/dev/null 2>&1; then
            info "Octave-Interface (InitCSX) OK."
            ok=$((ok+1))
        else
            warn "Octave-Interface nicht testbar (evtl. PATH/OCTAVE_PATH noch nicht aktiv)."
        fi
    fi

    # 5. easyMesh (optional)
    if [[ $WITH_EASYMESH -eq 1 && $WITH_PYTHON -eq 1 ]]; then
        local py_bin="python3"
        [[ -f "$PREFIX/venv/bin/python" ]] && py_bin="$PREFIX/venv/bin/python"
        if (cd / && "$py_bin" -c "import easyMesh" 2>/dev/null); then
            info "easyMesh OK."
            ok=$((ok+1))
        else
            warn "easyMesh nicht importierbar (evtl. venv nicht aktiv)."
        fi
    fi

    # 6. scikit-rf (optional)
    if [[ $WITH_SKRF -eq 1 && $WITH_PYTHON -eq 1 ]]; then
        local py_bin_skrf="python3"
        [[ -f "$PREFIX/venv/bin/python" ]] && py_bin_skrf="$PREFIX/venv/bin/python"
        if (cd / && "$py_bin_skrf" -c "import skrf" 2>/dev/null); then
            info "scikit-rf OK."
            ok=$((ok+1))
        else
            warn "scikit-rf nicht importierbar (evtl. venv nicht aktiv)."
        fi
    fi

    local max_checks=1  # openEMS-Binary wird immer geprüft
    [[ $WITH_GUI -eq 1 ]] && max_checks=$((max_checks+1))
    [[ $WITH_PYTHON -eq 1 ]] && max_checks=$((max_checks+1))
    [[ $WITH_OCTAVE -eq 1 ]] && max_checks=$((max_checks+1))
    [[ $WITH_EASYMESH -eq 1 && $WITH_PYTHON -eq 1 ]] && max_checks=$((max_checks+1))
    [[ $WITH_SKRF -eq 1 && $WITH_PYTHON -eq 1 ]] && max_checks=$((max_checks+1))

    echo ""
    log "Installation abgeschlossen. Verifikation: $ok/$max_checks Checks bestanden."
    echo ""
    echo "Nächste Schritte:"
    echo "  1. PATH aktivieren:  source $HOME/.bashrc   (oder neuen Terminal-Tab öffnen)"
    if [[ $WITH_PYTHON -eq 1 && -f "$PREFIX/venv/bin/activate" ]]; then
        echo "  2. Python venv:      source $PREFIX/venv/bin/activate"
        echo "  3. Test:             cd / && python3 -c 'import CSXCAD, openEMS; print(openEMS.__version__)'"
    else
        echo "  2. Test:             openEMS   (sollte Versionsbanner ausgeben)"
    fi
    echo "  Logfile: $LOG_FILE"
}

# ─── Hauptablauf ─────────────────────────────────────────────────────────────
main() {
    log "openEMS Vollautomatische Installation"
    info "Prefix:     $PREFIX"
    info "Quellcode:  $SRC_DIR"
    info "Python:     $([[ $WITH_PYTHON -eq 1 ]] && echo an || echo aus)"
    info "CTB:        $([[ $WITH_CTB -eq 1 ]] && echo an || echo aus)"
    info "GUI:        $([[ $WITH_GUI -eq 1 ]] && echo an || echo aus)"
    info "Octave:     $([[ $WITH_OCTAVE -eq 1 ]] && echo an || echo aus)"
    info "easyMesh:   $([[ $WITH_EASYMESH -eq 1 ]] && echo an || echo aus)"
    info "scikit-rf:  $([[ $WITH_SKRF -eq 1 ]] && echo an || echo aus)"
    info "Jobs:       $NJOBS"
    [[ $UPDATE_EXISTING -eq 1 ]] && info "Modus:      UPDATE"

    detect_os
    info "Erkanntes OS: $OS_ID (Paketmanager: $PKG_MGR)"

    if [[ $DRY_RUN -eq 0 ]]; then
        : > "$LOG_FILE"
    fi

    # 1. Bootstrap-Tools (git, cmake, compiler)
    install_bootstrap_deps

    # 2. Repo klonen (damit install_deps.sh verfügbar ist)
    clone_or_update_repo

    # 3. Vollständige Abhängigkeiten
    install_full_deps

    # 3b. Octave installieren (falls gewünscht)
    install_octave

    # 4. Build & Install
    build_and_install

    # 4b. easyMesh4openEMS installieren (nach Build, da Python-Extensions nötig)
    install_easymesh

    # 4c. scikit-rf installieren
    install_skrf

    # 5. Umgebung (PATH, Octave, etc.)
    setup_environment

    # 6. Verifikation
    verify_installation
}

main "$@"
