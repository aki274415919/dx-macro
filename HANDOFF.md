# dx-macro 交接说明

这个文件给维护者看。用户怎么用只写在 `README.md`。

## 当前状态（2026-07-10）

- **驱动已加载**（不只是探测到）：`InterceptionDriverPresent()` 返回 true，键盘类
  `UpperFilters = keyboard, kbdclass`。用户已重启。
- `dx-macro.dxm` 已写入真实设备：VID `0x413C` / PID `0x2113`（Dell 键盘）/ instance 1，`#DxHardInput on`。
- **Interception 后端初始化已实机验证**：构造成功，`FindKeyboard` 按 VID/PID 找到 id=2。
- **编译版 exe 完全自包含**（实测）：干净目录里只放 `dx-macro.exe` + 一个 `.dxm`，
  运行后自动从 exe 内部释放 `Lib\AutoHotInterception.dll`、`Lib\x64\interception.dll`、
  `Lib\x86\interception.dll`，Interception 正常初始化。用户只需分发这一个 exe。

### ⚠ 唯一仍需人工确认的事

**驱动级发送（尤其方向键）没能在自动化环境里验证**——不是 bug，是测试环境的前台焦点
拿不稳，驱动发的键跑到别的窗口去了（SendInput 后端当初也是同样情况）。
初始化/找键盘都通了，但「`Send "{Left}"` 经驱动真的打进目标程序」需要用户在真实目标里按一下确认。
重点看**扩展键**：`GetKeySC("Left")=0x14B`（带 0x100 扩展位），要确认 AHI 的
`SendKeyEvent` 和 `SubscribeKey` 都认这个位。dxm 里的宏全是方向键，这条必须实机过。

### 「能不能都塞进一个 app」——能，除了驱动本身

- **AHI 库（.dll）已经在 exe 里**：编译时 `FileInstall` 把它们打进 exe，运行时自解压到
  `Lib\`。用户不用管任何散落的库文件，就一个 `dx-macro.exe`。
- **Interception 驱动装不进 app**：它是 Windows 内核驱动，任何驱动级输入工具都得单独装它一次
  （已装好，之后什么都不用再装）。这不是「插件」，是系统驱动，性质上无法内嵌。
- 结论：普通用户 = 一个 exe + 一次性驱动安装。没有别的「插件」要装。

## 文件结构

| 文件 | 作用 |
|---|---|
| `main.ahk` | 运行入口、热键注册、托盘菜单、管理员提权、辅助热键、编辑器 |
| `config.ahk` | `.dxm` 解析、旧 `.ini` 兼容、校验 |
| `lib/Backends.ahk` | 输入后端：SendInput / Interception + 驱动探测 |
| `dx-macro.dxm` | 默认示例脚本 |
| `selftest.ahk` | 自检 |
| `run.bat` | 开发时跑脚本版 |
| `Monitor.ahk`, `lib/AutoHotInterception.*`, `lib/CLR.ahk`, `lib/x64`, `lib/x86` | AutoHotInterception，第三方，Git 忽略；Monitor 仅作高级诊断 |

### AHI 的目录布局不能改

AHI 里写死了这些相对路径，必须照它的约定摆，否则**编译会失败**：

- `AutoHotInterception.ahk` 里 `FileInstall("Lib\AutoHotInterception.dll", ...)`、
  `FileInstall("Lib\x64\interception.dll", ...)` —— 源路径相对**被编译脚本**（`main.ahk`）所在目录解析。
- `Monitor.ahk` 里 `#include Lib\AutoHotInterception.ahk` —— 所以 Monitor 必须在项目根。

