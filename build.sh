#!/bin/bash
# Build DevEco Studio for Linux directly on Debian/Ubuntu — no Arch/makepkg.
#
# This is a faithful port of the repository's PKGBUILD (prepare()/package())
# into a single portable bash script. It produces the same
#   devecostudio-<ver>-linux-x86_64.tar.gz
# (and optionally a .deb) that the GitHub Actions workflow builds.
#
# Requirements on Debian/Ubuntu:
#   sudo apt install p7zip-full jq curl binutils python3 libarchive-tools
# p7zip-full provides 7z (DMG extraction); libarchive-tools provides bsdtar,
# which preserves zip symlinks that 7z would refuse as "dangerous"
# (unzip works too); binutils provides strip; python3 restores executable
# bits and patches hvigor.
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   -m, --mac-zip FILE    devecostudio-mac-<ver>.zip     (default: ./devecostudio-mac.zip)
#   -c, --cli-zip FILE    commandline-tools-linux-x64-<ver>.zip (default: ./commandline-tools-linux-x64.zip)
#   -v, --version VER     override pkgver                (default: 26.0.0.621)
#   -r, --release N       override pkgrel                (default: 9)
#   -o, --out DIR         output directory for tarball/.deb (default: current dir)
#   -d, --deb             also build a .deb (needs dpkg-deb)
#   --stage DIR           don't build; just emit the tarball/.deb from an
#                         existing staged tree (e.g. makepkg's pkg/). Used by
#                         the Arch CI workflow, which builds with makepkg.
#   --keep                keep build/ (extracted sources + downloads) after
#                         the run; by default all intermediate files are
#                         deleted on exit, success or failure.
#   -h, --help            show this help
#
# Environment:
#   MAC_SHA256 / CLI_SHA256   verify the two user-supplied zips (default SKIP)
#   IDEA_URL / IDEA_SHA256    override the IDEA tarball source/checksum
#   PYTHON_URL / PYTHON_SHA256 override the CPython source/checksum
#   IDEA_VER, PKGVER, PKGREL  same as -v / -r (PKGBUILD is read as fallback)
#   EXPOSE_CLI_TOOLS, HPREFIX_GENERIC_TOOLS  mirror the PKGBUILD toggles
#   KEEP_BUILD=1          same as --keep
set -euo pipefail

# Cleanup control (default: remove all intermediate artifacts on exit,
# success or failure; --keep / KEEP_BUILD=1 retains them for inspection/cache)
_keep=0
_failed=0
_built=0
_started=0

# ─────────────────────────── defaults ───────────────────────────
pkgver="${PKGVER:-26.0.0.621}"
pkgrel="${PKGREL:-9}"
_ideaver="${IDEA_VER:-2026.1.3}"
_expose_cli_tools="${EXPOSE_CLI_TOOLS:-true}"
_hprefix_generic_tools="${HPREFIX_GENERIC_TOOLS:-true}"

# pinned checksums (idea/python are auto-downloaded, so they are verified)
_sha_idea='a6f049716da1d09d9e0ec1500c60bf01a5ff8a0fe2419178dd1ff2fdb2b77563'
_sha_python='e9cf6f7da499a4400ba30ae1da8f7ef25ce97827bd8c1084717aa05438035186'
mac_sha256="${MAC_SHA256:-SKIP}"
cli_sha256="${CLI_SHA256:-SKIP}"
idea_sha256="${IDEA_SHA256:-$_sha_idea}"
python_sha256="${PYTHON_SHA256:-$_sha_python}"

_idea_url="${IDEA_URL:-https://download.jetbrains.com/idea/idea-${_ideaver}.tar.gz}"
_python_url="${PYTHON_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/20250409/cpython-3.12.10+20250409-x86_64-unknown-linux-gnu-install_only.tar.gz}"
_python_fname="cpython-3.12.10+20250409-x86_64-unknown-linux-gnu-install_only.tar.gz"

