# DevEco Studio — Linux PKGBUILD

[`English`](README.md) | **中文**

<p align="center">
  <img src=".github/images/poster.png" alt="poster" width="80%" />
</p>

感谢 [Cris.Q](https://crisq.top/blog/deveco_linux_porting_notes) 的移植笔记，本项目受其启发。

这是一个 Arch Linux PKGBUILD，将 DevEco Studio（华为的 HarmonyOS 开发 IDE）的 Mac DMG 发行版重新打包到 Linux，借助 JetBrains IntelliJ IDEA 的原生启动器和 JBR 实现。

这不是官方包，也未获得华为或 JetBrains 的认可。

## 状态

除预览器外，功能基本可用。若发现任何问题，请提交一个 Issue。

若原生 Linux 版发行，此项目将归档。

> [!NOTE]  
> 如果你计划使用此项目，强烈建议完整阅读 README，其中折叠部分根据需要选择性阅读。

## 构建

使用前请务必自行检查 `PKGBUILD`。

<details>
<summary><b>我想在本地构建（任意发行版）</b></summary>
<br><table><thead><tr><td>

首先，从华为官网下载两个文件：

1. **DevEco Studio ${pkgver} for Mac**
2. **Command Line Tools for Linux (x86_64) ${pkgver}**

将两个 `.zip` 放在 PKGBUILD 旁边，并**重命名**为 `devecostudio-mac.zip` 和
`commandline-tools-linux-x64.zip`。

    # 克隆仓库
    git clone https://github.com/alex3236/devecostudio-linux.git
    cd devecostudio-linux

    # 检出最新 tag（如可接受未经测试的更改可跳过）
    git fetch --tags
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1))

接下来的步骤视你所处的发行版而定：

<details>
<summary><b>我在用 Arch Linux</b></summary>
<br><ul>

    makepkg -si

如果出现校验和不符，说明华为更新了 IDE，你需要自行测试此项目是否仍然可用。

要更新校验和以匹配你的本地文件：

    updpkgsums

</ul>
</details>

<details>
<summary><b>我在用其他发行版</b></summary>
<br><ul>

你将需要以下依赖：

    bsdtar 或 unzip, jq, python3, curl, binutils

如你需要构建 .deb/.rpm，则额外需要：

    nfpm, gettext

准备好后：

    # 查看构建脚本帮助
    ./build.sh -h

    # 例：构建 tarball
    ./build.sh
    
    # 例：构建 tarball 和 rpm 包
    ./build.sh --rpm

注意：`build.sh` 并**不会**校验两个华为 zip。IDEA 和 CPython 则会按 PKGBUILD 的 `sha256sums` 校验。

</ul>
</details>

</td></tr></thead></table>
</details>


<details>
<summary><b>我想用在线构建（GitHub Actions）</b></summary>
<br><table><thead><tr><td>

同样的构建可以在 GitHub Actions 中运行：

1. **Fork** 此仓库。
2. 打开 **Actions** 标签页，选择 **Build DevEco Studio PKGBUILD** 并点击 **Run workflow**。
3. 可选："Use workflow from" 选择某个已发布的 tag。
4. 填写两个下载 URL：
   - `mac_zip_url` — Mac zip 的 URL
   - `cli_zip_url` — Linux Command Line Tools zip 的 URL
5. 可选地覆盖版本号和校验值（留空则使用 `PKGBUILD` 中的值）：
   - `pkgver` — 例如 `6.1.1.280`
   - `mac_zip_sha256` / `cli_zip_sha256` — 两个 zip 的 SHA256；未测试过的版本可用 `SKIP` 跳过校验
6. 运行结束后，从运行页面下载对应平台的 artifact：
   - `devecostudio-arch` — Arch 包
   - `devecostudio-deb` — Debian/Ubuntu 包
   - `devecostudio-rpm` — Fedora/RHEL 包
   - `devecostudio-tarball` — 任何其他发行版

GitHub 账户在公共仓库上可以免费使用 Actions。

</td></tr></thead></table>
</details>

## 安装

此包的目标平台是 Arch Linux（makepkg）；
`.deb`/`.rpm` 构建覆盖 Debian 12+ / Ubuntu 22.04+ 与 Fedora / RHEL；
tarball 适用于任何 Linux。

    # Arch
    sudo pacman -U devecostudio-*.pkg.tar.zst

    # Debian / Ubuntu
    sudo apt install ./devecostudio_*.deb

    # Fedora / RHEL
    sudo dnf install ./devecostudio-*.rpm

