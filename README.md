# dx-macro — 基于 AutoHotkey v2 的脚本驱动键盘宏运行时（绿色版）

## 一、总体方案

不做新语言、不做新运行时。**在 AHK v2 上做二次开发**：AHK v2 已经把这个需求里最难的部分做完了——
全局热键、`KeyWait`、`WinActive`、扫描码映射、SendInput、单实例、托盘。
我们只加三样它没有的：

1. **脚本驱动**：热键和动作序列写在 `.dxm` 脚本里，不是硬编码在程序里。
2. **可替换输入后端**：`KeyDown / KeyUp / Tap` 三个方法一个接口，SendInput 和 Interception 各一个实现。
3. **安全兜底**：后端自己记录按下的键，异常或退出时一律松开。

### 为什么推荐 AHK v2 而不是 C# / C++ / Rust

你倾向 C# .NET 8，理由是「以后好改配置和 UI」。但：

| | AHK v2 | C# .NET 8 | C++ / Rust |
|---|---|---|---|
| 绿色版 | 单个 `AutoHotkey64.exe`，或 Ahk2Exe 编一个独立 exe | self-contained 发布 ~60MB | 单 exe，但代码量最大 |
| 全局热键 | 内建 | 自己写 `RegisterHotKey` / 低级键盘钩子 | 同左 |
| 按住不连发 | `KeyWait` 一行 | 自己写状态机 | 同左 |
| 窗口进程名 | `WinActive("ahk_exe x.exe")` | `GetForegroundWindow` + `GetWindowThreadProcessId` + `QueryFullProcessImageName` | 同左 |
| 键名→扫描码 | `GetKeySC()` 内建 | 自己维护映射表 | 同左 |
| Interception | AutoHotInterception 直接调 | P/Invoke native DLL | 直接调 |
| GUI | `Gui` 内建 | 最强 | 最麻烦 |

C# 只在「以后要做复杂 GUI」这一格赢，而 AHK v2 的 `Gui` 做个配置面板也够用。
本机现在也没装 .NET SDK。所以：**AHK v2**。

如果将来真要迁到 C#：接口原封不动搬过去就行

```csharp
public interface IInputBackend
{
    void KeyDown(ushort scanCode);
    void KeyUp(ushort scanCode);
    void Tap(ushort scanCode, int holdMs);
    void ReleaseAll();
}
```

`SendInputBackend` 用 `SendInput`（`user32.dll`，`KEYEVENTF_SCANCODE`）；
`InterceptionBackend` 用 `[DllImport("interception.dll")]` 调 `interception_send`。

---

## 二、为什么普通 SendInput 可能不够

`SendInput` 注入的事件在内核里带 `LLMHF_INJECTED` 标记。有些程序会：

- 用 **Raw Input**（`WM_INPUT`）读键盘，只认真实 HID 设备上报的数据；
- 用 **DirectInput** 直接读设备状态，不走 Windows 消息队列；
- 在低级键盘钩子里检查 `KBDLLHOOKSTRUCT.flags & LLKHF_INJECTED`，直接丢弃注入事件；
- 以 **管理员权限**运行，UIPI 会拦掉低权限进程发来的输入。

这几种情况 SendInput 都会「打不进去」。
Interception 是内核态键盘过滤驱动，事件从驱动栈上游进入，对应用层来说和真键盘按下没有区别，
所以它能覆盖前三种。第四种（管理员窗口）无论哪个后端都要求本程序也以管理员运行。

**层级从上到下**：`SendInput` → `Interception 驱动` → `虚拟 HID 设备`。
虚拟 HID 要写 KMDF 驱动 + 签名，成本远高于收益，Interception 已经够低了。
所以接口留着，实现不做。

---

## 三、架构

```
main.ahk              框架核心：读脚本 → 校验 → 建后端 → 注册热键 → 兜底清理
dx-macro.dxm          默认宏脚本
config.ahk            脚本/兼容配置加载器 + 默认配置
selftest.ahk          自检，跑一遍逻辑，不碰真键盘
lib/Backends.ahk      IInputBackend 基类 + SendInputBackend + InterceptionBackend
lib/AutoHotInterception/   （可选）用 Interception 后端时才需要
run.bat               绿色版启动器
AutoHotkey64.exe      （你自己放进来，绿色版关键）
```

