#!/bin/bash
# Run the PKGBUILD directly — no Arch/makepkg required — producing the
# staging tree (build/pkg/), then package it (tarball always; .deb/.rpm
# with nfpm). Works on any distro. Only the two Huawei zips need to be
# supplied by the user (they come from expiring signed links); IDEA and
# CPython are downloaded and cached under build/downloads/ with checksum
# verification.
#
# Usage:
#   ./build.sh [--deb] [--rpm] [--out DIR] [--clean]   full build
#   ./build.sh --stage=pkg/devecostudio [--deb] [--rpm]  package an
#       existing staging tree (e.g. makepkg's pkg/) without rebuilding
set -euo pipefail

usage() {
  cat <<'EOF'
Run the PKGBUILD directly then package it. Should works on any distro.

Usage:
  ./build.sh [--deb] [--rpm] [--out DIR] [--clean]
  ./build.sh --stage=DIR [--deb] [--rpm] [--out DIR]

Options:
  --deb        also build devecostudio_<ver>_<rel>_amd64.deb (needs nfpm)
  --rpm        also build devecostudio-<ver>-<rel>.x86_64.rpm (needs nfpm)
  --stage=DIR  package an existing staging tree (e.g. makepkg's pkg/) and
               skip the build entirely
  --out=DIR    output directory for tarball/.deb/.rpm (default: .)
  --clean      force re-extraction of sources (default: reuse build/src/)
  -h, --help   show this help

Sources:
  You'll need to place these files next to the script:
  - devecostudio-mac.zip
  - commandline-tools-linux-x64.zip
EOF
  exit 0
}

_clean=0
want_deb=0
want_rpm=0
outdir="."
stage_dir=""
for a in "$@"; do
  case "$a" in
    --deb) want_deb=1 ;;
    --rpm) want_rpm=1 ;;
    --clean) _clean=1 ;;
    --stage=*) stage_dir="${a#--stage=}" ;;
    --out=*) outdir="${a#--out=}" ;;
    --out) ;;
    -h|--help) usage ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

_msg()   { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
error()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }
# makepkg macros the PKGBUILD uses; stubbed here for standalone runs
msg2()   { _msg "$*"; }
warning(){ printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cd "$_dir"

# ── build the staging tree ──
if [[ -n "$stage_dir" ]]; then
  # --stage: only packaging, from an existing staging tree (e.g. makepkg's
  # pkg/). Source the PKGBUILD just to read pkgver/pkgrel.
  pkgdir="$stage_dir"
  [[ -d "$pkgdir/opt/devecostudio" ]] || error "stage dir has no opt/devecostudio: $pkgdir"
  # shellcheck source=PKGBUILD
  source PKGBUILD
else
  mkdir -p build/src build/downloads
  # devecostudio.desktop is a local source file; makepkg copies it into
  # $srcdir — do the same here
  cp devecostudio.desktop build/src/ 2>/dev/null || true

  # ── 0. Fetch IDEA + CPython (auto-downloaded by the PKGBUILD) ──
  _ideaver=$(grep -E '^_ideaver=' PKGBUILD | head -1 | cut -d= -f2 | tr -d '"'"'"' \r')
  _idea_url="https://download.jetbrains.com/idea/idea-${_ideaver}.tar.gz"
  _python_fname="cpython-3.12.10+20250409-x86_64-unknown-linux-gnu-install_only.tar.gz"
  _python_url="https://github.com/astral-sh/python-build-standalone/releases/download/20250409/${_python_fname}"

  # read the N-th entry of the PKGBUILD sha256sums array (1-based)
  _read_sha() { sed -n "/^sha256sums=(/,/^)/p" PKGBUILD | sed -n "$(( $1 + 1 ))p" | tr -d " '"; }
  _sha_idea=$(_read_sha 3)      # idea tarball
  _sha_python=$(_read_sha 5)    # cpython tarball

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

  # devecostudio-mac.zip → *.dmg
  if ! find build/src -name '*.dmg' -print -quit | grep -q .; then
    [[ -f devecostudio-mac.zip ]] || error "devecostudio-mac.zip not found (rename your downloaded zip)"
    _msg "Extracting devecostudio-mac.zip..."
    extract_zip devecostudio-mac.zip build/src
  fi
  # commandline-tools-linux-x64.zip → command-line-tools/
  if [[ ! -d build/src/command-line-tools ]]; then
    [[ -f commandline-tools-linux-x64.zip ]] || error "commandline-tools-linux-x64.zip not found"
    _msg "Extracting commandline-tools-linux-x64.zip..."
    extract_zip commandline-tools-linux-x64.zip build/src
  fi
  # idea tarball → idea-IU-*/
  if ! find build/src -maxdepth 1 -type d -name 'idea-IU-*' -print -quit | grep -q .; then
    dl "$_idea_url" "build/downloads/idea-${_ideaver}.tar.gz" "$_sha_idea"
    _msg "Extracting idea-${_ideaver}.tar.gz..."
    tar -xzf "build/downloads/idea-${_ideaver}.tar.gz" -C build/src
  fi
  # cpython → python/
  if [[ ! -d build/src/python ]]; then
    dl "$_python_url" "build/downloads/$_python_fname" "$_sha_python"
    _msg "Extracting $_python_fname ..."
    tar -xzf "build/downloads/$_python_fname" -C build/src
  fi

  # ── 2. Source the PKGBUILD and run prepare + package ──
  export srcdir="$PWD/build/src"
  export pkgdir="$PWD/build/pkg"
  export startdir="$PWD"
  rm -rf "$pkgdir"
  _msg "Running PKGBUILD prepare()/package()..."
  # shellcheck source=PKGBUILD
  source PKGBUILD
  prepare
  package
  _msg "Staging tree ready: $pkgdir"
fi

# ── 3. Distro-agnostic tarball (always produced) ──
mkdir -p "$outdir"
chmod -R u+rw "$pkgdir/opt/devecostudio"
cp "$pkgdir/usr/share/applications/devecostudio.desktop" "$pkgdir/opt/"
tar -C "$pkgdir/opt" -I "gzip -1" -cf "$outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz" \
  devecostudio devecostudio.desktop
rm -f "$pkgdir/opt/devecostudio.desktop"
_msg "Created $outdir/devecostudio-${pkgver}-linux-x86_64.tar.gz"

# ── 4. Optional nfpm packaging ──
if [[ "$want_deb" == "1" || "$want_rpm" == "1" ]]; then
  command -v nfpm >/dev/null 2>&1 || error "nfpm not found"
  command -v envsubst >/dev/null 2>&1 || error "envsubst (gettext) not found"
  PKGVER=$pkgver PKGREL=$pkgrel envsubst < nfpm.yaml > "$outdir/.nfpm-rendered.yaml"
  if [[ "$want_deb" == "1" ]]; then
    _msg "Building .deb..."
    nfpm pkg --config "$outdir/.nfpm-rendered.yaml" --packager deb \
      --target "$outdir/devecostudio_${pkgver}-${pkgrel}_amd64.deb"
  fi
  if [[ "$want_rpm" == "1" ]]; then
    _msg "Building .rpm..."
    nfpm pkg --config "$outdir/.nfpm-rendered.yaml" --packager rpm \
      --target "$outdir/devecostudio-${pkgver}-${pkgrel}.x86_64.rpm"
  fi
  rm -f "$outdir/.nfpm-rendered.yaml"
fi
