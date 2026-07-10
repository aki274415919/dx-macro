; 自检：不碰真键盘、不碰真窗口，用 MockBackend 验证动作序列 / 兜底松键 / 热键名解析。
;   AutoHotkey64.exe selftest.ahk      退出码 0 = 全过
#Requires AutoHotkey v2.0
#Include main.ahk

class MockBackend extends IInputBackend {
    __New() {
        super.__New()
        this.log := []
    }
    KeyDown(key) {
        this.log.Push("down:" key)
        this.held[key] := true
    }
    KeyUp(key) {
        this.log.Push("up:" key)
        this.held.Delete(key)
    }
}

Say(s)  => FileAppend(s "`n", "*")
Assert(cond, msg) {
    if !cond {
        Say("FAIL " msg)
        ExitApp(1)
    }
    Say("ok   " msg)
}
Throws(fn) {
    try fn()
    catch
        return true
    return false
}
; 一个只有单条 action 的最小配置，用来测校验器
BadConfig(action) => Map("hotkeys", Map("F9", [Map("actions", [action])]))

RunSelfTest()

RunSelfTest() {
    global Backend, Config

    ; 1. 热键名 -> KeyWait 基础键名
    Assert(BaseKey("F9")        = "F9",      "BaseKey F9")
    Assert(BaseKey("^!x")       = "x",       "BaseKey ^!x -> x")
    Assert(BaseKey("~*F9")      = "F9",      "BaseKey ~*F9 -> F9")
    Assert(ParseHotIf('WinActive("sample-app.exe")') = "sample-app.exe", "HotIf WinActive exe 简写")

    ; 2. 脚本读进来了
    cfg := Config["hotkeys"]["Numpad0"][1]
    Assert(RegExMatch(cfg["active_window"], "i)\.exe$"), "config active_window")
    Assert(cfg["repeat"] = false,               "config repeat=false")
    defaults := DefaultConfig()
    Assert(defaults["hotkeys"].Has("Numpad0") && defaults["hotkeys"].Has("NumpadEnter")
        && defaults["hotkeys"].Has("NumpadDot") && defaults["hotkeys"].Count = 3,
        "内置默认热键 = 0/Enter/Dot")

    ; 3. 真实配置里的 actions 跑出正确的按键序列
    Backend := MockBackend()
    for action in cfg["actions"]
        RunAction(action)
    got := ""
    for e in Backend.log
        got .= e " "
    want := "down:Left up:Left down:Left up:Left down:Left up:Left "
    Assert(got = want, "action 序列 = Left,Left,Left  (得到: " Trim(got) ")")
    Assert(Backend.held.Count = 0, "跑完没有键卡在按下状态")

    ; 4. Tap = down -> hold -> up
    Backend := MockBackend()
    Backend.Tap("Left", 10)
    Assert(Backend.log.Length = 2 && Backend.log[1] = "down:Left" && Backend.log[2] = "up:Left", "Tap 发出 down+up")

    oldConfig := Config
    Config := Map("blocks", Map("MoveLeft", [Map("tap", "Left")]))
    Backend := MockBackend()
    RunAction(Map("call", "MoveLeft"))
    Assert(Backend.log.Length = 2 && Backend.log[1] = "down:Left" && Backend.log[2] = "up:Left", "Call 执行 Block")
    Config := oldConfig

    ; 5. 宏中途异常 -> ReleaseAll 把按下的键全松开
    Backend := MockBackend()
    Backend.KeyDown("Down")
    Backend.KeyDown("Left")
    Assert(Backend.held.Count = 2, "两个键处于按下状态")
    Backend.ReleaseAll()
    Assert(Backend.held.Count = 0, "ReleaseAll 清空 held")
    Assert(Backend.log[3] ~= "^up:" && Backend.log[4] ~= "^up:", "ReleaseAll 对每个键发 up")

    ; 6. 无法识别的 action 要报错，不能静默跳过
    threw := false
    try RunAction(Map("bogus", 1))
    catch
        threw := true
    Assert(threw, "未知 action 抛异常")

    ; 7. 基类没实现 KeyDown 就抛错（接口约束真的生效）
    threw := false
    try IInputBackend().KeyDown("a")
    catch
        threw := true
    Assert(threw, "IInputBackend 抽象方法抛异常")

    ; 8. 键名校验器
    Assert(IsRealKey("F9") && IsRealKey("NumpadEnd") && IsRealKey("Left"), "合法键名通过")
    Assert(!IsRealKey("Downn") && !IsRealKey(""), "非法键名被拒")

    ; 9. 启动时校验：好配置放行，坏配置必须炸
    threw := false
    try ValidateConfig(Config)
    catch
        threw := true
    Assert(!threw, "真实脚本通过校验")

    oldConfig := Config
    Config := Map("hotkeys", Map("Numpad0", [Map("actions", [Map("tap", "Left")])]))
    Assert(SelectHotkeyConfig("F10") = "", "不存在的热键被忽略")
    Config := ""
    Assert(SelectHotkeyConfig("F10") = "", "未加载配置时热键被忽略")
    Config := oldConfig

    Assert(Throws(() => ValidateConfig(Map("hotkeys", Map()))), "空 hotkeys 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("key_down", "Downn")))), "键名拼错被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("sleep", -5)))),         "负数 sleep 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("bogus", 1)))),          "未知 action 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("tap", "Left", "hold", -1)))), "负数 Tap hold 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("send", "{Left}{Downn}")))), "多组 Send 的错误键名被拒")
    Assert(!Throws(() => ValidateConfig(BadConfig(Map("tap", "Left")))),      "合法 tap 通过")

    multiApp := Map("hotkeys", Map("F9", [
        Map("active_window", "one.exe", "actions", [Map("tap", "a")]),
        Map("active_window", "two.exe", "actions", [Map("tap", "b")])
    ]))
    Assert(!Throws(() => ValidateConfig(multiApp)), "同一热键可按不同 App 分发")

    duplicateApp := Map("hotkeys", Map("F9", [
        Map("active_window", "one.exe", "actions", [Map("tap", "a")]),
        Map("active_window", "one.exe", "actions", [Map("tap", "b")])
    ]))
    Assert(Throws(() => ValidateConfig(duplicateApp)), "同一热键同一 App 重复配置被拒")

    blockConfig := Map(
        "blocks", Map("MoveLeft", [Map("tap", "Left")]),
        "hotkeys", Map("Numpad2", [Map("actions", [Map("call", "MoveLeft")])])
    )
    Assert(!Throws(() => ValidateConfig(blockConfig)), "Call 指向已存在 Block 时通过")

    missingBlock := Map("hotkeys", Map("Numpad2", [Map("actions", [Map("call", "Missing")])]))
    Assert(Throws(() => ValidateConfig(missingBlock)), "Call 指向不存在 Block 时被拒")

    reservedConflict := Map(
        "settings", Map("pause_key", "F8", "exit_key", "^!x"),
        "hotkeys", Map("F8", [Map("actions", [Map("tap", "a")])])
    )
    Assert(Throws(() => ValidateConfig(reservedConflict)), "用户热键不能占用控制热键")

    settings := Map("backend", "sendinput")
    activeWindow := "", repeat := false
    ParseScriptDirective("#DxHardInput on", settings, &activeWindow, &repeat)
    Assert(settings["backend"] = "interception", "#DxHardInput on -> interception")
    ParseScriptDirective("#HardInput off", settings, &activeWindow, &repeat)
    Assert(settings["backend"] = "sendinput", "#HardInput off -> sendinput")
    ParseScriptDirective("#RequireAdmin", settings, &activeWindow, &repeat)
    Assert(settings["require_admin"] = true, "#RequireAdmin -> require_admin")
    ParseScriptDirective("#AskAdmin off", settings, &activeWindow, &repeat)
    Assert(settings["ask_admin"] = false, "#AskAdmin off -> ask_admin=false")
    ParseScriptDirective("#InterceptionInstance 2", settings, &activeWindow, &repeat)
    Assert(settings["interception_instance"] = 2, "#InterceptionInstance -> 2")

    ; Interception 后端必须「抛异常」而不是让 AHI 把进程 ExitApp 掉。
    ; 这个断言本身就是证据：如果 InterceptionBackend 又去先构造 AHI，
    ; 驱动缺失时自检进程会被 ExitApp 干掉，根本跑不到 ALL PASS。
    Assert(InterceptionDllPath() != "", "找得到 interception.dll")

    caught := ""
    try InterceptionBackend(Map("interception_vid", 0, "interception_pid", 0))
    catch DriverMissingError
        caught := "DriverMissingError"
    catch KeyboardNotConfiguredError
        caught := "KeyboardNotConfiguredError"
    catch as e
        caught := Type(e)

    if InterceptionDriverPresent() {
        Assert(caught = "KeyboardNotConfiguredError", "驱动已装但缺设备 -> KeyboardNotConfiguredError (得到: " caught ")")
    } else {
        Assert(caught = "DriverMissingError", "驱动没装 -> DriverMissingError (得到: " caught ")")
    }

    ; Send 拆组：纯 {Key} 序列走后端，含文本落回 SendInput
    Assert(ParseSendGroups("hello") = "", "纯文本 -> 不拆组（走 SendInput）")
    Assert(ParseSendGroups("{Left}abc") = "", "键+文本混合 -> 不拆组")
    Assert(ParseSendGroups("{}") = "", "空按键组不会崩溃")
    g := ParseSendGroups("{Left}{Right down}{Right up}")
    Assert(IsObject(g) && g.Length = 3, "三个组")
    Assert(g[1].key = "Left"  && g[1].state = "tap",  "组1 = Left tap")
    Assert(g[2].key = "Right" && g[2].state = "down", "组2 = Right down")
    Assert(g[3].key = "Right" && g[3].state = "up",   "组3 = Right up")
    Assert(ParseSendGroups("{Left 3}") = "", "{Left 3} 重复次数 -> 交给 SendInput")

    ; 录制器：down/up 事件流 -> 动作。相邻 down+up=Tap，交叠=分离，间隔=Sleep
    seqTap := EmitRecording([{type:"down",key:"Left",t:1000}, {type:"up",key:"Left",t:1050}])
    Assert(seqTap.Length = 1 && seqTap[1] = "    Tap Left 50", "相邻 down+up -> Tap 含按住时长 (得到: " (seqTap.Length ? seqTap[1] : "空") ")")

    seqGap := EmitRecording([{type:"down",key:"Left",t:1000}, {type:"up",key:"Left",t:1050}
                           , {type:"down",key:"Right",t:1200}, {type:"up",key:"Right",t:1230}])
    Assert(seqGap.Length = 3 && seqGap[2] = "    Sleep 150", "两个 Tap 之间插入 Sleep (得到: " (seqGap.Length >= 2 ? seqGap[2] : "?") ")")

    ; 交叠：Left 按住时 Right 按下再松开，Left 才松 -> 不能合成 Tap
    seqOverlap := EmitRecording([{type:"down",key:"Left",t:0}, {type:"down",key:"Right",t:10}
                              , {type:"up",key:"Right",t:20}, {type:"up",key:"Left",t:30}])
    Assert(seqOverlap[1] = "    Send " Chr(34) "{Left down}" Chr(34), "交叠 -> Left down 分离 (得到: " seqOverlap[1] ")")

    ; RunSend 端到端：纯 {Key} 序列真的走后端（不只是解析对）
    Backend := MockBackend()
    RunSend("{Left}{Right down}{Right up}")
    got := ""
    for e in Backend.log
        got .= e " "
    Assert(Trim(got) = "down:Left up:Left down:Right up:Right", "RunSend 把 {Key} 序列路由到后端 (得到: " Trim(got) ")")

    Backend := MockBackend()
    RunSend("hello")            ; 文本不该碰后端（走 SendInput）
    Assert(Backend.log.Length = 0, "RunSend 文本不经过后端")

    ; 内置配置器只改目标指令；安全写入能覆盖文件。
    directives := "#DxHardInput off`n#HotIf true`n"
    directives := SetScriptDirective(directives, "DxHardInput", "on")
    directives := SetScriptDirective(directives, "InterceptionInstance", 2)
    Assert(InStr(directives, "#DxHardInput on") && InStr(directives, "#InterceptionInstance 2"),
        "硬输入指令可写入脚本")

    tmp := A_Temp "\dx-macro-write-" DllCall("GetCurrentProcessId") ".txt"
    try {
        WriteTextFile(tmp, "first")
        WriteTextFile(tmp, "second")
        Assert(FileRead(tmp, "UTF-8") = "second", "安全写入可替换已有文件")
    } finally {
        try FileDelete(tmp)
    }

    recHook := InputHook("V L0")
    Assert(recHook.VisibleText && recHook.VisibleNonText, "录制器按键透传")

    ; 一个入口脚本可包含多个子脚本；相对路径和循环检测都在加载阶段完成。
    includeDir := A_Temp "\dx-macro-include-" DllCall("GetCurrentProcessId")
    DirCreate(includeDir)
    rootScript := includeDir "\root.dxm"
    childScript := includeDir "\child macro.dxm"
    cycleA := includeDir "\cycle-a.dxm"
    cycleB := includeDir "\cycle-b.dxm"
    try {
        WriteTextFile(childScript, "#HotIf true`nF10::`n    Tap a`nReturn`n")
        WriteTextFile(rootScript, "#Include `"child macro.dxm`"`n#HotIf true`nF11::`n    Tap b`nReturn`n")
        included := LoadScriptConfig(rootScript)
        Assert(included["hotkeys"].Has("F10") && included["hotkeys"].Has("F11")
            && !Throws(() => ValidateConfig(included)), "#Include 同时加载多个脚本")

        WriteTextFile(cycleA, "#Include `"cycle-b.dxm`"`n")
        WriteTextFile(cycleB, "#Include `"cycle-a.dxm`"`n")
        Assert(Throws(() => LoadScriptConfig(cycleA)), "循环 #Include 被拒")
    } finally {
        for path in [rootScript, childScript, cycleA, cycleB]
            try FileDelete(path)
        try DirDelete(includeDir)
    }

    Say("`nALL PASS")
    ExitApp(0)
}
