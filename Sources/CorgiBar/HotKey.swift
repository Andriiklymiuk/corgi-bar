import Carbon
import Foundation

/// One global hotkey through Carbon's RegisterEventHotKey: works without
/// Accessibility, which is why the bar uses it rather than an event tap.
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
        Preset(name: "cmd+shift+t", keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)),
        Preset(name: "f13", keyCode: 105, modifiers: 0),
        Preset(name: "off", keyCode: 0, modifiers: 0),
    ]

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var current: HotKey?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(_ preset: Preset) {
        unregister()
        guard preset.name != "off" else { return }
        HotKey.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.current?.action()
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x43524749), id: 1) // "CRGI"
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
