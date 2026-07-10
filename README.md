# dx-macro 使用说明

`dx-macro.exe` 是一个独立的键盘宏运行器。普通使用不需要先安装 AutoHotkey。

你只需要两个东西：

- `dx-macro.exe`
- 你的 `.dxm` 脚本

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

双击 `dx-macro.exe` 会打开简易 GUI 编辑器。
同时会自动把 `.dxm` 后缀名注册到当前用户，之后可以直接双击 `.dxm` 运行。

把 `.dxm` 文件拖到 `dx-macro.exe` 上。

或者命令行运行：

```powershell
dx-macro.exe "D:\macros\game.dxm"
```

也可以手动注册：

```powershell
dx-macro.exe --register
```

撤销后缀名关联：

```powershell
dx-macro.exe --unregister
```

这只写当前用户注册表，不需要管理员权限。

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

一个运行中的 `dx-macro` 可以加载多个脚本文件。建一个主脚本，用 `#Include` 拆分：

```ahk
#Requires dx-macro
#AskAdmin on
#DxHardInput on
#PauseKey F8

#Include "macros\move.dxm"
#Include "macros\combat.dxm"
```

相对路径从写下 `#Include` 的脚本目录开始计算。所有子脚本同时生效，共用一个 `F8` 和输入后端；
循环包含、以及跨文件的“同一热键 + 同一 App”冲突都会在启动时被拒绝。
全局设置建议只写在主脚本里，子脚本只写 `#HotIf`、热键和动作。

同一个键也可以在不同 App 里做不同动作：

```ahk
#HotIf WinActive("app1.exe")
Numpad1::
    Send "{Left}"
Return

#HotIf WinActive("app2.exe")
Numpad1::
    Send "{Right}"
Return
```

同一个键、同一个 App 重复写两段会被拒绝，避免你以为两段都会跑。

热键不能占用工具自己的控制键，例如 `F8`、`Ctrl+Alt+X`、`Ctrl+Alt+K`。保存/启动时会检查。

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

打开**按键识别器**：一个常驻小窗口，你按任意键它就实时显示这个键叫什么、扫描码，
以及能直接粘进脚本的写法（点按 / 按下 / 松开 / Tap），还有「复制 Send 写法」按钮。
不超时、不用反复按热键，测完关窗口即可。小键盘键会提示受 NumLock 影响。

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

## 6. GUI 编辑

运行后按：

```text
Ctrl+Alt+E
```

会打开当前脚本的简易编辑器。它不漂亮，但能做几件事：

- 检查脚本
- 保存脚本
- 保存并运行
- 注册 `.dxm` 后缀名

也可以直接打开编辑器：

```powershell
dx-macro.exe --edit "D:\macros\game.dxm"
```

## 7. 录制按键

运行后按：

```text
Ctrl+Alt+R
```

然后正常操作一串键，按 `Esc` 结束。录制期间按键仍会传给当前程序，结果会复制到剪贴板。

录制器会记录点按、按住时长、按下/松开和间隔；不记录鼠标操作。

## 8. 长宏怎么维护

先按 App 分段，再按热键分段，用空行和注释分块：

```ahk
#HotIf WinActive("target.exe")

; 移动：下、左、左
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

重复片段用 `#Block` + `Call`：

```ahk
#Block MoveLeft
    Send "{Left down}"
    Sleep 50
    Send "{Left up}"
Return

#HotIf WinActive("target.exe")
Numpad1::
    Call MoveLeft
    Sleep 100
    Call MoveLeft
Return
```

如果一个热键超过几十行，建议先拆成几个小热键调通，再用 `Call` 合并。

## 9. 常用控制键

| 按键 | 作用 |
|---|---|
| `F8` | 暂停/恢复全部宏 |
| `Ctrl+Alt+X` | 退出 |
| `Ctrl+Alt+W` | 查看并复制当前窗口 exe 名 |
| `Ctrl+Alt+K` | 按键识别器（实时看键名和 `Send` 写法） |
| `Ctrl+Alt+R` | 录制按键片段 |
| `Ctrl+Alt+E` | 打开简易编辑器 |
| `Ctrl+Alt+H` | 帮助：一屏列出全部功能和快捷键 |

**记不住快捷键？右键托盘图标**——菜单里列了全部功能（识别按键 / 查进程 / 录制 / 编辑 /
重载 / 暂停 / 帮助 / 退出），每项都标了快捷键，点也行。或者按 `Ctrl+Alt+H` 看帮助。

**重载**在托盘菜单里：改完 `.dxm` 点「重载脚本」就生效，不用关了再开，重载前会先松开所有按下的键。

