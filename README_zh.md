<p align="center"><img src="Icon/icon_1024.png" width="128" alt="WindowMirror 图标"></p>

<h1 align="center">WindowMirror · 窗口镜像</h1>

<p align="center"><b>投屏只投一个窗口，桌面、微信和通知都不会露出去。</b></p>

<p align="center">
  <a href="https://github.com/haoyibits/WindowMirror/releases/latest"><img src="https://img.shields.io/github/v/release/haoyibits/WindowMirror?label=%E4%B8%8B%E8%BD%BD&color=2F5BFF" alt="下载"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-13203A" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20%E8%8A%AF%E7%89%87%20%2B%20Intel-%E9%80%9A%E7%94%A8-13203A" alt="Apple 芯片和 Intel">
  <a href="LICENSE"><img src="https://img.shields.io/badge/%E5%85%8D%E8%B4%B9%E5%BC%80%E6%BA%90-MIT-2BC4A0" alt="免费开源 MIT"></a>
</p>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

<p align="center"><img src="docs/media/pick.gif" alt="在主屏点选浏览器窗口，副屏只显示这个窗口，旁边的私人备忘录不会出现"></p>
<p align="center"><sub>左边是你的 Mac，右边是投影。左边的私人备忘录不会出现在右边。</sub></p>

---

WindowMirror 是一个免费的 Mac 菜单栏小工具。它把你选中的一个窗口实时投到投影仪或第二块显示器上，演示时还能直接在上面画。聊天消息、通知和桌面都只留在你自己的屏幕上。

## 系统自带的镜像和扩展屏不够用吗？

| | 观众看到的 | 你自己看到的 |
|---|---|---|
| **镜像显示器**（macOS 自带） | 整个屏幕，包括弹出来的微信消息和其他应用 | 一样的画面 |
| **扩展显示器** | 你拖过去的那个窗口 | 看不到，得回头看投影 |
| **会议软件共享窗口** | 一个窗口，但只有线上参会的人能看到 | 正常的屏幕 |
| **WindowMirror** | 一个窗口，在投影上全屏显示 | 正常的屏幕，窗口还在原处，照常操作 |

任何应用都能投：浏览器、代码编辑器、Figma、PDF、终端都可以。

## 三步上手