# ─────────────────────────── helpers ───────────────────────────
msg()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { _failed=1; printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Build DevEco Studio for Linux directly on Debian/Ubuntu — no Arch/makepkg.

A portable port of the repository's PKGBUILD. Produces the same
devecostudio-<ver>-linux-x86_64.tar.gz (and optionally a .deb) that the
GitHub Actions workflow builds.

Requirements on Debian/Ubuntu:
  sudo apt install p7zip-full jq curl binutils python3 libarchive-tools

Usage:
  ./build.sh [options]

Options:
  -m, --mac-zip FILE    devecostudio-mac-<ver>.zip     (default: ./devecostudio-mac.zip)
  -c, --cli-zip FILE    commandline-tools-linux-x64-<ver>.zip (default: ./commandline-tools-linux-x64.zip)
  -v, --version VER     override pkgver                (default: 26.0.0.621)
  -r, --release N       override pkgrel                (default: 9)
  -o, --out DIR         output directory for tarball/.deb (default: current dir)
  -d, --deb             also build a .deb (needs dpkg-deb)
  --stage DIR           don't build; just emit the tarball/.deb from an
                        existing staged tree (e.g. makepkg's pkg/). Used by
                        the Arch CI workflow, which builds with makepkg.
  --keep                keep build/ (extracted sources + downloads) after
                        the run; by default all intermediate files are
                        deleted on exit, success or failure.
  -h, --help            show this help

Environment:
  MAC_SHA256 / CLI_SHA256      verify the two user-supplied zips (default SKIP)
  IDEA_URL / IDEA_SHA256       override the IDEA tarball source/checksum
  PYTHON_URL / PYTHON_SHA256   override the CPython source/checksum
  IDEA_VER, PKGVER, PKGREL     same as -v / -r (PKGBUILD is read as fallback)
  EXPOSE_CLI_TOOLS, HPREFIX_GENERIC_TOOLS  mirror the PKGBUILD toggles
  KEEP_BUILD=1                  same as --keep
EOF
  exit "${1:-0}"
}

# sha_ok FILE EXPECTED — EXPECTED=SKIP disables verification
sha_ok() {
  local f="$1" want="$2"
  [[ "$want" == "SKIP" ]] && return 0
  command -v sha256sum >/dev/null || return 0
  local got; got=$(sha256sum "$f" | awk '{print $1}')
  [[ "$got" == "$want" ]]
}

dl_verify() { # URL DEST SHA
  local url="$1" dest="$2" sha="$3"
  if [[ -f "$dest" ]] && sha_ok "$dest" "$sha"; then
    msg "Using cached $(basename "$dest")"
    return 0
  fi
  msg "Downloading $(basename "$dest") ..."
  curl -fL -o "$dest" "$url"
  sha_ok "$dest" "$sha" || die "SHA256 mismatch for $(basename "$dest")"
}

# build_deb PKGDIR PKGVER PKGREL OUTDIR — turn a staged tree (opt/, usr/) into a .deb.
build_deb() {
  local pkgdir="$1" pkgver="$2" pkgrel="$3" outdir="$4"
  local version deb
  version="${pkgver}-${pkgrel}"
  deb="devecostudio_${version}_amd64.deb"

  [[ -d "$pkgdir/opt/devecostudio" ]] || die "build_deb: $pkgdir/opt/devecostudio not found"
  command -v dpkg-deb >/dev/null 2>&1 || die "build_deb: dpkg-deb not found (install dpkg)"

  msg "Building $deb ..."
  rm -rf "$pkgdir/DEBIAN"
  mkdir -p "$pkgdir/DEBIAN"
  chmod 755 "$pkgdir/DEBIAN"

  # Map Arch package names to Debian/Ubuntu package names.
  # libasound2 also resolves on Ubuntu 24.04 (libasound2t64) via the
  # transitional package; libcrypt1 exists on Debian 12 / Ubuntu 22.04+.
  cat > "$pkgdir/DEBIAN/control" <<EOF
Package: devecostudio
Version: $version
Section: devel
Priority: optional
Architecture: amd64
Maintainer: devecostudio-linux <https://github.com/alex3236/devecostudio-linux>
Depends: libxss1, libxtst6, libnss3, libasound2, libcrypt1, libfreetype6, libpulse0
Recommends: fcitx5
Description: Huawei DevEco Studio repackaged for Debian/Ubuntu
 Repackages DevEco Studio (Huawei's HarmonyOS IDE) from its Mac DMG,
 using Linux-native components (launcher, JBR, native libraries) from
 JetBrains IntelliJ IDEA. Built from the Arch PKGBUILD in this
 repository; the .deb wraps the same /opt/devecostudio install tree.
EOF

  # Keep the desktop database in sync when desktop-file-utils is present
  # (harmless no-op otherwise).
  cat > "$pkgdir/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
EOF
  chmod 755 "$pkgdir/DEBIAN/postinst"
  cp "$pkgdir/DEBIAN/postinst" "$pkgdir/DEBIAN/postrm"

  # The tree is owned by the (non-root) builder user; --root-owner-group
  # rewrites ownership to root:root so apt/dpkg install cleanly. DEBIAN/ is
  # build metadata only — remove it regardless of outcome so the staged tree
  # is left clean.
  local _rc=0
  dpkg-deb --build --root-owner-group "$pkgdir" "$outdir/$deb" || _rc=$?
  rm -rf "$pkgdir/DEBIAN"
  [[ "$_rc" -eq 0 ]] || die "dpkg-deb failed for $deb"

  echo "  $outdir/$deb"
}

# extract_zip ZIP DEST — preserve symlinks (7z would refuse them as
# "dangerous": clang++→clang chains, node/bin/npm → ../lib/node_modules/...).
# This matches makepkg, which extracts zips with bsdtar.
extract_zip() {
  local zip="$1" dest="$2"
  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$zip" -C "$dest"
  elif command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$zip" -d "$dest"
  else
    die "need bsdtar (libarchive-tools) or unzip to extract '$zip' without losing symlinks"
  fi
}

# ─────────────────────────── args ───────────────────────────
_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
_build="$_dir/build"
mac_zip="$_dir/devecostudio-mac.zip"
cli_zip="$_dir/commandline-tools-linux-x64.zip"
outdir="$_dir"
want_deb=0
stage_dir=""
ver_set=0
rel_set=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mac-zip)    mac_zip="$2";   shift 2 ;;
    -c|--cli-zip)    cli_zip="$2";   shift 2 ;;
    -v|--version)    pkgver="$2"; ver_set=1; shift 2 ;;
    -r|--release)    pkgrel="$2"; rel_set=1; shift 2 ;;
    -o|--out)        outdir="$2";    shift 2 ;;
    -d|--deb)        want_deb=1;     shift ;;
    --stage)         stage_dir="$2"; shift 2 ;;
    --keep)          _keep=1;        shift ;;
    -h|--help)       usage 0 ;;
    *)               echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

