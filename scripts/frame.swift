// Saves one frame of a video as PNG, to check a recording isn't blank.
// Usage: swift frame.swift <video.mp4> <seconds> <out.png>
import AVFoundation
import AppKit

let a = CommandLine.arguments
guard a.count == 4 else { print("usage: frame.swift <video.mp4> <seconds> <out.png>"); exit(2) }
let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: a[1])))
gen.appliesPreferredTrackTransform = true
let done = DispatchSemaphore(value: 0)
var failed = false
Task {
  do {
    let (img, _) = try await gen.image(at: CMTime(seconds: Double(a[2]) ?? 1, preferredTimescale: 600))
    guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
      throw NSError(domain: "frame: PNG encoding failed", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: a[3]))
    print("frame: \(a[3])")
  } catch { print("frame failed: \(error)"); failed = true }
  done.signal()
}
done.wait()
exit(failed ? 1 : 0)
