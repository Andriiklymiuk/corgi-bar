import Carbon
import Foundation

/// Global hotkeys through Carbon's RegisterEventHotKey: they work without
/// Accessibility, which is why the bar uses them rather than an event tap.
/// One handler serves every key; each key has its own id.
final class HotKey {
    struct Preset: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var keyCode: UInt32
        var modifiers: UInt32
    }

    static let presets: [Preset] = [
        Preset(name: "ctrl+alt+space", keyCode: 49, modifiers: UInt32(controlKey | optionKey)),
        Preset(name: "ctrl+alt+t", keyCode: 17, modifiers: UInt32(controlKey | optionKey)),
        Preset(name: "ctrl+alt+p", keyCode: 35, modifiers: UInt32(controlKey | optionKey)),
        Preset(name: "ctrl+alt+n", keyCode: 45, modifiers: UInt32(controlKey | optionKey)),
        Preset(name: "cmd+shift+t", keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)),
        Preset(name: "cmd+shift+p", keyCode: 35, modifiers: UInt32(cmdKey | shiftKey)),
        Preset(name: "f13", keyCode: 105, modifiers: 0),
        Preset(name: "f14", keyCode: 107, modifiers: 0),
        Preset(name: "off", keyCode: 0, modifiers: 0),
    ]

    static func preset(named name: String) -> Preset? {
        presets.first { $0.name == name }
    }

    private var ref: EventHotKeyRef?
    private let id: UInt32
    private let action: () -> Void

    private static var registry: [UInt32: HotKey] = [:]
    private static var handler: EventHandlerRef?
    private static var nextId: UInt32 = 1

    init(action: @escaping () -> Void) {
        self.action = action
        id = HotKey.nextId
        HotKey.nextId += 1
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyId = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
            HotKey.registry[hotKeyId.id]?.action()
            return noErr
        }, 1, &spec, nil, &handler)
    }

    func register(_ preset: Preset) {
        unregister()
        guard preset.name != "off" else { return }
        HotKey.installHandler()
        HotKey.registry[id] = self
        let hotKeyId = EventHotKeyID(signature: OSType(0x43524749), id: id) // "CRGI"
        RegisterEventHotKey(preset.keyCode, preset.modifiers, hotKeyId, GetApplicationEventTarget(), 0, &ref)
    }

    func register(named name: String) {
        if let preset = HotKey.preset(named: name) { register(preset) } else { unregister() }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        HotKey.registry[id] = nil
    }
}