1. **[下载 DMG](https://github.com/haoyibits/WindowMirror/releases/latest)**，打开后把 WindowMirror 拖进“应用程序”。
2. 点菜单栏的双矩形图标，选**点选窗口…**，再点一下要投的窗口。
3. 副屏上就会全屏显示这个窗口。讲完点**停止镜像**。

第一次打开会被系统拦下，看下面的[首次打开](#首次打开)，20 秒就能搞定。

## 边讲边画

<p align="center"><img src="docs/media/present.gif" alt="用画笔在标题和数字下面画线，副屏同步显示笔迹"></p>

在自己屏幕的窗口上画，投影上同步显示。用窗口上方的工具栏，或者快捷键：

- **激光笔**（⌃⌥L）：一个跟着鼠标走的光点，窗口照样能点、能滚动。
- **画笔**（⌃⌥D）和**荧光笔**（⌃⌥H）：圈出一个数字，划出一行代码。
- **撤销**（⌃⌥Z）、**清除**（⌃⌥C），还能设置笔迹几秒后自动消失。

## 一键铺满投影，没有黑边

<p align="center"><img src="docs/media/fit.gif" alt="在工具栏选择适配方式，源窗口变成副屏的比例，副屏铺满"></p>

窗口的形状很少刚好和投影一样，所以两边会有黑边。点一下就能把窗口调成投影的宽高比，或者调成和投影一样的像素尺寸，画面最清晰。

## 其他

- **流畅清晰：** 60 帧，按窗口原生分辨率抓取。显示器支持的话，HDR 和广色域都会保留。
- **不打扰你：** 镜像不会抢走主屏的焦点。窗口被别的窗口挡住时，投影画面照常更新。
- **不占 Dock：** 所有操作都在菜单栏里。
- **中英双语：** 跟随系统语言，也可以在菜单里切换。

## 首次打开

App 没有经过 Apple 公证，第一次打开时系统会提示“无法验证开发者”。这样打开：

1. 先打开一次，关掉提示。
2. 到**系统设置 › 隐私与安全性**，往下拉，在 WindowMirror 旁边点**仍要打开**。

或者在终端运行：

```bash
xattr -dr com.apple.quarantine /Applications/WindowMirror.app
```

之后它会申请两项权限，都在“系统设置 › 隐私与安全性”里：

| 权限 | 为什么需要 | 不授权的话 |
|---|---|---|
| 屏幕与系统录音 | 看到窗口里的内容 | 仍然可以用**点选窗口…** |
| 辅助功能 | 把窗口调成投影的尺寸 | 其他功能都正常 |

## 常见问题

**收费吗？** 不收费。代码以 MIT 协议开源。

**会上传我的屏幕吗？** 不会。App 完全不联网，所有内容都留在你的 Mac 上。

**只有一块屏能用吗？** 能。镜像会以普通窗口的形式出现在你的屏幕上。

**支持哪些 Mac？** macOS 14 Sonoma 及以上，Apple 芯片和 Intel 都支持。

**遇到问题？** 欢迎[提 Issue](https://github.com/haoyibits/WindowMirror/issues)。觉得好用的话，点个 ⭐ 能让更多人看到它。

## 参考

<details>
<summary><b>全部快捷键</b></summary>

| 快捷键 | 功能 |
|---|---|
| ⌘P | 点选窗口…（菜单打开时） |
| ⌃⌥L | 激光笔：不拦截点击，窗口照常操作，镜像中隐藏系统指针 |
| ⌃⌥D | 画笔 |
| ⌃⌥H | 荧光笔 |
| ⌃⌥Z | 撤销上一笔 |
| ⌃⌥C | 清除全部 |
| ⌃⌥X | 退出标注，同时清除笔迹 |
| ⌃⌥M | 把窗口调成投影的像素尺寸（1:1） |
| ⌃⌥R | 按投影的宽高比，把窗口调到尽量大 |

标注快捷键在任何应用里都能用。再按一次当前工具的快捷键会退出标注。用画笔或荧光笔时，标注层会接住鼠标，要点窗口的话，切到激光笔或退出标注。

</details>

<details>
<summary><b>菜单选项</b></summary>

**选择窗口和显示器。** 可以直接点选窗口，也可以从“从主屏窗口列表选择”里挑。默认投到第一块副屏，可以在“目标显示器”里换。要停止，点“停止镜像”，或者点一下副屏画面后按 Esc。源窗口关闭时也会自动停止。镜像过程中，菜单会显示源和目标的像素尺寸，以及缩放倍率。

**按副屏调整源窗口。**

| 选项 | 效果 |
|---|---|
| 像素 1:1 | 窗口和投影像素尺寸相同，最清晰 |
| 同比例，尽量大 | 按投影的宽高比，在你的屏幕里放到最大 |
| 同比例，保持当前宽度 | 只调高度 |
| 同比例，保持当前高度 | 只调宽度 |

窗口放不下时会等比缩小，并挪回屏幕内。有些应用会限制窗口尺寸（比如终端按字符行列调整），这时比例会有一点偏差，App 会告诉你偏了多少。

**缩放方式。** 适应、填充、拉伸、原始像素（1:1 居中）。

**标注。** 选择笔迹颜色，打开笔迹自动消失，显示或隐藏窗口上方的工具栏。工具栏会跟着窗口移动，不会被镜像出去。

**Language / 语言。** 跟随系统、English 或简体中文，下次打开菜单时生效。

</details>

<details>
<summary><b>已知限制</b></summary>

- 窗口最小化后，投影画面会停止更新。
- 两块不同的屏幕颜色不可能完全一致，开着原彩显示（True Tone）时更明显。
- 副屏使用“缩放”分辨率时，系统还会再缩放一次，物理像素达不到严格 1:1。

</details>

<details>
<summary><b>从源码构建</b></summary>

需要 Xcode 命令行工具（提供 `swiftc`）。

```bash
git clone https://github.com/haoyibits/WindowMirror.git
cd WindowMirror
./install.sh
```

`install.sh` 会编译、签名、安装到 `/Applications`，然后启动 App。`./build.sh` 只编译不安装，产物在 `~/Library/Caches/WindowMirror/`。`./package.sh` 编译通用版本并打包成 DMG，放在同一目录。产物不放在项目目录里，是因为 iCloud 同步的文件夹会给 `.app` 加上扩展属性，导致签名失败。

App 使用 ad-hoc 签名，系统会把每次重新构建的版本当成新 App。重新构建后，要在两项权限里删掉旧条目、重新添加。如果想避免这个问题，在 `build.sh` 里把 `--sign -` 换成一个固定的代码签名证书名称。

```
Sources/main.swift        菜单栏 App、抓取引擎、镜像窗口、源窗口调整、界面语言
Sources/Annotation.swift  标注：数据模型、渲染、透明标注层、全局快捷键
Sources/Toolbar.swift     源窗口上方的悬浮工具栏
Icon/draw_icon.swift      用 CoreGraphics 绘制图标
Resources/*.lproj         本地化的 App 名称
docs/media/               README 用的演示 GIF
```

</details>

## 许可证

[MIT](LICENSE)
