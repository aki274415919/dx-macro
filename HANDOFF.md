# dx-macro 交接说明

这个文件给维护者看。用户怎么用只写在 `README.md`。

## 当前状态（2026-07-10）

- 驱动探测已通过，`interception_create_context()` 返回有效上下文。
- 缺少设备配置时，EXE 会弹出内置检测窗口；用户在目标键盘上按一个键后，程序自动写回
  `#InterceptionVid`、`#InterceptionPid` 和 `#InterceptionInstance`，随后重启以释放检测阶段的 AHI 上下文。
- 编译版会先把 AHI DLL 从 EXE 释放到自身目录，再做预检；单独复制 EXE 和 `.dxm` 也能进入硬输入流程。
- 仍需一次人工实机确认：在检测窗口按目标键盘，再到目标程序里触发一条普通方向键宏。

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
- `Ctrl+Alt+W` 复制当前前台进程名。
- `Ctrl+Alt+K` 捕获一个按键并复制 `Send "{Key}"` 写法。
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

`dx-macro.exe` 是构建产物，被 Git 忽略。

## 测试

```powershell
AutoHotkey64.exe /ErrorStdOut selftest.ahk
```

58 条当前环境断言，退出码 0 = 全过。自检不发送真实键盘输入，用 `MockBackend` 检查解析、校验、
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