```
      dx-macro.dxm
           │
           ▼
   ┌───────────────┐   Hotkey()   ┌──────────────┐
   │   main.ahk    │──────────────│  AHK 热键引擎 │
   └───────┬───────┘              └──────────────┘
           │ KeyDown/KeyUp/Tap
           ▼
   ┌────────────────┐
   │ IInputBackend  │  held Map + Tap + ReleaseAll
   └───┬────────┬───┘
       │        │
  SendInput  Interception   （虚拟 HID：接口预留）
```

**关键设计点**

- `#MaxThreadsPerHotkey 1` —— 同一个热键的宏永远不会并发执行。
- `repeat: false` 时宏跑完调 `KeyWait`，线程停在那里直到你松开按键。
  配合上一条，按住 Numpad1 只会执行一次。
- `held` Map 由后端维护。宏中途抛异常 → `catch` 里 `ReleaseAll()`；
  程序退出 → `OnExit` 里 `ReleaseAll()`。键不会卡在按下状态。
- 窗口不匹配时**直接 return**，一个键都不发。
- 启动时 `ValidateConfig()` 走一遍配置：热键名、键名、sleep、action 类型全查一遍。
  写错 `Downn` 会在启动时弹框告诉你哪个热键的第几个 action 错了，
  而不是等宏跑到一半才炸（那时候可能已经有键按下没松开）。

---

## 四、脚本

普通使用写 `.dxm` 脚本。默认读取 exe 同目录的 `dx-macro.dxm`。
脚本不必放在 exe 目录下，可以拖到 `dx-macro.exe` 上，或命令行传路径：
`dx-macro.exe "D:\macros\game.dxm"`。

```ahk
#Requires dx-macro
#DxHardInput off
#PauseKey F8
#ExitKey ^!x

#HotIf WinActive("ahk_exe target.exe")
Numpad1::
    Send "{Down down}"
    Sleep 50
    Send "{Down up}"
Return

Numpad2::
    Send "{a}"
    Sleep 100
    Send "{b}"
Return
```

`F8` 是总暂停键：程序还在托盘运行，但所有宏临时不触发；再按一次恢复。
不需要暂停就写 `#PauseKey` 后面留空。

`#DxHardInput off` 是普通 SendInput；`#DxHardInput on` 是驱动层硬输入（Interception），
需要先装 Interception/AHI，并填 `#InterceptionVid` / `#InterceptionPid`。

### 支持的 action

| action | 说明 |
|---|---|
| `Send "{Left down}"` | 按下不松 |
| `Send "{Left up}"` | 松开 |
| `Sleep 100` | 等待毫秒 |
| `Send "{Left}"` | 点按一次 |
| `Tap Left 50` | 按下 → 等 50 毫秒 → 松开 |
| `Send "hello"` | 打字符串 |

### 键名 / NumLock 区分

AHK 原生就把小键盘的两种状态当成**不同的键**，不需要你判断 NumLock：

| NumLock 开 | NumLock 关 |
|---|---|
| `Numpad1` | `NumpadEnd` |
| `Numpad2` | `NumpadDown` |
| `Numpad3` | `NumpadPgDn` |
| `Numpad4` | `NumpadLeft` |
| `Numpad5` | `NumpadClear` |
| `Numpad6` | `NumpadRight` |
| `Numpad7` | `NumpadHome` |
| `Numpad8` | `NumpadUp` |
| `Numpad9` | `NumpadPgUp` |
| `Numpad0` | `NumpadIns` |
| `NumpadDot` | `NumpadDel` |

方向键是独立的 `Up / Down / Left / Right`（扩展键，扫描码带 `0xE0` 前缀）。
功能键 `F1`..`F24`，字母数字直接写 `a` `1`。

