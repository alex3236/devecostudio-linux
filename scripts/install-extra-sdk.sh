#!/bin/bash
# Install an additional HarmonyOS SDK (e.g. 6.1.1 Release) from a Huawei
# command-line-tools zip into /opt/devecostudio/sdk/, alongside the bundled
# SDK. hvigor then picks the SDK by the project's compileSdkVersion — see
# the README "Release SDK" section.
# Usage: install-extra-sdk.sh /path/to/commandline-tools-linux-x64-<ver>.zip
set -euo pipefail

ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Usage: $(basename "$0") <commandline-tools-*.zip>" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Extracting SDK components from $ZIP ..."
# Use bsdtar/unzip, not 7z: 7z refuses the SDK's symlink chains
# (libunwind.so -> libunwind.so.1, clang -> bisheng-clang, clang-cl ->
# clang, node's bin/npm -> ../lib/...) as "Dangerous link via another
# link was ignored" and silently drops them, breaking native toolchains.
if command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xf "$ZIP" -C "$TMP" \
    "command-line-tools/sdk/default/openharmony" \
    "command-line-tools/sdk/default/hms" \
    "command-line-tools/sdk/default/sdk-pkg.json"
elif command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$ZIP" \
    "command-line-tools/sdk/default/openharmony/*" \
    "command-line-tools/sdk/default/hms/*" \
    "command-line-tools/sdk/default/sdk-pkg.json" -d "$TMP"
else
  echo "Neither bsdtar (libarchive) nor unzip is available — install one of them." >&2
  exit 1
fi
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

echo "Patching hvigor and IDE sync to accept any compileSdkVersion ..."
# The bundled hvigor validates the project's compileSdkVersion against its
# own SUPPORT_COMPILE_VERSION ("26.0.0") and the IDE's sync check requires
# it to equal the embedded SDK version — both would reject an older SDK
# like 6.1.1. Neutralize both checks so the extra SDK is usable.
python3 - << 'PYEOF'
import glob, os, re, shutil, zipfile

# 1) hvigor validate-util.js: neutralize UNSUPPORTED_COMPILESDKVERSION
hv = "/opt/devecostudio/tools/hvigor/hvigor-ohos-plugin/src/utils/validate/validate-util.js"
if os.path.exists(hv):
    s = open(hv).read()
    old = '(0,sdkmanager_common_1.isEqualApiVersion)(r,s)&&0===(0,sdkmanager_common_1.compareVersion)(t.api,n.api)||this._log.printErrorExit("UNSUPPORTED_COMPILESDKVERSION",[i.compileSdkVersion,o],[[version_const_js_1.VersionConst.SUPPORT_COMPILE_VERSION]])'
    new = '(0,sdkmanager_common_1.isEqualApiVersion)(r,s)&&0===(0,sdkmanager_common_1.compareVersion)(t.api,n.api)||void 0'
    if old in s:
        open(hv, "w").write(s.replace(old, new))
        print("  hvigor: patched")
    elif new in s:
        print("  hvigor: already patched")
    else:
        print("  hvigor: pattern not found — layout changed?")

# 1b) hvigor hmos-sdk-loader.js: hvigor 6.26.4+ added
#     COMPILE_SDK_VERSION_MISMATCH (00303313) in checkSdkVersionMatch —
#     rejects any compileSdkVersion whose API differs from the latest
#     support version. Neutralize it the same way.
hsl = "/opt/devecostudio/tools/hvigor/hvigor-ohos-plugin/src/sdk/hmos-sdk-loader.js"
if os.path.exists(hsl):
    s = open(hsl).read()
    old = 'o.fullVersion!==e&&_log.printErrorExit("COMPILE_SDK_VERSION_MISMATCH",[o.fullVersion,e])'
    new = 'o.fullVersion!==e||void 0'
    if old in s:
        open(hsl, "w").write(s.replace(old, new))
        print("  hvigor sdk-loader: patched")
    elif new in s:
        print("  hvigor sdk-loader: already patched")
    else:
        print("  hvigor sdk-loader: pattern not found — layout changed?")

# 2) IDE project sync: HosIntegrationChecker.checkSameCompileSdkIfConfig
#    (hos-project-mgmt-*.jar) aborts sync unless compileSdkVersion equals the
#    embedded SDK. Flip the ifne after StringUtil.equals() to a goto.
for jar in glob.glob("/opt/devecostudio/plugins/harmony/lib/hos-project-mgmt-*.jar"):
    inner = "com/huawei/deveco/projectmgmt/hos/sync/integration/HosIntegrationChecker.class"
    tmp = jar + ".tmp"
    patched = False
    with zipfile.ZipFile(jar) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == inner:
                old = b"\xb8\x00\xad\x9a\x00\x0b"  # invokestatic StringUtil.equals + ifne
                new = b"\xb8\x00\xad\xa7\x00\x0b"  # invokestatic StringUtil.equals + goto
                n = data.count(old)
                if n == 1:
                    data = data.replace(old, new)
                    patched = True
            zout.writestr(item, data)
    if patched:
        shutil.move(tmp, jar)
        print(f"  IDE sync: patched {os.path.basename(jar)}")
    else:
        os.remove(tmp)
        print(f"  IDE sync: {os.path.basename(jar)} pattern not unique/found — skipped")
PYEOF

echo "Done."
echo "Use it: set compileSdkVersion (and targetSdkVersion) in build-profile.json5,"
echo "e.g. '6.1.1(24)' for the 6.1.1 Release SDK."
echo "Note: after a package upgrade, re-run this script to re-apply the patches."
