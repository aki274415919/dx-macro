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
;  Interception 驱动探测
;
;  AHI 是别人的库，我们不改它。但要知道它的失败方式：
;  AutoHotInterception.__New() 和 GetKeyboardId() 在失败时是
;  MsgBox + ExitApp，不是 throw。一旦走进去，外层的 try/catch
;  和「回退到 SendInput」全都不会执行，进程直接没了。
;
;  所以：凡是能自己查的，都在碰 AHI 之前查完。
;  驱动装没装 → 直接问 interception.dll。它是用户态 DLL，
;  没有驱动也能 LoadLibrary，但 interception_create_context() 会返回 0。
; ------------------------------------------------------------
class DriverMissingError extends Error {
}


class KeyboardNotConfiguredError extends Error {
}


; 脚本版 A_ScriptDir 是项目根，编译版是 exe 所在目录 —— AHI 两边都用 Lib\，
; 所以这一个表达式两边都对。（Windows 路径不区分大小写，lib\ 就是 Lib\）
InterceptionDir() => A_ScriptDir "\Lib"


; AHI 自己也有 FileInstall，但它发生在构造函数里；我们必须先释放资源，
; 才能在不触发 AHI 的 MsgBox + ExitApp 前提下完成文件和驱动预检。
EnsureInterceptionFiles() {
    if !A_IsCompiled
        return
    dir := InterceptionDir()
    DirCreate(dir "\x64")
    DirCreate(dir "\x86")
    FileInstall("Lib\AutoHotInterception.dll", dir "\AutoHotInterception.dll", 1)
    FileInstall("Lib\x64\interception.dll", dir "\x64\interception.dll", 1)
    FileInstall("Lib\x86\interception.dll", dir "\x86\interception.dll", 1)
}


CreateAutoHotInterception() {
    oldDir := A_WorkingDir
    try {
        SetWorkingDir(A_ScriptDir) ; AHI 的 FileInstall 目标是相对路径 Lib\
        return AutoHotInterception()
    } finally {
        SetWorkingDir(oldDir)
    }
}


InterceptionDllPath() {
    bitness := (A_PtrSize = 8) ? "x64" : "x86"
    dll := InterceptionDir() "\" bitness "\interception.dll"
    return FileExist(dll) ? dll : ""
}


; 驱动装没装。interception.dll 是用户态 DLL，没有驱动也能 LoadLibrary，
; 但 interception_create_context() 会返回 0。
InterceptionDriverPresent() {
    dll := InterceptionDllPath()
    if (dll = "")
        return false

    h := DllCall("LoadLibrary", "Str", dll, "Ptr")
    if !h
        return false

    ctx := 0
    try ctx := DllCall(dll "\interception_create_context", "Ptr")
    if ctx
        DllCall(dll "\interception_destroy_context", "Ptr", ctx)
    DllCall("FreeLibrary", "Ptr", h)
    return ctx != 0
}


; ------------------------------------------------------------
;  B. Interception 后端 —— 驱动层键盘输入
;  需要: 1) 安装 Interception 驱动（装完要重启）
;        2) lib\ 下放好 AHI（编译版会从 exe 自动释放）
;        3) 脚本里写 #InterceptionVid / #InterceptionPid
;  说明见 README「Interception 后端」一节。
; ------------------------------------------------------------
class InterceptionBackend extends IInputBackend {
    __New(settings) {
        super.__New()
        this.hotkeyScs := Map()

        ; 顺序是有意的：先查文件，再查驱动，最后才构造 AHI。
        EnsureInterceptionFiles()
        if !IsSet(AutoHotInterception)
            throw Error("找不到 AutoHotInterception.ahk，请把 AHI 放到 lib\ 下")
        if (InterceptionDllPath() = "")
            throw Error("缺少 lib\" ((A_PtrSize = 8) ? "x64" : "x86") "\interception.dll")
        if !FileExist(InterceptionDir() "\AutoHotInterception.dll")
            throw Error("缺少 lib\AutoHotInterception.dll")

        if !InterceptionDriverPresent()
            throw DriverMissingError("没有检测到 Interception 驱动。")

        vid := settings.Has("interception_vid") ? settings["interception_vid"] : 0
        pid := settings.Has("interception_pid") ? settings["interception_pid"] : 0
        instance := settings.Has("interception_instance") ? settings["interception_instance"] : 1
        if (!vid || !pid)
            throw KeyboardNotConfiguredError("脚本里没写硬输入键盘。")
        if (!IsInteger(instance) || instance < 1)
            throw KeyboardNotConfiguredError("硬输入键盘实例号无效。")

        this.AHI := CreateAutoHotInterception()

        ; 不用 AHI.GetKeyboardId()：它找不到设备时会 MsgBox + ExitApp。
        ; GetDeviceList() 只是查询，安全。
        this.id := this.FindKeyboard(vid, pid, instance)
        if !this.id
            throw KeyboardNotConfiguredError("没有找到脚本里配置的硬输入键盘。")
    }

    FindKeyboard(vid, pid, instance := 1) {
        found := 0
        for id, dev in this.AHI.GetDeviceList() {
            if (!dev.IsMouse && dev.VID = vid && dev.PID = pid) {
                found += 1
                if (found = instance)
                    return id
            }
        }
        return 0
    }

    SubscribeHotkey(key, callback) {
        sc := GetKeySC(key)
        if !sc
            throw Error("无法取得扫描码: " key)
        if this.hotkeyScs.Has(sc)
            throw Error("与 " this.hotkeyScs[sc] " 使用同一扫描码")
        this.hotkeyScs[sc] := key
        try {
            ; block=true 与普通 AHK 热键一致：触发键本身不继续传给目标程序。
            this.AHI.SubscribeKey(this.id, sc, true, callback)
        } catch as e {
            this.hotkeyScs.Delete(sc)
            throw e
        }
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
