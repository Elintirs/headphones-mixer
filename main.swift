// Мини-утилита в строке меню: громкость отдельно по устройствам вывода
// и общий выход «Обе гарнитуры» на все подключённые Bluetooth-наушники.
import AppKit
import AudioToolbox
import CoreAudio
import ServiceManagement

let aggUID = "io.github.elintirs.headphones-mixer.both"
/// UID из первых версий: такой выход удаляем и собираем заново под новым UID.
let legacyAggUIDs = ["claude.multiout.both-headphones"]
let aggName = "Обе гарнитуры"
let system = AudioObjectID(kAudioObjectSystemObject)

// MARK: - Core Audio

func addr(_ sel: AudioObjectPropertySelector,
          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
}

func allDevices() -> [AudioObjectID] {
    var a = addr(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids)
    return ids
}

func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let v = value else { return "" }
    return v.takeRetainedValue() as String
}

func uint32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
    var a = addr(sel)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var v: UInt32 = 0
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
    return v
}

func outputChannels(_ id: AudioObjectID) -> Int {
    var a = addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, buf) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

struct Device {
    let id: AudioObjectID
    let name: String
    let uid: String
    let transport: UInt32
    var isAggregate: Bool { transport == kAudioDeviceTransportTypeAggregate }
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
}

func outputDevices() -> [Device] {
    allDevices()
        .filter { outputChannels($0) > 0 }
        .map { Device(id: $0,
                      name: string($0, kAudioObjectPropertyName),
                      uid: string($0, kAudioDevicePropertyDeviceUID),
                      transport: uint32($0, kAudioDevicePropertyTransportType)) }
}

func defaultOutput() -> AudioObjectID {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var id: AudioObjectID = 0
    AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id)
    return id
}

func setDefaultOutput(_ id: AudioObjectID) {
    for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
        var a = addr(sel)
        var v = id
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &v)
    }
}

// Громкость: сначала «виртуальная общая» (как у системного регулятора),
// если устройство её не умеет, то по каналам 0/1/2.
func volume(_ id: AudioObjectID) -> Float? {
    var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    var v: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    if AudioObjectHasProperty(id, &a),
       AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr { return v }
    for ch: UInt32 in [0, 1, 2] {
        var c = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, ch)
        size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(id, &c), AudioObjectGetPropertyData(id, &c, 0, nil, &size, &v) == noErr { return v }
    }
    return nil
}

func setVolume(_ id: AudioObjectID, _ value: Float) {
    var v = Float32(max(0, min(1, value)))
    var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    if AudioObjectHasProperty(id, &a),
       AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr { return }
    for ch: UInt32 in [0, 1, 2] {
        var c = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, ch)
        if AudioObjectHasProperty(id, &c) {
            AudioObjectSetPropertyData(id, &c, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }
}

func isMuted(_ id: AudioObjectID) -> Bool {
    var a = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    guard AudioObjectHasProperty(id, &a) else { return false }
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
    return v != 0
}

func setMuted(_ id: AudioObjectID, _ muted: Bool) {
    var a = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    guard AudioObjectHasProperty(id, &a) else { return }
    var v: UInt32 = muted ? 1 : 0
    AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
}

// MARK: - Общий выход

let prefs = UserDefaults.standard
/// Повышенная устойчивость: буфер 1024 кадра вместо 512 (меньше прерываний, +~12 мс задержки).
var stableBuffer: Bool {
    get { prefs.bool(forKey: "stableBuffer") }
    set { prefs.set(newValue, forKey: "stableBuffer") }
}
/// Ручная подстройка: на сколько мс задержать конкретную гарнитуру, чтобы совпасть со второй.
func extraDelayMs(_ uid: String) -> Int { prefs.integer(forKey: "delay." + uid) }
func setExtraDelayMs(_ uid: String, _ ms: Int) { prefs.set(ms, forKey: "delay." + uid) }

func setNominalRate(_ id: AudioObjectID, _ rate: Double) {
    var a = addr(kAudioDevicePropertyNominalSampleRate)
    var cur: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cur)
    guard cur != rate else { return }
    var v = Float64(rate)
    AudioObjectSetPropertyData(id, &a, 0, nil, size, &v)
}

/// Пересобирает «Обе гарнитуры» из всех подключённых Bluetooth-выходов и делает его выходом по умолчанию.
/// Эталонные часы берутся с динамиков мака (стабильный аппаратный генератор), а все гарнитуры
/// подстраиваются под них с максимальным качеством компенсации дрейфа. Сами динамики при этом не звучат.
@discardableResult
func rebuildMultiOutput(makeDefault: Bool = true) -> String? {
    let devices = outputDevices()
    for d in devices where d.uid == aggUID || legacyAggUIDs.contains(d.uid) { AudioHardwareDestroyAggregateDevice(d.id) }
    let bt = devices.filter { $0.isBluetooth }
    guard bt.count >= 2 else { return "Нужно минимум две подключённые Bluetooth-гарнитуры" }

    let rate = 44100.0 // родная частота A2DP, чтобы гарнитуры не пересэмплировали
    let clock = devices.first { $0.isBuiltIn }
    if let clock { setNominalRate(clock.id, rate) }

    var desc: [String: Any] = [
        kAudioAggregateDeviceNameKey: aggName,
        kAudioAggregateDeviceUIDKey: aggUID,
        kAudioAggregateDeviceIsStackedKey: 1,
        kAudioAggregateDeviceSubDeviceListKey: bt.map { d in
            [kAudioSubDeviceUIDKey: d.uid,
             kAudioSubDeviceDriftCompensationKey: 1,
             kAudioSubDeviceDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality,
             kAudioSubDeviceExtraOutputLatencyKey: Int(Double(extraDelayMs(d.uid)) * rate / 1000)] as [String: Any]
        },
    ]
    if let clock { desc[kAudioAggregateDeviceClockDeviceKey] = clock.uid }
    else { desc[kAudioAggregateDeviceMainSubDeviceKey] = bt[0].uid }

    var agg: AudioObjectID = 0
    let err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg)
    guard err == noErr else { return "Не удалось создать общий выход (код \(err))" }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
        setNominalRate(agg, rate)
        var b = addr(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeOutput)
        var frames: UInt32 = stableBuffer ? 1024 : 512
        AudioObjectSetPropertyData(agg, &b, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        if makeDefault { setDefaultOutput(agg) }
    }
    return nil
}

