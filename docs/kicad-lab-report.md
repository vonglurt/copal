# Making Alpine's KiCad Usable: Templates, Drawing Sheets, Demos, Plugins, and a Library Mismatch That Is Not One

*Lab Report — IEEE Format*

<!-- SPDX-License-Identifier: MIT -->
Copyright (c) 2026 Paul Richeson. MIT licensed — see `LICENSE`. Copal Linux is
an aggregation of Alpine Linux, not a derivative work of it; Alpine and its
packages remain under their own licences.

---

## Abstract

Alpine 3.24.1 ships KiCad 10.0.3 as a bare set of editors. On a Copal aarch64
guest, a fresh install opens with one project template, no drawing sheets, no
demo projects, a design-block library table that points at a file the library
package does not ship, and no plugins — and the Plugin and Content Manager
that would install plugins is a dialog with no command-line equivalent, so
Copal's unattended workshop stage could not use it. This report records what
was missing, how each gap was located from inside the guest, one apparent
fault that turned out not to be a fault (the library package is a release
behind the program and writes its paths with the previous major version's
variable names, which KiCad 10 resolves anyway), and the fix: a `kicad_configure`
step in stage 14 that installs upstream's template and worksheet release, the
demo package, an empty design-block table, seeded global library tables, and
a `kicad-addon` script that performs the Plugin and Content Manager's install
procedure headlessly and records it where the dialog looks. One defect in
the first version of that script — package directories named with dots, which
Python cannot import — was caught by running KiCad's own plugin loader and is
documented because it is exactly the kind of thing the dialog hides.

## I. Objective

1. Establish, by inspection rather than assumption, what a stock Alpine KiCad
   install lacks relative to an upstream one for each editor: schematic,
   symbol, PCB, footprint, and drawing sheet.
2. Decide whether the version skew between `kicad` (10.0.3) and
   `kicad-library` (9.0.7) breaks library resolution, with a test that cannot
   be argued with.
3. Find a way to install plugins without the GUI, and verify that KiCad then
   sees them as installed and loads them.
4. Fold all of it into stage 14 so a fresh Copal machine gets it unattended,
   and write a guide the machine carries.

## II. Materials

| Item | Value |
|---|---|
| Guest | Copal aarch64 under UTM, Alpine 3.24.1, Hyprland, 4 vCPU, 5.9 GB |
| KiCad | `kicad-10.0.3-r0` (community), IPC API built in, wxWidgets 3.2.9 |
| Libraries | `kicad-library-9.0.7-r1`, `kicad-library-3d-9.0.7-r1` (STEP models) |
| Demos | `kicad-demos-10.0.3-r0`, 91 MB, packaged but not a dependency |
| Templates | `kicad-templates` 10.0.6 from GitLab, 2.9 MB tarball, not packaged |
| Plugin index | `repository.kicad.org` → `packages-v1.json`, 124 packages |
| Java | OpenJDK 21 JRE, for Freerouting |
| Tools | `kicad-cli`, `strace`, `grim`, `hyprctl`, Python `pcbnew` and `wx` |

## III. Method

**A. Inventory.** List `/usr/share/kicad`, count what each package owns
(`apk info -L`), read the user's `~/.config/kicad/10.0/` after a first run,
and search the whole filesystem for `.kicad_wks` files.

**B. The variable-name question.** The stock `sym-lib-table` and `fp-lib-table`
write every path as `${KICAD9_SYMBOL_DIR}` and `${KICAD9_FOOTPRINT_DIR}`; all
14,805 footprint files name their model as `${KICAD9_3DMODEL_DIR}/…`. KiCad 10
defines `KICAD10_*`. Whether the old names resolve was tested two ways, both
headless and both under a throwaway `XDG_CONFIG_HOME` so the user's real
configuration was never touched:

1. A minimal schematic carrying one `Device:R` and *no* cached `lib_symbols`,
   run through `kicad-cli sch erc` under `strace -f -e trace=openat`, with
   four global tables: the stock one as-is (KICAD9), a copy rewritten to
   KICAD10, a copy rewritten to a nonsense variable, and an empty table. The
   question is simply which runs open `/usr/share/kicad/symbols/Device.kicad_sym`.
2. A board with one `R_0603_1608Metric`, written by the `pcbnew` Python
   module, exported with `kicad-cli pcb export step --subst-models` three
   times: model path as shipped (KICAD9), rewritten to KICAD10, rewritten to
   nonsense. The size of the STEP file and the presence of "Could not add 3D
   model" in the log tell whether the model was found.

