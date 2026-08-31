# DevEco Studio Linux Package — Implementation Details

This file documents **why** the PKGBUILD does what it does — every piece of
"magic", the upstream quirk it works around, and the details that matter
when maintaining or forking this package. The README is the user-facing
view; this is the developer-facing view.

## Architecture: three sources, one package

| Source | What it provides | Why |
|---|---|---|
| **Mac DMG** (`devecostudio-mac.zip`) | `lib/*.jar`, `plugins/`, `modules/`, `license/`, `build.txt`, `bin/devecostudio.svg`, `bin/idea.properties`, `bin/devecostudio.vmoptions`, `Resources/product-info.json`, `tools/UxTestService` | Huawei ships DevEco Studio for Windows, macOS, and Linux. The Windows installer is an `.exe` that is painful to extract and lags in version; the Mac DMG extracts trivially with `7z x` and all of these files are platform-independent (Java bytecode, resources, templates). |
| **JetBrains IDEA tarball** (`idea-${_ideaver}.tar.gz`) | `jbr/`, `bin/idea` launcher, `bin/fsnotifier`, `lib/native/linux-x86_64/`, `lib/pty4j/linux/`, `lib/jna/amd64/`, `lib/skiko-awt-runtime-all/` | The macOS-specific bits (JBR, launcher, native `.so`s) are replaced with Linux ones. DevEco's build number is pinned to a specific IDEA baseline — see "IDEA version matching" below. |
| **Command Line Tools for Linux** (`commandline-tools-linux-x64.zip`) | `sdk/`, `tool/node/`, `hvigor/`, `ohpm/`, `hstack/`, `codelinter/`, `emulator/`, `arktsdoc/`, `bin/` wrappers | The CLI zip already contains Linux-native versions of every tool, and its SDK is the one the IDE needs. |

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
The same bridge is added to the `Emulator` CLI wrapper (in
`tools/bin/Emulator`) so CLI-only users who never launch the IDE still get
working image paths.
The emulator also needs `QT_QPA_PLATFORM=xcb` (it ships only the xcb Qt
platform plugin — no Wayland build), set by the wrapper.

### Emulator software agreements (auto-accept)

The IDE launches the emulator **binary directly**, bypassing the CLI
wrapper. If the HarmonyOS software agreements were never accepted, the
emulator silently waits for a `y` on stdin and the IDE appears hung — the
classic "starts only after you've run the CLI once" trap.

The agreement state lives in `~/Library/Caches/Huawei/Emulator26.0/.emu_config`
(written by `Emulator -license accept`). The `Emulator` wrapper therefore
does:

```bash
_emu_config="$HOME/Library/Caches/Huawei/Emulator26.0/.emu_config"
if [[ ! -f "$_emu_config" ]]; then
    "$all_tool_dir/emulator/Emulator" -license accept
    exit 0   # original command not forwarded; re-run it
fi
```

Only **existence** is checked, not content — so users can opt out of the
auto-accept by truncating the file (`> .emu_config`), which makes the
wrapper pass through and let the emulator handle agreements itself. Note
`-license` itself always prompts regardless of state (it is not a status
query), and `-license accept` prints every agreement before finishing, so
it takes a while.

### Previewer: unavailable on Linux (how we know)

The previewer (on-device preview) is the one major feature that cannot
work on Linux. The reasons were found by disassembling the CLI's
`Previewer` ELF (`sdk/default/openharmony/previewer/common/bin/Previewer`),
not by guessing:

1. `strings` shows the smoking gun: `JsApp::Run ability start
   failed.Linux is not supported.`, and `objdump -d` reveals the failure
   is **compiled in**, not a runtime check — `RunDebugAbility` is a
   45-byte stub that only calls `PrintLog` with that message, while
   `RunNormalAbility` next to it is a full 1302-byte implementation.
   The debug path (which the IDE always uses, passing `-d`)
   was `#ifdef`-ed out of the Linux build.
2. The branch is chosen at runtime: `RunJsApp` reads a debug flag
   (`cmpb 0xaa(%r14)`), set from the command line via
   `CommandParser::IsSet("d")` → `JsApp::SetIsDebug(true)`.
