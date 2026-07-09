# dx-macro

一个轻量的键盘宏运行时。它像一个很小的 AutoHotkey 平行版：你写 `.dxm` 脚本，`dx-macro.exe` 负责运行。

普通使用不需要安装 AutoHotkey。只有改源码、跑自检、重新打包 exe 时才需要 AHK v2。

如果你是从源码仓库 clone 下来的，先看本文最后的“开发”章节打包出 `dx-macro.exe`。

## 快速开始

新建一个文本文件，后缀改成 `.dxm`，例如 `game.dxm`：

```ahk
#Requires dx-macro
#AskAdmin on
#DxHardInput off
#PauseKey F8
#ExitKey ^!x

#HotIf WinActive("target.exe")
Numpad1::
    Send "{Down down}"
    Sleep 50
    Send "{Down up}"
Return
```

运行方式任选一个：

```powershell
dx-macro.exe "D:\macros\game.dxm"
```

也可以把 `.dxm` 文件直接拖到 `dx-macro.exe` 上。

不传脚本路径时，`dx-macro.exe` 默认读取同目录的 `dx-macro.dxm`。

## 热键写法

热键就是这一行：

```ahk
Numpad1::
```

上面表示按“小键盘 1”触发。一个脚本里可以写很多热键：

```ahk
#HotIf true

F1::
    Send "hello"
Return

F2::
    Send "{Left}"
    Sleep 100
    Send "{Right}"
Return
```

限制只在某个程序窗口生效：

```ahk
#HotIf WinActive("notepad.exe")
```

取消窗口限制：

```ahk
#HotIf true
```

## 支持的动作

| 写法 | 作用 |
|---|---|
| `Send "abc"` | 输入文字 |
| `Send "{Left}"` | 点按一次 |
| `Send "{Left down}"` | 按下不松 |
| `Send "{Left up}"` | 松开 |
| `Sleep 100` | 等 100 毫秒 |
| `Tap Left 50` | 按下 50 毫秒再松开 |

每个热键最后写 `Return`。

## 查键名

运行脚本后按：

```text
Ctrl+Alt+K
```

然后按你想写进脚本的键。工具会弹窗显示并复制常用写法，例如：

```ahk
Send "{Left}"
Send "{Left down}"
Send "{Left up}"
Tap Left 50
```

查当前窗口进程名：

```text
Ctrl+Alt+W
```

它会显示并复制当前前台窗口的 exe 名，方便填：

```ahk
#HotIf WinActive("target.exe")
```

## 常用控制键

| 按键 | 作用 |
|---|---|
| `F8` | 暂停/恢复全部宏 |
| `Ctrl+Alt+X` | 退出 |
| `Ctrl+Alt+W` | 查看当前窗口 exe 名 |
| `Ctrl+Alt+K` | 查键名和 `Send` 写法 |

可以在脚本顶部改：

```ahk
#PauseKey F8
#ExitKey ^!x
```

不想要暂停键：

```ahk
#PauseKey
```

## 管理员权限

默认：

```ahk
#AskAdmin on
```

启动时会先弹一次管理员权限。你点“否”，工具会继续用普通权限运行。

如果目标程序本身是管理员权限运行，普通权限发不进去输入。此时加：

```ahk
#RequireAdmin
```

这样拒绝提权时会直接退出。

## 硬输入

普通模式：

```ahk
#DxHardInput off
```

硬输入模式：

```ahk
#DxHardInput on
#InterceptionVid 0x0000
#InterceptionPid 0x0000
```

硬输入使用 Interception/AutoHotInterception。它需要额外安装驱动和 AHI 文件；没装时会回退到普通 SendInput。

先用普通模式确认脚本逻辑，再考虑硬输入。

## 示例脚本

```ahk
#Requires dx-macro
#AskAdmin on
#DxHardInput off
#PauseKey F8
#ExitKey ^!x

#HotIf WinActive("target.exe")
Numpad1::
    Send "{Down down}"
    Sleep 50
    Send "{Down up}"
    Sleep 100
    Send "{Left down}"
    Sleep 50
    Send "{Left up}"
    Sleep 100
    Send "{Left down}"
    Sleep 50
    Send "{Left up}"
Return
```

触发键是 `Numpad1`，也就是小键盘 1。

## 当前不是完整 AHK

`.dxm` 只支持键盘宏需要的最小语法：

- `#Requires dx-macro`
- `#AskAdmin on/off`
- `#RequireAdmin`
- `#DxHardInput on/off`
- `#PauseKey`
- `#ExitKey`
- `#HotIf true`
- `#HotIf WinActive("xxx.exe")`
- `Hotkey::`
- `Send`
- `Sleep`
- `Tap`
- `Return`

不要把完整 AHK 脚本直接改后缀丢进来跑。

## 开发

文件说明：

| 文件 | 作用 |
|---|---|
| `main.ahk` | 运行时入口、热键注册、权限处理 |
| `config.ahk` | `.dxm` 解析和校验 |
| `lib/Backends.ahk` | 输入后端 |
| `dx-macro.dxm` | 默认示例脚本 |
| `selftest.ahk` | 自检 |
| `run.bat` | 脚本版启动器 |

跑自检：

```powershell
AutoHotkey64.exe /ErrorStdOut selftest.ahk
```

打包 exe：

```powershell
Ahk2Exe.exe /in main.ahk /out dx-macro.exe /base AutoHotkey64.exe
```

`dx-macro.exe` 是构建产物，不提交进 Git。