构建布局：`Monitor.ahk` 可放根目录，其余 AHI 文件在 `lib\`（含 `lib\x64\`、`lib\x86\`）。
放成 `lib\AutoHotInterception\` 会让 `Ahk2Exe` 直接编译失败（exit 54）。
## 运行行为

- `dx-macro.exe <script.dxm>` 可以运行任意路径的脚本。
- 入口脚本可用 `#Include` 递归加载多个 `.dxm`；相对路径按包含者目录解析，循环包含会被拒绝。
- 编译后的 exe 不传参数时注册 `.dxm` 文件关联并打开 GUI 编辑器。
- 开发脚本版不传参数时仍读取同目录的 `dx-macro.dxm`，没有则兼容读取旧的 `dx-macro.ini`。
- 程序内 `--register` / `--unregister` 也能注册或撤销 `.dxm` 文件关联。
- `--edit [path]` 打开简易编辑器。
- 同一个热键可以按不同 `active_window` 分发；同一个热键同一个窗口重复配置会被校验拒绝。
- `#AskAdmin on` 启动时尝试提权；用户拒绝则继续普通权限。
- `#RequireAdmin` 拒绝提权时直接退出。
- `#DxHardInput off` 使用 SendInput。
- `#DxHardInput on` 使用 Interception 后端。
- Interception 后端会用 `SubscribeKey` 接管无修饰用户热键；组合热键和工具控制键仍用 AHK `Hotkey()`。
- `Ctrl+Alt+W` 复制当前前台进程名。
- `Ctrl+Alt+K` 打开常驻按键识别器：按任意键实时显示键名、扫描码和可粘贴的写法，
  小键盘键提示 NumLock 影响。窗口关掉才结束，不超时、不用反复按热键。单实例（`KeyInspectorOpen`）。
- `Ctrl+Alt+E` 打开当前脚本的简易编辑器。
- `Ctrl+Alt+R` 录制按键（含按住时长、按下/松开分离、间隔）到剪贴板，按 Esc 停。
- 托盘菜单：编辑脚本 / 重载脚本 / 暂停恢复 / 退出。重载没有占用热键，只在托盘里。
- `#DxHardInput on` 但驱动没装：弹一个能点去下载页的框，然后回退到 SendInput 继续跑。

## 支持的 `.dxm` 语法

- 指令：`#Requires`、`#AskAdmin`、`#RequireAdmin`、`#DxHardInput`、`#PauseKey`、`#ExitKey`、`#HotIf`、`#Repeat`、`#InterceptionVid`、`#InterceptionPid`、`#InterceptionInstance`、`#Include`、`#Block`
- 热键：`Name::`
- 动作：`Send`、`Sleep`、`Tap`、`KeyDown`、`KeyUp`、`Call`、`Return`
- 窗口条件：`#HotIf true`、`#HotIf WinActive("name.exe")`、`#HotIf WinActive("ahk_exe name.exe")`

## 构建

需要 AutoHotkey v2 和 Ahk2Exe。

```powershell
Ahk2Exe.exe /in main.ahk /out dx-macro.exe /base AutoHotkey64.exe
```

`dx-macro.exe` 是构建产物，被 Git 忽略。注意：Ahk2Exe 的退出码不可靠（成功也可能非 0），
判断成功要看有没有生成 exe，别看退出码。

## 打发布包（一个包，不用满世界下载）

```powershell
pwsh -File build-release.ps1
```

产出 `release\` 和 `dx-macro-release.zip`，里面自带：自包含的 `dx-macro.exe`、
Interception 驱动安装器（脚本自动从官方唯一来源下一次，带 SHA256 校验）、一键安装/卸载
`.bat`（自动提权）、使用说明。用户拿到 zip 解压即用，换机器整包拷走，不用再下载任何东西。

- AHI 的 dll 已经在编译时打进 exe，运行硬输入时自解压到 exe 旁边的 `Lib\`。**已实测**：
  只把 exe + `.dxm` 放进空目录运行，能自解压并初始化 Interception。
- **唯一装不进 app 的是 Interception 内核驱动**——任何驱动级输入工具都得单独装它一次，
  这是系统驱动不是插件。发布包已把安装器带上，所以也不用去 GitHub 找。
- `release\` 和 `*.zip` 都被 Git 忽略，是可随时重新生成的产物。

## 测试

```powershell
AutoHotkey64.exe /ErrorStdOut selftest.ahk
```

61 条当前环境断言，退出码 0 = 全过。自检不发送真实键盘输入，用 `MockBackend` 检查解析、校验、
动作展开、松键兜底、硬输入指令、管理员指令、`#HotIf` 解析、`ParseSendGroups` 拆组、
`RunSend` 路由到后端、`EmitRecording` 录制转换。

