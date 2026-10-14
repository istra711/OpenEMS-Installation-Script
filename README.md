# openEMS Installation Script

Fully automated installation scripts for **[openEMS](https://www.openems.de/)** (open Electromagnetic Magnetic Simulator) — a free, open-source FDTD (Finite-Difference Time-Domain) electromagnetic field solver.

These scripts build **CSXCAD + openEMS** from source (Linux/macOS) or install the official pre-built Windows package, including all dependencies (compiler, VTK, CGAL, Boost, HDF5, TinyXML, Qt, Python/Octave interfaces) and optionally **[easyMesh4openEMS](https://github.com/MustafaAlchalabi/easyMesh4openEMS)** (automated mesher) and **[scikit-rf](https://scikit-rf.org/)** (RF library).

---

## Table of Contents

- [Supported Systems](#supported-systems)
- [Quick Start](#quick-start)
- [Linux / macOS (Source Build)](#linux--macos-source-build)
- [Windows (PowerShell, Pre-built Package)](#windows-powershell-pre-built-package)
- [Options](#options)
- [What the Script Does](#what-the-script-does)
- [Verify Installation](#verify-installation)
- [scikit-rf](#scikit-rf)
- [easyMesh4openEMS](#easymesh4openems)
- [Update](#update)
- [Log File](#log-file)
- [Troubleshooting](#troubleshooting)
- [External Sources & References](#external-sources--references)
- [License](#license)

---

## Supported Systems

| OS / Distro | Package Manager | Status |
|-------------|----------------|--------|
| Debian / Ubuntu | apt | ✅ |
| Fedora / RHEL / AlmaLinux / Rocky | dnf | ✅ |
| Arch Linux | pacman | ✅ |
| Alpine | apk | ✅ |
| Void Linux | xbps | ✅ |
| openSUSE | zypper | ✅ |
| macOS | Homebrew | ✅ |
| FreeBSD | pkg | ✅ |
| Windows 10/11 (64-bit) | PowerShell | ✅ (pre-built package) |

---

## Quick Start

### Linux / macOS (source build)

```bash
git clone https://github.com/istra711/OpenEMS-Installation-Script.git
cd OpenEMS-Installation-Script
chmod +x install_openems.sh
sudo ./install_openems.sh
```

Activate PATH afterwards:

```bash
source ~/.bashrc
```

### Windows (PowerShell, pre-built package)

```powershell
git clone https://github.com/istra711/OpenEMS-Installation-Script.git
cd OpenEMS-Installation-Script

# Run in PowerShell (right-click → "Run with PowerShell" or in terminal):
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install_openems.ps1
```

Optional:

```powershell
.\install_openems.ps1 -InstallDir D:\Tools\openEMS   # Custom install directory
.\install_openems.ps1 -NoOctave                       # Skip Octave interface
.\install_openems.ps1 -NoPython                       # Skip Python extensions
.\install_openems.ps1 -DryRun                         # Preview only
```

---

## Linux / macOS (Source Build)

The shell script (`install_openems.sh`) compiles openEMS from source using the official `update_openEMS.sh` build system from [thliebig/openEMS-Project](https://github.com/thliebig/openEMS-Project).

### Installation Steps

1. **OS Detection** — package manager is auto-detected
2. **Bootstrap** — installs git, cmake, compiler toolchain
3. **Clone** — recursively clones `thliebig/openEMS-Project` (including submodules)
4. **Dependencies** — via official `scripts/install_deps.sh --auto` (fallback: manual package lists)
5. **Octave** — installed (unless `--no-octave`)
6. **Build** — via `update_openEMS.sh` (official build system)
7. **easyMesh** — `easyMesh4openEMS` installed via `pip install` into the openEMS venv (unless `--no-easymesh`; requires Python extensions)
8. **scikit-rf** — installed via `pip install scikit-rf` into the openEMS venv (unless `--no-skrf`)
9. **Environment** — PATH + OCTAVE_PATH written to `~/.bashrc` / `~/.zshrc`
10. **Verification** — tests for openEMS binary, AppCSXCAD, Python extensions, Octave, easyMesh, scikit-rf

---

## Windows (PowerShell, Pre-built Package)

The PowerShell script (`install_openems.ps1`) uses the **official pre-built Windows package** (no source build needed, as recommended by the [official docs](https://docs.openems.de/en/latest/install/package.html)).

### Installation Steps

1. Determines the latest release via the GitHub API
2. Downloads `openEMS_win*.zip`
3. Extracts to `C:\openEMS` (or `-InstallDir`)
4. Installs Python extensions (CSXCAD + openEMS wheels, matching your Python version)
5. Sets `PATH` + `CSXCAD_INSTALL_PATH` (user environment variables)
6. Installs **scikit-rf** via pip
7. Clones + installs **easyMesh4openEMS** via pip
8. Sets up `OCTAVE_PATH` (if Octave is present)
9. Verifies everything

### Parameters

| Parameter | Description |
|-----------|-------------|
| `-InstallDir` | Target directory (default: `C:\openEMS`) |
| `-Python` | Python interpreter (default: `python3`/`python`/`py -3`) |
| `-NoPython` | Skip Python extensions |
| `-NoSkrf` | Skip scikit-rf installation |
| `-NoEasyMesh` | Skip easyMesh installation |
| `-NoOctave` | Skip Octave interface setup |
| `-DryRun` | Preview only |

### Prerequisites

- Windows 10/11 (64-bit)
- Python 3 (for Python extensions, optional)
- Git (for easyMesh, optional)

---

## Options (Linux/macOS)

```
--prefix DIR       Install directory (default: ~/opt/openEMS)
--src-dir DIR      Source code clone directory (default: ~/openEMS-Project)
--no-python        Skip Python extensions
--no-ctb           Skip Circuit Toolbox (CTB)
--no-gui           Disable AppCSXCAD GUI (headless, e.g. servers)
--no-octave        Skip Octave installation
--no-easymesh      Skip easyMesh4openEMS (auto-mesher)
--no-skrf          Skip scikit-rf (RF library)
--with-hyp2mat     Enable hyp2mat (HyperLynx PCB import, deprecated)
--with-MPI         Enable MPI support
--njobs N          Number of parallel build jobs (default: CPU cores)
--update           Update existing installation (git pull + rebuild)
--skip-dep-check   Skip automatic dependency check
--dry-run          Preview only, don't execute
-h, --help         Show help
```

### Examples

```bash
# Full installation to ~/opt/openEMS (with Octave)
sudo ./install_openems.sh

# To /opt/openEMS, headless (no GUI), 4 build jobs
sudo ./install_openems.sh --prefix /opt/openEMS --no-gui --njobs 4

# Without Octave
sudo ./install_openems.sh --no-octave

# Without easyMesh
sudo ./install_openems.sh --no-easymesh

# Without scikit-rf
sudo ./install_openems.sh --no-skrf

# Update existing installation
sudo ./install_openems.sh --update

# C++ engine only, no Python
sudo ./install_openems.sh --no-python
```

---

## What the Script Does

### Dependencies Installed

| Dependency | Purpose | Source |
|------------|---------|--------|
| **git** | Source code cloning | [git-scm.com](https://git-scm.com/) |
| **cmake** | Build system | [cmake.org](https://cmake.org/) |
| **GCC / Clang** | C++ compiler | [gcc.gnu.org](https://gcc.gnu.org/) / [clang.llvm.org](https://clang.llvm.org/) |
| **VTK** | 3D visualization (AppCSXCAD) | [vtk.org](https://www.vtk.org/) |
| **CGAL** | Computational geometry | [cgal.org](https://www.cgal.org/) |
| **Boost** | C++ utility libraries | [boost.org](https://www.boost.org/) |
| **HDF5** | Hierarchical data format (field dumps) | [hdfgroup.org](https://www.hdfgroup.org/solutions/hdf5/) |
| **TinyXML** | XML parsing | [tinyxml.sourceforge.io](http://www.sourceforge.net/projects/tinyxml/) |
| **Qt5** | GUI framework (AppCSXCAD) | [qt.io](https://www.qt.io/) |
| **Octave** | Matlab-compatible scripting interface | [octave.org](https://octave.org/) |
| **Python 3** | Scripting + extensions | [python.org](https://www.python.org/) |

---

## Verify Installation

```bash
# Test binary
openEMS   # Should print version banner

# Test Python extensions (activate venv first if present)
source ~/opt/openEMS/venv/bin/activate
cd / && python3 -c "import CSXCAD, openEMS; print(openEMS.__version__)"

# Test Octave interface
octave --eval "InitCSX"

# Test easyMesh
source ~/opt/openEMS/venv/bin/activate
cd / && python3 -c "import easyMesh; print('easyMesh OK')"

# Test scikit-rf
source ~/opt/openEMS/venv/bin/activate
cd / && python3 -c "import skrf; print('scikit-rf', skrf.__version__)"
```

### Windows

```powershell
# Test binary
openEMS.exe   # Should print version banner

# Test Python extensions
python -c "import CSXCAD, openEMS; print('CSXCAD', CSXCAD.__version__); print('openEMS', openEMS.__version__)"

# Test AppCSXCAD
AppCSXCAD.exe
```

---

## scikit-rf

[scikit-rf](https://scikit-rf.org/) (skrf) is a Python library for RF/microwave network analysis — S-parameters, network analysis, plotting, and more. Used for post-processing openEMS simulation results (e.g., from `UI_data` / S-parameter exports).

Installation is automatic via `pip install scikit-rf` into the openEMS venv.

### Usage

```python
import skrf as rf

# Load S-parameters from a Touchstone file (e.g., openEMS export)
ntwk = rf.Network('my_simulation.s2p')

# Analyze
print(ntwk.s_db)          # S-parameters in dB
ntwk.plot_s_db()          # Plot

# Time domain / impedance
t = ntwk.s_time
```

**Documentation:** <https://scikit-rf.readthedocs.io/>

---

## easyMesh4openEMS

[easyMesh4openEMS](https://github.com/MustafaAlchalabi/easyMesh4openEMS) is an automated mesher for the Python bindings of openEMS/CSXCAD. It auto-detects geometries and generates an optimized FDTD grid.

**Requirement:** CSXCAD/openEMS Python extensions (the script builds these by default with `--python`).

### Usage

```python
from openEMS import openEMS
from CSXCAD import ContinuousStructure
from easyMesh import GenerateMesh, enhance_csx_for_auto_mesh, enhance_FDTD_for_auto_mesh

FDTD = openEMS()
CSX = ContinuousStructure()
FDTD.SetCSX(CSX)

# Wrap CSX/FDTD BEFORE adding geometry/ports/boundary
primitives_mesh_setup = {}
properties_mesh_setup = {}
CSX = enhance_csx_for_auto_mesh(CSX, primitives_mesh_setup)
FDTD = enhance_FDTD_for_auto_mesh(FDTD, primitives_mesh_setup)

# Set boundary AFTER wrapping (PML detection)
FDTD.SetBoundaryCond(['PML_8', 'PML_8', 'PML_8', 'PML_8', 'PML_8', 'PML_8'])

global_mesh_setup = {
    'start_frequency': 1e9,
    'stop_frequency': 3e9,
    'drawing_unit': 1e-6,
    'mesh_resolution': 'medium',
    'boundary_distance': ['auto', 'auto', 'auto', 'auto', 'auto', 'auto'],
}

# Define geometry (AddBox, AddMaterial etc.) ...

# Generate mesh
GenerateMesh(CSX, global_mesh_setup, primitives_mesh_setup, properties_mesh_setup)
```

**More details & tutorials:** <https://github.com/MustafaAlchalabi/easyMesh4openEMS>

---

## Update

```bash
sudo ./install_openems.sh --update
```

This performs a `git pull --recurse-submodules` and rebuilds.

---

## Log File

All installation output is written to `~/openems_install.log`.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `openEMS: command not found` | Run `source ~/.bashrc` or open a new terminal |
| Python extensions not importable | Activate venv: `source ~/opt/openEMS/venv/bin/activate` |
| `CSXCAD_INSTALL_PATH` not set (Windows) | Re-run installer or set manually: `[Environment]::SetEnvironmentVariable("CSXCAD_INSTALL_PATH", "C:\openEMS", "User")` |
| Build fails on missing VTK/CGAL | Install manually: `sudo apt install libvtk9-dev libcgal-dev` (Debian/Ubuntu) |
| Octave `InitCSX` not found | Set `OCTAVE_PATH`: `export OCTAVE_PATH="$OCTAVE_PATH:~/opt/openEMS/share/openEMS/octave"` |
| easyMesh import fails | Ensure CSXCAD/openEMS Python extensions are installed first |
| Permission denied | Use `sudo` for dependency installation; build runs as user |

---

## External Sources & References

This project depends on and references the following open-source projects:

### Core

| Project | License | Source | Description |
|---------|---------|--------|-------------|
| **openEMS** | GPLv3 | [openems.de](https://www.openems.de/) · [github.com/thliebig/openEMS](https://github.com/thliebig/openEMS) | FDTD time-domain electromagnetic field solver |
| **openEMS-Project** | GPLv3 | [github.com/thliebig/openEMS-Project](https://github.com/thliebig/openEMS-Project) | Main repository (CSXCAD + openEMS + tools) |
| **CSXCAD** | LGPLv3 | [github.com/thliebig/CSXCAD](https://github.com/thliebig/CSXCAD) | Continuous Structure library for openEMS |

### Mesh Generation

| Project | License | Source | Description |
|---------|---------|--------|-------------|
| **easyMesh4openEMS** | GPL-3.0 | [github.com/MustafaAlchalabi/easyMesh4openEMS](https://github.com/MustafaAlchalabi/easyMesh4openEMS) | Automated FDTD mesh generation for openEMS/CSXCAD Python bindings |

### RF / Simulation Libraries

| Project | License | Source | Description |
|---------|---------|--------|-------------|
| **scikit-rf** | BSD-3-Clause | [scikit-rf.org](https://scikit-rf.org/) · [github.com/scikit-rf/scikit-rf](https://github.com/scikit-rf/scikit-rf) | Python library for RF/microwave network analysis (S-parameters, Touchstone) |

### Build Dependencies

| Project | License | Source | Description |
|---------|---------|--------|-------------|
| **VTK** | BSD-3-Clause | [vtk.org](https://www.vtk.org/) · [github.com/Kitware/VTK](https://github.com/Kitware/VTK) | 3D visualization and computer graphics (AppCSXCAD) |
| **CGAL** | GPL-3.0 / LGPL-3.0 | [cgal.org](https://www.cgal.org/) · [github.com/CGAL/cgal](https://github.com/CGAL/cgal) | Computational Geometry Algorithms Library |
| **Boost** | BSL-1.0 | [boost.org](https://www.boost.org/) · [github.com/boostorg/boost](https://github.com/boostorg/boost) | C++ utility libraries |
| **HDF5** | BSD-3-Clause | [hdfgroup.org](https://www.hdfgroup.org/solutions/hdf5/) · [github.com/HDFGroup/hdf5](https://github.com/HDFGroup/hdf5) | Hierarchical Data Format (field dump storage) |
| **TinyXML** | zlib | [sourceforge.net/projects/tinyxml](https://sourceforge.net/projects/tinyxml/) | XML parsing library |
| **Qt5** | LGPL-3.0 | [qt.io](https://www.qt.io/) · [github.com/qt/qtbase](https://github.com/qt/qtbase) | Cross-platform GUI framework (AppCSXCAD) |
| **CMake** | BSD-3-Clause | [cmake.org](https://cmake.org/) · [github.com/Kitware/CMake](https://github.com/Kitware/CMake) | Build system generator |
| **GCC** | GPL-3.0 | [gcc.gnu.org](https://gcc.gnu.org/) | GNU Compiler Collection |
| **Clang/LLVM** | Apache-2.0 | [clang.llvm.org](https://clang.llvm.org/) · [github.com/llvm/llvm-project](https://github.com/llvm/llvm-project) | C/C++ compiler |
| **GNU Octave** | GPL-3.0 | [octave.org](https://octave.org/) · [github.com/gnu-octave/octave](https://github.com/gnu-octave/octave) | Matlab-compatible scripting language |
| **Python** | PSF | [python.org](https://www.python.org/) · [github.com/python/cpython](https://github.com/python/cpython) | Scripting language + extensions |

### Data Formats

| Format | Specification | Description |
|--------|--------------|-------------|
| **Touchstone** | [IBIS Open](https://www.ibis.org/touchstone_ver2.0/touchstone_ver2_0.pdf) | S-parameter file exchange (`.s1p`, `.s2p`, …) |
| **HDF5** | [hdfgroup.org](https://www.hdfgroup.org/solutions/hdf5/) | openEMS field dump storage |

### Official Documentation

| Document | URL |
|----------|-----|
| openEMS Homepage | <https://www.openems.de/> |
| openEMS Documentation | <https://docs.openems.de/> |
| openEMS Tutorials | <https://openems.de/index.php/Tutorials.html> |
| Windows Package Install | <https://docs.openems.de/en/latest/install/package.html> |
| Source Install (Linux) | <https://docs.openems.de/en/latest/install/source.html> |
| CSXCAD Reference | <https://docs.openems.de/en/latest/python_interface/csxcad.html> |
| openEMS Python Interface | <https://docs.openems.de/en/latest/python_interface/openEMS.html> |

---

## License

| Component | License |
|-----------|---------|
| **This installation script** | See repository license |
| **openEMS** | [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html) |
| **CSXCAD** | [LGPLv3](https://www.gnu.org/licenses/lgpl-3.0.html) |
| **easyMesh4openEMS** | [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html) |
| **scikit-rf** | [BSD-3-Clause](https://github.com/scikit-rf/scikit-rf/blob/master/LICENSE.txt) |

> **Note:** openEMS and easyMesh4openEMS are GPL-3.0 licensed. If you distribute a combined work, the GPL-3.0 terms apply to the whole.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Create a Pull Request

---

## Acknowledgements

- **[Thorsten Liebig](https://github.com/thliebig)** — creator of openEMS and CSXCAD
- **[Mustafa Alchalabi](https://github.com/MustafaAlchalabi)** — easyMesh4openEMS
- **openEMS community** — [openems.de](https://www.openems.de/) · [GitHub Discussions](https://github.com/thliebig/openEMS-Project/discussions)
