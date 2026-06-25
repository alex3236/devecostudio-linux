# Maintainer: Your Name <you@example.com>
# Contributor: alex3236
#
# === Manual downloads (place in same directory as PKGBUILD) ===
# Both files must match the version in pkgver. The SHA256 checksums below
# are for the expected versions; if you use a different version, change the
# checksums to "SKIP" and update pkgver.
#
# 1. devecostudio-mac-${pkgver}.zip — Mac (X86 or ARM, either works)
#    Download from: https://developer.huawei.com/consumer/cn/deveco-studio/
#
# 2. commandline-tools-linux-x64-${pkgver}.zip — Command Line Tools for Linux
#    Download from same page

pkgname=devecostudio
pkgver=6.1.1.280
_ideaver=2026.1.3
pkgrel=3
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
)
optdepends=(
  'fcitx5: Chinese input method support for JBR JCEF'
)
makedepends=('jq' 'p7zip')
options=('!strip')
source=(
  "devecostudio-mac-${pkgver}.zip"
  "commandline-tools-linux-x64-${pkgver}.zip"
  "idea-${_ideaver}.tar.gz::https://download.jetbrains.com/idea/idea-${_ideaver}.tar.gz"
  "devecostudio.desktop"
)
sha256sums=(
  'ff91d2c51e4887be279eb08eeda1d9094382a4869673c3666db7c663d1611925'
  'b9caf7b73c541b90e6c8f3c7c3de7f2bea9b35e41e80cd3525f2f759ebf16cf4'
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
  mkdir -p "$_pkg"/{bin,jbr,lib,plugins,modules,tools/hvigor,tools/ohpm,tools/UxTestService,license,sdk}

  msg2 "Copying cross-platform files from Mac DMG..."

  # lib/*.jar
  cp -a "$_mac/lib/"*.jar "$_pkg/lib/"
  # Also copy lib/modules/ and lib/cds/ (needed for module descriptor resolution)
  cp -a "$_mac/lib/modules" "$_pkg/lib/"
  cp -a "$_mac/lib/cds" "$_pkg/lib/"

  # plugins (minus ohos-trace which has the lemon bug)
  # Use * glob to avoid nested plugins/plugins/ directory
  cp -a "$_mac/plugins/"* "$_pkg/plugins/"
  rm -rf "$_pkg/plugins/ohos-trace"

  # modules
  cp -a "$_mac/modules/"* "$_pkg/modules/"

  # tools (cross-platform: hvigor = JS, ohpm = JS, UxTestService = Python)
  cp -a "$_mac/tools/hvigor/"* "$_pkg/tools/hvigor/"
  cp -a "$_mac/tools/ohpm/"* "$_pkg/tools/ohpm/"
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
  rm -rf "$_pkg/lib/native" "$_pkg/lib/pty4j" "$_pkg/lib/jna"
  mkdir -p "$_pkg/lib/native/linux-x86_64" "$_pkg/lib/pty4j/linux" "$_pkg/lib/jna/amd64"
  cp -a "$_idea/lib/native/linux-x86_64/"* "$_pkg/lib/native/linux-x86_64/"
  cp -a "$_idea/lib/pty4j/linux/"* "$_pkg/lib/pty4j/linux/"
  cp -a "$_idea/lib/jna/amd64/libjnidispatch.so" "$_pkg/lib/jna/amd64/"

  msg2 "Replacing platform-specific components from CLI tools (Node.js, SDK)..."

  # Node.js
  rm -rf "$_pkg/tools/node"
  cp -a "$_cli/tool/node/" "$_pkg/tools/node/"
  # Symlink bin/* to top level (IDE expects node/npm/npx/corepack alongside bin/)
  ln -sf bin/* "$_pkg/tools/node/"

  # SDK
  rm -rf "$_pkg/sdk"
  cp -a "$_cli/sdk/" "$_pkg/sdk/"

  # ── Sign path fix (some Huawei plugins expect macOS-style path) ──
  mkdir -p "$_pkg/jbr/Contents/Home"
  ln -sf ../../bin "$_pkg/jbr/Contents/Home/bin"

  # ── Wrapper script ──
  cat > "$_pkg/bin/devecostudio.sh" << 'SHEOF'
#!/bin/bash
export _JAVA_AWT_WM_NONREPARENTING=1
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
  # Restore executability for binaries
  chmod +x "$_pkg"/bin/* 2>/dev/null || true
  find "$_pkg/jbr" -type f \( -name '*.so' -o -path '*/bin/*' \) -exec chmod +x {} \; 2>/dev/null || true
  find "$_pkg/lib" -name '*.so' -exec chmod +x {} \; 2>/dev/null || true
  find "$_pkg/tools" -type f \( -name 'node' -o -name 'npm' -o -name 'npx' -o -name 'ohpm' -o -name 'hvigor' \) -exec chmod +x {} \; 2>/dev/null || true

  msg2 "Cleaning platform cruft..."
  find "$_pkg" -name '*.exe' -delete
  find "$_pkg" -name '*.dll' -delete
  find "$_pkg" -name '*.dylib' -delete
  find "$_pkg" -name '*.jnilib' -delete
  find "$_pkg" -name '*.bat' -delete
  find "$_pkg" -name '*.ps1' -delete
  find "$_pkg" -name '*.sh' -not -path '*/bin/devecostudio.sh' -delete

  # ── Desktop entry & symlink ──
  install -Dm644 "$srcdir/devecostudio.desktop" "$pkgdir/usr/share/applications/devecostudio.desktop"
  mkdir -p "$pkgdir/usr/bin"
  ln -sf /opt/devecostudio/bin/devecostudio.sh "$pkgdir/usr/bin/devecostudio"
}