后端断言是回归护栏：驱动没装时抛 `DriverMissingError`，缺设备配置时抛
`KeyboardNotConfiguredError`。
如果有人把它改回「先构造 AHI / 用 GetKeyboardId」，自检进程会被 AHI 的 `ExitApp` 干掉，
根本跑不到 `ALL PASS`。

## Interception

使用步骤：

1. 安装 Interception 驱动（`install-interception.exe /install`，要管理员，装完重启）。
2. AHI 文件按上面的布局放好并编译 EXE。
3. 脚本里写 `#DxHardInput on` 并运行。
4. 内置检测窗口出现后，在目标键盘上按任意键，程序会自动补齐：

```ahk
#DxHardInput on
#InterceptionVid 0x0000
#InterceptionPid 0x0000
#InterceptionInstance 1
```

### AHI 失败时是 ExitApp，不是 throw —— 这条决定了后端的代码结构

`lib/AutoHotInterception.ahk` 里这两处失败都是 `MsgBox` + `ExitApp`：

- `AutoHotInterception.__New()`：DLL 缺失 / 被 MOTW block / 位数不对
- `GetDeviceId()`（`GetKeyboardId()` 调它）：**找不到设备**

`ExitApp` 穿透 `try/catch`。所以只要走进去，`main.ahk` 里「回退到 SendInput」的 `catch`
永远不会执行，进程直接没了。实测：驱动没装时调 `GetKeyboardId(0x1234,0x5678)`，
进程停在 MsgBox 上，必须外部杀掉。

`InterceptionBackend.__New()` 因此严格按这个顺序，能自己查的绝不交给 AHI：

1. `EnsureInterceptionFiles()` —— 编译版先从 EXE 释放 DLL
2. `IsSet(AutoHotInterception)` / 文件检查 —— AHI 是否完整
3. `InterceptionDriverPresent()` —— 直接 `DllCall` `interception_create_context()`，
   返回 0 就是驱动没装。抛 `DriverMissingError`
4. 设备配置有没有填；没填则抛 `KeyboardNotConfiguredError` 给主程序启动检测窗
5. 到这一步才 `AutoHotInterception()`（实测：DLL 都在时，无驱动也能安全构造）
6. `FindKeyboard()` 用 `GetDeviceList()` 自己找 id，**不用 `GetKeyboardId()`**
   （`GetDeviceList()` 只查询，无驱动时返回 0 个设备，安全）

改这个类之前先想清楚上面这条，否则回退逻辑会静默失效。

### NumLock 陷阱

Interception 发的是扫描码，`Numpad1` 和 `NumpadEnd` 都是 `0x4F`（同一个物理键），
最终是 `1` 还是 `End` 取决于目标机器的 NumLock。SendInput 后端发 VK，没这个问题。

## 当前限制

- 不是完整 AutoHotkey 解释器。
- GUI 编辑器是基础版：有「未保存就关闭」的提醒，但没有语法高亮、没有另存为。
- 录制器录键名、间隔、按住时长和按下/松开分离：相邻的 down+up 合成 `Tap 键名 毫秒`，
  交叠按键输出分离的 `Send "{Key down}"` / `Send "{Key up}"`，间隔输出 `Sleep`。
  忽略系统自动重复；不录鼠标。逻辑在纯函数 `EmitRecording()` 里，自检覆盖。
- `#Block` / `Call` 支持片段复用，`#Include` 支持把入口脚本拆成多个文件。
- `Send` 里纯 `{Key}` / `{Key down}` / `{Key up}` 序列会经 `RunSend()` 逐个走后端
  （硬输入也生效）。只有含**字面文本**（如 `Send "hello"`）或带重复次数（`{Left 3}`）
  才落回 `SendInput`——那种没法用扫描码驱动干净地发。
  注意 `RunSend` 里的 `\G` 锚点：不能换成 `^`，`^` 只锚整串开头，多组会全落回 SendInput。
- `#SingleInstance Force`：同一时刻只有一个运行进程，但入口 `.dxm` 可 `#Include` 任意数量子脚本。
  编辑器里点「保存并运行」会拉起新实例并顶掉当前进程，所以那行代码后面不能再有 `MsgBox`。
- `.dxm` 文件关联写入 `HKCU\Software\Classes`，不需要管理员权限。
- 不提交 release exe；需要本地构建。
