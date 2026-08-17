// Renders an emoji onto a transparent square canvas and writes it as a PNG.
// Run with `swift` (not compiled): swift make_icon.swift <emoji> <out.png>
// install.sh feeds the output through sips/iconutil to build an .icns.

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_icon.swift <emoji> <out.png>\n".data(using: .utf8)!)
    exit(64)
}
let emoji = args[1]
let outputPath = args[2]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let font = NSFont.systemFont(ofSize: size * 0.75)
let str = NSAttributedString(string: emoji, attributes: [.font: font])
let strSize = str.size()
let point = NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2)
str.draw(at: point)
image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
