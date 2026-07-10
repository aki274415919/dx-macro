; ============================================================
;  dx-macro  —  基于 AutoHotkey v2 的脚本驱动键盘宏运行时
;
;  #MaxThreadsPerHotkey 1  同一个热键的宏不会并发执行
;  KeyWait                 按住不连发，必须松开才能再触发
;  OnExit + try/catch      异常或退出时松开所有按下的键
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1

#Include lib\Backends.ahk
#Include *i lib\AutoHotInterception.ahk
#Include config.ahk

AppName := "dx-macro"
Config  := ""
Paused  := false
Backend := ""
InterceptionUrl := "https://github.com/oblitum/Interception/releases"
HotkeyPause := "F8"      ; 帮助/托盘要用，Main 里按脚本设置覆盖
HotkeyExit  := "^!x"

; 只有直接运行 main.ahk 时才启动；被 selftest.ahk #Include 时不启动。
if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    Main()
else
    Config := LoadConfig()


Main() {
    global Config, Backend, AppName, LoadedConfigPath

    if HandleUtilityCommand()
        return

    if (A_IsCompiled && A_Args.Length = 0) {
        try RegisterFileAssociation()
        ShowScriptEditor(ConfigPath())
        return
    }

    ; 脚本写错就在启动时炸，别等宏跑到一半
    try {
        Config := LoadConfig()
        ValidateConfig(Config)
    } catch as e {
        MsgBox("宏脚本有问题：`n`n" e.Message, AppName)
        ExitApp(1)
    }

    settings := Config.Has("settings") ? Config["settings"] : Map()
    if !A_IsAdmin {
        requireAdmin := settings.Has("require_admin") && settings["require_admin"]
        askAdmin := !settings.Has("ask_admin") || settings["ask_admin"]
        if (requireAdmin || askAdmin) {
            if TryRelaunchAsAdmin()
                ExitApp
            if requireAdmin
                ExitApp(1)
        }
    }

    try {
        Backend := InitBackend(settings)
    } catch KeyboardNotConfiguredError as e {
        try {
            if ConfigureInterceptionScript(LoadedConfigPath) {
                ; 检测器刚释放订阅时不要立刻再建 AHI；重启后只创建正式后端。
                ReloadScript()
                return
            } else {
                MsgBox("没有选择键盘，先用 SendInput 继续运行。", AppName, "Icon!")
                Backend := SendInputBackend()
            }
        } catch as setupError {
            MsgBox("硬输入键盘配置失败：`n`n" setupError.Message "`n`n先用 SendInput 继续运行。", AppName, "Icon!")
            Backend := SendInputBackend()
        }
    } catch DriverMissingError as e {
        OfferInterceptionDownload()
        Backend := SendInputBackend()
    } catch as e {
        MsgBox("硬输入后端起不来：`n`n" e.Message "`n`n先用 SendInput 继续运行。", AppName, "Icon!")
        Backend := SendInputBackend()
    }

    RegisterHotkeys()

    global HotkeyPause, HotkeyExit
    HotkeyPause := settings.Has("pause_key") ? settings["pause_key"] : "F8"
    HotkeyExit  := settings.Has("exit_key")  ? settings["exit_key"]  : "^!x"

    if (HotkeyPause != "")
        SafeHotkey(HotkeyPause, TogglePause)
    if (HotkeyExit != "")
        SafeHotkey(HotkeyExit, (*) => ExitApp())

    ; 辅助功能热键（托盘菜单里也都有，不用记）
    SafeHotkey("^!w", ShowActiveProcess)
    SafeHotkey("^!k", ShowKeyInspector)
    SafeHotkey("^!e", ShowCurrentScriptEditor)
    SafeHotkey("^!r", RecordSnippet)
    SafeHotkey("^!h", ShowHelp)

    SetupTray()
    OnExit(OnExitHandler)

    TrayTip("右键托盘图标 = 全部功能和快捷键`n或按 Ctrl+Alt+H 打开帮助",
        AppName " 已启动（后端: " Type(Backend) "）")
}


ConfigureInterceptionScript(path) {
    global AppName
    if RegExMatch(path, "i)\.ini$")
        throw Error("自动检测只支持 .dxm 脚本")

    device := CaptureInterceptionKeyboard()
    if !device
        return false

    text := FileRead(path, "UTF-8")
    text := SetScriptDirective(text, "DxHardInput", "on")
    text := SetScriptDirective(text, "InterceptionVid", Format("0x{:04X}", device.vid))
    text := SetScriptDirective(text, "InterceptionPid", Format("0x{:04X}", device.pid))
    text := SetScriptDirective(text, "InterceptionInstance", device.instance)
    WriteTextFile(path, text)
    MsgBox("硬输入键盘已写入当前脚本，程序将重新启动。", AppName, "Iconi")
    return true
}


