import AppKit

// Renders the 1024px app icon: white eye.fill on a dark gradient, inside Apple's 824px icon grid.
let canvas: CGFloat = 1024, tile: CGFloat = 824, radius: CGFloat = 185, symbolSize: CGFloat = 430

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    let inset = (canvas - tile) / 2
    let rect = NSRect(x: inset, y: inset, width: tile, height: tile)
    NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.36, alpha: 1),
               ending: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.14, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let eye = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    eye.draw(in: NSRect(x: (canvas - eye.size.width) / 2, y: (canvas - eye.size.height) / 2,
                        width: eye.size.width, height: eye.size.height))
    return true
}

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
