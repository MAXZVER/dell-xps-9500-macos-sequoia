// displayfix — вернуть картинку на внутреннюю панель, когда она горит, но чёрная.
//
// Симптом: при подключении внешнего монитора внутренняя панель остаётся
// включённой (подсветка регулируется, система считает экран активным и
// расширяет на него рабочий стол), но изображения на ней нет. То есть
// отваливается именно вывод, а не дисплей.
//
// Лечение: заставить систему заново задать видеорежим внутренней панели —
// переключить её на другой режим и тут же вернуть обратно.
//
//   displayfix            встряхнуть внутреннюю панель прямо сейчас
//   displayfix --list     показать все экраны и их режимы
//   displayfix --watch    следить и встряхивать сама при смене состава экранов

import Foundation
import CoreGraphics

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    print("\(f.string(from: Date())) \(s)")
    fflush(stdout)
}

func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func describe(_ d: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(d)
    let kind = CGDisplayIsBuiltin(d) != 0 ? "встроенный" : "внешний"
    let mode = CGDisplayCopyDisplayMode(d)
    let mw = mode?.pixelWidth ?? 0, mh = mode?.pixelHeight ?? 0
    return "id=\(d) \(kind) \(Int(b.width))x\(Int(b.height)) @(\(Int(b.origin.x)),\(Int(b.origin.y))) режим \(mw)x\(mh) активен=\(CGDisplayIsActive(d) != 0) спит=\(CGDisplayIsAsleep(d) != 0) онлайн=\(CGDisplayIsOnline(d) != 0)"
}

func modes(_ d: CGDirectDisplayID) -> [CGDisplayMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    return (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode]) ?? []
}

@discardableResult
func setMode(_ d: CGDirectDisplayID, _ m: CGDisplayMode) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
    return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
}

/// Переключить внутреннюю панель на другой режим и вернуть обратно.
func nudgeBuiltin() {
    guard let builtin = activeDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
        log("встроенной панели среди активных экранов нет"); return
    }
    guard let cur = CGDisplayCopyDisplayMode(builtin) else {
        log("не смог прочитать текущий режим встроенной панели"); return
    }
    let all = modes(builtin)
    // берём любой режим с другим разрешением — переключение туда и обратно
    // заставляет драйвер заново поднять вывод
    guard let other = all.first(where: { $0.pixelWidth != cur.pixelWidth || $0.pixelHeight != cur.pixelHeight }) else {
        log("нет второго режима, встряхнуть нечем"); return
    }
    log("встряхиваю: \(cur.pixelWidth)x\(cur.pixelHeight) -> \(other.pixelWidth)x\(other.pixelHeight) -> обратно")
    setMode(builtin, other)
    Thread.sleep(forTimeInterval: 1.2)
    let ok = setMode(builtin, cur)
    log(ok ? "режим возвращён" : "не удалось вернуть режим — задайте разрешение вручную в Настройках")
}

var pendingNudge = false      // глобально: C-функция обратного вызова не может захватывать контекст

let args = CommandLine.arguments

if args.contains("--list") {
    for d in activeDisplays() {
        print(describe(d))
        let ms = modes(d)
        let uniq = Array(Set(ms.map { "\($0.pixelWidth)x\($0.pixelHeight)" })).sorted()
        print("    режимов: \(ms.count) — \(uniq.joined(separator: ", "))")
    }
    exit(0)
}

// --ext 1920x1080 — задать режим внешнему монитору.
// Нужно, чтобы проверить версию про нехватку ресурсов: если внутренняя панель
// оживает, когда внешний работает в меньшем разрешении, значит вдвоём они не
// помещаются в лимиты (частота Core Display Clock либо выделенная видеопамять).
if let i = args.firstIndex(of: "--ext"), i + 1 < args.count {
    let want = args[i + 1].lowercased().split(separator: "x").compactMap { Int($0) }
    guard want.count == 2,
          let ext = activeDisplays().first(where: { CGDisplayIsBuiltin($0) == 0 }) else {
        log("нужен внешний экран и размер вида --ext 1920x1080"); exit(1)
    }
    let cands = modes(ext).filter { $0.pixelWidth == want[0] && $0.pixelHeight == want[1] }
    guard let m = cands.max(by: { $0.refreshRate < $1.refreshRate }) else {
        log("у внешнего нет режима \(want[0])x\(want[1])"); exit(1)
    }
    log("внешний -> \(m.pixelWidth)x\(m.pixelHeight) @ \(Int(m.refreshRate)) Гц")
    log(setMode(ext, m) ? "применено" : "не применилось")
    for d in activeDisplays() { log(describe(d)) }
    exit(0)
}