CaptureInterceptionKeyboard() {
    global AppName
    ahi := CreateAutoHotInterception()
    keyboards := Map()
    for id, dev in ahi.GetDeviceList() {
        if !dev.IsMouse
            keyboards[id] := dev
    }
    if (keyboards.Count = 0)
        throw Error("Interception 没有检测到键盘")

    picked := {id: 0}
    g := Gui("+AlwaysOnTop +ToolWindow", AppName)
    g.SetFont("s10", "Segoe UI")
    g.AddText("w420", "请在要用于硬输入的键盘上按任意键。`n按 Esc 或点取消可继续使用普通输入。")
    g.AddButton("w100", "取消").OnEvent("Click", (*) => g.Destroy())

    OnKey(id, code, state) {
        if (!state || picked.id || code = GetKeySC("Escape"))
            return
        picked.id := id
        g.Destroy()
    }

    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    subscribed := []
    hwnd := g.Hwnd
    try {
        for id in keyboards {
            ahi.SubscribeKeyboard(id, false, OnKey.Bind(id))
            subscribed.Push(id)
        }
        g.Show("AutoSize Center")
        WinWaitClose("ahk_id " hwnd)
    } finally {
        for id in subscribed
            try ahi.UnsubscribeKeyboard(id)
    }

    if !picked.id
        return ""

    selected := keyboards[picked.id]
    if (!selected.VID || !selected.PID)
        throw Error("这块键盘没有可用的 VID/PID，暂时不能作为硬输入设备")

    instance := 0
    for id, dev in keyboards {
        if (dev.VID = selected.VID && dev.PID = selected.PID) {
            instance += 1
            if (id = picked.id)
                break
        }
    }
    return {vid: selected.VID, pid: selected.PID, instance: instance}
}


SetScriptDirective(text, name, value) {
    line := "#" name (value = "" ? "" : " " value)
    pattern := "im)^[ `t]*#" name "\b[^`r`n]*"
    if RegExMatch(text, pattern)
        return RegExReplace(text, pattern, line, , 1)
    newline := InStr(text, "`r`n") ? "`r`n" : "`n"
    return line newline text
}


WriteTextFile(path, text) {
    tmp := path ".tmp-" DllCall("GetCurrentProcessId") "-" A_TickCount
    try {
        FileAppend(text, tmp, "UTF-8")
        FileMove(tmp, path, 1)
    } catch as e {
        try FileDelete(tmp)
        throw e
    }
}


; 托盘右键菜单 = 全部功能。每项都标了快捷键，不用背。
SetupTray() {
    global HotkeyPause, HotkeyExit
    tray := A_TrayMenu
    tray.Delete()                                  ; 去掉 AHK 默认项，换成我们自己的
    tray.Add("识别按键`tCtrl+Alt+K", (*) => ShowKeyInspector())
    tray.Add("查前台进程`tCtrl+Alt+W", (*) => ShowActiveProcess())
    tray.Add("录制按键`tCtrl+Alt+R", (*) => RecordSnippet())
    tray.Add()
    tray.Add("编辑脚本`tCtrl+Alt+E", (*) => ShowCurrentScriptEditor())
    tray.Add("重载脚本", ReloadScript)
    tray.Add("暂停/恢复`t" HumanHotkey(HotkeyPause), TogglePause)
    tray.Add()
    tray.Add("帮助 / 全部功能`tCtrl+Alt+H", (*) => ShowHelp())
    tray.Add("退出`t" HumanHotkey(HotkeyExit), (*) => ExitApp())
    tray.Default := "帮助 / 全部功能`tCtrl+Alt+H"
}


; AHK 修饰符写法转成人能读的：^!x -> Ctrl+Alt+X，F8 -> F8
HumanHotkey(hk) {
    prefixes := Map("^", "Ctrl+", "!", "Alt+", "+", "Shift+", "#", "Win+")
    out := ""
    i := 1
    while (i <= StrLen(hk) && prefixes.Has(SubStr(hk, i, 1))) {
        out .= prefixes[SubStr(hk, i, 1)]
        i++
    }
    base := SubStr(hk, i)
    return out (StrLen(base) = 1 ? StrUpper(base) : base)
}