// MARK: - UI

final class VolumeRow: NSView {
    let deviceID: AudioObjectID
    let slider = NSSlider()
    let muteButton = NSButton()
    let percent = NSTextField(labelWithString: "")

    init(device: Device, isDefault: Bool) {
        deviceID = device.id
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 50))

        let icon = NSImageView()
        let symbol = device.isBluetooth ? "headphones" : device.isBuiltIn ? "laptopcomputer" : "hifispeaker"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: device.name)
        title.font = .systemFont(ofSize: 13, weight: isDefault ? .semibold : .regular)
        title.lineBreakMode = .byTruncatingTail

        percent.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percent.textColor = .secondaryLabelColor
        percent.alignment = .right

        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)

        muteButton.isBordered = false
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.toolTip = "Выключить / включить звук"

        for v in [icon, title, percent, slider, muteButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            title.trailingAnchor.constraint(lessThanOrEqualTo: percent.leadingAnchor, constant: -6),
            percent.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percent.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            percent.widthAnchor.constraint(equalToConstant: 40),
            muteButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            muteButton.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 20),
            slider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 4),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let v = volume(deviceID)
        slider.isEnabled = v != nil
        slider.floatValue = v ?? 0
        let muted = isMuted(deviceID)
        percent.stringValue = v == nil ? "—" : muted ? "выкл" : "\(Int(((v ?? 0) * 100).rounded()))%"
        let symbol = muted ? "speaker.slash.fill" : (v ?? 0) < 0.01 ? "speaker.fill" : (v ?? 0) < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
        muteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @objc func changed() {
        if isMuted(deviceID) { setMuted(deviceID, false) }
        setVolume(deviceID, slider.floatValue)
        refresh()
    }

    @objc func toggleMute() {
        setMuted(deviceID, !isMuted(deviceID))
        refresh()
    }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Громкость наушников")
        menu.delegate = self
        statusItem.menu = menu
        // Старый общий выход мог быть собран с другими настройками: пересобираем по текущим.
        let devices = outputDevices()
        if let agg = devices.first(where: { $0.uid == aggUID || legacyAggUIDs.contains($0.uid) }) {
            rebuildMultiOutput(makeDefault: agg.id == defaultOutput())
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { build() }

    func build() {
        menu.removeAllItems()
        let devices = outputDevices()
        let current = defaultOutput()
        let physical = devices.filter { !$0.isAggregate }
            .sorted { ($0.isBluetooth ? 0 : 1, $0.name) < ($1.isBluetooth ? 0 : 1, $1.name) }

        menu.addItem(header("Громкость"))
        for d in physical {
            let item = NSMenuItem()
            item.view = VolumeRow(device: d, isDefault: d.id == current)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(header("Куда идёт звук"))
        for d in devices.sorted(by: { ($0.isAggregate ? 0 : 1, $0.name) < ($1.isAggregate ? 0 : 1, $1.name) }) {
            let item = NSMenuItem(title: d.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(d.id)
            item.state = d.id == current ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let rebuild = NSMenuItem(title: "Собрать «\(aggName)» из подключённых", action: #selector(rebuild), keyEquivalent: "")
        rebuild.target = self
        menu.addItem(rebuild)
        let sync = NSMenuItem(title: "Синхронизация", action: nil, keyEquivalent: "")
        let syncMenu = NSMenu()
        let stable = NSMenuItem(title: "Без пролагов (буфер побольше, +12 мс)", action: #selector(toggleStable), keyEquivalent: "")
        stable.target = self
        stable.state = stableBuffer ? .on : .off
        syncMenu.addItem(stable)
        syncMenu.addItem(.separator())
        for d in physical where d.isBluetooth {
            let item = NSMenuItem(title: "Задержать «\(d.name)»", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for ms in stride(from: 0, through: 200, by: 10) {
                let opt = NSMenuItem(title: ms == 0 ? "Без задержки" : "+\(ms) мс", action: #selector(pickDelay(_:)), keyEquivalent: "")
                opt.target = self
                opt.representedObject = d.uid
                opt.tag = ms
                opt.state = extraDelayMs(d.uid) == ms ? .on : .off
                sub.addItem(opt)
            }
            item.submenu = sub
            syncMenu.addItem(item)
        }
        sync.submenu = syncMenu
        menu.addItem(sync)
        let midi = NSMenuItem(title: "Настройка Audio-MIDI…", action: #selector(openMidi), keyEquivalent: "")
        midi.target = self
        menu.addItem(midi)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc func pick(_ sender: NSMenuItem) { setDefaultOutput(AudioObjectID(sender.tag)) }

    @objc func rebuild() {
        if let error = rebuildMultiOutput() {
            let alert = NSAlert()
            alert.messageText = error
            alert.runModal()
        }
    }

    @objc func toggleStable() {
        stableBuffer.toggle()
        rebuild()
    }

    @objc func pickDelay(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        setExtraDelayMs(uid, sender.tag)
        rebuild()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось изменить автозапуск"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func openMidi() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
