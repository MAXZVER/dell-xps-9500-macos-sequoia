// micguard — держит вход по умолчанию на встроенном микрофоне.
//
// Зачем: AppleALC с layout-id 13 создаёт два входных движка — внутренний
// микрофон (imic) и вход с гнезда 3.5 мм (emic). Движок гнезда появляется
// примерно через 15 секунд после загрузки, позже внутреннего, и coreaudiod
// по своему правилу «последнее появившееся устройство становится основным»
// делает основным входом именно его. В гнездо ничего не воткнуто, поэтому
// все программы получают тишину. Сохранённая настройка при этом правильная —
// её просто перебивают.
//
// Внешние микрофоны (USB, Bluetooth) не трогаем: вмешиваемся только когда
// основным входом стало встроенное устройство, отличное от внутреннего микрофона.

import Foundation
import CoreAudio

let targetUID = "AppleHDAEngineInput:1F,3,0,1,0:1"   // внутренний микрофон, источник imic

func prop(_ s: AudioObjectPropertySelector,
          _ sc: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: sc, mElement: kAudioObjectPropertyElementMain)
}

func devices() -> [AudioDeviceID] {
    var a = prop(kAudioHardwarePropertyDevices); var n: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n)
    var ids = [AudioDeviceID](repeating: 0, count: Int(n) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n, &ids)
    return ids
}

func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
    var a = prop(sel); var n = UInt32(MemoryLayout<CFString?>.size); var cf: CFString? = nil
    withUnsafeMutablePointer(to: &cf) { AudioObjectGetPropertyData(id, &a, 0, nil, &n, $0) }
    return cf as String? ?? ""
}

func transport(_ id: AudioDeviceID) -> UInt32 {
    var a = prop(kAudioDevicePropertyTransportType); var v: UInt32 = 0; var n = UInt32(4)
    AudioObjectGetPropertyData(id, &a, 0, nil, &n, &v)
    return v
}

func defaultInput() -> AudioDeviceID {
    var a = prop(kAudioHardwarePropertyDefaultInputDevice); var id: AudioDeviceID = 0; var n = UInt32(4)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &n, &id)
    return id
}

func log(_ s: String) {
    let f = ISO8601DateFormatter()
    FileHandle.standardOutput.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

func enforce() {
    let cur = defaultInput()
    guard var target = devices().first(where: { string($0, kAudioDevicePropertyDeviceUID) == targetUID }) else { return }
    if cur == target { return }
    // внешний микрофон, выбранный пользователем, оставляем в покое
    if cur != 0, transport(cur) != kAudioDeviceTransportTypeBuiltIn { return }
    var a = prop(kAudioHardwarePropertyDefaultInputDevice)
    let st = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                        UInt32(MemoryLayout<AudioDeviceID>.size), &target)
    log(st == noErr
        ? "вход «\(string(cur, kAudioObjectPropertyName))» -> «\(string(target, kAudioObjectPropertyName))»"
        : "не удалось переключить вход, код \(st)")
}

log("micguard запущен, цель: \(targetUID)")

let q = DispatchQueue(label: "micguard")

// Основной механизм — опрос раз в 15 секунд. Он не зависит от того, удалось ли
// подписаться на уведомления CoreAudio, и сам по себе почти ничего не стоит.
let timer = DispatchSource.makeTimerSource(queue: q)
timer.schedule(deadline: .now() + 1, repeating: 15.0)
timer.setEventHandler { enforce() }
timer.resume()

// Дополнительно — мгновенная реакция на смену устройства, если подписка пройдёт.
for sel in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
    var a = prop(sel)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, q) { _, _ in
        q.asyncAfter(deadline: .now() + 0.5) { enforce() }
    }
}
log("подписка на уведомления оформлена")

RunLoop.main.run()
