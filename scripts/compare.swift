// Puts the design frame (left) and the app screenshot (right) side by side at the same height, to compare in one look.
// Usage: swift compare.swift <design.png> <shot.png> <out.png>
import AppKit

let a = CommandLine.arguments
guard a.count == 4 else { print("usage: compare.swift <design.png> <shot.png> <out.png>"); exit(2) }
guard let d = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let s = NSImage(contentsOfFile: a[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { print("compare: can't read \(a[1]) or \(a[2])"); exit(1) }

// both scaled to 1600 px high (a 3x phone shot is ~2500): readable and small enough to Read
let h = 1600.0, gap = 24.0
let dw = Double(d.width) * h / Double(d.height), sw = Double(s.width) * h / Double(s.height)
guard let ctx = CGContext(data: nil, width: Int(dw + gap + sw), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }
ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1)) // magenta gap: never mistaken for UI
ctx.fill(CGRect(x: 0, y: 0, width: dw + gap + sw, height: h))
ctx.interpolationQuality = .high
ctx.draw(d, in: CGRect(x: 0, y: 0, width: dw, height: h))
ctx.draw(s, in: CGRect(x: dw + gap, y: 0, width: sw, height: h))
guard let img = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]),
      (try? png.write(to: URL(fileURLWithPath: a[3]))) != nil
else { print("compare: can't write \(a[3])"); exit(1) }
print(a[3])