热键名前面可以加 AHK 修饰符：`^`Ctrl `!`Alt `+`Shift `#`Win `~`不吞掉原键 `*`忽略其他修饰键。
`BaseKey()` 会自动把这些前缀剥掉再给 `KeyWait`。

---

## 五、使用步骤

### 1. 拿到绿色版解释器

去 <https://www.autohotkey.com/download/> 下 **AutoHotkey v2** 的 zip（不是 installer），
解压出 `AutoHotkey64.exe`，丢进本文件夹。

（或者装了 AHK v2 也行，`run.bat` 会自动去 `Program Files\AutoHotkey\v2\` 找。）

### 2. 写脚本

打开 `dx-macro.dxm`，把 `target.exe` 换成你的目标进程名。
不知道叫什么？先双击 `dx-macro.exe` 或 `run.bat` 跑起来，切到目标窗口按 **Ctrl+Alt+W**，
托盘会弹出进程名并**自动复制到剪贴板**。

也可以用任务管理器：详细信息标签页 → 「名称」列就是 exe 名。

### 3. 运行

双击 `dx-macro.exe`。托盘出现图标 = 正在运行。
开发时也可以双击 `run.bat` 跑脚本版。

脚本可以放在别的目录：

```
dx-macro.exe "D:\macros\game.dxm"
```

也可以把 `.dxm` 文件直接拖到 `dx-macro.exe` 上。

| 按键 | 作用 |
|---|---|
| `Numpad1` | 执行宏（仅当前台是配置的窗口） |
| `F8` | 暂停 / 恢复 |
| `Ctrl+Alt+X` | 退出（退出时松开所有键） |
| `Ctrl+Alt+W` | 显示并复制前台进程名 |

托盘图标右键 → Exit 也能退。

> **关于 Ctrl+C 退出**：AHK 脚本不是控制台程序，收不到 `Ctrl+C` 的控制台信号，
> 所以用可配置的 `exit_key`（默认 `Ctrl+Alt+X`）代替。
> 也别把退出键设成裸 `Esc`——Esc 到处都在用，一按就退出很难受。

### 4. 打包成单个 exe（可选，最绿色）

用 AHK 自带的 `Ahk2Exe`（在 v2 的 `Compiler` 目录）：

```
Ahk2Exe.exe /in main.ahk /out dx-macro.exe /base AutoHotkey64.exe
```

`dx-macro.exe` 默认读取同目录的 `dx-macro.dxm`。传入脚本路径时可以放任意目录。

### 5. 测试

**自动**：跑 `selftest.ahk`，21 项断言，不碰真键盘、不开窗口，退出码 0 = 全过。

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut selftest.ahk
```

覆盖：热键名解析、脚本读取、action 序列展开、`Tap`、`ReleaseAll` 兜底、
未知 action 抛异常、抽象方法约束、以及校验器（拼错键名 / 负数 sleep / 未知 action 都要被拒）。
它用一个 `MockBackend` 记录 `KeyDown/KeyUp` 调用，所以验的是框架逻辑，不是 `SendInput` 本身。

> 为什么不在 selftest 里验真的 `SendInput`？因为 AHK 的 `SendInput`
> 会临时禁用**本脚本自己的**键盘钩子，`InputHook` 抓不到自己发的键；
> 而往自己的 Gui 里打字又依赖窗口激活，在自动化环境下不稳。
> 真 `SendInput` 的通路请用下面的手动步骤验。

**手动**（验真实输入）：

1. **先测通路**：把 `active_window` 改成 `""`，打开记事本，
   把宏的 `Down/Left` 换成 `Map("send", "abc")`，按 Numpad1 应该打出 `abc`。
2. **测窗口限制**：`active_window` 改成 `"notepad.exe"`，切到浏览器按 Numpad1 → 应该没反应。
3. **测按住不连发**：按住 Numpad1 三秒不放 → 宏只跑一遍。松开再按 → 跑第二遍。
4. **测时序**：把 `sleep` 调到 500，肉眼确认 Down→Left→Left 的节奏。
5. **测脚本校验**：故意写 `Send "{Downn}"`，启动时就该弹框，而不是能跑起来。