<details>
<summary><b>其他发行版（通过 tarball）</b></summary>
<br><table><thead><tr><td>

解压 tarball 并手动设置启动器：

    sudo tar -xzf devecostudio-<版本>-linux-x86_64.tar.gz -C /opt
    sudo ln -s /opt/devecostudio/bin/devecostudio.sh /usr/local/bin/devecostudio
    sudo desktop-file-install /opt/devecostudio.desktop

还需要安装运行时依赖（包名因发行版而异）：`libxss`、`libxtst`、`nss`、`alsa-lib`、`libxcrypt-compat`、`freetype2`、`libpulse`。中文输入支持需要 `fcitx5`。与 Arch 包不同，内置 CLI 工具不会链接到 `/usr/bin`——请用完整路径调用 `/opt/devecostudio/tools/bin/` 下的工具。

</td></tr></thead></table>
</details>

## 使用

使用任意你熟悉的方式（开始菜单/程序坞/命令行）启动 DevEco Studio。

### PATH 上的 CLI 工具

IDE 运行需要捆绑的华为命令行工具，它们也可以独立在终端使用。
默认情况下，包会把它们软链到 `/usr/bin`：

- 始终暴露的命令：`devecostudio`, `hdc`
- 默认暴露的命令：`hvigorw`, `ohpm`, `hstack`, `hcodelinter`, `hemulator`, `harktsdoc`；

其中 `Emulator`、`codelinter` 和 `arktsdoc` 添加了前缀以避免可能的冲突。

<details>
<summary><b>调整这些软链行为</b></summary>
<br><table><thead><tr><td>

两种行为都由 PKGBUILD 顶部的变量控制：

- `_expose_cli_tools=true`
    - 若设为 `false`，默认暴露的指令不再暴露到 `/usr/bin`
    - 仍可通过 `/opt/devecostudio/tools/bin/`完整路径调用
- `_hprefix_generic_tools=true`
    - 若设为 `false`，则不添加 `h` 前缀，以原名暴露 `codelinter` 和 `Emulator`

</td></tr></thead></table>
</details>

### 额外 SDK（旧版本）

内置 SDK 为 HarmonyOS 26.0.0（Release）。
可以额外安装旧版 SDK（如 6.1.1 Release），按项目切换使用——便于复现问题或针对旧 API 版本构建。

<details>
<summary><b>怎么做？</b></summary>
<br><table><thead><tr><td>

1. 下载相应的 CLI 工具包；
2. 通过以下命令安装 SDK 至 IDE 目录：
    ```shell
    # 从华为 CLI zip 安装 SDK（需要 sudo）
    sudo /opt/devecostudio/bin/install-extra-sdk.sh /commandline-tools-linux-x64-6.1.1.280.zip
    ```

3. 在你的项目中设置编译 SDK：
    ```json5
    "compileSdkVersion": "6.1.1(24)",
    "targetSdkVersion": "6.1.1(24)"
    ```

</td></tr></thead></table>

安装旧版 SDK 时，脚本会应用补丁使其可用。补丁只在执行 `install-extra-sdk.sh` 时应用。

注意：使用了 API 26 独有接口的源码（如新版相机 API）无法用 6.1.1 编译，需要相应调整或防护。
</details>

### 模拟器

模拟器可用，但首次使用前需要通过命令行同意软件协议并下载系统镜像。

<details>
<summary><b>怎么做？</b></summary>
<br><table><thead><tr><td>

    # 查看可用镜像
    hemulator -imageList
    
    # 只查看手机镜像
    hemulator -imageList -deviceType phone
    
    # 使用 jq 以获得简洁输出
    hemulator -imageList -deviceType phone | jq '.[].osVersion'
    
    # 安装镜像
    hemulator -install -deviceType phone -osVersion "HarmonyOS 6.1.1(24)"

安装完成后，即可在 IDE 的设备管理器中创建、管理和启动模拟器。

</td></tr></thead></table>
</details>

### 预览器

预览器不可用。华为尚未将 Rosen 渲染引擎移植到 Linux。

### DevEco CLI

华为的 `DevEco CLI` 可以帮助你和你的 AI Agent 轻松初始化、构建、签名、调试项目，以及查找官方文档。

本项目可以为 DevEco CLI 提供环境支持。设置 `DEVECO_CLI_STUDIO_PATH=/opt/devecostudio` 即可。

## 这是如何实现的？

