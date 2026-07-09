; ============================================================
;  config.ahk  —  脚本/配置加载器。普通使用写 dx-macro.dxm。
;  风格贴近 AHK v2 / 你给的 YAML，但不需要任何 JSON/YAML 解析器。
; ============================================================
;
;  key_down / key_up 用的键名 = AHK v2 键名，例如：
;    方向键: Up Down Left Right
;    小键盘(NumLock 开): Numpad0..Numpad9  NumpadDot  NumpadEnter
;    小键盘(NumLock 关): NumpadEnd NumpadDown NumpadPgDn NumpadLeft
;                        NumpadClear NumpadRight NumpadHome NumpadUp NumpadPgUp
;                        NumpadIns NumpadDel
;    功能键: F1..F24    普通键: a b c 1 2 3 ...
;
;  active_window: 前台进程名(exe)。留空 "" = 不限制窗口。
;                 不知道进程名？运行后按 Ctrl+Alt+W 会弹出并复制到剪贴板。
;  repeat: false = 按住不会连发，必须松开才能再次触发。
;          true  = 按住会顺序循环执行（上一遍跑完才跑下一遍）。

LoadConfig() {
    ini := ConfigPath()
    if FileExist(ini)
        return LoadConfigFile(ini)
    return DefaultConfig()
}


ConfigPath() {
    if (A_Args.Length > 0) {
        path := A_Args[1]
        if !FileExist(path)
            throw Error("找不到配置文件: " path)
        return path
    }
    script := A_ScriptDir "\dx-macro.dxm"
    return FileExist(script) ? script : A_ScriptDir "\dx-macro.ini"
}


LoadConfigFile(path) {
    return RegExMatch(path, "i)\.ini$") ? LoadIniConfig(path) : LoadScriptConfig(path)
}


LoadScriptConfig(path) {
    settings := Map("backend", "sendinput", "pause_key", "F8", "exit_key", "^!x"
        , "ask_admin", true, "require_admin", false
        , "interception_vid", 0, "interception_pid", 0)
    hotkeys := Map()
    activeWindow := ""
    repeat := false
    current := ""

    for raw in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(raw)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if (SubStr(line, 1, 1) = "#") {
            ParseScriptDirective(line, settings, &activeWindow, &repeat)
            continue
        }

        if RegExMatch(line, "^(.+)::$", &m) {
            current := Trim(m[1])
            hotkeys[current] := Map("active_window", activeWindow, "repeat", repeat, "actions", [])
            continue
        }

        if RegExMatch(line, "i)^(return|exit)$") {
            current := ""
            continue
        }

        if (current = "")
            throw Error("action 不在任何热键下面: " raw)
        hotkeys[current]["actions"].Push(ParseScriptAction(line))
    }

    return Map("settings", settings, "hotkeys", hotkeys)
}


ParseScriptDirective(line, settings, &activeWindow, &repeat) {
    if RegExMatch(line, "i)^#HotIf\s*(.*)$", &m) {
        activeWindow := ParseHotIf(m[1])
        return
    }
    if RegExMatch(line, "i)^#IfWinActive\s*(.*)$", &m) {
        activeWindow := ParseHotIf(m[1])
        return
    }
    if RegExMatch(line, "i)^#(\w+)\s*(.*)$", &m) {
        name := StrLower(m[1]), value := Trim(m[2])
        switch name {
            case "requires", "singleinstance":
                return
            case "requireadmin", "runasadmin":
                settings["require_admin"] := true
            case "askadmin":
                settings["ask_admin"] := (value = "") ? true : ParseIniBool(value, "#AskAdmin")
            case "backend":
                settings["backend"] := NeedValue(value, "#Backend")
            case "dxhardinput", "hardinput":
                settings["backend"] := ParseIniBool(value, "#" m[1]) ? "interception" : "sendinput"
            case "pausekey":
                settings["pause_key"] := value
            case "exitkey":
                settings["exit_key"] := value
            case "interceptionvid":
                settings["interception_vid"] := ParseIniInt(value, "#InterceptionVid")
            case "interceptionpid":
                settings["interception_pid"] := ParseIniInt(value, "#InterceptionPid")
            case "repeat":
                repeat := ParseIniBool(value, "#Repeat")
            default:
                throw Error("不支持的指令: " line)
        }
        return
    }
    throw Error("不支持的指令: " line)
}


