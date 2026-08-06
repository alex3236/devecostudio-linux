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
pkgver=26.0.0.621
_ideaver=2026.1.3
pkgrel=1
install='devecostudio.install'
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
  cp -a "$_cli/tool/node/" "$_pkg/tools/node/"
  # symlink bin/* to tools/node (IDE expects node/npm/npx/corepack alongside bin/)
  (cd "$_pkg/tools/node" && ln -sf bin/* .)
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
  # installed as /usr/bin/<tool>; sed-fix their relative ../tool/node and ../sdk references
  mkdir -p "$_pkg/tools/bin"
  cp -a "$_cli/bin/"* "$_pkg/tools/bin/"
  sed -i 's|\$all_tool_dir/tool/node|\$all_tool_dir/node|g; s|\$all_tool_dir/sdk|\$all_tool_dir/../sdk|g' "$_pkg/tools/bin/"*
  chmod +x "$_pkg/tools/bin/"*
  mkdir -p "$pkgdir/usr/bin"
  for _w in hvigorw ohpm hstack codelinter Emulator; do
    ln -sf /opt/devecostudio/tools/bin/$_w "$pkgdir/usr/bin/$_w"
  done

  # ── Sign path fix (some Huawei plugins expect macOS-style path) ──
  mkdir -p "$_pkg/jbr/Contents/Home"
  ln -sf ../../bin "$_pkg/jbr/Contents/Home/bin"

  # ── Wrapper script ──
  cat > "$_pkg/bin/devecostudio.sh" << 'SHEOF'
#!/bin/bash
export _JAVA_AWT_WM_NONREPARENTING=1
# Emulator uses the Qt xcb platform plugin (no wayland build shipped)
export QT_QPA_PLATFORM=xcb
# JCEF (CEF-based UI: project structure, markdown preview) crashes its GPU
# process under Wayland (eglCreateWindowSurface segfault). Force the X11
# backend by default; set DEVECO_DISABLE_X11_WORKAROUND=1 to keep Wayland.
if [[ "${DEVECO_DISABLE_X11_WORKAROUND:-0}" != "1" ]]; then
  unset WAYLAND_DISPLAY
  export GDK_BACKEND=x11
fi
# Emulator hardcodes the macOS-style image path ~/Library/Huawei/Sdk;
# bridge it to the Linux location so it finds system images
mkdir -p "$HOME/Library/Huawei"
ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"
exec "$(dirname "$(readlink -f "$0")")/devecostudio" "$@"
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
  find "$_pkg" -name '*.exe' -delete
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
