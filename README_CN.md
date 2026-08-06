# DevEco Studio — Linux PKGBUILD

[`English`](README.md) | **中文**

感谢 [Cris.Q](https://crisq.top/blog/deveco_linux_porting_notes) 的移植笔记，本项目受其启发。

这是一个 Arch Linux PKGBUILD，将 DevEco Studio（华为的 HarmonyOS 开发 IDE）的 Mac DMG 发行版重新打包到 Linux，借助 JetBrains IntelliJ IDEA 的原生启动器和 JBR 实现。

这不是官方包，也未获得华为或 JetBrains 的认可。

## 构建

### 本地用 makepkg 构建

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

### 用 GitHub Actions 构建

如果你手边没有 Arch 机器，也可以用 GitHub Actions 跑同样的构建：

1. **Fork** 本仓库（该工作流需要手动触发），或使用你自己的 fork。
2. 打开 **Actions** 标签页，选择 **Build DevEco Studio PKGBUILD** 工作流，点击 **Run workflow**。
3. 填写两个下载 URL（华为的链接会过期，每次构建都需要从[下载页](https://developer.huawei.com/consumer/cn/deveco-studio/)获取新链接）：
   - `mac_zip_url` — Mac zip 的 URL
   - `cli_zip_url` — Linux Command Line Tools zip 的 URL
4. 可选地覆盖版本号和校验值（留空则使用 `PKGBUILD` 中的值）：
   - `pkgver` — 例如 `6.1.1.280`
   - `mac_zip_sha256` / `cli_zip_sha256` — 两个 zip 的 SHA256；未测试过的版本可用 `SKIP` 跳过校验
5. 运行结束后，从运行页面下载 `devecostudio-pkg` artifact，并在本地安装：

       sudo pacman -U devecostudio-*.pkg.tar.zst

GitHub 账户在公共仓库上可以免费使用 Actions。

## PATH 上的 CLI 工具

IDE 运行需要捆绑的华为命令行工具，它们也可以独立在终端使用。默认情况下，包会把它们软链到 `/usr/bin`：

| `/usr/bin` 入口 | 工具 | 说明 |
|---|---|---|
| `devecostudio` | IDE 启动器 | 始终安装 |
| `hvigorw` | 构建工具 | 华为特有名称，原名暴露 |
| `ohpm` | 包管理器 | 华为特有名称，原名暴露 |
| `hstack` | 工具链辅助 | 华为特有名称，原名暴露 |
| `hcodelinter` | 代码检查 | 加 `h` 前缀避免冲突 |
| `hemulator` | 模拟器 CLI | 加 `h` 前缀避免冲突 |

两种行为都由 PKGBUILD 顶部的变量控制：

- `_expose_cli_tools=true` — 设为 `false` 则完全不暴露到 `/usr/bin`（工具仍留在 `/opt/devecostudio/tools/bin/`，可用完整路径调用）。
- `_hprefix_generic_tools=true` — 设为 `false` 则去掉 `h` 前缀，以原名暴露 `codelinter` / `Emulator`（可能与其他包冲突）。

## 模拟器

模拟器可用，但需手动下载系统镜像：

- 用命令行下载（无需华为账号）：`hemulator -install -deviceType phone -osVersion "<版本>"`（`hemulator -imageList` 查看可用版本），或
- 从其他平台的 DevEco Studio 安装中把 `system-image/` 目录复制到 `~/.Huawei/Sdk/system-image/`。

## Wayland

IDE 大部分功能在 Wayland 下正常，但基于 CEF 的界面——项目结构对话框、Markdown 预览等——的 GPU 进程在 Wayland 下会崩溃（`eglCreateWindowSurface` 段错误）。启动器 wrapper 默认强制 X11 后端来解决（`unset WAYLAND_DISPLAY`、`GDK_BACKEND=x11`），让所有 CEF 页面通过 XWayland 正常渲染。

如果你更想原生运行在 Wayland 下，可以在启动前设置 `DEVECO_DISABLE_X11_WORKAROUND=1`——但 CEF 页面会空白或异常。

## 背后做了什么

PKGBUILD 解压 Mac DMG，取出平台无关的部分——JAR、插件、modules、工具（hvigor、ohpm 等）。然后用 IntelliJ IDEA 的 Linux 对应组件替换 macOS 专属部分（启动器、JBR、原生库）。vmoptions 和 product-info.json 会在构建时动态转换，让 IDE 知道自己运行在 Linux 上。

最终得到一个无需 Wine 或容器即可运行的原生体验 DevEco Studio。

为什么从 Mac 版重新打包？华为为 Windows、macOS 和 Linux 分发 DevEco Studio。Linux 发行版有两个问题：安装器是难以解包的 `.exe`，且打包版本更新滞后。Mac DMG 可以轻松解包，且包含我们需要的全部跨平台文件。

真正平台相关的、需要替换的部分只有：
- Java 运行时（JBR）— macOS → Linux
- 原生启动器二进制
- 共享库（.so 文件）

其他一切——Java 代码、插件、模板、构建工具——都是平台无关的。

### 模拟器

有两个与模拟器相关的问题值得说明。其一，华为的代码只区分 Mac 与非 Mac，而非 Mac 分支硬编码了 `Emulator.exe` 文件名。在 Linux 上这个文件不存在，导致 Device Manager 和调试不可用。本包通过符号链接修复：`tools/emulator/` 下的 `Emulator.exe -> Emulator`。

其二，系统镜像必须手动下载，这是官方安装器的工作方式决定的：当模拟器缺失时，其向导会同时下载二进制和系统镜像。由于本包已内置二进制，IDE 认为模拟器已安装、从不弹出向导，系统镜像成了唯一缺失的部分——获取方式见上文"模拟器"一节。

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
