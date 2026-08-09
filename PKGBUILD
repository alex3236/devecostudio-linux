# Maintainer: Your Name <you@example.com>
# Contributor: alex3236
#
# === Manual downloads (place in same directory as PKGBUILD) ===
# Both files must be renamed to the fixed names below (the filenames are
# version-independent, so only pkgver and the checksums change on upgrade).
# If you use a different version, update pkgver and the SHA256 checksums
# (or set them to "SKIP" to skip verification).
#
# 1. devecostudio-mac.zip — Mac (X86 or ARM, either works)
#    Download from: https://developer.huawei.com/consumer/cn/deveco-studio/
#
# 2. commandline-tools-linux-x64.zip — Command Line Tools for Linux
#    Download from same page

pkgname=devecostudio
pkgdesc='Huawei DevEco Studio repackaged for Arch Linux'
pkgver=26.0.0.621
_ideaver=2026.1.3
pkgrel=7
# ── CLI tool exposure ──
# The bundled Huawei CLI tools (hvigorw, ohpm, hstack, codelinter, Emulator)
# live under /opt/devecostudio/tools/bin/. Set _expose_cli_tools=false to
# keep them out of /usr/bin entirely (use full paths instead).
_expose_cli_tools=true
# codelinter and Emulator are generic names that may collide with other
# packages; prefix them with "h" unless you opt out.
_hprefix_generic_tools=true
arch=('x86_64')
url='https://developer.huawei.com/consumer/cn/deveco-studio/'
license=('custom:Commercial')
depends=(
  'libxss'
  'libxtst'
  'nss'
  'alsa-lib'
  'libxcrypt-compat'
  'freetype2'
  'libpulse'  # Emulator links system libpulse.so.0
)
optdepends=(
  'fcitx5: Chinese input method support for JBR JCEF'
)
makedepends=('jq' 'p7zip')
options=('!strip')
source=(
  "devecostudio-mac.zip"
  "commandline-tools-linux-x64.zip"
  "idea-${_ideaver}.tar.gz::https://download.jetbrains.com/idea/idea-${_ideaver}.tar.gz"
  "devecostudio.desktop"
)
sha256sums=(
  '5d67a2cfdd7b984a9c9f64e5abc6e082c5e3bc958833a92a55370cc623799ce1'
  '0cea7ad6cc1af98ac701b9c61b7c9aae2d0f2104749a80ae84c1f6ca0fc17555'
  'a6f049716da1d09d9e0ec1500c60bf01a5ff8a0fe2419178dd1ff2fdb2b77563'
  'b530705424c7fdd61c3eaa477d6c79643e5d9d0cf7ecadc8f6e96559b7c6dc2d'
)

prepare() {
  # ── Extract Mac DMG ──
  msg2 "Extracting Mac DMG..."
  _dmg=$(find "$srcdir" -name '*.dmg' -type f | head -1)
  if [[ -z "$_dmg" ]]; then
    error "deveco-studio-*.dmg not found (was the zip corrupted?)"
    exit 1
  fi
  7z x -y -o"$srcdir/mac_dmg" "$_dmg" \
    "DevEco-Studio/DevEco-Studio.app/Contents" \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/sdk/default' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/jbr' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/emulator' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/dumpParser' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/llvm' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/profiler' \
    -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/node' \
    2>&1 | grep -v "^\s*$" | grep -v "Sub items Errors" | tail -3
  _mac="$srcdir/mac_dmg/DevEco-Studio/DevEco-Studio.app/Contents"
  if [[ ! -d "$_mac/plugins" || ! -f "$_mac/Resources/product-info.json" ]]; then
    error "Mac DMG extraction failed — could not find Contents/plugins or product-info.json"
    ls -la "$srcdir/mac_dmg/"
    exit 1
  fi

  # ── Locate auto-extracted sources ──
  _idea=$(find "$srcdir" -mindepth 1 -maxdepth 1 -type d -name 'idea-IU-*' | head -1)
  if [[ ! -d "$_idea" ]]; then
    error "IntelliJ IDEA not found (macro error)"
    ls "$srcdir/"
    exit 1
  fi

  _cli="$srcdir/command-line-tools"
  if [[ ! -d "$_cli" ]]; then
    error "CLI tools not found (macro error)"
    ls "$srcdir/"
    exit 1
  fi
}