---

## 六、管理员权限

| 情况 | 需要管理员？ |
|---|---|
| 目标程序普通权限 + SendInput 后端 | 不需要 |
| 目标程序**以管理员运行** | **需要**。UIPI 禁止低完整性级别进程向高完整性窗口发输入 |
| 安装 Interception 驱动 | **需要**（一次性） |
| 装好驱动后用 Interception 后端 | 一般不需要，个别环境需要 |

要管理员运行：右键 `run.bat` → 以管理员身份运行。
或在 `main.ahk` 顶部加：

```ahk
if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}
```

---

## 七、Interception 后端怎么继续实现

### 依赖与版本

| 组件 | 来源 | 版本 |
|---|---|---|
| Interception 驱动 | <https://github.com/oblitum/Interception> | 1.0.1（`Interception.zip` 里的 `command line installer`） |
| AutoHotInterception (AHI) | <https://github.com/evilC/AutoHotInterception> | 取 **AHK v2 分支/发布** |
| AHK | v2.0+ | 同上 |

AHI 内部是一个 C# DLL（`AutoHotInterception.dll`）通过 CLR 加载，
再由 `Lib\AutoHotInterception.ahk` 包装成 AHK 类。**不注入任何目标进程**，只往本机键盘驱动栈发事件。

### 安装步骤

```powershell
# 1. 解压 Interception.zip，进入 command line installer 目录
#    以管理员打开 PowerShell / cmd
.\install-interception.exe /install

# 2. 重启电脑（驱动必须重启才加载）
```

```
# 3. 把 AHI 解压到本项目：
dx 宏\lib\AutoHotInterception\
    AutoHotInterception.ahk
    AutoHotInterception.dll
    interception.dll
    Monitor.ahk
    ...
```

### 选择键盘 device id

不要猜。跑 AHI 自带的 `Monitor.ahk`：

```
AutoHotkey64.exe lib\AutoHotInterception\Monitor.ahk
```

它会列出所有键盘/鼠标，格式类似 `Keyboard ID 3, VID 0x04F2, PID 0x0112`。
**在你要用的那块键盘上按一下键**，看哪一行有事件跳动，记下它的 VID / PID，填进 `.dxm` 脚本：

```ahk
#DxHardInput on
#InterceptionVid 0x04F2
#InterceptionPid 0x0112
```

代码里用 `AHI.GetKeyboardId(vid, pid)` 拿 id，比硬编码 id 稳——插拔 USB 后 id 会变，VID/PID 不会。

### 已经写好的部分

`lib\Backends.ahk` 里的 `InterceptionBackend` 已经实现完了：

```ahk
KeyDown(key) {
    this.AHI.SendKeyEvent(this.id, GetKeySC(key), 1)
    this.held[key] := true
}
```

`GetKeySC()` 是 AHK 内建函数，把键名转成扫描码。本机实测：

| 键名 | GetKeySC |
|---|---|
| `Down` | `0x150` |
| `Left` | `0x14B` |
| `NumpadEnter` | `0x11C` |
| `Numpad1` | `0x4F` |
| `NumpadEnd` | `0x4F` |
| `a` | `0x1E` |

高位 `0x100` 表示扩展键（`E0` 前缀），AHI 的 `SendKeyEvent` 会把它翻译成扩展标志位。

### ⚠ Interception 后端的 NumLock 陷阱

看上面这张表：**`Numpad1` 和 `NumpadEnd` 的扫描码都是 `0x4F`**——它们本来就是同一个物理键。

- **SendInput 后端**发的是虚拟键码（VK），`{Numpad1 down}` 和 `{NumpadEnd down}` 是两回事，行为确定。
- **Interception 后端**发的是扫描码，只能发 `0x4F`。目标程序收到之后
  **按它自己看到的 NumLock 状态**决定这是 `1` 还是 `End`。