**C. Plugins without the dialog.** Read the official index, fetch a handful of
package zips, and look at their layout. Recover the record format the dialog
writes from `strings /usr/bin/kicad`, and the repository identifier from the
name of KiCad's own cache directory. Write `kicad-addon`, exercise it in an
isolated configuration (install, a library package, remove), then verify the
result by calling `pcbnew.LoadPlugins()` — the same function the PCB editor
calls at startup — with a `wx.App` created on the live display, and by
opening the editors on the desktop and screenshotting them with `grim`.

**D. Templates.** Read `kicad-templates`' own `CMakeLists.txt` to learn the
install layout, then reproduce it.

## IV. Results

### A. What a stock install has

| Path | Contents | Owner |
|---|---|---|
| `symbols/` | 225 `.kicad_sym` | kicad-library |
| `footprints/` | 15,571 files in `.pretty` directories | kicad-library |
| `3dmodels/` | 7,306 STEP models | kicad-library-3d |
| `template/` | `sym-lib-table`, `fp-lib-table`, `kicad.kicad_pro` — three files | kicad, kicad-library |
| `demos/` | absent unless `kicad-demos` is installed | — |
| `*.kicad_wks` | none anywhere on the filesystem | — |
| `template/design-block-lib-table` | absent, though the user's global table points at it | — |
| `plugins/`, `scripting/plugins/` | the BOM scripts and footprint wizards KiCad bundles | kicad |

So: **the schematic and PCB editors have their symbol, footprint and 3D
libraries; the project manager has one template; the Drawing Sheet Editor has
nothing to open; Design Blocks start with a dangling reference; there are no
demos and no plugins.** Upstream's design-block library repository, checked
on the same day, contains only category directories with `.gitkeep` files, so
"empty" is also the accurate content for that table.

### B. The KICAD9 names resolve under KiCad 10

Symbol lookup, from the strace of `kicad-cli sch erc`:

| Global table | `Device.kicad_sym` opened |
|---|---|
| stock, `${KICAD9_SYMBOL_DIR}` | yes |
| rewritten to `${KICAD10_SYMBOL_DIR}` | yes |
| rewritten to `${KICAD_BOGUS_DIR}` | yes |
| empty table | no |

The third row was unexpected: a library whose URI cannot be expanded is still
found by nickname in the stock symbol directory. That is a fallback, and it
means the symbol test alone cannot distinguish "the old name resolves" from
"the old name fails and the fallback rescues it". The 3D-model test can:

| Model path in the board | STEP output | Log |
|---|---|---|
| `${KICAD9_3DMODEL_DIR}/…` as shipped | 49 KB | clean |
| `${KICAD10_3DMODEL_DIR}/…` | 49 KB | clean |
| `${KICAD_BOGUS_DIR}/…` | 8 KB | "Could not add 3D model for R1" |

The model resolver has no nickname fallback, so this settles it: **KiCad 10
defines the KICAD9 names itself.** The version skew is cosmetic. Rewriting
the tables would gain nothing and would diverge from what the package
manager will eventually ship.

### C. What the Plugin and Content Manager actually does

From the index, the zips, and the binary:

- 124 packages; 100 have a stable version declared compatible with 10.0
  (78 plugins, 15 libraries, 17 colour themes). Every version entry carries
  a download URL, size and SHA-256; a few older ones carry no checksum.
- A package zip has `metadata.json` at the root and one or more of
  `plugins/`, `resources/`, `colors/`, `symbols/`, `footprints/`, `3dmodels/`.
- The install record, `~/.config/kicad/10.0/installed_packages.json`, is
  `{"packages": [...]}`; the field names present in the binary are
  `package`, `current_version`, `install_timestamp`, `pinned`,
  `repository_id`, `repository_name`.
- KiCad's cache directory for the official repository is
  `~/.cache/kicad/10.0/pcm/46f88614eade3439`, which is the first sixteen hex
  digits of SHA-256 of `https://repository.kicad.org/repository.json`. That
  is the `repository_id`.
- **The directory a package unpacks into is its identifier with every dot
  replaced by an underscore.** The first version of `kicad-addon` used the
  identifier verbatim. `pcbnew.LoadPlugins()` then reported
  `ModuleNotFoundError: No module named 'com'` for every package: the loader
  runs `importlib.import_module()` on the directory name, and a dotted name
  is a package path to Python. With underscores, the same call found all six
  plugin classes (Interactive HTML BOM, Freerouting, Fabrication Toolkit,
  Replicate Layout, Board2Pdf, KiBuzzard); the only remaining exception was
  the C++ assertion a plugin raises when it registers outside a running
  KiCad, which is expected in a bare Python process.
- A library package (tested with the 0.4 MB 4ms library) needs 43 rows added
  to the global tables, named `PCM_<file>` and addressed through
  `${KICAD10_3RD_PARTY}`; removal must take them out again. Both work.
