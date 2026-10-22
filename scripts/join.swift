// Joins clips into one MP4, fitted inside 1920x1080 (portrait phone video stays ~500x1080; no ffmpeg needed).
// Usage: swift join.swift <out.mp4> <clip.mp4>...
import AVFoundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: join.swift <out.mp4> <clips...>"); exit(2) }
let out = URL(fileURLWithPath: args[0])
let done = DispatchSemaphore(value: 0)
var failed = false

Task {
  do {
    let comp = AVMutableComposition()
    guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(domain: "join", code: 1)
    }
    var cursor = CMTime.zero
    for path in args.dropFirst() {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      // a clip without video is a broken recording: fail rather than publish a video missing a step
      guard let src = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(domain: "join: no video track in \(path)", code: 3)
      }
      let duration = try await asset.load(.duration)
      if cursor == .zero { track.preferredTransform = try await src.load(.preferredTransform) }
      try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: src, at: cursor)
      cursor = cursor + duration
    }
    try? FileManager.default.removeItem(at: out)
    guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset1920x1080) else {
      throw NSError(domain: "join", code: 2)
    }
    try await export.export(to: out, as: .mp4)
    print("video: \(out.path) (\(String(format: "%.1f", CMTimeGetSeconds(cursor)))s)")
  } catch {
    print("join failed: \(error.localizedDescription) (\(out.path))")
    failed = true
  }
  done.signal()
}
done.wait()
exit(failed ? 1 : 0)