> 注意 `Ctrl+Alt+W`「查进程」要用**快捷键**、在目标窗口有焦点时按。从托盘菜单点会先夺走目标
> 窗口的焦点，那一刻没有前台窗口，会提示你改用快捷键。

这些可以在脚本顶部改：

```ahk
#PauseKey F8
#ExitKey ^!x
```

不想要暂停键：

```ahk
#PauseKey
```

## 10. 管理员权限

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

## 11. 硬输入

普通模式：

```ahk
#DxHardInput off
```

硬输入模式：

```ahk
#DxHardInput on
#InterceptionVid 0x0000
#InterceptionPid 0x0000
#InterceptionInstance 1
```

硬输入需要额外安装 Interception 驱动。**没装也不会出问题**：启动时会弹一个框告诉你，
问你要不要打开下载页，你点「否」它就用普通输入继续跑，宏照常工作。

装驱动：下载 [Interception](https://github.com/oblitum/Interception/releases)，
解压后以管理员运行 `install-interception.exe /install`，**装完必须重启**。
卸载是 `install-interception.exe /uninstall`，同样要重启。

第一次运行时如果脚本还没有键盘配置，程序会弹出检测窗口。直接在要使用的键盘上按任意键，
程序会把设备配置写回当前 `.dxm`，自动重启后用硬输入运行。按 `Esc` 或点取消则本次回退到普通输入。
这个检测过程已经包含在 `dx-macro.exe` 里，不需要安装 AutoHotkey，也不需要另跑 `Monitor.ahk`。

硬输入开启时，像 `Numpad0`、`F1` 这种不带修饰键的宏热键也由 Interception 驱动直接监听，
不再依赖目标程序是否接受 AHK 热键钩子。`F8` 和带 Ctrl/Alt/Shift 的组合控制键仍由 AHK 监听。

先用 `#DxHardInput off` 把脚本测通，再考虑硬输入。

### 进程级占用（只在目标程序里占用这个键）

无论普通还是硬输入模式，限了窗口的热键**只在目标程序激活时才占用这个键**——切到别的程序，
这个键原样恢复正常使用。比如 `#HotIf WinActive("game.exe")` 下的 `Numpad0`，在游戏里触发宏，
在记事本里照常打「0」。`#HotIf true`（不限窗口）的热键则处处生效。

硬输入模式靠定时轮询前台窗口来动态开关驱动拦截，间隔可调：

```ahk
#PollMs 200
```

默认 200 毫秒（下限 30）。**这只是软件定时器查一下前台窗口，很轻，不产生硬件中断。**
设小（如 50）切窗口更跟手、CPU 每秒多醒几次（仍几乎无感）；设大（如 500）更省，但从游戏
切走后那个键最多多拦这么久才放开。拦/放只在窗口切换那一下发生，窗口不变时完全不动。

> 小键盘的坑：硬输入发的是扫描码，`Numpad1` 和 `NumpadEnd` 是同一个扫描码 `0x4F`，
> 最终是 `1` 还是 `End` 取决于目标机器的 NumLock。普通输入发的是虚拟键码，没这个问题。
> 宏里要输出小键盘键又必须稳的话，用方向键或字母键代替。

## 12. 完整示例

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

## 13. 不是完整 AHK

`.dxm` 不是完整 AutoHotkey。当前只支持键盘宏需要的这些语法：

- `#Requires dx-macro`
- `#AskAdmin on/off`
- `#RequireAdmin`
- `#DxHardInput on/off`
- `#InterceptionVid`、`#InterceptionPid`、`#InterceptionInstance`（由程序自动写入）
- `#PollMs`（硬输入下按窗口拦/放的轮询间隔，毫秒）
- `#Include "相对或绝对路径.dxm"`
- `#PauseKey`
- `#ExitKey`
- `#HotIf true`
- `#HotIf WinActive("xxx.exe")`
- `#Block name`
- `Hotkey::`
- `Send`
- `Sleep`
- `Tap`
- `Call`
- `Return`

## 14. 许可证

- dx-macro 自身代码：**GPL-3.0**（见 [`LICENSE`](LICENSE)）。
- **个人 / 非商业免费用。** 只有一处收费点：用硬输入（Interception 驱动）**商用**时，
  需向 Interception 作者购买商业授权；不用硬输入则完全无此限制。
- 用到的第三方：AutoHotkey（GPL v2）、AutoHotInterception（MIT）、Interception
  （LGPL-3.0 非商业 / 商业授权）。详见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。