// --main ext | int — сделать выбранный экран главным (строка меню, новые окна).
// Когда внутренняя панель чёрная, а главной остаётся она, до терминала не
// добраться: окна открываются на невидимом экране.
if let i = args.firstIndex(of: "--main"), i + 1 < args.count {
    let all = activeDisplays()
    let wantExt = args[i + 1].hasPrefix("e")
    guard let target = all.first(where: { (CGDisplayIsBuiltin($0) == 0) == wantExt }),
          let other = all.first(where: { $0 != target }) else {
        log("нужны оба экрана"); exit(1)
    }
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { log("не смог начать"); exit(1) }
    CGConfigureDisplayOrigin(cfg, target, 0, 0)
    CGConfigureDisplayOrigin(cfg, other, Int32(CGDisplayPixelsWide(target)), 0)
    let ok = CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    log(ok ? "главный экран -> \(wantExt ? "внешний" : "встроенный")" : "не применилось")
    for d in activeDisplays() { log(describe(d)) }
    exit(0)
}

// --mirror on|off — дублирование экранов.
// Пользователь заметил, что в дублировании чёрная панель оживает. В этом режиме
// оба экрана берут картинку с одного конвейера, в расширенном — с разных.
if let i = args.firstIndex(of: "--mirror"), i + 1 < args.count {
    let all = onlineDisplays()
    guard let builtin = all.first(where: { CGDisplayIsBuiltin($0) != 0 }),
          let ext = all.first(where: { CGDisplayIsBuiltin($0) == 0 }) else {
        log("нужны оба экрана"); exit(1)
    }
    let on = args[i + 1].hasPrefix("on")
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { log("не смог начать"); exit(1) }
    CGConfigureDisplayMirrorOfDisplay(cfg, ext, on ? builtin : kCGNullDirectDisplay)
    let ok = CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    log(ok ? "дублирование \(on ? "включено" : "выключено")" : "не применилось")
    Thread.sleep(forTimeInterval: 2.0)
    for d in activeDisplays() { log(describe(d)) }
    exit(0)
}

// --autofix — сторож. Опрашивает состав экранов и, когда он меняется,
// прогоняет цикл «усыпить дисплеи — разбудить».
//
// Зачем именно так. Горячее подключение монитора и пробуждение после сна
// дисплеев идут в драйвере РАЗНЫМИ путями. Первый роняет вывод на встроенную
// панель: она остаётся включённой, подсветка горит, система рисует в неё
// рабочий стол — а картинки нет. Второй отрабатывает правильно и чинит всё,
// включая последующее отключение монитора. Проверено вручную.
//
// Уведомления CGDisplayRegisterReconfigurationCallback в этом окружении до
// процесса не доходят, поэтому опрос, а не подписка.
func run(_ path: String, _ cmdArgs: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = cmdArgs
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}

if args.contains("--autofix") {
    log("сторож запущен: слежу за составом экранов и за пробуждением")
    var known = onlineDisplays().count
    var lastTick = Date()
    log("сейчас экранов: \(known)")
    while true {
        Thread.sleep(forTimeInterval: 2.0)
        let now = onlineDisplays().count

        // Разрыв во времени между двумя проверками означает, что машина спала.
        // После пробуждения вывод на панель может не подняться — тот же дефект,
        // что и при горячем подключении монитора. Лечим тем же циклом.
        let gap = Date().timeIntervalSince(lastTick)
        lastTick = Date()
        let wokeUp = gap > 10.0

        if now == known && !wokeUp { continue }
        if wokeUp { log(String(format: "похоже, машина спала: разрыв %.0f с", gap)) }
        else { log("состав экранов изменился: \(known) -> \(now)") }
        known = now
        guard now > 0 else { continue }
        Thread.sleep(forTimeInterval: 3.0)       // дать системе доподнять режим
        log("усыпляю дисплеи")
        run("/usr/bin/pmset", ["displaysleepnow"])
        Thread.sleep(forTimeInterval: 3.0)
        log("бужу")
        run("/usr/bin/caffeinate", ["-u", "-t", "3"])
        Thread.sleep(forTimeInterval: 8.0)       // переждать вызванную нами же перенастройку
        known = onlineDisplays().count
        lastTick = Date()
        for d in onlineDisplays() { log("   " + describe(d)) }
        log("готово, экранов: \(known)")
    }
}

if args.contains("--watch") {
    log("слежу за составом экранов; при изменении встряхну встроенную панель")
    let cb: CGDisplayReconfigurationCallBack = { _, flags, _ in
        let interesting: CGDisplayChangeSummaryFlags = [.addFlag, .removeFlag, .disabledFlag, .enabledFlag, .setModeFlag]
        guard !flags.intersection(interesting).isEmpty else { return }
        guard !flags.contains(.beginConfigurationFlag) else { return }
        if pendingNudge { return }
        pendingNudge = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            log("состав экранов изменился")
            for d in activeDisplays() { log("   " + describe(d)) }
            nudgeBuiltin()
            pendingNudge = false
        }
    }
    CGDisplayRegisterReconfigurationCallback(cb, nil)
    for d in activeDisplays() { log("сейчас: " + describe(d)) }
    CFRunLoopRun()
}

for d in activeDisplays() { log(describe(d)) }
nudgeBuiltin()
