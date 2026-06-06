# DevEco Studio — Linux PKGBUILD

Thanks to [Cris.Q](https://crisq.top/blog/deveco_linux_porting_notes) for the original porting notes that inspired this project.

This is an Arch Linux PKGBUILD that packages DevEco Studio (Huawei's IDE for HarmonyOS development) from its Mac DMG distribution, bringing it to Linux with the help of JetBrains' IntelliJ IDEA native launcher and JBR.

It is not an official package. It is not endorsed by Huawei or JetBrains.

## How to build

Always check `PKGBUILD` yourself.

You will need to manually download two files from Huawei's website:

1. **DevEco Studio ${pkgver} for Mac**
2. **Command Line Tools for Linux (x86_64) ${pkgver}**

Place both `.zip` files next to the PKGBUILD. Then:

    makepkg -si

The IntelliJ IDEA tarball is fetched automatically from JetBrains' CDN.

The version in `pkgver` and its SHA256 checksums are what the author tested.
To use a different version:
- Check the PKGBUILD for the expected filenames,
- Download the version you want, then update `pkgver` and the two SHA256 checksums (or `"SKIP"` if you'd rather skip verification). 
- You can also change
`_ideaver` for a different IDEA base.

Only the versions in `pkgver` have been
tested — if you modify them, test the result yourself.

## Known limitations

- **Emulator** — The macOS emulator binary is not portable. There is an OpenHarmony emulator from the [Oniro project](https://docs.oniroproject.org/device-development/developer-boards/emulator), but it cannot replace the HarmonyOS emulator.

## What happens under the hood

The PKGBUILD extracts the Mac DMG and takes the platform-independent parts — JARs, plugins, modules, tools (hvigor, ohpm, etc.). Then it replaces the macOS-specific bits (launcher, JBR, native libraries) with their Linux counterparts from IntelliJ IDEA. The vmoptions and product-info.json are transformed on the fly so the IDE knows it's running on Linux.

The result is a native-feeling DevEco Studio that runs without Wine or containers.

## Why repackage from the Mac version?

Huawei distributes DevEco Studio for Windows, macOS, and Linux. The Linux distribution has two problems: the installer is an `.exe` that is hard to extract, and the packaged version lags behind in updates. The Mac DMG is trivially extractable and contains all the cross-platform files we need.

The only truly platform-specific things we swap out are:
- The Java runtime (JBR) — macOS → Linux
- The native launcher binary
- Shared libraries (.so files)

Everything else — the Java code, plugins, templates, build tools — is platform-independent.

## License situation

This project is not affiliated with or endorsed by Huawei.

DevEco Studio is a commercial product owned by Huawei. Before using it, you agree to the HUAWEI DevEco Studio User Agreement (reproduced in LICENSE.huawei). A few clauses worth noting:

- **Clause 1.6** grants a "limited, non-exclusive, free, non-transferable, non-sublicensable, and revocable" license to use DevEco Studio solely for developing applications that run on OpenHarmony-compatible devices and/or HarmonyOS.
- **Clause 1.7(f)** prohibits copying or modifying the service, or merging any part of it with other programs.
- **Clause 1.7(h)** prohibits reverse engineering, decompiling, or creating derivative works.
- **Clause 1.7(i)** prohibits distributing, selling, or transferring the service.

This packaging project extracts platform-independent files from the Mac DMG and recombines them with Linux-native components (launcher, JBR, native libraries) from IntelliJ IDEA. The Java bytecode and resources are not modified, but configuration files are transformed. This likely constitutes "modification" and "merging" under clauses 1.7(f) and 1.7(h). 

What this means in practice:
- Building this package for personal use is what the author does, and the project exists to document that process.
- Distributing the resulting package to others is likely not permitted under Huawei's terms.
- If you have legal concerns, consult Huawei's official licensing at https://developer.huawei.com/consumer/cn/deveco-studio/ and your own legal counsel.

### Licensing of the packaging scripts

The files that make up this packaging project (PKGBUILD, devecostudio.install, devecostudio.desktop, workflow, and README) are provided under the BSD 2-Clause license. They are not part of DevEco Studio and carry no restrictions from Huawei's terms.

### Licensing of bundled components

- DevEco Studio itself and its plugins are proprietary works of Huawei.
- JetBrains Runtime (JBR) is GPLv2 with the classpath exception, based on OpenJDK.
- IntelliJ IDEA Community components are available under Apache 2.0.
- Various third-party libraries bundled with DevEco Studio carry their own licenses.
