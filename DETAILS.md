# DevEco Studio Linux Package — Implementation Details

This file documents **why** the PKGBUILD does what it does — every piece of
"magic", the upstream quirk it works around, and the details that matter
when maintaining or forking this package. The README is the user-facing
view; this is the developer-facing view.

## Architecture: three sources, one package

| Source | What it provides | Why |
|---|---|---|
| **Mac DMG** (`devecostudio-mac.zip`) | `lib/*.jar`, `plugins/`, `modules/`, `license/`, `build.txt`, `bin/devecostudio.svg`, `bin/idea.properties`, `bin/devecostudio.vmoptions`, `Resources/product-info.json`, `tools/UxTestService` | Huawei ships DevEco Studio for Windows, macOS, and Linux. The Linux installer is an `.exe` that is painful to extract and lags in version; the Mac DMG extracts trivially with `7z x` and all of these files are platform-independent (Java bytecode, resources, templates). |
| **JetBrains IDEA tarball** (`idea-${_ideaver}.tar.gz`) | `jbr/`, `bin/idea` launcher, `bin/fsnotifier`, `lib/native/linux-x86_64/`, `lib/pty4j/linux/`, `lib/jna/amd64/`, `lib/skiko-awt-runtime-all/` | The macOS-specific bits (JBR, launcher, native `.so`s) are replaced with Linux ones. DevEco's build number is pinned to a specific IDEA baseline — see "IDEA version matching" below. |
| **Command Line Tools for Linux** (`commandline-tools-linux-x64.zip`) | `sdk/`, `tool/node/`, `hvigor/`, `ohpm/`, `hstack/`, `codelinter/`, `emulator/`, `bin/` wrappers | The CLI zip already contains Linux-native versions of every tool, and its SDK is the one the IDE needs. |

Everything from the Mac DMG that is not on the list above is either
platform-native (and unusable on Linux) or duplicated by the CLI: `jbr`,
`sdk/default`, `tools/emulator`, `tools/llvm`, `tools/profiler`,
`tools/node`, `tools/dumpParser` are all excluded during DMG extraction
(`prepare()`).

The two Huawei zips are **user-supplied** (Huawei's download links are
signed and expire), renamed to version-independent filenames
(`devecostudio-mac.zip`, `commandline-tools-linux-x64.zip`). Only the IDEA
tarball is auto-downloaded. Checksums live in `sha256sums`; users changing
versions update `pkgver` + the two checksums (or use `SKIP`).

## The magic, by area

### Emulator (`Emulator.exe` symlink)

