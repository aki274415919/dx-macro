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
#Include *i lib\AutoHotInterception\AutoHotInterception.ahk
#Include config.ahk

AppName := "dx-macro"
Config  := ""
Paused  := false
Backend := ""

; 只有直接运行 main.ahk 时才启动；被 selftest.ahk #Include 时不启动。
if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    Main()
else
    Config := LoadConfig()


Main() {
    global Config, Backend, AppName

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
    } catch as e {
        MsgBox("后端初始化失败：`n" e.Message "`n`n已回退到 SendInput 后端。", AppName)
        Backend := SendInputBackend()
    }

    RegisterHotkeys()

    pauseKey := settings.Has("pause_key") ? settings["pause_key"] : "F8"
    exitKey  := settings.Has("exit_key")  ? settings["exit_key"]  : "^!x"

    if (pauseKey != "")
        SafeHotkey(pauseKey, TogglePause)
    if (exitKey != "")
        SafeHotkey(exitKey, (*) => ExitApp())

    ; 查前台窗口进程名，顺便复制到剪贴板，方便填 active_window
    SafeHotkey("^!w", ShowActiveProcess)
    SafeHotkey("^!k", ShowKeySnippet)

    OnExit(OnExitHandler)

    TrayTip(Format("后端: {1}`n暂停/恢复: {2}`n退出: {3}`n查进程: Ctrl+Alt+W`n查键名: Ctrl+Alt+K",
        Type(Backend), pauseKey, exitKey), AppName " 已启动")
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

    for name, cfg in config["hotkeys"] {
        if !IsRealKey(BaseKey(name))
            throw Error("热键名无效: `"" name "`"")
        if (!cfg.Has("actions") || cfg["actions"].Length = 0)
            throw Error("热键 " name " 没有 actions")
        for i, action in cfg["actions"]
            ValidateAction(name, i, action)
    }
}


ValidateAction(hk, idx, action) {
    where := Format("热键 {1} 的第 {2} 个 action", hk, idx)

    for verb in ["key_down", "key_up", "tap"] {
        if action.Has(verb) {
            if !IsRealKey(action[verb])
                throw Error(where "：键名无效 `"" action[verb] "`"")
            return
        }
    }
    if action.Has("sleep") {
        if (!IsInteger(action["sleep"]) || action["sleep"] < 0)
            throw Error(where "：sleep 必须是非负整数")
        return
    }
    if action.Has("send")
        return

    throw Error(where "：无法识别（需要 key_down / key_up / tap / sleep / send 之一）")
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
    global Config
    if !Config.Has("hotkeys")
        return
    for name, cfg in Config["hotkeys"]
        SafeHotkey(name, RunHotkey.Bind(name))
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
    global Config, Backend, Paused, AppName

    if Paused
        return

    cfg := Config["hotkeys"][name]

    ; 窗口限制：前台进程不匹配就什么都不做
    if (cfg.Has("active_window") && cfg["active_window"] != "") {
        if !WinActive("ahk_exe " cfg["active_window"])
            return
    }

    try {
        for action in cfg["actions"]
            RunAction(action)
    } catch as e {
        Backend.ReleaseAll()   ; 宏中途出错，别把键卡在按下状态
        TrayTip("宏执行出错: " e.Message, AppName)
    }

    ; repeat=false 时等热键松开，避免按住连发
    repeat := cfg.Has("repeat") ? cfg["repeat"] : false
    if !repeat
        KeyWait(BaseKey(name))
}


RunAction(action) {
    global Backend
    if action.Has("sleep")
        Sleep(action["sleep"])
    else if action.Has("key_down")
        Backend.KeyDown(action["key_down"])
    else if action.Has("key_up")
        Backend.KeyUp(action["key_up"])
    else if action.Has("tap")
        Backend.Tap(action["tap"], action.Has("hold") ? action["hold"] : 50)
    else if action.Has("send")
        SendInput(action["send"])          ; 原样透传给 SendInput，方便打字符串
    else
        throw Error("无法识别的 action")
}


; "^!x" -> "x"，"~Numpad1" -> "Numpad1"。KeyWait 只认基础键名。
BaseKey(hk) => RegExReplace(hk, "^[\^!+#<>*~$ ]+", "")


TogglePause(*) {
    global Paused, AppName
    Paused := !Paused
    TrayTip(Paused ? "已暂停" : "已恢复", AppName)
}


ShowActiveProcess(*) {
    global AppName
    try {
        exe := WinGetProcessName("A")
        A_Clipboard := exe
        TrayTip("前台进程: " exe "`n（已复制到剪贴板）`n标题: " WinGetTitle("A"), AppName)
    } catch as e {
        TrayTip("读取前台窗口失败: " e.Message, AppName)
    }
}


ShowKeySnippet(*) {
    global AppName
    TrayTip("按一个要写进脚本的键，10 秒内有效。", AppName)
    ih := InputHook("L1 T10")
    ih.KeyOpt("{All}", "E")
    ih.Start()
    ih.Wait()

    key := ih.EndKey != "" ? ih.EndKey : ih.Input
    if (key = "")
        return

    q := Chr(34)
    snippet := "Send " q "{" key "}" q
    text := "键名: " key
        . "`n`n点按:`n" snippet
        . "`n`n按下:`nSend " q "{" key " down}" q
        . "`n`n松开:`nSend " q "{" key " up}" q
        . "`n`nTap:`nTap " key " 50"
    A_Clipboard := snippet
    MsgBox(text "`n`n已复制点按写法。", AppName)
}


OnExitHandler(*) {
    global Backend
    try {
        if Backend
            Backend.ReleaseAll()
    }
    return 0   ; 允许退出
}
