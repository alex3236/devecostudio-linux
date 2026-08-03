# DevEco Studio — Linux PKGBUILD

[`English`](README.md) | **中文**

感谢 [Cris.Q](https://crisq.top/blog/deveco_linux_porting_notes) 的移植笔记，本项目受其启发。

这是一个 Arch Linux PKGBUILD，将 DevEco Studio（华为的 HarmonyOS 开发 IDE）的 Mac DMG 发行版重新打包到 Linux，借助 JetBrains IntelliJ IDEA 的原生启动器和 JBR 实现。

这不是官方包，也未获得华为或 JetBrains 的认可。

## 如何构建

请务必自行检查 `PKGBUILD`。

你需要从华为官网手动下载两个文件：

1. **DevEco Studio ${pkgver} for Mac**
2. **Command Line Tools for Linux (x86_64) ${pkgver}**

将两个 `.zip` 文件放到 PKGBUILD 所在目录，并**重命名**为 PKGBUILD 期望的固定文件名——`devecostudio-mac.zip` 和 `commandline-tools-linux-x64.zip`（文件名与版本无关）。然后执行：

    makepkg -si

IntelliJ IDEA 的 tarball 会自动从 JetBrains CDN 下载。

`pkgver` 中的版本及其 SHA256 校验值是作者测试过的。要使用其他版本：

1. 查看 PKGBUILD 中期望的文件名（文件名不含版本号，只需重命名一次下载文件），
2. 下载所需版本，重命名为固定文件名，然后更新 `pkgver` 和两个 SHA256 校验值（如果不想校验，可设为 `"SKIP"`），
3. 也可以修改 `_ideaver` 换用不同的 IDEA 基础版本。

只有 `pkgver` 中的版本经过测试——如果你做了修改，请自行测试结果。

如果通过 GitHub Actions 工作流构建，可以提供 `pkgver` 和两个华为下载文件的 SHA256 校验值；其中任何一项留空则使用 PKGBUILD 中已有的值。

## 已知限制

- **模拟器** — macOS 的模拟器二进制无法移植。Oniro 项目提供了 [OpenHarmony 模拟器](https://docs.oniroproject.org/device-development/developer-boards/emulator)，但它无法替代 HarmonyOS 模拟器。

## 背后做了什么

PKGBUILD 解压 Mac DMG，取出平台无关的部分——JAR、插件、modules、工具（hvigor、ohpm 等）。然后用 IntelliJ IDEA 的 Linux 对应组件替换 macOS 专属部分（启动器、JBR、原生库）。vmoptions 和 product-info.json 会在构建时动态转换，让 IDE 知道自己运行在 Linux 上。

最终得到一个无需 Wine 或容器即可运行的原生体验 DevEco Studio。

## 为什么从 Mac 版重新打包？

华为为 Windows、macOS 和 Linux 分发 DevEco Studio。Linux 发行版有两个问题：安装器是难以解包的 `.exe`，且打包版本更新滞后。Mac DMG 可以轻松解包，且包含我们需要的全部跨平台文件。

真正平台相关的、需要替换的部分只有：
- Java 运行时（JBR）— macOS → Linux
- 原生启动器二进制
- 共享库（.so 文件）

其他一切——Java 代码、插件、模板、构建工具——都是平台无关的。

## 许可情况

本项目与华为无关联，也未获华为认可。

DevEco Studio 是华为的商业产品。使用前即表示你同意《华为 DevEco Studio 用户协议》（见 LICENSE.huawei）。几个值得注意的条款：

- **第 1.6 条** 授予"有限的、非排他的、免费的、不可转让的、不可再许可的、可撤销的"许可，仅用于开发可在 OpenHarmony 兼容设备和/或 HarmonyOS 上运行的应用。
- **第 1.7(f) 条** 禁止复制或修改本服务，或将本服务的任何部分与其他程序合并。
- **第 1.7(h) 条** 禁止反向工程、反编译或创作衍生作品。
- **第 1.7(i) 条** 禁止分发、出售或转让本服务。

本项目从 Mac DMG 提取平台无关文件，并与来自 IntelliJ IDEA 的 Linux 原生组件（启动器、JBR、原生库）重新组合。Java 字节码和资源未被修改，但配置文件被转换。这可能构成第 1.7(f) 和 1.7(h) 条下的"修改"和"合并"。

这在实际中意味着：
- 构建此包供个人使用是作者的做法，本项目存在的意义就是记录这一过程。
- 将构建结果分发给他人很可能不符合华为的条款。
- 如有法律方面的顾虑，请查阅华为官方许可 https://developer.huawei.com/consumer/cn/deveco-studio/ 并咨询你自己的法律顾问。

### 打包脚本的许可

构成此打包项目的文件（PKGBUILD、devecostudio.install、devecostudio.desktop、工作流和 README）采用 BSD 2-Clause 许可。它们不属于 DevEco Studio，不承载华为条款中的任何限制。

### 内置组件的许可

- DevEco Studio 本身及其插件是华为的专有作品。
- JetBrains Runtime (JBR) 基于 OpenJDK，采用带 classpath exception 的 GPLv2。
- IntelliJ IDEA Community 组件以 Apache 2.0 提供。
- DevEco Studio 捆绑的各种第三方库各自带有其许可。
