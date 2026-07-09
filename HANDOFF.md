# dx-macro 交接说明

这个文件给维护者看。用户怎么用只写在 `README.md`。

## 文件结构

| 文件 | 作用 |
|---|---|
| `main.ahk` | 运行入口、热键注册、管理员提权、辅助热键 |
| `config.ahk` | `.dxm` 解析、旧 `.ini` 兼容、校验 |
| `lib/Backends.ahk` | 输入后端：SendInput / Interception |
| `dx-macro.dxm` | 默认示例脚本 |
| `selftest.ahk` | 自检 |
| `run.bat` | 开发时跑脚本版 |
| `register-dxm.bat` | 当前用户 `.dxm` 文件关联注册 |
| `unregister-dxm.bat` | 撤销 `.dxm` 文件关联 |

## 运行行为

- `dx-macro.exe <script.dxm>` 可以运行任意路径的脚本。
- 不传参数时读取 exe 同目录的 `dx-macro.dxm`，没有则兼容读取旧的 `dx-macro.ini`。
- `register-dxm.bat` 写 `HKCU\Software\Classes`，不需要管理员权限。
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
- `Ctrl+Alt+R` 录制点按和间隔到剪贴板。

## 支持的 `.dxm` 语法

- 指令：`#Requires`、`#AskAdmin`、`#RequireAdmin`、`#DxHardInput`、`#PauseKey`、`#ExitKey`、`#HotIf`、`#Repeat`、`#InterceptionVid`、`#InterceptionPid`、`#Block`
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

自检不发送真实键盘输入。它用 `MockBackend` 检查解析、校验、动作展开、松键兜底、硬输入指令、管理员指令和 `#HotIf` 解析。

## Interception

Interception 后端已经实现，但当前环境没有完整硬件实测。

使用步骤：

1. 单独安装 Interception 驱动。
2. 把 AutoHotInterception v2 文件放到 `lib/AutoHotInterception/`。
3. 用 AHI 的监控工具查键盘 VID/PID。
4. 脚本里写：

```ahk
#DxHardInput on
#InterceptionVid 0x0000
#InterceptionPid 0x0000
```

注意：Interception 发的是扫描码，`Numpad1` 和 `NumpadEnd` 是同一个物理扫描码，最终表现受 NumLock 状态影响。

## 当前限制

- 不是完整 AutoHotkey 解释器。
- GUI 编辑器已存在，但只是基础版。
- 录制器已存在，但只录制键盘点按和间隔。
- `#Block` / `Call` 支持基础复用，还没有 `include`。
- `.dxm` 文件关联通过 `register-dxm.bat` 或 `--register` 手动注册，不自动写注册表。
- 不提交 release exe；需要本地构建。