package() {
  local _mac="$srcdir/mac_dmg/DevEco-Studio/DevEco-Studio.app/Contents"
  local _idea=$(find "$srcdir" -mindepth 1 -maxdepth 1 -type d -name 'idea-IU-*' | head -1)
  local _cli="$srcdir/command-line-tools"
  local _pkg="$pkgdir/opt/devecostudio"

  msg2 "Creating directory skeleton..."
  mkdir -p "$_pkg"/{bin,jbr,lib,plugins,modules,tools,license,sdk}

  msg2 "Copying cross-platform files from Mac DMG..."

  # lib/*.jar (26.0.0+ flattens all platform jars into lib/)
  cp -a "$_mac/lib/"*.jar "$_pkg/lib/"

  # plugins (minus ohos-trace which has the lemon bug)
  # Use * glob to avoid nested plugins/plugins/ directory
  cp -a "$_mac/plugins/"* "$_pkg/plugins/"
  rm -rf "$_pkg/plugins/ohos-trace"

  # modules
  cp -a "$_mac/modules/"* "$_pkg/modules/"

  # tools: prefer CLI (Linux) versions where available; UxTestService is
  # Mac-only (Python, cross-platform) and stays from the DMG.
  # hvigor/ohpm/hstack/codelinter/emulator/node from CLI tools
  cp -a "$_cli/hvigor/" "$_pkg/tools/hvigor"
  cp -a "$_cli/ohpm/" "$_pkg/tools/ohpm"
  cp -a "$_cli/hstack/" "$_pkg/tools/hstack"
  cp -a "$_cli/codelinter/" "$_pkg/tools/codelinter"
  cp -a "$_cli/emulator/" "$_pkg/tools/emulator"
  # Huawei's code only distinguishes Mac vs non-Mac; the non-Mac branch
  # hardcodes the "Emulator.exe" name. Symlink it to the real binary so
  # Device Manager and debugging work on Linux.
  ln -sf Emulator "$_pkg/tools/emulator/Emulator.exe"
  cp -a "$_cli/tool/node/" "$_pkg/tools/node/"
  # symlink bin/* to tools/node (IDE expects node/npm/npx/corepack alongside bin/)
  (cd "$_pkg/tools/node" && ln -sf bin/* .)
  # The IDE's node version check (getNpmVersionFast) looks for npm's
  # package.json at <parentDir>/lib/node_modules/npm/package.json where
  # parentDir = <nodeDir>/.. — i.e. tools/lib/node_modules — but the CLI
  # ships npm under <nodeDir>/lib/node_modules (upstream node layout).
  # Without these symlinks, project sync reports "Invalid project Node.js
  # path" even though node itself is fine.
  ln -sfn lib/node_modules "$_pkg/tools/node/node_modules"
  mkdir -p "$_pkg/tools/lib"
  ln -sfn ../node/lib/node_modules "$_pkg/tools/lib/node_modules"
  # UxTestService from Mac DMG (Python, cross-platform)
  mkdir -p "$_pkg/tools/UxTestService"
  cp -a "$_mac/tools/UxTestService/"* "$_pkg/tools/UxTestService/"

  # license
  cp -a "$_mac/license/"* "$_pkg/license/"

  # build.txt
  cp -a "$_mac/Resources/build.txt" "$_pkg/"

  # svg icon
  cp -a "$_mac/bin/devecostudio.svg" "$_pkg/bin/"

  # idea.properties (cross-platform, use as-is)
  cp -a "$_mac/bin/idea.properties" "$_pkg/bin/"

  msg2 "Transforming vmoptions (macOS → Linux)..."
  sed \
    -e 's/-Dsun.java2d.metal=true/-Dsun.java2d.opengl=true/' \
    -e '/^-Djava.security.manager/d' \
    -e '/^-Dwsl/d' \
    "$_mac/bin/devecostudio.vmoptions" > "$_pkg/bin/devecostudio64-lin.vmoptions"
  cat >> "$_pkg/bin/devecostudio64-lin.vmoptions" << 'VMEOF'
-Dawt.lock.fair=true
-Dsun.tools.attach.tmp.only=true
-Dglfw.im.module=fcitx
VMEOF

  msg2 "Replacing platform-specific components from IntelliJ IDEA (JBR, launcher, native libs)..."

  # JBR
  rm -rf "$_pkg/jbr"
  cp -a "$_idea/jbr/" "$_pkg/jbr/"

  # launcher
  cp -a "$_idea/bin/idea" "$_pkg/bin/devecostudio"
  chmod +x "$_pkg/bin/devecostudio"

  # fsnotifier
  cp -a "$_idea/bin/fsnotifier" "$_pkg/bin/"

  # native libs
  rm -rf "$_pkg/lib/native" "$_pkg/lib/pty4j" "$_pkg/lib/jna" "$_pkg/lib/skiko-awt-runtime-all"
  mkdir -p "$_pkg/lib/native/linux-x86_64" "$_pkg/lib/pty4j/linux" "$_pkg/lib/jna/amd64" "$_pkg/lib/skiko-awt-runtime-all"
  cp -a "$_idea/lib/native/linux-x86_64/"* "$_pkg/lib/native/linux-x86_64/"
  cp -a "$_idea/lib/pty4j/linux/"* "$_pkg/lib/pty4j/linux/"
  cp -a "$_idea/lib/jna/amd64/libjnidispatch.so" "$_pkg/lib/jna/amd64/"
  cp -a "$_idea/lib/skiko-awt-runtime-all/"* "$_pkg/lib/skiko-awt-runtime-all/"

  msg2 "Replacing platform-specific components from CLI tools (SDK, wrappers)..."

  # SDK
  rm -rf "$_pkg/sdk"
  cp -a "$_cli/sdk/" "$_pkg/sdk/"

  # CLI terminal wrappers (bin/hvigorw, bin/ohpm, bin/hstack, bin/codelinter, bin/Emulator)
  # stay under tools/bin/ for the IDE; optionally expose them via /usr/bin
  # (sed-fix their relative ../tool/node and ../sdk references first)
  mkdir -p "$_pkg/tools/bin"
  cp -a "$_cli/bin/"* "$_pkg/tools/bin/"
  # Resolve $0 through readlink so the wrappers also work when invoked via
  # the /usr/bin symlinks (dirname "$0" would resolve to /usr/bin)
  sed -i 's|cd "$(dirname "$0")"|cd "$(dirname "$(readlink -f "$0")")"|' "$_pkg/tools/bin/"*
  sed -i 's|\$all_tool_dir/tool/node|\$all_tool_dir/node|g; s|\$all_tool_dir/sdk|\$all_tool_dir/../sdk|g' "$_pkg/tools/bin/"*
  chmod +x "$_pkg/tools/bin/"*
  # codelinter's launcher hardcodes <tools>/tool/node and <tools>/sdk;
  # rewrite them to our actual layout instead of adding symlinks that
  # could confuse the IDE's node discovery.
  sed -i 's|\$ROOT_PATH/tool/node|\$ROOT_PATH/node|; s|\$ROOT_PATH/sdk|\$ROOT_PATH/../sdk|' "$_pkg/tools/codelinter/bin/codelinter"
  # Emulator wrapper additions: bridge the macOS-style image path symlink,
  # and auto-accept the software agreements on first use so the IDE never
  # hangs silently waiting for a 'y' (the IDE launches the emulator binary
  # directly, bypassing this wrapper, so the agreements must already be
  # accepted). When .emu_config is missing we run `-license accept` only
  # (the requested command is not forwarded) and print how to opt out.
  cat > "$srcdir/emulator-wrapper-patch.sh" << 'PATCHEOF'
mkdir -p "$HOME/Library/Huawei"
ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"
_emu_config="$HOME/Library/Caches/Huawei/Emulator26.0/.emu_config"
if [[ ! -f "$_emu_config" ]]; then
    echo "Emulator software agreements not yet accepted. Displaying and accepting them now..."
    "$all_tool_dir/emulator/Emulator" -license accept
    echo ""
    echo "Re-run your command to proceed."
    echo "To opt out: truncate $_emu_config."
    exit 0
fi
PATCHEOF
  sed -i '/"$all_tool_dir\/emulator\/Emulator" "\$@"/r '"$srcdir/emulator-wrapper-patch.sh" "$_pkg/tools/bin/Emulator"
  if [[ "$_expose_cli_tools" == "true" ]]; then
    mkdir -p "$pkgdir/usr/bin"
    # Huawei-specific names: expose as-is
    for _w in hvigorw ohpm hstack; do
      ln -sf /opt/devecostudio/tools/bin/$_w "$pkgdir/usr/bin/$_w"
    done
    # Generic names: prefix with "h" by default to avoid collisions
    if [[ "$_hprefix_generic_tools" == "true" ]]; then
      ln -sf /opt/devecostudio/tools/bin/codelinter "$pkgdir/usr/bin/hcodelinter"
      ln -sf /opt/devecostudio/tools/bin/Emulator "$pkgdir/usr/bin/hemulator"
    else
      ln -sf /opt/devecostudio/tools/bin/codelinter "$pkgdir/usr/bin/codelinter"
      ln -sf /opt/devecostudio/tools/bin/Emulator "$pkgdir/usr/bin/Emulator"
    fi
  fi

  # ── Sign path fix (some Huawei plugins expect macOS-style path) ──
  mkdir -p "$_pkg/jbr/Contents/Home"
  ln -sf ../../bin "$_pkg/jbr/Contents/Home/bin"

  # ── Wrapper script ──
  cat > "$_pkg/bin/devecostudio.sh" << 'SHEOF'
#!/bin/bash
export _JAVA_AWT_WM_NONREPARENTING=1
# Emulator uses the Qt xcb platform plugin (no wayland build shipped)
export QT_QPA_PLATFORM=xcb
# XWayland reports monitor scale 1.0 to JBR, so the IDE locks UI scale to
# 1.0 — too small on HiDPI. Inject the compositor's real scale (wlr-randr,
# needs WAYLAND_DISPLAY so run it before unsetting it) as -Dide.ui.scale.
# DEVECO_UI_SCALE: number (override, as-is) or "off" (disable).
_hidpi_scale=""
case "${DEVECO_UI_SCALE:-auto}" in
  off) ;;
  auto)
    _cs=""
    command -v wlr-randr >/dev/null 2>&1 && \
      _cs=$(wlr-randr 2>/dev/null | awk '/Scale:/{print $2; exit}')
    if [[ "$_cs" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      _hidpi_scale=$(LC_ALL=C awk -v s="$_cs" 'BEGIN{ q=int(s*4+0.5)/4; if (q<1.0) q=1.0; printf "%.2f", q }')
    fi
    ;;
  *)
    if [[ "$DEVECO_UI_SCALE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      _hidpi_scale="$DEVECO_UI_SCALE"
    else
      printf 'Ignoring invalid DEVECO_UI_SCALE=%q (expected auto, off, or a number)\n' \
        "$DEVECO_UI_SCALE" >&2
    fi
    ;;
esac
if [[ -n "$_hidpi_scale" ]]; then
  _cfg="${XDG_CONFIG_HOME:-$HOME/.config}/Huawei/DevEcoStudio26.0"
  if mkdir -p "$_cfg"; then
    echo "-Dide.ui.scale=$_hidpi_scale" > "$_cfg/devecostudio-hidpi.vmoptions"
    export DEVECOSTUDIO_VM_OPTIONS="$_cfg/devecostudio-hidpi.vmoptions"
  else
    printf 'Unable to create the HiDPI vmoptions overlay in %s\n' "$_cfg" >&2
  fi
fi
# JCEF GPU process crashes under Wayland; use the X11 backend by default
# (DEVECO_DISABLE_X11_WORKAROUND=1 to keep Wayland).
if [[ "${DEVECO_DISABLE_X11_WORKAROUND:-0}" != "1" ]]; then
  unset WAYLAND_DISPLAY
  export GDK_BACKEND=x11
fi
# JCEF headless + out-of-process rendering fixes blank CEF pages in some
# environments (DEVECO_DISABLE_JCEF_HEADLESS=1 to opt out).
_JCEF_ARGS=()
if [[ "${DEVECO_DISABLE_JCEF_HEADLESS:-0}" != "1" ]]; then
  _JCEF_ARGS=("-Dide.browser.jcef.headless.enabled=true" "-Dide.browser.jcef.out-of-process.enabled=true")
fi
# Emulator hardcodes the macOS-style image path ~/Library/Huawei/Sdk
mkdir -p "$HOME/Library/Huawei"
ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"
exec "$(dirname "$(readlink -f "$0")")/devecostudio" "${_JCEF_ARGS[@]}" "$@"
SHEOF
  chmod +x "$_pkg/bin/devecostudio.sh"

  # ── product-info.json (extracted from Mac DMG, transformed for Linux via jq) ──
  jq \
    --arg os "Linux" \
    --arg arch "amd64" \
    --arg launcher "bin/devecostudio" \
    --arg java "jbr/bin/java" \
    --arg vmopts "bin/devecostudio64-lin.vmoptions" \
    --arg wmclass "deveco-studio" \
    --arg svg "bin/devecostudio.svg" \
    '.svgIconPath = $svg |
     .launch[0].os = $os |
     .launch[0].launcherPath = $launcher |
     .launch[0].javaExecutablePath = $java |
     .launch[0].arch = $arch |
     .launch[0].vmOptionsFilePath = $vmopts |
     .launch[0].startupWmClass = $wmclass |
     del(.launch[0].svgIconPath) |
     .launch[0].additionalJvmArguments |= (
       map(gsub("\\$APP_PACKAGE/Contents/"; "$IDE_HOME/")) |
       map(select(test("com\\.apple\\.eawt|com\\.apple\\.laf|sun\\.lwawt") | not)) |
       . + [
         "--enable-native-access=ALL-UNNAMED",
         "-Dawt.lock.fair=true",
         "-Dsun.tools.attach.tmp.only=true",
         "-Dglfw.im.module=fcitx",
         "--add-opens=java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED",
         "--add-opens=java.desktop/javax.swing.text.html.parser=ALL-UNNAMED",
         "--add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED"
       ]
     )' \
    "$_mac/Resources/product-info.json" > "$_pkg/product-info.json"

  msg2 "Stripping Linux binaries..."
  # Strip JBR, launcher, native .so; skip cross-compiled ARM SDK binaries
  find "$_pkg/jbr" -type f -executable -exec strip --strip-all {} \; 2>/dev/null || true
  strip --strip-all "$_pkg/bin/devecostudio" 2>/dev/null || true
  find "$_pkg/lib" -name '*.so' -exec strip --strip-unneeded {} \; 2>/dev/null || true
  strip --strip-all "$_pkg/bin/fsnotifier" 2>/dev/null || true

  msg2 "Fixing permissions (Mac DMG files have 700)..."
  # Mac DMG preserves 700 permissions via cp -a; fix for world-readability
  find "$_pkg" -type d -exec chmod 755 {} \;
  find "$_pkg" -type f -exec chmod 644 {} \;
  # Restore executability for all ELF binaries and shebang scripts.
  # Use Python (not `file`) to avoid crashes on the huge file tree.
  python3 - "$_pkg" << 'PYEOF'
import os, sys
root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        try:
            with open(p, 'rb') as f:
                head = f.read(256)
            # ELF magic, or a shebang anywhere in the first 256 bytes
            # (some CLI scripts put a copyright comment before #!)
            if head[:4] == b'\x7fELF' or b'#!' in head:
                st = os.stat(p)
                if not st.st_mode & 0o111:
                    os.chmod(p, st.st_mode | 0o111)
        except OSError:
            pass
PYEOF

  msg2 "Cleaning platform cruft..."
  find "$_pkg" -name '*.exe' -not -name 'Emulator.exe' -delete
  find "$_pkg" -name '*.dll' -delete
  find "$_pkg" -name '*.dylib' -delete
  find "$_pkg" -name '*.jnilib' -delete
  find "$_pkg" -name '*.bat' -delete
  find "$_pkg" -name '*.ps1' -delete
  # Remove Windows/macOS wrapper scripts, but keep real .sh files inside the
  # SDK (lldb launchers, cmake modules, build helpers)
  find "$_pkg/bin" "$_pkg/tools/bin" -name '*.sh' -not -path '*/bin/devecostudio.sh' -delete 2>/dev/null || true
  find "$_pkg/plugins" -name '*.sh' -delete 2>/dev/null || true

  # ── Desktop entry & symlink ──
  install -Dm644 "$srcdir/devecostudio.desktop" "$pkgdir/usr/share/applications/devecostudio.desktop"
  mkdir -p "$pkgdir/usr/bin"
  ln -sf /opt/devecostudio/bin/devecostudio.sh "$pkgdir/usr/bin/devecostudio"
}