3. Removing `-d` from the command line (so `RunNormalAbility` runs)
   makes it crash instead: SIGSEGV inside `RSUIContextManager`'s
   constructor, reached via `Window::Create → RSUIDirector::Init`.
   That is the Rosen **render-service client** — a system service that
   only exists on HarmonyOS devices, not on desktop Linux.

So the previewer is doubly blocked upstream: debug preview is compiled
out, and the non-debug path dies in the render-service client. Neither
can be fixed by packaging. (A red herring first: the previewer also
fails to load `libshared_libz.so` / `libhilog.so` — the CLI ships
`libhilog_linux.so` and no zlib shim — but adding those only gets the
engine to the point where it prints "Linux is not supported".)

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

`devecostudio` always links to the wrapper. `hdc` is also always linked
(from the SDK toolchains; it is a plain ELF, not a wrapper). The five CLI
tools are exposed only if `_expose_cli_tools=true`; `hvigorw`/`ohpm`/`hstack`
use their original names (Huawei-specific, unlikely to collide), while
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

### X11 / XWayland HiDPI

XWayland reports monitor scale 1.0 to JBR (per-monitor RANDR info is
missing), so with JRE-managed HiDPI the IDE locks its UI scale to 1.0 —
too small on HiDPI screens. Two things matter:

- `-Dide.ui.scale` (an IntelliJ property) forces the IDE scale; JBR's
  `sun.java2d.uiScale` alone does not work because per-monitor mode
  overrides it.
- The JCEF browser scale follows the IDE scale via
  `JBCefApp.getForceDeviceScaleFactor()`: with JRE HiDPI enabled it
  returns -1 (Chromium auto-detects — good), otherwise it returns
  `ScaleContext.PIX_SCALE` (the IDE scale — correct only if the IDE scale
  is right). Disabling JRE HiDPI (`uiScale.enabled=false` +
  `hidpi.mode=off`) therefore fixes the Swing UI but makes JCEF huge.

The wrapper reads the compositor scale (`wlr-randr`; needs
`WAYLAND_DISPLAY`, so it runs before the X11 workaround unsets it),
rounds to the nearest quarter step, and writes a one-line user vmoptions
overlay injected via `DEVECOSTUDIO_VM_OPTIONS`. That env var is read by
the native launcher and merged with the system vmoptions (verified: the
launcher reads both the main vmoptions file and the user overlay; a
user-level `devecostudio64.vmoptions` in the config dir works the same
way). `DEVECO_UI_SCALE` overrides the value (any number, as-is); `off`
skips the injection and leaves scaling to the JVM.

### Permissions and executability

Mac DMG files ship 700; `cp -a` preserves that, so the package does a
global `chmod 755` on dirs and `644` on files, then restores exec bits.
The chmods use `find -exec chmod {} +` (batched), not the per-file `{} \;`
form — with ~130k files the per-file form forks a process per file and is
the slowest part of the build.
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

### Bundled python is macOS-only (appanalyzer)

The Mac DMG ships a full python under `plugins/app-analyzer/lib/python/`
(Mach-O
binaries plus `com.apple.cs.CodeSignature` xattr sidecar files — proof it
was never meant for Linux). The IDE's appanalyzer (`hos-app-analyzer` jar)
uses it for venv/pip:

- `PathUtil.getInnerPythonHome()` → `<IDE>/plugins/app-analyzer/lib/python/bin`
- `PythonConfigUtil.PYTHON_COMMAND` → `python3`
- `createVenv` runs `<bin>/python3 -m venv --clear <venv>` — execve
  refuses Mach-O, so venv creation always failed with Huawei's misleading
  "check the venv directory permissions / is it locked" message. The venv
  parent dir is actually user-writable
  (`PathManager.getSystemPath()/caches/appanalyzer/pythonconfig`).
- `AllowedPython.VERSION_NUMBER` is parsed dynamically from
  `python3 --version`, but falls back to a hardcoded `3.12.10` when the
  probe fails — which it always does, because `getRealPythonPath()` returns
  a **file** path while `findRealPythonDir()` expects a directory. So the
  venv dir name is effectively pinned to `python_3.12.10`.