PKGBUILD 解压 Mac DMG，取出平台无关的部分，然后用 IntelliJ IDEA 的 Linux 对应组件替换 macOS 专属部分（启动器、JBR、原生库）。vmoptions 和 product-info.json 会在构建时动态转换，让 IDE 知道自己运行在 Linux 上。

最终得到一个无需 Wine 或容器即可运行的原生体验 DevEco Studio。

为什么从 Mac 版重新打包？华为为 Windows、macOS 和 Linux 分发 DevEco Studio。Linux 发行版有两个问题：安装器是难以解包的 `.exe`，且打包版本更新滞后。Mac DMG 可以轻松解包，且包含我们需要的全部跨平台文件。

<details>
<summary><b>查看各组件的细节</b></summary>
<table><thead><tr><td>

### 模拟器

有三个与模拟器相关的问题值得说明。

其一，华为的代码只区分 Mac 与非 Mac，而非 Mac 分支硬编码了 `Emulator.exe` 文件名。在 Linux 上这个文件不存在，导致 Device Manager 和调试不可用。本包通过符号链接修复：`tools/emulator/` 下的 `Emulator.exe -> Emulator`。

其二，系统镜像必须手动下载，这是官方安装器的工作方式决定的：当模拟器缺失时，其向导会同时下载二进制和系统镜像。由于本包已内置二进制，IDE 认为模拟器已安装、从不弹出向导，系统镜像成了唯一缺失的部分——获取方式见上文"模拟器"一节。

其三，模拟器的软件协议：IDE 直接启动模拟器二进制，如果协议从未被同意，它会静默等待输入 `y`。`Emulator` 包装器在首次使用时自动同意（当 `~/Library/Caches/Huawei/Emulator26.0/.emu_config` 不存在时，执行 `hemulator ...` 会运行 `-license accept` 并退出），因此当你在 IDE 中使用时协议已经就绪。如需退出自动同意，请清空该 `.emu_config` 文件。

### Wayland

IDE 大部分功能在 Wayland 下正常，但基于 CEF 的界面——项目结构对话框、Markdown 预览等——的 GPU 进程在 Wayland 下会崩溃（`eglCreateWindowSurface` 段错误）。启动器 wrapper 默认强制 X11 后端来解决（`unset WAYLAND_DISPLAY`、`GDK_BACKEND=x11`），让所有 CEF 页面通过 XWayland 正常渲染。

如果你更想原生运行在 Wayland 下，可以在启动前设置 `DEVECO_DISABLE_X11_WORKAROUND=1`——但 CEF 页面会空白或异常。

启动器默认还启用了 JCEF 的 headless + 子进程渲染（相当于注册表中的 `ide.browser.jcef.headless.enabled` 和 `ide.browser.jcef.out-of-process.enabled`），可解决特定环境下 CEF 页面空白的问题。如需关闭，启动前设置 `DEVECO_DISABLE_JCEF_HEADLESS=1`。

### HiDPI

XWayland 不会向 JVM 报告 per-monitor 缩放（它报告 1.0），因此在 HiDPI 屏幕上 IDE 会把 UI 缩放锁定为 1.0——太小。启动器会读取合成器的真实缩放（`wlr-randr`），四舍五入到最近的 0.25 步，并通过用户级 vmoptions 覆盖文件以 `-Dide.ui.scale` 注入。

覆盖值或禁用检测：

    DEVECO_UI_SCALE=1.2 devecostudio   # 直接使用 1.2
    DEVECO_UI_SCALE=off devecostudio   # 把缩放交给 JVM

你也可以通过 IDE 的 *Help → Edit Custom VM Options* 手动设置缩放。更多信息请参考 [IDEA HiDPI 文档](https://intellij-support.jetbrains.com/hc/en-us/articles/360007994999-HiDPI-configuration)。

</td></tr></thead></table>
</details>

限于篇幅，你可以查看 [DETAILS.md](DETAILS.md) 了解本项目使用的其他魔法。

## 许可情况

本项目与华为无关联，也未获华为认可。

<details>
<summary><b>条款、分发与内置组件许可</b></summary>
<br><table><thead><tr><td>

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

构成此打包项目的文件采用 BSD 2-Clause 许可。

它们不属于 DevEco Studio，不承载华为条款中的任何限制。

### 内置组件的许可

- DevEco Studio 本身及其插件是华为的专有作品。
- JetBrains Runtime (JBR) 基于 OpenJDK，采用带 classpath exception 的 GPLv2。
- IntelliJ IDEA Community 组件以 Apache 2.0 提供。
- DevEco Studio 捆绑的各种第三方库各自带有其许可。

</td></tr></thead></table>
</details>
