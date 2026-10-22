#!/usr/bin/env python3
"""Patch OsTypeUtil in DevEco Studio jars so remote emulator images appear on Linux.

Huawei's remote SDK manager (getSdkList) returns an empty list for osType "linux",
but returns all 48 x86_64 system images for "windows". Since emulator system images
are QEMU guest images, they are platform-independent. Huawei's own Linux CLI emulator
binary (/opt/devecostudio/tools/emulator/Emulator) hardcodes "windows" as its osType query
for this exact reason.

In bytecode (getOsType):
  ldc #31 ("linux") + areturn   (\\x12\\x1f\\xb0)
    ->
  ldc #27 ("windows") + areturn (\\x12\\x1b\\xb0)

Target classes:
  - com/huawei/deveco/sdkmanager/core/util/OsTypeUtil.class (in sdk-core-*.jar)
  - com/huawei/deveco/common/env/OsTypeUtil.class          (in hwlib.jar)

Usage:
  # In packaging scripts (PKGBUILD):
  python3 patch-emulator-list.py "$_pkg"

  # Or on an existing installation:
  sudo python3 patch-emulator-list.py /opt/devecostudio
"""

import glob
import os
import shutil
import sys
import zipfile

OLD_PAT = b"\x12\x1f\xb0"
NEW_PAT = b"\x12\x1b\xb0"

TARGET_CLASSES = {
    "com/huawei/deveco/sdkmanager/core/util/OsTypeUtil.class",
    "com/huawei/deveco/common/env/OsTypeUtil.class",
}


def patch_jar(jar_path):
    if not os.path.isfile(jar_path):
        return False
    temp_jar = jar_path + ".tmp"
    patched_any = False
    try:
        with zipfile.ZipFile(jar_path, "r") as zin:
            names = set(zin.namelist())
            matched = names.intersection(TARGET_CLASSES)
            if not matched:
                return False

            with zipfile.ZipFile(temp_jar, "w", compression=zipfile.ZIP_DEFLATED) as zout:
                for item in zin.infolist():
                    data = zin.read(item.filename)
                    if item.filename in TARGET_CLASSES:
                        if OLD_PAT in data:
                            data = data.replace(OLD_PAT, NEW_PAT)
                            patched_any = True
                            print(
                                "  patch-emulator-list: patched %s in %s"
                                % (item.filename, os.path.basename(jar_path))
                            )
                        elif NEW_PAT in data:
                            print(
                                "  patch-emulator-list: already patched in %s"
                                % os.path.basename(jar_path)
                            )
                    zout.writestr(item, data)

        if patched_any:
            shutil.copymode(jar_path, temp_jar)
            shutil.move(temp_jar, jar_path)
            return True
        return False
    finally:
        if os.path.exists(temp_jar):
            os.remove(temp_jar)


def main():
    if len(sys.argv) < 2:
        print("Usage: patch-emulator-list.py <pkgdir-or-jar>...", file=sys.stderr)
        return 1

    for arg in sys.argv[1:]:
        if os.path.isdir(arg):
            patch_jar(os.path.join(arg, "lib", "hwlib.jar"))
            for jar in glob.glob(
                os.path.join(arg, "plugins", "openharmony", "lib", "sdk-core-*.jar")
            ):
                patch_jar(jar)
        elif os.path.isfile(arg):
            patch_jar(arg)


if __name__ == "__main__":
    main()