The fix replaces the whole `bin/ lib/ include/ share/` tree with a real
Linux CPython **3.12.10** from python-build-standalone
(astral-sh, MIT; `cpython-3.12.10+20250409-...-install_only.tar.gz` is a
automatic source with a pinned checksum). The version must stay exactly
3.12.10: the appanalyzer jar only ships requirements resources for
`python/3.11/` and `python/3.12/`, and `getLocalRequirements` reads
`/python/<minor>/requirements_internal.json` — a 3.14 interpreter produced
`/python/3.14/...` → resource missing → `localRequirements == null` → NPE
in `PipLibraryDownloadUtil.getPipLibraryDownloaded`. `python` sits in
`makedepends` (the exec-bit restore script needs a system interpreter), not
`depends` (the IDE never runs the system python).

### appanalyzer requirements path case mismatch

`initRequirements()` writes `requirements/python_3.12.10/requirements.json`
(`AllowedPython.getFileName()` = `python_%s`), but `getPipLibraryDownloaded`
reads `requirements/Python_3.12.10/requirements.json` — the version string
comes from `python3 --version` output (`"Python 3.12.10"`) with spaces
replaced by `_`. Case-insensitive filesystems (macOS/Windows, where Huawei
tests) treat these as the same file; Linux does not, so the read fails,
`parseProcess(null)` returns null, and every appanalyzer run dies with the
`localRequirements is null` NPE. The launcher bridges the two names with a
symlink (`Python_<ver> → python_<ver>`) and seeds `requirements.json` from
the jar's `python/3.12/requirements_external.json` when missing.

### appanalyzer torch scenario

Torch-related analysis works, with two upstream bugs worked around: (1) the
requirements pin `torchvision==0.21.0` which requires torch 2.6 (the pin is
torch 2.2.2) — a conflict that only resolves on non-Linux because the cuda
deps are `platform_system == "Linux"`-gated; (2) the pip flow runs
`pip wheel <lib> --no-deps` then `pip install <lib> --no-index
--find-links <cache>`, so torch's 11 Linux-only nvidia wheels
(nvrtc/cudnn/cublas/…) are never downloaded.

Fix, both in the package:

- **torchvision 0.21.0 → 0.17.2** in `requirements.json` (runtime, in the
  launcher, when the seed file still has the upstream version).
- **wrap the bundled `bin/python3`** at build time: a bash shim that strips
  `--no-deps`/`--no-index` from argv and `exec -a "$0"` the real ELF. The
  appanalyzer venv's `bin/python3` is a symlink to the bundled one, so the
  venv inherits the wrapper on creation — no timing gap on first use. Only
  Huawei's two pip invocations carry those flags, so every other call
  (version probes, `-m venv`, user pip) passes through untouched.

  Two traps: the shim must exec the **absolute** path to the real
  `python3.12` — `dirname $0` resolves to the venv's `bin/` where
  `python3.12 → python3` is a symlink loop (venv creation hangs); and it
  must keep `exec -a "$0"` so Python still finds the venv's `pyvenv.cfg`
  (otherwise pip installs into the bundled interpreter, which is
  root-owned and unwritable).

### codelinter needs a writable result dir

`tools/codelinter/linter/result/` holds `codelinter.log`, `arkPerfCheck.log`,
`hpauditTmp/`. The wrapper creates it and the linter writes into it on every
run; with the dir at root:755 and stale root-owned 600 logs from a previous
`sudo` run, a non-root user gets "failed to execute" with no log written.
The package chmods the dir to 777; a fresh install starts empty so no stale
files remain. (Root-owned 600 leftovers from manual sudo runs must be
deleted locally.)

### `ohos-trace` plugin removal

`plugins/ohos-trace` is deleted; it carries the "lemon" plugin bug (exit hang).

### UxTestService

Mac-only tool in the DMG (Python, cross-platform). Comes from the DMG, not
the CLI. (The 26.0.0.821 Mac app still ships it under
`Contents/tools/UxTestService`.)

### app-analyzer moved to its own plugin (26.0.0.821)