Huawei's code (`LocalDeviceConnection.getEmulatorPathName`) only
distinguishes **Mac vs non-Mac**; the non-Mac branch hardcodes
`Emulator.exe`. On Linux the binary is named `Emulator`, so without a
symlink the Device Manager fails every operation ("get emulator status
failed") and debugging fails ("The emulator file ... is missing"). The
package ships `tools/emulator/Emulator.exe -> Emulator`.

Two consequences of the symlink:
- The `.exe` cleanup pass must keep it: `find "$_pkg" -name '*.exe' -not -name 'Emulator.exe' -delete`. (A past bug deleted it; it only existed locally because it had been created by hand.)
- The emulator binary itself comes from the **CLI** zip (Linux ELF), not the Mac DMG (Mach-O).

### Emulator system images

The IDE's "install emulator" wizard only appears when the emulator binary
is missing, and downloads binary **and** system image together. Because we
bundle the binary, the wizard never triggers — system images are the only
missing piece and must be fetched manually:
`Emulator -install -deviceType phone -osVersion "<version>"` (anonymous),
or copied from another platform's install into `~/.Huawei/Sdk/system-image/`.

### Emulator paths (`~/Library/Huawei/Sdk`)

The emulator binary hardcodes the macOS-style user path
`~/Library/Huawei/Sdk` for system images. The launcher wrapper bridges it:
`ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"` on every start.
The emulator also needs `QT_QPA_PLATFORM=xcb` (it ships only the xcb Qt
platform plugin — no Wayland build), set by the wrapper.

### Node.js layout (three symlinks, no real-file copy)

The CLI's `tool/node/` is the upstream node tarball layout: real binaries
in `bin/`, npm under `lib/node_modules/npm`. Three things are needed on top:

1. **Top-level tool symlinks**: `node`, `npm`, `npx`, `corepack` →
   `bin/*`. The IDE's File Watcher and various tools call
   `<nodeDir>/npm` etc. (This predates 26.0.0; it was the original 6.1.1
   fix.)
2. **`tools/node/node_modules -> lib/node_modules`** — satisfies the
   Windows branch of the IDE's npm check.
3. **`tools/lib/node_modules -> ../node/lib/node_modules`** — the actual
   Linux fix. The IDE's `getNpmVersionFast`
   (`project-mgmt-*.jar`, class `NodeConfigUtil`) reads npm's
   `package.json` **only** at `<nodeDir>/../lib/node_modules/npm/package.json`
   on Linux, i.e. `tools/lib/node_modules/...`, which upstream node layout
   never satisfies. Without it, every project sync reports *"Invalid
   project Node.js path ... Node.js 24.x is recommended"* and sync is
   interrupted (`SyncInterruptException`).

   The version check (`AbstractNodejsChecker.checkIsValidVersions`) needs
   **both** node and npm versions valid, or it notifies + throws. A
   "diagnostic" where renaming `tools/node/node` to `node.bak` makes the
   warning disappear is explained by `findRealNodeDir()` falling back to
   `tools/node/bin` when the top-level `node` is absent — and the npm
   check path then happens to resolve to the real npm location.

### CLI tool wrappers (three sed rewrites)

The CLI zip's `bin/` wrappers (`hvigorw`, `ohpm`, `hstack`, `codelinter`,
`Emulator`) are bash scripts that resolve their own location via
`cd "$(dirname "$0")"` and then walk up to find tools. Three fixes:

1. **`dirname "$0"` → `dirname "$(readlink -f "$0")"`**: when invoked
   through the `/usr/bin` symlinks, `$0` is `/usr/bin/<tool>` and
   `dirname` resolves to `/usr/bin` — every tool would look in the wrong
   place. (Same bug class as the old `/usr/bin/devecostudio` wrapper
   recursion.)
2. **`$all_tool_dir/tool/node` → `$all_tool_dir/node`** and
   **`$all_tool_dir/sdk` → `$all_tool_dir/../sdk`**: the wrappers assume
   the CLI's `bin/` sits next to `tool/` and `sdk/`; we copy them to
   `tools/bin/` where node is `tools/node` and sdk is `/opt/.../sdk`
   (parent of `tools/`).
3. **codelinter's inner launcher** (`tools/codelinter/bin/codelinter`)
   hardcodes `$ROOT_PATH/tool/node` and `$ROOT_PATH/sdk` (ROOT_PATH =
   `tools/`). Rather than creating `tools/tool/node` symlinks — which look
   like a second node install and can confuse IDE node discovery — the
   script itself is rewritten to `$ROOT_PATH/node` / `$ROOT_PATH/../sdk`.

### /usr/bin exposure

`devecostudio` always links to the wrapper. The five CLI tools are exposed
only if `_expose_cli_tools=true`; `hvigorw`/`ohpm`/`hstack` use their
original names (Huawei-specific, unlikely to collide), while
`codelinter`/`Emulator` get an `h` prefix (`hcodelinter`, `hemulator`)
unless `_hprefix_generic_tools=false`. Toggle both at the top of the
PKGBUILD.

### vmoptions transformation

`bin/devecostudio64-lin.vmoptions` is the Mac `devecostudio.vmoptions`
sed-converted:
- `-Dsun.java2d.metal=true` → `-Dsun.java2d.opengl=true`
- drops `-Djava.security.manager` and the `-Dwsl` line
- appends `-Dawt.lock.fair=true`, `-Dsun.tools.attach.tmp.only=true`,
  `-Dglfw.im.module=fcitx` (GLFW IME module for JBR 25)

