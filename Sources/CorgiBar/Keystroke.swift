import Foundation
import ApplicationServices

/// A chord like "ctrl+y" turned into one key press through CGEvent. Needs
/// Accessibility for the app that posts it.
struct Chord: Equatable {
    var keyCode: CGKeyCode
    var flags: CGEventFlags

    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50, "space": 49, "enter": 36, "return": 36, "tab": 48, "escape": 53, "esc": 53, "backspace": 51,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    static func parse(_ text: String) -> Chord? {
        var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let key = parts.popLast(), let code = keyCodes[key] else { return nil }
        var flags = CGEventFlags()
        for part in parts {
            switch part {
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            default: return nil
            }
        }
        return Chord(keyCode: code, flags: flags)
    }

    enum SendError: Error { case notTrusted, badChord }

    /// Press and release the chord in whatever window is in front.
    static func send(_ text: String) throws {
        guard let chord = parse(text) else { throw SendError.badChord }
        guard AXIsProcessTrusted() else { throw SendError.notTrusted }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: false) else {
            throw SendError.badChord
        }
        down.flags = chord.flags
        up.flags = chord.flags
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }
}