The apptest/appanalyzer jar set and its bundled Mach-O python moved from
`plugins/harmony/lib/` to a dedicated `plugins/app-analyzer/` plugin. The
PKGBUILD's python replacement and the wrapper's venv workaround now target
`plugins/app-analyzer/lib/python`. Everything else (the case-symlink bridge,
the venv-name 3.12.10 fallback, the pip wrapper) is unchanged.

### arktsdoc (new in 26.0.0.821)

An ArkTS documentation generator shipped in the CLI tools. `arktsdoc-deveco`
resolves its root as `ARKTSDOC_HOME/../..` = `/opt/devecostudio`, so its
`tools/node` + `sdk` paths are already correct. The main `arktsdoc` wrapper
resolves `SHELLDIR/../..` = `/opt/devecostudio/tools` and references
`tool/node` + `sdk` relative to that — the PKGBUILD rewrites them like
codelinter's (`$ROOT_DIR/tool/node` → `$ROOT_DIR/node`, `$ROOT_DIR/sdk` →
`$ROOT_DIR/../sdk`). Both are exposed via `tools/bin/arktsdoc`.

### Dual SDK: 26.0.0 vs older (6.1.1 etc.)

DevEco 26.0.0 shipped SDK components as Beta2 (`releaseType: Beta2`,
26.0.0.32), so built artifacts declared `Beta2`. 26.0.0.821 (the current
pkgver) ships a **Release** SDK (26.0.0.105) — the default install now
produces `Release` artifacts and needs no patches. The extra-SDK machinery
remains for older SDKs (e.g. 6.1.1 Release), switchable per project via
`compileSdkVersion`.