`product-info.json` is not a static file — it is extracted from the DMG
and transformed with `jq` at build time: OS/arch/launcher/java/vmoptions
paths rewritten (`$APP_PACKAGE/Contents/` → `$IDE_HOME/`), macOS-only
`--add-opens` (com.apple.*, sun.lwawt) filtered out, Linux add-opens
(sun.awt.X11, com.sun.java.swing.plaf.gtk) and the native-access
flag appended, `startupWmClass=deveco-studio`. The 202-entry
`bootClassPathJarNames` comes straight from the DMG — the jq filter never
hardcodes it. (A stale `product-info.json` in the repo was deleted for
this reason: it isn't read by the build.)

### JBR and native libs

JBR is wholesale replaced by the IDEA Linux JBR (`jbr/`). Native libs are
replaced per-directory: `lib/native/linux-x86_64`, `lib/pty4j/linux`,
`lib/jna/amd64/libjnidispatch.so`, and `lib/skiko-awt-runtime-all`
(26.0.0 added this dir; the Mac DMG ships a `.dylib`, replaced by the
Linux version). A mac-style `jbr/Contents/Home/bin` symlink exists because
some Huawei plugins hardcode that path.

### JCEF / CEF UI under Wayland

CEF-based UI (project structure dialog, markdown preview) crashes its GPU
process under Wayland: `eglCreateWindowSurface` segfault in the
`jcef_helper` GPU process, detected by the IDE as repeated GPU-process
restarts. The wrapper forces the X11 backend by default (`unset
WAYLAND_DISPLAY`, `GDK_BACKEND=x11`), which routes Chromium through
XWayland/GLX and works. Opt out with `DEVECO_DISABLE_X11_WORKAROUND=1`
(CEF pages then break). The IDE may also have persisted
`ide.browser.jcef.gpu.disable=true` in its registry from a crash episode.

### Permissions and executability

Mac DMG files ship 700; `cp -a` preserves that, so the package does a
global `chmod 755` on dirs and `644` on files, then restores exec bits.
The exec-bit restore uses **Python reading the first 256 bytes** (ELF
magic `\x7fELF`, or a shebang `#!` anywhere in the head — some CLI scripts
put a copyright comment before the shebang, notably `hstack`). The `file`
utility was tried first and crashed with SIGSYS on the huge tree, silently
leaving helpers (e.g. `jbr/lib/jspawnhelper`, `emulator/Emulator`,
`tools/node/bin/node`) without +x, which broke child-process spawning
(`posix_spawn: EACCES`) — one of the classic "works until you run
something" bugs.

### Strip

`options=('!strip')` at the package level; stripping is done manually and
selectively (JBR binaries, launcher, native `.so`s, fsnotifier). The SDK
is deliberately **not** stripped (contains cross-compiled ARM binaries).

### Cleanup pass

`*.exe` (except `Emulator.exe`), `*.dll`, `*.dylib`, `*.jnilib`, `*.bat`,
`*.ps1` are deleted. `*.sh` cleanup is scoped to `bin/`, `tools/bin/`, and
`plugins/` — a blanket delete previously removed real SDK content
(`llvm/bin/lldb.sh`, cmake `Squish*.sh`).

### `ohos-trace` plugin removal

`plugins/ohos-trace` is deleted; it carries the "lemon" plugin bug (exit hang).

### UxTestService

Mac-only tool in the DMG (Python, cross-platform). Comes from the DMG, not
the CLI.

## Runtime layout (installed)

```
/opt/devecostudio/
├── bin/
│   ├── devecostudio            ← IDEA launcher (stripped)
│   ├── devecostudio.sh         ← wrapper (env setup + path bridges)
│   ├── devecostudio.svg
│   ├── devecostudio64-lin.vmoptions
│   ├── idea.properties
│   └── fsnotifier
├── jbr/                        ← IDEA Linux JBR (+ Contents/Home/bin symlink)
├── lib/                        ← DMG jars + native/linux-x86_64 + pty4j + jna + skiko
├── modules/
├── plugins/
├── sdk/                        ← CLI SDK (hdc at sdk/default/openharmony/toolchains/hdc)
├── license/
├── build.txt
├── product-info.json           ← jq-transformed from DMG
└── tools/
    ├── bin/                    ← CLI wrappers (readlink-fixed)
    ├── node/ + lib/node_modules (2 symlinks above)
    ├── hvigor/ ohpm/ hstack/ codelinter/ emulator/ UxTestService/
/usr/bin/devecostudio → /opt/devecostudio/bin/devecostudio.sh
/usr/bin/{hvigorw,ohpm,hstack,hcodelinter,hemulator} (configurable)
```

The wrapper (devecostudio.sh) responsibilities, in order:
1. `_JAVA_AWT_WM_NONREPARENTING=1`
2. `QT_QPA_PLATFORM=xcb` (emulator Qt)
3. X11 backend for JCEF unless `DEVECO_DISABLE_X11_WORKAROUND=1`
4. `~/Library/Huawei/Sdk` → `~/.Huawei/Sdk` bridge (emulator images)
5. exec the real launcher via `readlink -f` on `$0` (works through the
   `/usr/bin` symlink)

## Maintenance checklist

### New DevEco Studio release

1. Get the new `devecostudio-mac-<v>.zip` + `commandline-tools-linux-x64-<v>.zip`
   from Huawei (signed, expiring links).
2. **Analyze the actual layouts first** (rule: never trust paths inherited
   from the previous release): `7z l`/`7z x` the DMG, diff `lib/`,
   `plugins/`, `tools/`, and read the new `Resources/product-info.json`
   (buildNumber → baseline IDEA version → `_ideaver`). Upstream moves
   things between versions — e.g. 26.0.0 flattened all jars into `lib/`
   and removed `lib/modules` + `lib/cds`, and added
   `lib/skiko-awt-runtime-all` and `tools/dumpParser` (Mach-O, excluded).
3. Update `pkgver`, `_ideaver`, and the two Huawei zip `sha256sums`.
4. `makepkg -f`, install, and run the test checklist below.

### Test checklist (after build)

- [ ] `devecostudio --version` prints the right build
- [ ] Project opens; hvigor **sync** succeeds (no Node.js path warning)
- [ ] CEF UI works: project structure dialog, markdown preview
- [ ] Device Manager: emulator list loads; create/start/stop/edit/delete
- [ ] Debugging from the run panel (emulator started via CLI or IDE)
- [ ] All five CLI tools: `hvigorw --version`, `ohpm --version`,
      `hstack --version`, `hcodelinter --version`, `hemulator --version`
- [ ] `hdc list targets` sees a running emulator

### Release

- Bump `pkgrel` for packaging changes, commit, GPG-sign, push
- Tag `v?`-style like `26.0.0.621-2` (annotated + signed) after local
  verification; README tells users to build from the tag.

## Known upstream quirks / traps

- **Huawei zips inside a zip**: `devecostudio-mac-*.zip` contains a `.dmg`.
  `prepare()` finds the `.dmg` with `find`.
- **`makepkg` auto-extracts** the two zips and the tarball into `$srcdir`
  before `prepare()` — do not re-extract them; `prepare()` only handles the
  DMG (with `7z x` include paths limited to `DevEco-Studio.app/Contents`
  and `-x!` exclusions).
- **pacman file conflicts on upgrade**: manually created symlinks on a
  previously-installed system (e.g. `tools/lib/node_modules`,
  `tools/node/node_modules`, `tools/emulator/Emulator.exe`) conflict with
  the package versions — remove them before `pacman -U`.
- **`7z x` "Dangerous link path" warning** for DMG extraction disappears
  once `Contents/jbr` is excluded.
- **`file` crashes** (SIGSYS) on the large tree — use the Python head-byte
  scan for exec-bit detection.
- **`ln -sf bin/*` from the wrong cwd** silently creates a broken
  `bin/*` symlink — always `(cd dir && ln -sf ...)`.
- The `find "$_pkg" -name '*.sh' -delete` blanket rule is a footgun (SDK
  content) — keep it scoped.
- Wayland: JCEF GPU process crashes; use the X11 workaround.