所以：小键盘键在 Interception 后端下**受 NumLock 影响**，两个后端可能表现不一致。
如果你的宏输出里有小键盘键，要么保证 NumLock 状态固定，要么改用方向键 / 字母键。
（作为**热键触发**用没问题——AHK 的 `Hotkey()` 走 VK，照样能区分 `Numpad1` 和 `NumpadEnd`。）

### 这一段没有实机验证

我在这台机器上跑通了 SendInput 后端和全部框架逻辑，但**没装 Interception 驱动，没跑过 AHI**。
上面的 `SendKeyEvent(id, GetKeySC(key), state)` 是按 AHI 的接口写的，你装好后：

1. 先拿 `a` 这种普通键验证通路（不涉及扩展位）。
2. 再测方向键。如果方向键发出来不对，八成是扩展位处理差异，
   去 AHI 的 `SendKeyEvent` 里看它怎么处理 `code > 0xFF`，必要时改成：

```ahk
sc := GetKeySC(key)
this.AHI.SendKeyEvent(this.id, sc & 0xFF, state)   ; 若 AHI 不吃 0x100 位
```

### 切换后端

`.dxm` 脚本里改一个字符串：

```ahk
#DxHardInput on
```

初始化失败（驱动没装 / AHI 没放 / VID PID 没填）会弹框说明原因，并**自动回退到 SendInput**，
不会让你莫名其妙地按键没反应。

### 虚拟 HID 设备

需要写 KMDF 驱动或用 `VirtualHere` / `HidHide` 这类方案，还要处理签名（测试签名模式会掉 Secure Boot）。
Interception 已经在驱动层了，再往下收益很小。接口（`IInputBackend` 基类）留着，真要做就再加一个子类，
`main.ahk` 一行不用改。虚拟 HID 反而能解决上面那个 NumLock 陷阱——它可以上报完整的 HID usage，
不受扫描码歧义限制。真要做小键盘输出且必须稳，这是唯一的干净解法。

---

## 八、风险、边界、卸载

### 用途边界

这个工具做的是**本机键盘输入模拟 + 窗口内热键**：把一串按键绑到一个键上，减少重复劳动和手部负担。
它不注入进程、不读写别人的内存、没有图像识别、没有无人值守循环。
按住热键必须松开才能再触发，本身就不适合挂机。

用之前**确认目标软件 / 游戏的规则**。很多在线游戏的用户协议禁止任何形式的宏和多键绑定，
「技术上能做」和「你被允许做」是两件事，后者你得自己去看条款。单机、生产力软件、自建服务器随便用。

### 杀软 / 反作弊会怎么反应

- Interception 是**内核态键盘过滤驱动**。装它会：杀软弹窗、部分反作弊直接拒绝启动游戏、
  某些企业设备管控策略不允许安装。这是预期行为，不是 bug。
- AHK 本身也常被杀软误报（因为它能模拟输入）。
- 我不提供任何隐藏、伪装或绕过检测的方法。如果一个程序明确不想被宏控制，就别用宏控制它。

### 安全退出 / 不会卡键

三层保险，都已经在代码里：

1. `RunAction` 抛异常 → `RunHotkey` 的 `catch` 调 `Backend.ReleaseAll()`。
2. 正常/异常退出 → `OnExit(OnExitHandler)` 调 `Backend.ReleaseAll()`。
3. 后端的 `held` Map 记录每一个 `KeyDown` 过的键，`ReleaseAll()` 逐个 `KeyUp`。

万一真卡住（比如强杀进程）：手动敲一下那个键，或者 `Ctrl+Alt+Del` 进锁屏再返回，会重置键盘状态。

### 卸载 Interception 驱动

```powershell
# 以管理员运行
.\install-interception.exe /uninstall
# 然后重启
```

`install-interception.exe` 在你当初解压的 `Interception.zip` → `command line installer` 目录里。
**把这个 zip 留着**，不然卸载的时候得重新下。

卸载驱动后，把 `.dxm` 脚本里的 `#DxHardInput` 改回 `off`，工具照常工作。

删掉整个文件夹 = 完全卸载本工具（绿色版不写注册表、不写系统目录）。