ParseHotIf(expr) {
    expr := Trim(expr)
    if (expr = "" || StrLower(expr) = "true")
        return ""
    if RegExMatch(expr, "i)^ahk_exe\s+(.+)$", &m)
        return Trim(m[1])
    if RegExMatch(expr, "i)^WinActive\(`"ahk_exe\s+([^`"]+)`"\)$", &m)
        return m[1]
    if RegExMatch(expr, "i)^WinActive\(`"([^`"]+\.exe)`"\)$", &m)
        return m[1]
    throw Error("只支持 #HotIf WinActive(`"ahk_exe xxx.exe`")")
}


ParseScriptAction(text) {
    if !RegExMatch(text, "i)^(\w+)\s*(.*)$", &m)
        throw Error("无法识别 action: " text)

    cmd := StrLower(m[1]), rest := Trim(m[2])
    switch cmd {
        case "sleep":
            return Map("sleep", ParseIniInt(rest, "Sleep"))
        case "send", "sendinput":
            return ParseSendAction(Unquote(rest))
        case "tap":
            parts := Words(rest)
            if (parts.Length < 1 || parts.Length > 2)
                throw Error("Tap 格式应为: Tap 键名 [hold毫秒]")
            action := Map("tap", parts[1])
            if (parts.Length = 2)
                action["hold"] := ParseIniInt(parts[2], "Tap hold")
            return action
        case "keydown":
            return Map("key_down", NeedValue(rest, "KeyDown"))
        case "keyup":
            return Map("key_up", NeedValue(rest, "KeyUp"))
    }
    throw Error("不支持的 action: " text)
}


ParseSendAction(value) {
    if RegExMatch(value, "^\{([^{}]+)\}$", &m) {
        parts := Words(m[1])
        if (parts.Length = 1)
            return Map("tap", parts[1])
        if (parts.Length = 2) {
            state := StrLower(parts[2])
            if (state = "down")
                return Map("key_down", parts[1])
            if (state = "up")
                return Map("key_up", parts[1])
        }
    }
    return Map("send", value)
}


LoadIniConfig(path) {
    sections := Map()
    section := ""

    for raw in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(raw)
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue

        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            section := Trim(SubStr(line, 2, StrLen(line) - 2))
            if !sections.Has(section)
                sections[section] := []
            continue
        }

        if (section = "")
            throw Error("配置行不在任何 section 中: " raw)

        eq := InStr(line, "=")
        if !eq
            throw Error("配置行缺少 = ：" raw)

        sections[section].Push([Trim(SubStr(line, 1, eq - 1)), Unquote(Trim(SubStr(line, eq + 1)))])
    }

    settings := Map("backend", "sendinput", "pause_key", "F8", "exit_key", "^!x"
        , "ask_admin", true, "require_admin", false
        , "interception_vid", 0, "interception_pid", 0)
    if sections.Has("settings") {
        for pair in sections["settings"] {
            key := StrLower(pair[1]), val := pair[2]
            switch key {
                case "backend", "pause_key", "exit_key":
                    settings[key] := val
                case "ask_admin", "require_admin":
                    settings[key] := ParseIniBool(val, key)
                case "interception_vid", "interception_pid":
                    settings[key] := ParseIniInt(val, key)
            }
        }
    }

    hotkeys := Map()
    for name, pairs in sections {
        if (SubStr(name, 1, 7) != "hotkey.")
            continue
        hk := SubStr(name, 8)
        cfg := Map("active_window", "", "repeat", false, "actions", [])
        for pair in pairs {
            key := StrLower(pair[1]), val := pair[2]
            if (key = "active_window")
                cfg["active_window"] := val
            else if (key = "repeat")
                cfg["repeat"] := ParseIniBool(val, key)
            else if RegExMatch(key, "^action\d+$")
                cfg["actions"].Push(ParseIniAction(val))
        }
        hotkeys[hk] := cfg
    }

    return Map("settings", settings, "hotkeys", hotkeys)
}


ParseIniAction(text) {
    text := Trim(text)
    sp := InStr(text, " ")
    verb := StrLower(sp ? SubStr(text, 1, sp - 1) : text)
    rest := sp ? Trim(SubStr(text, sp + 1)) : ""

    switch verb {
        case "key_down", "down":
            return Map("key_down", NeedValue(rest, verb))
        case "key_up", "up":
            return Map("key_up", NeedValue(rest, verb))
        case "sleep":
            return Map("sleep", ParseIniInt(rest, "sleep"))
        case "tap":
            parts := Words(rest)
            if (parts.Length < 1 || parts.Length > 2)
                throw Error("tap 格式应为: tap 键名 [hold毫秒]")
            action := Map("tap", parts[1])
            if (parts.Length = 2)
                action["hold"] := ParseIniInt(parts[2], "tap hold")
            return action
        case "send":
            return Map("send", rest)
    }
    throw Error("未知 action: " text)
}


Words(text) {
    out := []
    for word in StrSplit(Trim(text), " ") {
        if (word != "")
            out.Push(word)
    }
    return out
}


NeedValue(value, name) {
    if (value = "")
        throw Error(name " 缺少值")
    return value
}


ParseIniBool(value, name) {
    switch StrLower(value) {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
    }
    throw Error(name " 必须是 true/false")
}


ParseIniInt(value, name) {
    if !RegExMatch(value, "i)^(0x[0-9a-f]+|\d+)$")
        throw Error(name " 必须是非负整数")
    return Integer(value)
}


Unquote(value) {
    if (StrLen(value) >= 2 && SubStr(value, 1, 1) = '"' && SubStr(value, -1) = '"')
        return SubStr(value, 2, StrLen(value) - 2)
    return value
}


DefaultConfig() {
    return Map(
        "settings", Map(
            "backend",   "sendinput",   ; sendinput | interception
            "pause_key", "F8",          ; 暂停/恢复
            "exit_key",  "^!x",         ; 退出 (Ctrl+Alt+X)
            "ask_admin", true,
            "require_admin", false,
            ; 只有 backend=interception 时才用到，用 AHI 的 Monitor 工具查：
            "interception_vid", 0x0000,
            "interception_pid", 0x0000
        ),

        "hotkeys", Map(
            "Numpad1", Map(
                "active_window", "psobbw.exe",
                "repeat", false,
                "actions", [
                    Map("key_down", "Down"),
                    Map("sleep", 50),
                    Map("key_up", "Down"),
                    Map("sleep", 100),
                    Map("key_down", "Left"),
                    Map("sleep", 50),
                    Map("key_up", "Left"),
                    Map("sleep", 100),
                    Map("key_down", "Left"),
                    Map("sleep", 50),
                    Map("key_up", "Left")
                ]
            )

            ; 再加热键就照抄上面一段，例如用 tap 简写（按下并在 hold 毫秒后松开）：
            ; , "Numpad2", Map(
            ;     "active_window", "",
            ;     "repeat", false,
            ;     "actions", [
            ;         Map("tap", "Left", "hold", 50),
            ;         Map("sleep", 100),
            ;         Map("tap", "Left", "hold", 50)
            ;     ]
            ; )
        )
    )
}
