; ============================================================
;  Backends.ahk  —  可替换的输入后端
;  接口: KeyDown(key) / KeyUp(key) / Tap(key, holdMs) / ReleaseAll()
;  所有后端自己记录按下的键，异常或退出时统一松开。
; ============================================================

class IInputBackend {
    __New() {
        this.held := Map()
    }

    ; 子类必须覆盖这两个
    KeyDown(key) => this._abstract()
    KeyUp(key)   => this._abstract()

    Tap(key, holdMs := 50) {
        this.KeyDown(key)
        Sleep(holdMs)
        this.KeyUp(key)
    }

    ; 松开所有还按着的键。Clone() 是因为 KeyUp 会改 held。
    ReleaseAll() {
        for key in this.held.Clone() {
            try this.KeyUp(key)
        }
        this.held.Clear()
    }

    _abstract() {
        throw Error("后端未实现该方法")
    }
}


; ------------------------------------------------------------
;  A. SendInput 后端 —— Win32 SendInput，零依赖，兼容性最好
; ------------------------------------------------------------
class SendInputBackend extends IInputBackend {
    KeyDown(key) {
        SendInput("{" key " down}")
        this.held[key] := true
    }

    KeyUp(key) {
        SendInput("{" key " up}")
        this.held.Delete(key)
    }
}


; ------------------------------------------------------------
;  B. Interception 后端 —— 驱动层键盘输入
;  需要: 1) 安装 Interception 驱动
;        2) lib\AutoHotInterception\ 放好 AHI
;        3) config.ahk 填 interception_vid / interception_pid
;  说明见 README「Interception 后端」一节。
; ------------------------------------------------------------
class InterceptionBackend extends IInputBackend {
    __New(settings) {
        super.__New()

        if !IsSet(AutoHotInterception)
            throw Error("找不到 AutoHotInterception。请把 AHI 解压到 lib\AutoHotInterception\")

        this.AHI := AutoHotInterception()

        vid := settings.Has("interception_vid") ? settings["interception_vid"] : 0
        pid := settings.Has("interception_pid") ? settings["interception_pid"] : 0
        if (!vid || !pid)
            throw Error("请先在 config.ahk 填 interception_vid / interception_pid（用 AHI 的 Monitor.ahk 查）")

        this.id := this.AHI.GetKeyboardId(vid, pid)
        if !this.id
            throw Error(Format("按 VID=0x{:04X} PID=0x{:04X} 找不到键盘设备", vid, pid))
    }

    ; GetKeySC() 是 AHK 内建函数，把键名转成扫描码。
    ; 扩展键(方向键等)返回值带 0x100 位，AHI 会转成 E0 扩展标志。
    ;
    ; 注意：扫描码分不出 NumLock 状态。GetKeySC("Numpad1") 和
    ; GetKeySC("NumpadEnd") 都是 0x4F（同一个物理键），发出去之后
    ; 到底是 "1" 还是 "End" 取决于目标机器当时的 NumLock。
    ; SendInput 后端发的是 VK，没这个问题。详见 README。
    KeyDown(key) {
        this.AHI.SendKeyEvent(this.id, GetKeySC(key), 1)
        this.held[key] := true
    }

    KeyUp(key) {
        this.AHI.SendKeyEvent(this.id, GetKeySC(key), 0)
        this.held.Delete(key)
    }
}
