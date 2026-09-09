// Renders the menu bar's SF Symbol "dog" in each mood colour, for the README mock.
import AppKit

let colours: [(String, NSColor)] = [
    ("quiet", NSColor(white: 0.91, alpha: 1)),
    ("working", NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1)),
    ("needs", NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)),
    ("done", NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)),
    ("limited", NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)),
]
let symbol = NSImage(systemSymbolName: "dog", accessibilityDescription: nil)!
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: .regular))!
for (name, tint) in colours {
    let size = NSSize(width: 96, height: 96)
    let image = NSImage(size: size, flipped: false) { rect in
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        tint.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let origin = NSPoint(x: (rect.width - tinted.size.width) / 2, y: (rect.height - tinted.size.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        return true
    }
    let tiff = image.tiffRepresentation!
    let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "docs/media/dog/\(name).png"))
}