; 一个窗口列出所有功能和快捷键，回答「有啥功能」。Ctrl+Alt+H 或托盘菜单打开。
ShowHelp(*) {
    global AppName, Backend, HotkeyPause, HotkeyExit
    q := Chr(34)
    backendName := (Type(Backend) = "InterceptionBackend") ? "Interception 驱动级输入" : "SendInput 普通输入"

    text := "当前输入后端：" backendName "`r`n"
        . "──────────────────────────────`r`n"
        . "全局快捷键（任何时候按都生效）：`r`n`r`n"
        . "  Ctrl+Alt+K   识别按键：按任意键，实时显示它叫什么、怎么写进脚本`r`n"
        . "  Ctrl+Alt+W   复制前台窗口进程名（填 #HotIf WinActive 用）`r`n"
        . "  Ctrl+Alt+R   录制按键片段到剪贴板（含按住时长），按 Esc 停`r`n"
        . "  Ctrl+Alt+E   打开脚本编辑器`r`n"
        . "  Ctrl+Alt+H   打开本帮助`r`n"
        . "  " Pad(HumanHotkey(HotkeyPause)) " 暂停 / 恢复全部宏`r`n"
        . "  " Pad(HumanHotkey(HotkeyExit)) " 退出（退出时会松开所有按下的键）`r`n`r`n"
        . "托盘图标右键：上面的功能都能直接点，不用记快捷键。`r`n"
        . "──────────────────────────────`r`n"
        . "写脚本 (.dxm)：`r`n`r`n"
        . "  NumpadAdd::                ← 热键：按小键盘 +`r`n"
        . "      Send " q "{Right}" q "          ← 发一个方向键`r`n"
        . "      Sleep 80               ← 等 80 毫秒`r`n"
        . "      Tap Right 50           ← 按住 50ms 再松`r`n"
        . "  Return`r`n`r`n"
        . "  动作：Send / Sleep / Tap 键名 毫秒 / KeyDown / KeyUp / Call`r`n"
        . "  只在某程序生效：#HotIf WinActive(" q "游戏.exe" q ")`r`n"
        . "  不知道某个键叫什么？按 Ctrl+Alt+K 一按就知道。"

    g := Gui("+AlwaysOnTop", AppName " · 帮助 / 全部功能")
    g.SetFont("s10", "Consolas")
    g.AddEdit("w620 h440 ReadOnly -Wrap", text)
    g.SetFont("s9", "Segoe UI")
    g.AddButton("w100", "关闭").OnEvent("Click", (*) => g.Destroy())
    g.Show()
}


; 左对齐补空格，让帮助里快捷键那两行对齐（可配置的暂停/退出键长度不定）
Pad(s, width := 12) {
    while (StrLen(s) < width)
        s .= " "
    return s
}


; 原始需求里的「重载」。改完脚本不用手动关了再开。
ReloadScript(*) {
    global Backend, LoadedConfigPath
    try Backend.ReleaseAll()        ; 先松键，别让重载把键卡在按下状态

    if !A_IsCompiled {
        Reload()
        return
    }
    ; 编译版：重新拉一个自己，#SingleInstance Force 会顶掉当前进程
    try Run(QuoteArg(A_ScriptFullPath) " " QuoteArg(LoadedConfigPath))
    ExitApp()
}


; #DxHardInput on 但驱动没装：给个能点去下载的框，然后照常用 SendInput 跑。
OfferInterceptionDownload() {
    global AppName, InterceptionUrl
    text := "脚本里写了 #DxHardInput on，但这台机器没装 Interception 驱动。"
        . "`n`n现在先用 SendInput 继续运行——宏照常工作，只是不是驱动级输入。"
        . "`n如果目标程序读不到 SendInput（比如用 Raw Input / DirectInput 的游戏），才需要装驱动。"
        . "`n`n装驱动要下载 Interception，解压后以管理员运行："
        . "`n    install-interception.exe /install"
        . "`n装完必须重启。卸载是 /uninstall。"
        . "`n`n现在打开下载页吗？"

    if (MsgBox(text, AppName, "YesNo Icon?") = "Yes")
        try Run(InterceptionUrl)
}


