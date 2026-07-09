# dx-macro 使用说明

`dx-macro.exe` 是一个键盘宏运行器。你新建 `.dxm` 脚本，然后用 `dx-macro.exe` 跑它。

## 1. 新建脚本

新建一个文本文件，把后缀改成 `.dxm`，例如：

```text
game.dxm
```

写入：

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

把 `target.exe` 改成目标程序的进程名。

## 2. 运行脚本

把 `.dxm` 文件拖到 `dx-macro.exe` 上。

或者命令行运行：

```powershell
dx-macro.exe "D:\macros\game.dxm"
```

不传脚本时，默认读取 `dx-macro.exe` 同目录下的 `dx-macro.dxm`。

## 3. 我映射到了哪个键？

看 `::` 前面的内容：

```ahk
Numpad1::
```

这表示按“小键盘 1”触发。

再比如：

```ahk
F1::
```

这表示按 `F1` 触发。

一个脚本可以写多个热键：

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

## 4. 窗口限制

只在某个程序窗口里触发：

```ahk
#HotIf WinActive("notepad.exe")
```

不限制窗口：

```ahk
#HotIf true
```

想知道当前窗口进程名，运行后按：

```text
Ctrl+Alt+W
```

它会弹出并复制当前窗口的 exe 名。

## 5. Send 怎么写？

运行后按：

```text
Ctrl+Alt+K
```

然后按你想写进脚本的键。工具会弹窗并复制写法。

常用动作：

| 写法 | 作用 |
|---|---|
| `Send "abc"` | 输入文字 |
| `Send "{Left}"` | 点按一次 Left |
| `Send "{Left down}"` | 按住 Left |
| `Send "{Left up}"` | 松开 Left |
| `Sleep 100` | 等 100 毫秒 |
| `Tap Left 50` | 按住 Left 50 毫秒再松开 |

每个热键最后写：

```ahk
Return
```

## 6. 常用控制键

| 按键 | 作用 |
|---|---|
| `F8` | 暂停/恢复全部宏 |
| `Ctrl+Alt+X` | 退出 |
| `Ctrl+Alt+W` | 查看当前窗口 exe 名 |
| `Ctrl+Alt+K` | 查键名和 `Send` 写法 |

这些可以在脚本顶部改：

```ahk
#PauseKey F8
#ExitKey ^!x
```

不想要暂停键：

```ahk
#PauseKey
```

## 7. 管理员权限

默认：

```ahk
#AskAdmin on
```

启动时会先问管理员权限。点“否”会继续普通权限运行。

如果目标程序是管理员权限运行，普通权限发不进去输入。此时加：

```ahk
#RequireAdmin
```

这样拒绝管理员权限时会直接退出。

## 8. 硬输入

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

硬输入需要额外安装 Interception/AutoHotInterception。没装时会回退到普通输入。

先用 `#DxHardInput off` 把脚本测通，再考虑硬输入。

## 9. 完整示例

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

这个脚本只在 `target.exe` 窗口里生效，按小键盘 `1` 触发。

## 10. 不是完整 AHK

`.dxm` 不是完整 AutoHotkey。当前只支持键盘宏需要的这些语法：

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
