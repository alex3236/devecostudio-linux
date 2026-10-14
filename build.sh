#!/bin/bash
# Run the PKGBUILD directly — no Arch/makepkg required — producing the
# staging tree (build/pkg/), then package it (tarball always; .deb/.rpm
# with nfpm). Works on any distro. Only the two Huawei zips need to be
# supplied by the user (they come from expiring signed links); IDEA and
# CPython are downloaded and cached under build/downloads/ with checksum
# verification. Both architectures (x86_64, aarch64) are supported; the
# build host has to match the target because every native component comes
# from target-arch archives.
#
# Usage:
#   ./build.sh [--arch=ARCH] [--deb] [--rpm] [--out DIR] [--clean]   full build
#   ./build.sh --stage=pkg/devecostudio [--deb] [--rpm]  package an
#       existing staging tree (e.g. makepkg's pkg/) without rebuilding
set -euo pipefail

usage() {
  cat <<'EOF'
Run the PKGBUILD directly then package it. Should works on any distro.

Usage:
  ./build.sh [--arch=ARCH] [--deb] [--rpm] [--out DIR] [--clean]
  ./build.sh --stage=DIR [--arch=ARCH] [--deb] [--rpm] [--out DIR]

Options:
  --arch=ARCH  target architecture, x86_64 or aarch64 (default: the host's).
               Building for another architecture is refused: JBR, the
               launcher, node, the Emulator and the SDK host toolchains all
               come from target-arch archives.
  --force-cross  with --arch: allow that mismatch anyway. The staging tree is
               complete (all native files come from the target-arch archives),
               but `strip` cannot strip the target-arch binaries and the
               package only runs on the target architecture — for inspecting
               the packaging, not for release.
  --deb        also build devecostudio_<ver>_<rel>_<deb_arch>.deb (needs nfpm)
  --rpm        also build devecostudio-<ver>-<rel>.<rpm_arch>.rpm (needs nfpm)
  --stage=DIR  package an existing staging tree (e.g. makepkg's pkg/) and
               skip the build entirely
  --out=DIR    output directory for tarball/.deb/.rpm (default: .)
  --clean      force re-extraction of sources (default: reuse build/src/)
  -h, --help   show this help

Sources:
  You'll need to place these files next to the script (Huawei's versioned
  filenames are detected, no renaming needed):
  - devecostudio-mac*.zip                 Mac x64 or ARM, either works
  - commandline-tools-linux-x64*.zip      for --arch=x86_64
  - commandline-tools-linux-arm64*.zip    for --arch=aarch64
EOF
  exit 0
}

_clean=0
want_deb=0
want_rpm=0
force_cross=0
outdir="."
stage_dir=""
_arch=""
for a in "$@"; do
  case "$a" in
    --deb) want_deb=1 ;;
    --rpm) want_rpm=1 ;;
    --clean) _clean=1 ;;
    --force-cross) force_cross=1 ;;
    --arch=*) _arch="${a#--arch=}" ;;
    --stage=*) stage_dir="${a#--stage=}" ;;
    --out=*) outdir="${a#--out=}" ;;
    --out) ;;
    -h|--help) usage ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