- The IPC API server, which plugins written against KiCad 9 and later use
  instead of the SWIG bindings, is off by default in `kicad_common.json` and
  `kicad-cli version` creates that file if it does not exist, so the toggle
  can be applied before KiCad has ever been opened.

Editors opened on the live desktop with the plugin set installed showed no
error dialog; the schematic editor's only banner was the format-upgrade
notice for a test file written in KiCad 8 syntax.

### D. Templates and sheets

`kicad-templates` 10.0.6 (the newest tag for the installed 10.0 series)
installs, per its CMake, every `Projects/*` directory and every
`Worksheets/**/*.kicad_wks` file *flat* into the stock template directory.
That yields 20 project templates and 36 drawing sheets (ISO 5457 / ISO 7200
A2–A4 in full and compact forms, English, German and Greek, the ASME Y14.35
variant, GOST landscape and portrait, and KiCad's default and logo sheets),
5.7 MB on disk. On this guest, with no root, they were installed to the user
template directory instead, where the project manager lists them under *User
Templates*; stage 14 puts them in `/usr/share/kicad/template/`.

### E. Mail clients and wxMaxima (asked mid-session)

Thunderbird was already in the catalogue. KMail exists in Alpine 3.24
community for aarch64 and x86_64 only, and was added with a `64` gate.
wxMaxima is packaged nowhere in Alpine — main, community and testing, every
branch — but builds from source against Alpine's wxWidgets 3.2.9; see the
build notes in stage 14's maths bundle.

## V. Discussion

**Test the thing, not the theory.** Two plausible stories were wrong here.
"KiCad 10 won't resolve KICAD9 paths" is what the file contents suggest and
what a fix-by-sed would have addressed, and it is false. "A plugin directory
named after its identifier will load" is what the index implies, and it is
also false, for a reason (Python's import grammar) that nothing in the PCM
documentation mentions. Both were settled by making the software do the work
and watching — strace for one, the loader itself for the other. The GUI
screenshots were reassuring but, on their own, could not distinguish "loaded"
from "not yet loaded"; the loader call could.

**Match the dialog exactly, or the dialog fights you.** Writing the same
record the PCM writes, with the same repository id, means the dialog lists
these packages as installed, offers updates for them, and can remove them.
A private install layout would have worked for loading and then produced
duplicate installs the first time someone opened the dialog.

**Limits.** The record format is inferred from strings in the binary and one
cache directory name, not from source; it was not confirmed by opening the
PCM dialog on this guest, which needs a mouse. Freerouting's PCM package is
a launcher for a Java program and needs `openjdk21-jre`; the stage installs
it. KiKit's PCM package is a shell around a Python distribution that must be
installed separately, so it is documented in the guide rather than installed.

## VI. Procedures

**Reproduce the resolution test** (any KiCad, no root, nothing touched):

```sh
mkdir -p /tmp/k/A/kicad/10.0
cp ~/.config/kicad/10.0/{sym,fp}-lib-table /tmp/k/A/kicad/10.0/
XDG_CONFIG_HOME=/tmp/k/A strace -f -e trace=openat -o /tmp/k/A.trace \
    kicad-cli sch erc -o /tmp/k/A.json some.kicad_sch
grep -c 'Device.kicad_sym' /tmp/k/A.trace
```

**Install the plugin set by hand**, as the account that runs KiCad:

```sh
kicad-addon api on
kicad-addon defaults
kicad-addon list | head
```

**Verify the loader sees them**, again as that account, on a desktop:

```sh
python3 -c '
import os, wx; wx.App(False); import pcbnew
h=os.path.expanduser("~")
pcbnew.LoadPlugins("/usr/share/kicad/scripting", h+"/.local/share/kicad/10.0/scripting", h+"/.local/share/kicad/10.0/3rdparty/plugins")
print([c.__module__ for c in pcbnew.ActionPlugin.__subclasses__()])'
```

## VII. Files touched

| File | Change |
|---|---|
| `copal-prep.sh` | `kicad_configure`, `write_kicad_addon`, `write_kicad_guide` before `workshop_electronics`; the bundle installs `kicad-demos` and `py3-pip` and calls `kicad_configure`; KMail catalogue row; `64` comment list |
| `docs/copal-handbook.md` | Electronics paragraph, workshop row, Mail row, 64-bit list |
| `docs/kicad-lab-report.md` | this report |
| on this guest | `~/.config/kicad/10.0/design-block-lib-table` (emptied; `.bak` kept), `kicad_common.json` (API on), `installed_packages.json`; `~/.local/share/kicad/10.0/3rdparty/` and `template/` |