HandleUtilityCommand() {
    global AppName
    if (A_Args.Length = 0)
        return false

    cmd := StrLower(A_Args[1])
    if (cmd = "--register") {
        RegisterFileAssociation()
        MsgBox(".dxm 后缀名已注册到当前用户。", AppName)
        return true
    }
    if (cmd = "--unregister") {
        UnregisterFileAssociation()
        MsgBox(".dxm 后缀名关联已移除。", AppName)
        return true
    }
    if (cmd = "--edit") {
        path := A_Args.Length >= 2 ? A_Args[2] : ConfigPath()
        ShowScriptEditor(path)
        return true
    }
    return false
}


TryRelaunchAsAdmin() {
    target := A_IsCompiled ? QuoteArg(A_ScriptFullPath)
        : QuoteArg(A_AhkPath) " " QuoteArg(A_ScriptFullPath)
    args := QuoteArgs(A_Args)
    try {
        Run("*RunAs " target (args = "" ? "" : " " args))
        return true
    } catch {
        return false
    }
}


QuoteArgs(args) {
    out := ""
    for arg in args
        out .= (out = "" ? "" : " ") QuoteArg(arg)
    return out
}


QuoteArg(value) => Chr(34) StrReplace(value, Chr(34), Chr(92) Chr(34)) Chr(34)


; GetKeySC/GetKeyVK 对无效键名返回 0（不抛异常），拿来当键名校验器。
IsRealKey(name) => (name != "") && (GetKeySC(name) != 0 || GetKeyVK(name) != 0)