# Fall back to the repo's PKGBUILD for version/release when not overridden
# (keeps the Arch CI workflow and this script in sync; harmless if absent).
if [[ "$ver_set" -eq 0 && -z "${PKGVER:-}" ]]; then
  _pv=$(grep '^pkgver=' "$_dir/PKGBUILD" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r') || true
  [[ -n "$_pv" ]] && pkgver="$_pv"
fi
if [[ "$rel_set" -eq 0 && -z "${PKGREL:-}" ]]; then
  _pr=$(grep '^pkgrel=' "$_dir/PKGBUILD" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r') || true
  [[ -n "$_pr" ]] && pkgrel="$_pr"
fi
[[ "${KEEP_BUILD:-0}" == "1" ]] && _keep=1

# ─────────────────────────── cleanup ───────────────────────────
# Runs on every exit (normal, error, signal). Removes build/ (extracted
# sources, staged tree, downloaded IDEA/CPython) unless --keep, and removes
# partial output files if the run failed part-way through producing them.
_cleanup() {
  local code=$?
  if [[ "$_keep" == "1" ]]; then
    return 0
  fi
  if [[ "$_built" == "1" && -d "$_build" ]]; then
    msg "Cleaning up build dir ($_build) ..."
    rm -rf "$_build"
  fi
  if [[ "$_started" == "1" && "$_failed" == "1" ]]; then
    rm -f "$outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz" \
          "$outdir/devecostudio_${pkgver}-${pkgrel}_amd64.deb" 2>/dev/null || true
    warn "Removed partial output artifacts from the failed run"
  fi
  exit "$code"
}
trap _cleanup EXIT INT TERM

# ─────────────────────────── preflight ───────────────────────────
if [[ -n "$stage_dir" ]]; then
  # --stage: only packaging/outputs, no extraction toolchain required
  _pkg="$stage_dir"
  [[ -d "$_pkg/opt/devecostudio" ]] || die "stage dir has no opt/devecostudio: $_pkg"
  _base="$_pkg/opt/devecostudio"
  command -v tar >/dev/null 2>&1 || die "missing required tool 'tar'"
else
  for t in 7z jq curl python3 tar; do
    command -v "$t" >/dev/null 2>&1 || die "missing required tool '$t'. On Debian/Ubuntu: sudo apt install p7zip-full jq curl python3"
  done
  # zip extraction must preserve symlinks (see extract_zip): 7z would drop them
  if ! command -v bsdtar >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
    die "missing 'bsdtar' (apt install libarchive-tools) or 'unzip' — needed to extract the Huawei zips without losing symlinks"
  fi

  [[ -f "$mac_zip" ]] || die "Mac zip not found: $mac_zip (pass -m, or download devecostudio-mac-<ver>.zip next to this script)"
  [[ -f "$cli_zip" ]] || die "CLI zip not found: $cli_zip (pass -c, or download commandline-tools-linux-x64-<ver>.zip next to this script)"
  sha_ok "$mac_zip" "$mac_sha256" || die "Mac zip SHA256 mismatch (set MAC_SHA256=SKIP or the correct hash)"
  sha_ok "$cli_zip" "$cli_sha256" || die "CLI zip SHA256 mismatch (set CLI_SHA256=SKIP or the correct hash)"
fi

# ─────────────────────────── full build: prepare + package ───────────────────────────
if [[ -z "$stage_dir" ]]; then

# ─────────────────────────── work dirs ───────────────────────────
_src="$_dir/build/src"
_pkg="$_dir/build/pkg"
_dl="$_dir/build/downloads"
mkdir -p "$_src" "$_pkg" "$_dl"
_built=1

# ─────────────────────────── prepare(): extract sources ───────────────────────────
msg "Extracting Mac zip..."
extract_zip "$mac_zip" "$_src/mac_zip"
_dmg=$(find "$_src/mac_zip" -name '*.dmg' -type f -print -quit)
[[ -n "$_dmg" ]] || die "No .dmg found inside the Mac zip"

msg "Extracting Mac DMG (platform-independent parts only)..."
7z x -y -o"$_src/mac_dmg" "$_dmg" \
  "DevEco-Studio/DevEco-Studio.app/Contents" \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/sdk/default' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/jbr' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/emulator' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/dumpParser' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/llvm' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/profiler' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/node' \
  >/dev/null
_mac="$_src/mac_dmg/DevEco-Studio/DevEco-Studio.app/Contents"
[[ -d "$_mac/plugins" && -f "$_mac/Resources/product-info.json" ]] \
  || die "DMG extraction failed: Contents/plugins or product-info.json missing"

msg "Extracting CLI tools..."
extract_zip "$cli_zip" "$_src"
_cli="$_src/command-line-tools"
[[ -d "$_cli" ]] || die "CLI tools extraction failed"
# Sanity check: 7z would have dropped these symlinks as "dangerous"
# (node bin/* -> ../lib/node_modules/..., clang++ -> clang). Make sure the
# extractor preserved them, or the SDK toolchain / npm will be broken.
[[ -L "$_cli/tool/node/bin/npm" ]] \
  || die "CLI zip extraction lost node symlinks (install bsdtar/libarchive-tools or unzip and re-run)"
[[ -L "$_cli/sdk/default/openharmony/native/llvm/bin/clang++" ]] \
  || warn "LLVM clang++ symlink missing after extraction — C/C++ cross-build may be affected"

msg "Fetching IntelliJ IDEA ${_ideaver} (for JBR + Linux launcher + native libs)..."
dl_verify "$_idea_url" "$_dl/idea-${_ideaver}.tar.gz" "$idea_sha256"
tar -xzf "$_dl/idea-${_ideaver}.tar.gz" -C "$_src"
_idea=$(find "$_src" -mindepth 1 -maxdepth 1 -type d -name 'idea-IU-*' -print -quit)
[[ -d "$_idea" ]] || die "IDEA extraction failed (expected a directory named idea-IU-*)"

msg "Fetching CPython 3.12.10 (replaces the DMG's macOS-only python for appanalyzer)..."
dl_verify "$_python_url" "$_dl/$_python_fname" "$python_sha256"
tar -xzf "$_dl/$_python_fname" -C "$_src"
[[ -d "$_src/python" ]] || die "CPython extraction failed"

# ─────────────────────────── package(): assemble the tree ───────────────────────────
_base="$_pkg/opt/devecostudio"

msg "Creating directory skeleton..."
mkdir -p "$_base"/{bin,jbr,lib,plugins,modules,tools,license,sdk}

msg "Copying cross-platform files from Mac DMG..."

# lib/*.jar (26.0.0+ flattens all platform jars into lib/)
cp -a "$_mac/lib/"*.jar "$_base/lib/"

# plugins (minus ohos-trace which has the lemon bug)
cp -a "$_mac/plugins/"* "$_base/plugins/"
rm -rf "$_base/plugins/ohos-trace"

# modules
cp -a "$_mac/modules/"* "$_base/modules/"

# tools: prefer CLI (Linux) versions where available; UxTestService is
# Mac-only (Python, cross-platform) and stays from the DMG.
cp -a "$_cli/hvigor/" "$_base/tools/hvigor"
cp -a "$_cli/ohpm/" "$_base/tools/ohpm"
cp -a "$_cli/hstack/" "$_base/tools/hstack"
cp -a "$_cli/codelinter/" "$_base/tools/codelinter"
cp -a "$_cli/emulator/" "$_base/tools/emulator"
# Huawei's code only distinguishes Mac vs non-Mac; the non-Mac branch
# hardcodes the "Emulator.exe" name. Symlink it to the real binary.
ln -sf Emulator "$_base/tools/emulator/Emulator.exe"
cp -a "$_cli/tool/node/" "$_base/tools/node/"
# symlink bin/* to tools/node (IDE expects node/npm/npx/corepack alongside bin/)
( cd "$_base/tools/node" && ln -sf bin/* . )
# npm check path (see DETAILS.md "Node.js layout"): three symlinks, no copy
ln -sfn lib/node_modules "$_base/tools/node/node_modules"
mkdir -p "$_base/tools/lib"
ln -sfn ../node/lib/node_modules "$_base/tools/lib/node_modules"
# UxTestService from Mac DMG (Python, cross-platform)
mkdir -p "$_base/tools/UxTestService"
cp -a "$_mac/tools/UxTestService/"* "$_base/tools/UxTestService/"

# license, build.txt, svg icon, idea.properties
cp -a "$_mac/license/"* "$_base/license/"
cp -a "$_mac/Resources/build.txt" "$_base/"
cp -a "$_mac/bin/devecostudio.svg" "$_base/bin/"
cp -a "$_mac/bin/idea.properties" "$_base/bin/"

msg "Writing install-extra-sdk.sh (SDK switcher, not on PATH)..."
cat > "$_base/bin/install-extra-sdk.sh" << 'SDKEOF'
#!/bin/bash
# Install an additional HarmonyOS SDK (e.g. 6.1.1 Release) from a Huawei
# command-line-tools zip into /opt/devecostudio/sdk/, alongside the bundled
# 26.0.0 Beta SDK. hvigor then picks the SDK by the project's
# compileSdkVersion — see the README "Release SDK" section.
# Usage: install-extra-sdk.sh /path/to/commandline-tools-linux-x64-<ver>.zip
set -euo pipefail

ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Usage: $(basename "$0") <commandline-tools-*.zip>" >&2
  exit 1
fi
command -v 7z >/dev/null || { echo "7z is required" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Extracting SDK components from $ZIP ..."
7z x -y "$ZIP" \
  "command-line-tools/sdk/default/openharmony" \
  "command-line-tools/sdk/default/hms" \
  "command-line-tools/sdk/default/sdk-pkg.json" -o"$TMP" >/dev/null
SRC="$TMP/command-line-tools/sdk/default"
[[ -d "$SRC/openharmony" ]] || { echo "No SDK found in $ZIP" >&2; exit 1; }

PKG=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['data']['path'])" "$SRC/sdk-pkg.json")
[[ -n "$PKG" ]] || { echo "Cannot read sdk-pkg.json" >&2; exit 1; }
DST="/opt/devecostudio/sdk/$PKG"

if [[ -e "$DST" ]]; then
  echo "Already installed at $DST — remove it first to reinstall." >&2
  exit 1
fi
echo "Installing to $DST (needs root) ..."
sudo mkdir -p "$DST"
sudo cp -a "$SRC/openharmony" "$SRC/hms" "$DST/"
sudo cp "$SRC/sdk-pkg.json" "$DST/"
_ver=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$DST/sdk-pkg.json" | tail -1)
echo "OK: $PKG ($_ver)"
echo "Use it: set compileSdkVersion (and targetSdkVersion) in build-profile.json5,"
echo "e.g. '6.1.1(24)' for the 6.1.1 Release SDK."
SDKEOF
chmod +x "$_base/bin/install-extra-sdk.sh"

msg "Transforming vmoptions (macOS → Linux)..."
sed \
  -e 's/-Dsun.java2d.metal=true/-Dsun.java2d.opengl=true/' \
  -e '/^-Djava.security.manager/d' \
  -e '/^-Dwsl/d' \
  "$_mac/bin/devecostudio.vmoptions" > "$_base/bin/devecostudio64-lin.vmoptions"
cat >> "$_base/bin/devecostudio64-lin.vmoptions" << 'VMEOF'
-Dawt.lock.fair=true
-Dsun.tools.attach.tmp.only=true
-Dglfw.im.module=fcitx
VMEOF

msg "Replacing platform-specific components from IntelliJ IDEA (JBR, launcher, native libs)..."

# JBR
rm -rf "$_base/jbr"
cp -a "$_idea/jbr/" "$_base/jbr/"

# launcher
cp -a "$_idea/bin/idea" "$_base/bin/devecostudio"
chmod +x "$_base/bin/devecostudio"

# fsnotifier
cp -a "$_idea/bin/fsnotifier" "$_base/bin/"

# native libs
rm -rf "$_base/lib/native" "$_base/lib/pty4j" "$_base/lib/jna" "$_base/lib/skiko-awt-runtime-all"
mkdir -p "$_base/lib/native/linux-x86_64" "$_base/lib/pty4j/linux" "$_base/lib/jna/amd64" "$_base/lib/skiko-awt-runtime-all"
cp -a "$_idea/lib/native/linux-x86_64/"* "$_base/lib/native/linux-x86_64/"
cp -a "$_idea/lib/pty4j/linux/"* "$_base/lib/pty4j/linux/"
cp -a "$_idea/lib/jna/amd64/libjnidispatch.so" "$_base/lib/jna/amd64/"
cp -a "$_idea/lib/skiko-awt-runtime-all/"* "$_base/lib/skiko-awt-runtime-all/"

msg "Replacing platform-specific components from CLI tools (SDK, wrappers)..."

# SDK
rm -rf "$_base/sdk"
cp -a "$_cli/sdk/" "$_base/sdk/"

# CLI terminal wrappers (bin/hvigorw, bin/ohpm, bin/hstack, bin/codelinter, bin/Emulator)
mkdir -p "$_base/tools/bin"
cp -a "$_cli/bin/"* "$_base/tools/bin/"
# Resolve $0 through readlink so the wrappers also work via symlinks
sed -i 's|cd "$(dirname "$0")"|cd "$(dirname "$(readlink -f "$0")")"|' "$_base/tools/bin/"*
sed -i 's|\$all_tool_dir/tool/node|\$all_tool_dir/node|g; s|\$all_tool_dir/sdk|\$all_tool_dir/../sdk|g' "$_base/tools/bin/"*
chmod +x "$_base/tools/bin/"*
# codelinter's launcher hardcodes <tools>/tool/node and <tools>/sdk
sed -i 's|\$ROOT_PATH/tool/node|\$ROOT_PATH/node|; s|\$ROOT_PATH/sdk|\$ROOT_PATH/../sdk|' "$_base/tools/codelinter/bin/codelinter"
# Emulator wrapper: bridge the macOS-style image path symlink, and
# auto-accept the software agreements on first use.
cat > "$_src/emulator-wrapper-patch.sh" << 'PATCHEOF'
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
sed -i '/"$all_tool_dir\/emulator\/Emulator" "\$@"/r '"$_src/emulator-wrapper-patch.sh" "$_base/tools/bin/Emulator"

# /usr/bin exposure
if [[ "$_expose_cli_tools" == "true" ]]; then
  mkdir -p "$_pkg/usr/bin"
  for _w in hvigorw ohpm hstack; do
    ln -sf /opt/devecostudio/tools/bin/$_w "$_pkg/usr/bin/$_w"
  done
  if [[ "$_hprefix_generic_tools" == "true" ]]; then
    ln -sf /opt/devecostudio/tools/bin/codelinter "$_pkg/usr/bin/hcodelinter"
    ln -sf /opt/devecostudio/tools/bin/Emulator "$_pkg/usr/bin/hemulator"
  else
    ln -sf /opt/devecostudio/tools/bin/codelinter "$_pkg/usr/bin/codelinter"
    ln -sf /opt/devecostudio/tools/bin/Emulator "$_pkg/usr/bin/Emulator"
  fi
fi

# hdc (device debug tool) lives in the SDK toolchains; expose it as-is
mkdir -p "$_pkg/usr/bin"
ln -sf /opt/devecostudio/sdk/default/openharmony/toolchains/hdc "$_pkg/usr/bin/hdc"

# Sign path fix (some Huawei plugins expect macOS-style path)
mkdir -p "$_base/jbr/Contents/Home"
ln -sf ../../bin "$_base/jbr/Contents/Home/bin"

msg "Writing launcher wrapper (devecostudio.sh)..."
cat > "$_base/bin/devecostudio.sh" << 'SHEOF'
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
# appanalyzer python workaround (Huawei Linux gap): initRequirements
# writes requirements/python_X/, but getPipLibraryDownloaded reads
# requirements/Python_X/ (from `python3 --version` output). Case-
# insensitive filesystems hide this; Linux does not → NPE. Bridge the
# two names and seed requirements.json from the jar when missing. Also
# fix the torch scenario: the pinned torchvision 0.21.0 needs torch 2.6
# while the pin is torch 2.2.2 (a conflict that only resolves on
# non-Linux because the cuda deps are Linux-gated); downgrade to 0.17.2.
_pybin="/opt/devecostudio/plugins/harmony/lib/python/bin"
_pyver=$("$_pybin/python3" --version 2>/dev/null | awk '{print $2}')
if [[ -n "$_pyver" ]]; then
  _an="$HOME/.cache/Huawei/DevEcoStudio26.0/caches/appanalyzer"
  _req_dir="$_an/pythonconfig/requirements"
  _req_file="$_req_dir/python_$_pyver/requirements.json"
  mkdir -p "$_req_dir"
  ln -sfn "python_$_pyver" "$_req_dir/Python_$_pyver"
  if [[ ! -s "$_req_file" ]]; then
    unzip -p "/opt/devecostudio/plugins/harmony/lib/hos-app-analyzer-26.0.0.621.jar" \
      "python/${_pyver%.*}/requirements_external.json" > "$_req_file" 2>/dev/null
  fi
  "$_pybin/python3" - "$_req_file" << 'PYEOF'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p) and os.path.getsize(p) > 0:
    try:
        d = json.load(open(p))
        for dep in d.get("dependencies", []):
            if dep.get("name") == "torchvision" and dep.get("version") == "0.21.0":
                dep["version"] = "0.17.2"
                json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
                break
    except Exception:
        pass
PYEOF
fi
exec "$(dirname "$(readlink -f "$0")")/devecostudio" "${_JCEF_ARGS[@]}" "$@"
SHEOF
chmod +x "$_base/bin/devecostudio.sh"

msg "Transforming product-info.json for Linux (jq)..."
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
  "$_mac/Resources/product-info.json" > "$_base/product-info.json"

msg "Stripping Linux binaries..."
if command -v strip >/dev/null 2>&1; then
  find "$_base/jbr" -type f -executable -exec strip --strip-all {} \; 2>/dev/null || true
  strip --strip-all "$_base/bin/devecostudio" 2>/dev/null || true
  find "$_base/lib" -name '*.so' -exec strip --strip-unneeded {} \; 2>/dev/null || true
  strip --strip-all "$_base/bin/fsnotifier" 2>/dev/null || true
else
  warn "strip not found — skipping binary stripping"
fi

msg "Fixing permissions (Mac DMG files have 700)..."
find "$_base" -type d -exec chmod 755 {} \;
find "$_base" -type f -exec chmod 644 {} \;
# Restore executability for all ELF binaries and shebang scripts.
python3 - "$_base" << 'PYEOF'
import os, sys
root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        try:
            with open(p, 'rb') as f:
                head = f.read(256)
            if head[:4] == b'\x7fELF' or b'#!' in head:
                st = os.stat(p)
                if not st.st_mode & 0o111:
                    os.chmod(p, st.st_mode | 0o111)
        except OSError:
            pass
PYEOF

msg "Patching hvigor to accept any compileSdkVersion..."
python3 - "$_base/tools/hvigor/hvigor-ohos-plugin/src/utils/validate/validate-util.js" << 'PYEOF'
import sys
p = sys.argv[1]
old = '(0,sdkmanager_common_1.isEqualApiVersion)(r,s)&&0===(0,sdkmanager_common_1.compareVersion)(t.api,n.api)||this._log.printErrorExit("UNSUPPORTED_COMPILESDKVERSION",[i.compileSdkVersion,o],[[version_const_js_1.VersionConst.SUPPORT_COMPILE_VERSION]])'
new = '(0,sdkmanager_common_1.isEqualApiVersion)(r,s)&&0===(0,sdkmanager_common_1.compareVersion)(t.api,n.api)||void 0'
s = open(p).read()
if old in s:
    open(p, 'w').write(s.replace(old, new))
    print('  hvigor patch applied')
else:
    print('  hvigor patch: pattern not found (layout changed?)')
PYEOF

msg "Cleaning platform cruft..."
find "$_base" -name '*.exe' -not -name 'Emulator.exe' -delete
find "$_base" -name '*.dll' -delete
find "$_base" -name '*.dylib' -delete
find "$_base" -name '*.jnilib' -delete
find "$_base" -name '*.bat' -delete
find "$_base" -name '*.ps1' -delete
# Replace the DMG's Mach-O python with real Linux CPython 3.12.10.
# Prefer the standard plugins/harmony/lib/python; if this version moved it,
# use the real location; if there is none at all, materialize the standard
# path (which the IDE's getInnerPythonHome() hardcodes) and install there
# anyway — never let a missing dir abort the build.
_pybase="$_base/plugins/harmony/lib/python"
if [[ ! -d "$_pybase" ]]; then
  _found=$(find -L "$_base/plugins/harmony" -maxdepth 5 -type d -name python -print -quit 2>/dev/null)
  [[ -n "$_found" ]] && _pybase="$_found"
fi
mkdir -p "$_pybase"
rm -rf "$_pybase/bin" "$_pybase/include" "$_pybase/lib" "$_pybase/share"
cp -a "$_src/python/bin" "$_pybase/bin"
cp -a "$_src/python/lib" "$_pybase/lib"
cp -a "$_src/python/include" "$_pybase/include"
# Wrap the bundled python3 (the venv symlinks inherit it): Huawei's pip
# flow runs `pip wheel <lib> --no-deps` then `pip install <lib>
# --no-index`, so torch's Linux-only nvidia deps are never fetched. Strip
# both flags so pip resolves deps from the network on demand.
rm -f "$_pybase/bin/python3"
_real_python="/opt/devecostudio/${_pybase#$_base/}/bin/python3.12"
sed "s|@REAL_PYTHON@|$_real_python|" > "$_pybase/bin/python3" << 'WRAPEOF'
#!/bin/bash
# Huawei's pip flow drops deps (wheel --no-deps, install --no-index); strip.
# exec -a preserves argv[0] so Python keeps its venv/base identity.
args=()
for arg in "$@"; do
  case "$arg" in
    --no-deps|--no-index) ;;
    *) args+=("$arg") ;;
  esac
done
exec -a "$0" @REAL_PYTHON@ "${args[@]}"
WRAPEOF
chmod +x "$_pybase/bin/python3"
# codelinter result dir must be world-writable
chmod 777 "$_base/tools/codelinter/linter/result" 2>/dev/null \
  || warn "codelinter result dir not found — code linting may fail on this version"
# macOS code-signature xattr sidecar files ("<file>:com.apple.cs.*")
find "$_base" -name '*:com.apple.cs.*' -delete 2>/dev/null || true
# Remove Windows/macOS wrapper scripts, but keep real .sh files inside the
# SDK (lldb launchers, cmake modules, build helpers)
find "$_base/bin" "$_base/tools/bin" -name '*.sh' \
  -not -path '*/bin/devecostudio.sh' \
  -not -path '*/bin/install-extra-sdk.sh' -delete 2>/dev/null || true
find "$_base/plugins" -name '*.sh' -delete 2>/dev/null || true

# ─────────────────────────── desktop entry & /usr/bin ───────────────────────────
msg "Installing desktop entry..."
if [[ -f "$_dir/devecostudio.desktop" ]]; then
  install -Dm644 "$_dir/devecostudio.desktop" "$_pkg/usr/share/applications/devecostudio.desktop"
else
  cat > "$_pkg/usr/share/applications/devecostudio.desktop" << 'DEOF'
[Desktop Entry]
Name=DevEco Studio
Comment=HarmonyOS Development IDE
Exec=/opt/devecostudio/bin/devecostudio.sh
Icon=/opt/devecostudio/bin/devecostudio.svg
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=deveco-studio
DEOF
fi
mkdir -p "$_pkg/usr/bin"
ln -sf /opt/devecostudio/bin/devecostudio.sh "$_pkg/usr/bin/devecostudio"

fi  # end full build

# ─────────────────────────── outputs ───────────────────────────
_started=1
mkdir -p "$outdir"

# Optional .deb (built before the desktop file is copied into pkg/opt/ so
# the package stays clean).
if [[ "$want_deb" == "1" ]]; then
  build_deb "$_pkg" "$pkgver" "$pkgrel" "$outdir"
fi

msg "Creating devecostudio-${pkgver}-linux-x86_64.tar.gz ..."
chmod -R u+rw "$_base"
cp "$_pkg/usr/share/applications/devecostudio.desktop" "$_pkg/opt/"
tar -C "$_pkg/opt" -czf "$outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz" devecostudio devecostudio.desktop

echo ""
echo "Done: $outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz"
echo ""
echo "Install it on Debian/Ubuntu:"
echo "  sudo tar -xzf $outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz -C /opt"
echo "  sudo ln -s /opt/devecostudio/bin/devecostudio.sh /usr/local/bin/devecostudio"
echo "  sudo desktop-file-install /opt/devecostudio.desktop"