**Why the metadata edits failed (don't try again):**

- Editing only `releaseType` in the component metadata has no effect because
  hvigor's daemon caches component data, and the value is read from several
  places (`sdk-pkg.json`, `openharmony/*/oh-uni-package.json`,
  `hms/*/uni-package.json`).
- Editing the version numbers too (`26.0.0.32` → `6.1.1.125`) breaks
  version matching: `HosSdkInfoHandler.getLocalSdks()` filters local
  components by `HosSdkVersion.equals(compileSdkVersion-derived)`; a
  mismatch yields `SDK component missing`.

**The blockers and where their patches live:**

1. hvigor 26.0.0 validates the project's `compileSdkVersion` against
   `VersionConst.SUPPORT_COMPILE_VERSION` (= `"26.0.0"`) in
   `ValidateUtil.integrationVersionCheck()` (`validate-util.js`), rejecting
   anything else with `UNSUPPORTED_COMPILESDKVERSION`.
2. hvigor 6.26.4 (26.0.0.821) added `HmosSdkLoader.checkSdkVersionMatch`
   (`hmos-sdk-loader.js`) which rejects any `compileSdkVersion` whose API
   level differs from the latest support version with
   `COMPILE_SDK_VERSION_MISMATCH` (00303313) — surfaced as "configured
   version: 24, DevEco Studio version: 26.0.0"
   (https://developer.huawei.com/.../ide-hvigor-errorcode-00303-1).
3. The IDE's project sync (`HosIntegrationChecker.checkSameCompileSdkIfConfig`
   in `plugins/harmony/lib/hos-project-mgmt-*.jar`) requires every product's
   `compileSdkVersion` to equal the embedded SDK version (the max of
   `sdk-hos-core-osVersionMapperV2.properties` = `"26.0.0"`) and aborts sync
   with `SyncInterruptException` otherwise.

All three checks are hardwired to the bundled SDK version, so **no patch is
applied by default** — `bin/install-extra-sdk.sh` applies them when it
installs an older SDK:

- hvigor (`validate-util.js`): Python string replacement turning the
  `printErrorExit` into `||void 0`
  (pattern `...isEqualApiVersion)(r,s)&&...||void 0`);
- hvigor (`hmos-sdk-loader.js`): same trick on
  `o.fullVersion!==e&&_log.printErrorExit(...)` → `o.fullVersion!==e||void 0`;
- IDE jar: single-byte patch in `HosIntegrationChecker.class` — the `ifne`
  after `StringUtil.equals()` becomes `goto` (byte sequence
  `b8 00 ad 9a 00 0b` → `b8 00 ad a7 00 0b`, verified identical in
  26.0.0.621 and 26.0.0.821), so the error notification is never reached.

All patches are idempotent. Backup of the pristine hvigor file:
`hvigor-patch-backup/validate-util.js.orig-26.0.0` in the repo root.

The extra SDK is extracted with **bsdtar/unzip, not 7z**: 7z refuses the
SDK's symlink chains (`libunwind.so → libunwind.so.1`, `clang →
bisheng-clang`, `clang-cl → clang`, node's `bin/npm → ../lib/...`) as
"Dangerous link via another link was ignored" and silently drops them,
breaking the native toolchains (issue #10). The PKGBUILD's own DMG
extraction still uses 7z — that path only feeds `.dmg` → `Contents` and has
no such links.

With the checks gone, hvigor scans the whole SDK root
(`/opt/devecostudio/sdk/`) for components of any version and selects the
set whose `HosSdkVersion` matches the project's `compileSdkVersion`. The
artifact's `releaseType` follows the *selected SDK's own* metadata
(6.1.1 → `Release`, 26.0.0 → `Release`) — no `getReleaseType` patch needed.

**Installing the extra SDK** — `bin/install-extra-sdk.sh` (bundled, not on
PATH): extracts `sdk/default/{openharmony,hms,sdk-pkg.json}` from a Huawei
commandline-tools zip, reads the SDK's `data.path` (e.g. `HarmonyOS-6.1.1`)
from `sdk-pkg.json` to name the destination directory, copies it under
`/opt/devecostudio/sdk/<path>` with sudo, then applies the two patches
above. The directory name comes from the zip, so the same script works for
any version. After a package upgrade the patches are gone — re-run the
script (or use `-f`-style reinstall by removing the target first) to
re-apply.

**Verified behavior** (26.0.0.621-9 and 26.0.0.821-1):

| project compileSdkVersion | SDK used | artifact |
|---|---|---|
| `'6.1.1(24)'` | HarmonyOS-6.1.1 | `Release`, compileSdkVersion 6.1.1.125 |
| `'26.0.0'` (or unset) | default | `Release`, compileSdkVersion 26.0.0.105 |

**Caveats:**

- After the patches are applied, restart any running hvigor daemon
  (`pkill -f daemon-process-boot-script`) so the new code is loaded.
- Code using API 26-only interfaces (e.g. `@ohos.multimedia.camera`
  `VideoSession`/`PhotoSession` — 26.0.0 made `VideoSession` a superset of
  `PhotoSession`; 6.1.1's `VideoSession` lacks the 5 manual-control mixins)
  won't compile against 6.1.1; widen the declared type (e.g. `PhotoSession`
  → `VideoSession`) or guard the calls.

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
    ├── bin/                    ← CLI wrappers (readlink-fixed) + arktsdoc
    ├── node/ + lib/node_modules (2 symlinks above)
    ├── hvigor/ ohpm/ hstack/ codelinter/ emulator/ arktsdoc/ UxTestService/
/usr/bin/devecostudio → /opt/devecostudio/bin/devecostudio.sh
/usr/bin/hdc → /opt/devecostudio/sdk/default/openharmony/toolchains/hdc (always)
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

### Shared build scripts (`scripts/`)

The files that end up verbatim inside the package live in `scripts/` and
are the single source of truth — the PKGBUILD references them via
`$startdir/scripts/...` (makepkg cannot take subdirectory local sources):

- `scripts/devecostudio.sh` — the launcher wrapper (HiDPI injection, X11
  JCEF workaround, headless JCEF args, `~/Library/Huawei/Sdk` bridge,
  appanalyzer requirements case-bridge + torchvision seed)
- `scripts/install-extra-sdk.sh` — the extra-SDK installer (bsdtar/unzip
  extraction + the three compileSdkVersion patches); installed to
  `bin/install-extra-sdk.sh`
- `scripts/emulator-wrapper-patch.sh` — the license auto-accept block
  `sed`-inserted into the Emulator wrapper
- `scripts/python3-wrapper` — the pip `--no-deps`/`--no-index` stripping
  shim installed as the bundled python3
- `scripts/vmoptions.append` — the Linux-specific vmoptions lines appended
  after the DMG's macOS vmoptions conversion

They are NOT in `source=()` (no checksums): they are repo files like
`devecostudio.desktop`, so edit + commit + rebuild. The standalone
`build.sh` must reference the same files — never re-embed them.

### Standalone build (`build.sh`) + nfpm packaging

`build.sh` runs the PKGBUILD on any distribution without Arch/makepkg: it
`source`s the PKGBUILD, stubs the makepkg macros (`msg2`/`error`/`warning`),
sets `$srcdir`/`$pkgdir`/`$startdir` to `build/src`/`build/pkg`/the repo
root, and calls `prepare` + `package`. This is the answer to the
standalone build.sh from PR #11 — no 700-line port, the PKGBUILD stays
the single source of truth. **Rule: the PKGBUILD must only use the
`msg2`/`error`/`warning` macros and the `srcdir`/`pkgdir`/`startdir`
variables** — introducing another makepkg-only macro breaks standalone
builds.

Two modes:

- **Full build** (default): extracts the sources, downloads IDEA + CPython
  (cached under `build/downloads/`, checksums read by position from the
  PKGBUILD's `sha256sums` — #3 idea, #5 cpython), then runs
  `prepare` + `package`. `--clean` forces re-extraction.
- **`--stage=DIR`**: package an existing staging tree (e.g. makepkg's
  `pkg/`) without building. This is what the GitHub Actions workflow uses
  after `makepkg` — no duplicated build.

Both modes always produce the distro-agnostic tarball
(`devecostudio-<ver>-linux-x86_64.tar.gz`, `gzip -1` for speed — the same
compression the workflow uses), and optionally `.deb`/`.rpm` with **nfpm**
(`--deb`/`--rpm`). `-h`/`--help` prints usage.

What build.sh does beyond makepkg:

- Extracts the sources itself (bsdtar/unzip for zips — 7z would drop the
  SDK symlinks — and tar for the IDEA/CPython tarballs).
- Copies `devecostudio.desktop` into `$srcdir` (makepkg does that for
  local sources).
- nfpm packaging: `nfpm.yaml` maps dependencies per format
  (`overrides: deb/rpm` — Debian names vs Fedora names like
  `libXScrnSaver`, `pulseaudio-libs`, `libxcrypt-compat`), `type: tree`
  pulls in the whole `/opt/devecostudio` tree, and the `/usr/bin`
  symlinks are declared individually. `scripts/postinstall.sh` runs
  `update-desktop-database` for both deb and rpm scriptlets.

Pitfalls learned:

- nfpm 2.47 does **not** expand `{{ .Env.X }}` templates in the config
  (version ends up literal in metadata) — `build.sh` pre-renders with
  `envsubst` (`version: "${PKGVER}"`), which requires gettext.
- The staging tree from build.sh differs from makepkg's only by the SDK's
  static libraries (`*.a`): makepkg's fakeroot tidy removes 177 of them
  (SDK BiSheng `libc++.a` etc.), build.sh keeps them. No functional impact
  (static libs are link-time only).

### CI artifacts (GitHub Actions)

The workflow runs `makepkg -sf` (Arch package; **no `-c`** — `--clean`
removes `pkg/`, which the packaging step needs), then
`./build.sh --stage=pkg/devecostudio --deb --rpm` (tarball + nfpm
deb/rpm from the same tree). nfpm is not in the Arch repos, so the
workflow downloads the static binary from the GitHub release
(`nfpm_2.47.0_Linux_x86_64.tar.gz`, version pinned — update deliberately).

The nfpm rpm packager builds the whole cpio payload in memory and peaks
at ~16 GB RSS (measured) — far above the runner's RAM. The workflow
creates a swapfile sized from the free disk (up to 14 GB, `fallocate` +
`swapon`) before packaging so the rpm build does not get OOM-killed.

Artifacts are uploaded **separately** (not one giant bundle) so users
only download what they need; each is ~3–4 GB:

- `devecostudio-arch` — `.pkg.tar.zst`
- `devecostudio-deb` — `.deb`
- `devecostudio-rpm` — `.rpm`
- `devecostudio-tarball` — `.tar.gz`

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