_msg()   { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
# makepkg macros the PKGBUILD uses; stubbed here for standalone runs
msg2()   { _msg "$*"; }
warning(){ printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cd "$_dir"

# ── target architecture ──
# CARCH drives everything arch-specific in the PKGBUILD. Sourcing it here (it
# only assigns variables and defines functions) keeps URLs and checksums in
# one place — this script must never restate them.
_host_arch=$(uname -m)
export CARCH=${_arch:-$_host_arch}
# shellcheck source=PKGBUILD
source PKGBUILD

if [[ "$CARCH" != "$_host_arch" ]]; then
  if [[ -n "$stage_dir" ]]; then
    # only used for the output names and the package metadata arch
    warning "--arch=$CARCH differs from the host ($_host_arch)"
  elif [[ "$force_cross" == "1" ]]; then
    warning "cross build: $_host_arch host, $CARCH package — strip is a no-op for"
    warning "the target-arch binaries and the result only runs on $CARCH"
  else
    error "--arch=$CARCH differs from the host ($_host_arch): build on a machine of that architecture (or --force-cross to inspect the packaging)"
  fi
fi

# ── build the staging tree ──
if [[ -n "$stage_dir" ]]; then
  # --stage: only packaging, from an existing staging tree (e.g. makepkg's
  # pkg/). pkgver/pkgrel/CARCH already come from the sourced PKGBUILD.
  pkgdir="$stage_dir"
  [[ -d "$pkgdir/opt/devecostudio" ]] || error "stage dir has no opt/devecostudio: $pkgdir"
  _msg "Staging tree ready: $pkgdir"
else
  mkdir -p build/src build/downloads
  # devecostudio.desktop is a local source file; makepkg copies it into
  # $srcdir — do the same here
  cp devecostudio.desktop build/src/ 2>/dev/null || true

  # first existing file among the globs, in the order given
  _first_match() {
    local pat f
    for pat in "$@"; do
      for f in $pat; do
        [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
      done
    done
    return 1
  }

  sha_ok() { [[ "$2" == "SKIP" || "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" == "$2" ]]; }
  dl() { # url dest sha
    if [[ -f "$2" ]] && sha_ok "$2" "$3"; then
      _msg "Using cached $(basename "$2")"
    else
      _msg "Downloading $(basename "$2") ..."
      command -v curl >/dev/null 2>&1 || error "curl is required to download $(basename "$2")"
      curl -fL -o "$2" "$1"
      sha_ok "$2" "$3" || error "SHA256 mismatch for $(basename "$2")"
    fi
  }

  # ── 1. Extract sources (what makepkg would do automatically) ──
  extract_zip() { # zip dest
    if command -v bsdtar >/dev/null 2>&1; then bsdtar -xf "$1" -C "$2"
    elif command -v unzip >/dev/null 2>&1; then unzip -q -o "$1" -d "$2"
    else error "need bsdtar or unzip"; fi
  }

  if [[ "$_clean" == "1" ]]; then rm -rf build/src; mkdir -p build/src; fi

  # devecostudio-mac*.zip → *.dmg
  if ! find build/src -name '*.dmg' -print -quit | grep -q .; then
    _mac_zip=$(_first_match 'devecostudio-mac.zip' 'devecostudio-mac*.zip') \
      || error "no devecostudio-mac*.zip next to this script (the Mac zip is user-supplied)"
    _msg "Extracting $_mac_zip ..."
    extract_zip "$_mac_zip" build/src
  fi
  # commandline-tools-linux-<x64|arm64>*.zip → command-line-tools/
  if [[ ! -d build/src/command-line-tools ]]; then
    _cli_zip=$(_first_match "commandline-tools-linux-${_cliarch}.zip" \
                            "commandline-tools-linux-${_cliarch}*.zip") \
      || error "no commandline-tools-linux-${_cliarch}*.zip for --arch=$CARCH"
    _msg "Extracting $_cli_zip ..."
    extract_zip "$_cli_zip" build/src
  fi
  # idea tarball → idea-IU-*/
  if ! find build/src -maxdepth 1 -type d -name 'idea-IU-*' -print -quit | grep -q .; then
    dl "$_idea_url" "build/downloads/$_idea_file" "$_sha_idea"
    _msg "Extracting $_idea_file ..."
    tar -xzf "build/downloads/$_idea_file" -C build/src
  fi
  # cpython → python/
  if [[ ! -d build/src/python ]]; then
    dl "$_py_url" "build/downloads/$_py_file" "$_sha_python"
    _msg "Extracting $_py_file ..."
    tar -xzf "build/downloads/$_py_file" -C build/src
  fi

  # ── 2. Run prepare + package ──
  export srcdir="$PWD/build/src"
  export pkgdir="$PWD/build/pkg"
  export startdir="$PWD"
  rm -rf "$pkgdir"
  _msg "Running PKGBUILD prepare()/package()..."
  prepare
  package
  _msg "Staging tree ready: $pkgdir"
fi

# ── 3. Distro-agnostic tarball (always produced) ──
mkdir -p "$outdir"
_msg "Building tarball..."
chmod -R u+rw "$pkgdir/opt/devecostudio"
cp "$pkgdir/usr/share/applications/devecostudio.desktop" "$pkgdir/opt/"
tar -C "$pkgdir/opt" -I "gzip -1" -cf "$outdir/devecostudio-${pkgver}-linux-${CARCH}.tar.gz" \
  devecostudio devecostudio.desktop
rm -f "$pkgdir/opt/devecostudio.desktop"
_msg "Created $outdir/devecostudio-${pkgver}-linux-${CARCH}.tar.gz"

# ── 4. Optional nfpm packaging ──
# .deb and .rpm want different architecture spellings (arm64 vs aarch64),
# so nfpm.yaml is rendered once per format with PKG_ARCH set.
if [[ "$want_deb" == "1" || "$want_rpm" == "1" ]]; then
  command -v nfpm >/dev/null 2>&1 || error "nfpm not found"
  command -v envsubst >/dev/null 2>&1 || error "envsubst (gettext) not found"
  _nfpm_render() { # pkg_arch -> config path
    PKGVER=$pkgver PKGREL=$pkgrel PKG_ARCH=$1 STAGE="$pkgdir" \
      envsubst < nfpm.yaml > "$outdir/.nfpm-rendered-$1.yaml"
    printf '%s' "$outdir/.nfpm-rendered-$1.yaml"
  }
  if [[ "$want_deb" == "1" ]]; then
    _msg "Building .deb..."
    nfpm pkg --config "$(_nfpm_render "$_deb_arch")" --packager deb \
      --target "$outdir/devecostudio_${pkgver}-${pkgrel}_${_deb_arch}.deb"
  fi
  if [[ "$want_rpm" == "1" ]]; then
    _msg "Building .rpm..."
    nfpm pkg --config "$(_nfpm_render "$_rpm_arch")" --packager rpm \
      --target "$outdir/devecostudio-${pkgver}-${pkgrel}.${_rpm_arch}.rpm"
  fi
  rm -f "$outdir"/.nfpm-rendered-*.yaml
fi
