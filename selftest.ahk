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
BadConfig(action) => Map("hotkeys", Map("Numpad1", [Map("actions", [action])]))

RunSelfTest()

RunSelfTest() {
    global Backend, Config

    ; 1. 热键名 -> KeyWait 基础键名
    Assert(BaseKey("Numpad1")   = "Numpad1", "BaseKey Numpad1")
    Assert(BaseKey("^!x")       = "x",       "BaseKey ^!x -> x")
    Assert(BaseKey("~*Numpad1") = "Numpad1", "BaseKey ~*Numpad1 -> Numpad1")
    Assert(ParseHotIf('WinActive("target.exe")') = "target.exe", "HotIf WinActive exe 简写")

    ; 2. 脚本读进来了
    cfg := Config["hotkeys"]["Numpad0"][1]
    Assert(cfg["active_window"] = "target.exe", "config active_window")
    Assert(cfg["repeat"] = false,               "config repeat=false")

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
    Assert(IsRealKey("Numpad1") && IsRealKey("NumpadEnd") && IsRealKey("Left"), "合法键名通过")
    Assert(!IsRealKey("Downn") && !IsRealKey(""), "非法键名被拒")

    ; 9. 启动时校验：好配置放行，坏配置必须炸
    threw := false
    try ValidateConfig(Config)
    catch
        threw := true
    Assert(!threw, "真实脚本通过校验")

    Assert(Throws(() => ValidateConfig(Map("hotkeys", Map()))), "空 hotkeys 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("key_down", "Downn")))), "键名拼错被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("sleep", -5)))),         "负数 sleep 被拒")
    Assert(Throws(() => ValidateConfig(BadConfig(Map("bogus", 1)))),          "未知 action 被拒")
    Assert(!Throws(() => ValidateConfig(BadConfig(Map("tap", "Left")))),      "合法 tap 通过")

    multiApp := Map("hotkeys", Map("Numpad1", [
        Map("active_window", "one.exe", "actions", [Map("tap", "a")]),
        Map("active_window", "two.exe", "actions", [Map("tap", "b")])
    ]))
    Assert(!Throws(() => ValidateConfig(multiApp)), "同一热键可按不同 App 分发")

    duplicateApp := Map("hotkeys", Map("Numpad1", [
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

    Say("`nALL PASS")
    ExitApp(0)
}