ValidateConfig(config) {
    if (!config.Has("hotkeys") || config["hotkeys"].Count = 0)
        throw Error("没有配置任何 hotkeys")

    blocks := config.Has("blocks") ? config["blocks"] : Map()
    settings := config.Has("settings") ? config["settings"] : Map()
    reserved := ReservedHotkeys(settings)

    for name, variants in config["hotkeys"] {
        if !IsRealKey(BaseKey(name))
            throw Error("热键名无效: `"" name "`"")
        if reserved.Has(StrLower(name))
            throw Error("热键 " name " 与系统功能 " reserved[StrLower(name)] " 冲突")
        seen := Map()
        for cfg in variants {
            app := cfg.Has("active_window") ? StrLower(cfg["active_window"]) : ""
            if seen.Has(app)
                throw Error("热键 " name " 对窗口 " (app = "" ? "[所有窗口]" : app) " 重复配置")
            seen[app] := true
            if (!cfg.Has("actions") || cfg["actions"].Length = 0)
                throw Error("热键 " name " 没有 actions")
            for i, action in cfg["actions"]
                ValidateAction(name, i, action, blocks)
        }
    }

    for name, actions in blocks {
        if (actions.Length = 0)
            throw Error("Block " name " 没有动作")
        for i, action in actions
            ValidateAction("Block " name, i, action, blocks)
    }
}


ReservedHotkeys(settings) {
    out := Map("^!w", "查窗口", "^!k", "识别按键", "^!e", "编辑器", "^!r", "录制", "^!h", "帮助")
    pauseKey := settings.Has("pause_key") ? settings["pause_key"] : "F8"
    exitKey := settings.Has("exit_key") ? settings["exit_key"] : "^!x"
    if (pauseKey != "")
        out[StrLower(pauseKey)] := "暂停/恢复"
    if (exitKey != "")
        out[StrLower(exitKey)] := "退出"
    return out
}


ValidateAction(hk, idx, action, blocks := "") {
    where := Format("热键 {1} 的第 {2} 个 action", hk, idx)

    for verb in ["key_down", "key_up", "tap"] {
        if action.Has(verb) {
            if !IsRealKey(action[verb])
                throw Error(where "：键名无效 `"" action[verb] "`"")
            if (verb = "tap" && action.Has("hold")
                && (!IsInteger(action["hold"]) || action["hold"] < 0))
                throw Error(where "：Tap hold 必须是非负整数")
            return
        }
    }
    if action.Has("sleep") {
        if (!IsInteger(action["sleep"]) || action["sleep"] < 0)
            throw Error(where "：sleep 必须是非负整数")
        return
    }
    if action.Has("send") {
        groups := ParseSendGroups(action["send"])
        if IsObject(groups) {
            for group in groups {
                if !IsRealKey(group.key)
                    throw Error(where "：键名无效 `"" group.key "`"")
            }
        }
        return
    }
    if action.Has("call") {
        if (blocks = "" || !blocks.Has(action["call"]))
            throw Error(where "：找不到 Block `"" action["call"] "`"")
        return
    }

    throw Error(where "：无法识别（需要 key_down / key_up / tap / sleep / send / call 之一）")
}


InitBackend(settings) {
    name := settings.Has("backend") ? StrLower(settings["backend"]) : "sendinput"
    switch name {
        case "sendinput":    return SendInputBackend()
        case "interception": return InterceptionBackend(settings)
        default:             throw Error("未知后端: " name)
    }
}


RegisterHotkeys() {
    global Config, Backend
    if !Config.Has("hotkeys")
        return
    for name, variants in Config["hotkeys"] {
        if (Type(Backend) = "InterceptionBackend" && IsSimpleHardHotkey(name))
            SafeHardHotkey(name)
        else {
            ; 进程级占用：只在「当前前台窗口有匹配配置」时激活热键并吞键，
            ; 不匹配的进程上这个键原样透传，不被全局吃掉。
            ; （active_window="" 的全局热键总有兜底配置，所以处处生效，符合预期。）
            HotIf(HotkeyContextActive.Bind(name))
            SafeHotkey(name, RunHotkey.Bind(name))
            HotIf()          ; 复位，别把上下文带给后面注册的暂停/退出/辅助热键
        }
    }
    HotIf()                  ; 保险再复位一次
}


IsSimpleHardHotkey(name) => (name = BaseKey(name) && GetKeySC(name) != 0)


; HotIf 上下文判断：有匹配配置就激活（吞键），没有就让键透传。必须快、无副作用。
HotkeyContextActive(name, *) => SelectHotkeyConfig(name) != ""


SafeHardHotkey(name) {
    global Backend, AppName
    try {
        Backend.SubscribeHotkey(name, RunHardHotkey.Bind(name))
    } catch as e {
        MsgBox("注册驱动热键失败: " name "`n" e.Message "`n`n已改用普通热键监听。", AppName, "Icon!")
        SafeHotkey(name, RunHotkey.Bind(name))
    }
}


SafeHotkey(keyName, callback) {
    global AppName
    try {
        Hotkey(keyName, callback, "On")
    } catch as e {
        MsgBox("注册热键失败: " keyName "`n" e.Message, AppName)
    }
}


RunHotkey(name, *) {
    RunHotkeyCore(name, true)
}


RunHardHotkey(name, state) {
    static down := Map()
    if !state {
        down.Delete(name)
        return
    }

    cfg := SelectHotkeyConfig(name)
    if !cfg
        return
    repeat := cfg.Has("repeat") ? cfg["repeat"] : false
    if (down.Has(name) && !repeat)
        return
    down[name] := true
    RunHotkeyCore(name, false)
}


RunHotkeyCore(name, waitForRelease) {
    global Config, Backend, Paused, AppName

    if Paused
        return

    cfg := SelectHotkeyConfig(name)
    if !cfg
        return

    try {
        ExecuteActions(cfg["actions"])
    } catch as e {
        Backend.ReleaseAll()   ; 宏中途出错，别把键卡在按下状态
        TrayTip("宏执行出错: " e.Message, AppName)
    }

    ; repeat=false 时等热键松开，避免按住连发
    repeat := cfg.Has("repeat") ? cfg["repeat"] : false
    if (!repeat && waitForRelease)
        KeyWait(BaseKey(name))
}


SelectHotkeyConfig(name) {
    global Config
    if (!IsObject(Config) || !Config.Has("hotkeys") || !Config["hotkeys"].Has(name))
        return ""
    fallback := ""
    for cfg in Config["hotkeys"][name] {
        app := cfg.Has("active_window") ? cfg["active_window"] : ""
        if (app = "") {
            fallback := cfg
            continue
        }
        if WinActive("ahk_exe " app)
            return cfg
    }
    return fallback
}


ExecuteActions(actions, depth := 0) {
    if (depth > 20)
        throw Error("Call 嵌套过深")
    for action in actions
        RunAction(action, depth)
}


RunAction(action, depth := 0) {
    global Backend, Config
    if action.Has("sleep")
        Sleep(action["sleep"])
    else if action.Has("key_down")
        Backend.KeyDown(action["key_down"])
    else if action.Has("key_up")
        Backend.KeyUp(action["key_up"])
    else if action.Has("tap")
        Backend.Tap(action["tap"], action.Has("hold") ? action["hold"] : 50)
    else if action.Has("send")
        RunSend(action["send"])
    else if action.Has("call")
        ExecuteActions(Config["blocks"][action["call"]], depth + 1)
    else
        throw Error("无法识别的 action")
}


; Send 字符串：纯 {Key} 序列走后端（硬输入也生效），含文本才落回 SendInput。
RunSend(str) {
    global Backend
    groups := ParseSendGroups(str)
    if (groups = "") {
        SendInput(str)          ; 含文本，只能普通注入
        return
    }
    for g in groups {
        if (g.state = "tap")
            Backend.Tap(g.key, 50)
        else if (g.state = "down")
            Backend.KeyDown(g.key)
        else
            Backend.KeyUp(g.key)
    }
}


; "^!x" -> "x"，"~F9" -> "F9"。KeyWait 只认基础键名。
BaseKey(hk) => RegExReplace(hk, "^[\^!+#<>*~$ ]+", "")


TogglePause(*) {
    global Paused, AppName
    Paused := !Paused
    TrayTip(Paused ? "已暂停" : "已恢复", AppName)
}


ShowActiveProcess(*) {
    global AppName
    ; "A"=当前激活窗口。从托盘菜单点会丢焦点，或焦点在开始菜单/桌面时，
    ; 根本没有前台窗口，WinGetProcessName("A") 会抛 "Target window not found"。
    ; 先用 WinExist 拿 hwnd，为空就给能照做的提示，而不是糊涂的报错。
    hwnd := WinExist("A")
    if !hwnd {
        TrayTip("现在没有前台窗口。`n请先点一下目标程序窗口，再按快捷键 Ctrl+Alt+W。`n"
            . "（从托盘菜单点会夺走目标焦点，所以这个要用快捷键。）", AppName)
        return
    }
    try {
        exe := WinGetProcessName(hwnd)
        title := WinGetTitle(hwnd)
    } catch as e {
        TrayTip("读取前台窗口失败: " e.Message, AppName)
        return
    }
    A_Clipboard := exe
    TrayTip("前台进程: " exe "`n（已复制到剪贴板，填进 #HotIf WinActive 用）`n标题: " title, AppName)
}


; 常驻按键识别器：按键实时更新，不超时、不用反复按热键。
; 显示键名、扫描码、可直接粘进 .dxm 的写法；小键盘键提示 NumLock 影响。
ShowKeyInspector(*) {
    global AppName, KeyInspectorOpen
    if (IsSet(KeyInspectorOpen) && KeyInspectorOpen)
        return                          ; 已经开着，别开第二个
    KeyInspectorOpen := true

    q := Chr(34)
    lastSnippet := ""
    pressed := Map()                    ; 忽略系统自动重复

    g := Gui("+AlwaysOnTop", AppName " 按键识别器")
    g.SetFont("s10", "Segoe UI")
    g.AddText("xm w380", "按任意键，这里实时显示它是什么、以及写进脚本的方式。")
    g.SetFont("s16 Bold", "Consolas")
    nameCtrl := g.AddText("xm w380 h34", "（等待按键…）")
    g.SetFont("s10", "Consolas")
    codeCtrl := g.AddEdit("xm w380 h150 ReadOnly -Wrap")
    g.SetFont("s9", "Segoe UI")
    g.AddButton("xm w150", "复制 Send 写法").OnEvent("Click", CopyNow)
    g.AddButton("x+8 w80", "关闭").OnEvent("Click", (*) => Done())

    ih := InputHook()
    ih.KeyOpt("{All}", "N")             ; 通知但不拦截，按键照常生效
    ih.OnKeyDown := OnDown
    ih.OnKeyUp := OnUp
    ih.Start()

    g.OnEvent("Close", (*) => Done())
    g.Show()
    return

    OnDown(h, vk, sc) {
        name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if (name = "" || pressed.Has(name))
            return
        pressed[name] := true

        lastSnippet := "Send " q "{" name "}" q
        detail := "扫描码: 0x" Format("{:03X}", sc) (sc & 0x100 ? "  (扩展键)" : "")
            . "`r`n`r`n点按:  " lastSnippet
            . "`r`n按下:  Send " q "{" name " down}" q
            . "`r`n松开:  Send " q "{" name " up}" q
            . "`r`nTap:   Tap " name " 50"
        if (SubStr(name, 1, 6) = "Numpad")
            detail .= "`r`n`r`n⚠ 小键盘键：硬输入下 Numpad1 和 NumpadEnd 同扫描码，"
                . "`r`n   实际字符取决于 NumLock；普通输入无此问题。"
        nameCtrl.Text := name
        codeCtrl.Value := detail
    }

    OnUp(h, vk, sc) {
        name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if (name != "")
            pressed.Delete(name)
    }

    CopyNow(*) {
        if (lastSnippet = "")
            return
        A_Clipboard := lastSnippet
        ToolTip("已复制: " lastSnippet)
        SetTimer(() => ToolTip(), -1200)
    }

    Done() {
        global KeyInspectorOpen
        KeyInspectorOpen := false
        try ih.Stop()
        g.Destroy()
    }
}


RecordSnippet(*) {
    global AppName
    events := []
    pressed := Map()            ; 当前按下的键，用来忽略系统自动重复

    OnDown(hook, vk, sc) {
        if (vk = 0x1B) {        ; Esc 停止录制，本身不录
            hook.Stop()
            return
        }
        key := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if (key = "" || pressed.Has(key))
            return
        pressed[key] := true
        events.Push({type: "down", key: key, t: A_TickCount})
    }
    OnUp(hook, vk, sc) {
        if (vk = 0x1B)
            return
        key := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if (key = "" || !pressed.Has(key))
            return
        pressed.Delete(key)
        events.Push({type: "up", key: key, t: A_TickCount})
    }

    TrayTip("开始录制。正常操作，按 Esc 停止，结果复制到剪贴板。", AppName)
    ih := InputHook("V L0")      ; V=透传按键，L0=不收集文本、无长度上限
    ih.KeyOpt("{All}", "N")
    ih.KeyOpt("{Escape}", "NS") ; Esc 只停止录制，不传给目标程序
    ih.OnKeyDown := OnDown
    ih.OnKeyUp := OnUp
    ih.Start()
    ih.Wait()

    lines := EmitRecording(events)
    if (lines.Length = 0)
        return
    text := JoinLines(lines)
    A_Clipboard := text
    MsgBox("已复制录制片段：`n`n" text, AppName)
}


; 把 down/up 事件流转成 .dxm 动作。纯函数，方便自检。
;  - down 紧跟自己的 up（中间没别的键）-> Tap 键名 按住毫秒
;  - 交叠按键 -> 分开的 Send "{Key down}" / Send "{Key up}"
;  - 事件之间的间隔 -> Sleep（<15ms 的忽略，算噪声）
EmitRecording(events) {
    lines := []
    q := Chr(34)
    i := 1
    prevEnd := events.Length ? events[1].t : 0

    while (i <= events.Length) {
        e := events[i]
        gap := e.t - prevEnd
        if (gap >= 15)
            lines.Push("    Sleep " gap)

        if (e.type = "down" && i < events.Length
            && events[i + 1].type = "up" && events[i + 1].key = e.key) {
            hold := events[i + 1].t - e.t
            lines.Push("    Tap " e.key " " Max(hold, 1))
            prevEnd := events[i + 1].t
            i += 2
        } else {
            lines.Push("    Send " q "{" e.key (e.type = "down" ? " down" : " up") "}" q)
            prevEnd := e.t
            i += 1
        }
    }
    return lines
}


JoinLines(lines) {
    text := ""
    for line in lines
        text .= (text = "" ? "" : "`n") line
    return text
}


ShowCurrentScriptEditor(*) {
    global LoadedConfigPath
    ShowScriptEditor(LoadedConfigPath != "" ? LoadedConfigPath : ConfigPath())
}


ShowScriptEditor(path) {
    global AppName
    text := FileExist(path) ? FileRead(path, "UTF-8") : ""

    g := Gui("+Resize", AppName " editor")
    g.SetFont("s10", "Consolas")
    info := g.AddText("xm w760", "脚本: " path)
    edit := g.AddEdit("xm w760 h460 -Wrap WantTab", text)
    g.SetFont("s9", "Segoe UI")

    st := {saved: text}         ; 记录最后一次保存的内容，用来判断有没有未保存改动

    buttons := [g.AddButton("xm w90", "检查")
              , g.AddButton("x+8 w90", "保存")
              , g.AddButton("x+8 w110", "保存并运行")
              , g.AddButton("x+8 w110", "注册 .dxm")
              , g.AddButton("x+8 w90", "关闭")]

    buttons[1].OnEvent("Click", (*) => CheckEditor(edit))
    buttons[2].OnEvent("Click", (*) => SaveEditor(path, edit, false, st))
    buttons[3].OnEvent("Click", (*) => SaveEditor(path, edit, true, st))
    buttons[4].OnEvent("Click", (*) => SafeRegisterAssociation())
    buttons[5].OnEvent("Click", (*) => CloseEditor(g, edit, st))

    g.OnEvent("Size", ResizeEditor.Bind(info, edit, buttons))
    g.OnEvent("Close", (*) => CloseEditor(g, edit, st))   ; 右上角 X 也走这里
    g.Show()
}


CloseEditor(g, edit, st) {
    global AppName
    if (edit.Value != st.saved) {
        if (MsgBox("有未保存的修改，确定关闭吗？", AppName, "YesNo Icon!") != "Yes")
            return
    }
    g.Destroy()
}


; +Resize 不会自动挪控件，得自己来，不然拉大窗口只有背景变大。
ResizeEditor(info, edit, buttons, g, minMax, w, h) {
    if (minMax = -1)          ; 最小化时窗口尺寸没意义
        return

    pad := 10, gap := 8
    buttons[1].GetPos(, , &btnW, &btnH)
    info.Move(pad, pad, w - 2 * pad)
    edit.Move(pad, 38, w - 2 * pad, h - 38 - btnH - 2 * pad)

    x := pad, y := h - btnH - pad
    for b in buttons {
        b.GetPos(, , &btnW)
        b.Move(x, y)
        x += btnW + gap
    }
}


CheckEditor(edit) {
    global AppName
    try {
        ValidateScriptText(edit.Value)
    } catch as e {
        MsgBox("脚本有问题：`n`n" e.Message, AppName, "Icon!")
        return
    }
    MsgBox("检查通过。", AppName, "Iconi")
}


SaveEditor(path, edit, runAfter, st := "") {
    global AppName
    try {
        ValidateScriptText(edit.Value)
    } catch as e {
        MsgBox("没保存。脚本有问题：`n`n" e.Message, AppName, "Icon!")
        return
    }
    try {
        WriteTextFile(path, edit.Value)
    } catch as e {
        MsgBox("保存失败：`n`n" e.Message, AppName, "Icon!")
        return
    }
    if (st != "")
        st.saved := edit.Value          ; 保存成功，清掉未保存标记
    if runAfter {
        ; 新实例会靠 #SingleInstance Force 顶掉当前进程，所以这后面不能再有代码。
        RunDxMacro(path)
        return
    }
    MsgBox("已保存。", AppName, "Iconi")
}


SafeRegisterAssociation() {
    global AppName
    try {
        RegisterFileAssociation()
        MsgBox(".dxm 已注册到当前用户。", AppName, "Iconi")
    } catch as e {
        MsgBox("注册失败：`n`n" e.Message, AppName, "Icon!")
    }
}


ValidateScriptText(text) {
    tmp := A_Temp "\dx-macro-check-" A_TickCount ".dxm"
    try {
        FileAppend(text, tmp, "UTF-8")
        cfg := LoadScriptConfig(tmp)
        ValidateConfig(cfg)
    } finally {
        try FileDelete(tmp)
    }
}


RunDxMacro(path) {
    target := A_IsCompiled ? QuoteArg(A_ScriptFullPath)
        : QuoteArg(A_AhkPath) " " QuoteArg(A_ScriptFullPath)
    Run(target " " QuoteArg(path))
}


AssociationExe() {
    if A_IsCompiled
        return A_ScriptFullPath
    exe := A_ScriptDir "\dx-macro.exe"
    if FileExist(exe)
        return exe
    throw Error("找不到 dx-macro.exe，无法注册 .dxm")
}


RegisterFileAssociation() {
    exe := AssociationExe()
    RegWrite("dx-macro.Script", "REG_SZ", "HKCU\Software\Classes\.dxm")
    RegWrite("dx-macro script", "REG_SZ", "HKCU\Software\Classes\dx-macro.Script")
    RegWrite(Chr(34) exe Chr(34) ",0", "REG_SZ", "HKCU\Software\Classes\dx-macro.Script\DefaultIcon")
    RegWrite(Chr(34) exe Chr(34) " " Chr(34) "%1" Chr(34), "REG_SZ", "HKCU\Software\Classes\dx-macro.Script\shell\open\command")
}


UnregisterFileAssociation() {
    try RegDeleteKey("HKCU\Software\Classes\.dxm")
    try RegDeleteKey("HKCU\Software\Classes\dx-macro.Script")
}


OnExitHandler(*) {
    global Backend
    try {
        if Backend
            Backend.ReleaseAll()
    }
    return 0   ; 允许退出
}
