@preconcurrency import AVFoundation
import CoreImage
import FlutterMacOS
import Foundation

private enum ComposerPluginError: LocalizedError {
  case invalidArguments
  case fileMissing(String)
  case noVideoTrack(String)
  case noAudioTrack(String)
  case invalidDuration(String)
  case exportSessionUnavailable
  case exportFailed

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "视频合成参数无效"
    case .fileMissing(let path):
      return "视频文件不存在：\(path)"
    case .noVideoTrack(let path):
      return "视频文件没有视频轨：\(path)"
    case .noAudioTrack(let path):
      return "音频文件没有音频轨：\(path)"
    case .invalidDuration(let path):
      return "视频时长无效：\(path)"
    case .exportSessionUnavailable:
      return "无法创建视频导出会话"
    case .exportFailed:
      return "视频导出失败"
    }
  }
}

private final class ExportSessionBox: @unchecked Sendable {
  let session: AVAssetExportSession

  init(_ session: AVAssetExportSession) {
    self.session = session
  }
}

private struct ComposeSegment {
  let videoPath: String
  let audioPath: String?
  let transition: String?
  let filterPreset: String?
}

private struct RenderSegment {
  let timeRange: CMTimeRange
  let transition: String?
  let filterPreset: String?
}

final class ComposerPlugin {
  private static var instance: ComposerPlugin?
  private var channel: FlutterMethodChannel?

  static func register(with controller: FlutterViewController) {
    let plugin = ComposerPlugin()
    let channel = FlutterMethodChannel(
      name: "dramaflow/composer",
      binaryMessenger: controller.engine.binaryMessenger)
    plugin.channel = channel
    channel.setMethodCallHandler(plugin.handle)
    instance = plugin
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probeDuration":
      Task {
        do {
          let path = try stringArgument(call.arguments, key: "path")
          let duration = try await probeDuration(path: path)
          result(duration)
        } catch {
          result(flutterError(error))
        }
      }
    case "inspectMedia":
      Task {
        do {
          let path = try stringArgument(call.arguments, key: "path")
          result(try await inspectMedia(path: path))
        } catch {
          result(flutterError(error))
        }
      }
    case "concat":
      Task {
        do {
          let paths = try stringArrayArgument(call.arguments, key: "paths")
          let output = try stringArgument(call.arguments, key: "output")
          try await concat(paths: paths, output: output)
          result(nil)
        } catch {
          result(flutterError(error))
        }
      }
    case "compose":
      Task {
        do {
          let segments = try composeSegmentsArgument(call.arguments, key: "segments")
          let output = try stringArgument(call.arguments, key: "output")
          try await compose(segments: segments, output: output)
          result(nil)
        } catch {
          result(flutterError(error))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func probeDuration(path: String) async throws -> Double? {
    try ensureFileExists(path)
    let asset = AVAsset(url: URL(fileURLWithPath: path))
    let duration = try await loadDuration(asset)
    let seconds = CMTimeGetSeconds(duration)
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }

  private func inspectMedia(path: String) async throws -> [String: Any] {
    try ensureFileExists(path)
    let asset = AVAsset(url: URL(fileURLWithPath: path))
    let duration = try await loadDuration(asset)
    let seconds = CMTimeGetSeconds(duration)
    var info: [String: Any] = [
      "videoTrackCount": asset.tracks(withMediaType: .video).count,
      "audioTrackCount": asset.tracks(withMediaType: .audio).count,
    ]
    if seconds.isFinite && seconds > 0 {
      info["durationSec"] = seconds
    }
    return info
  }

  private func concat(paths: [String], output: String) async throws {
    try await compose(
      segments: paths.map {
        ComposeSegment(
          videoPath: $0,
          audioPath: nil,
          transition: nil,
          filterPreset: nil)
      },
      output: output)
  }

  private func compose(segments: [ComposeSegment], output: String) async throws {
    if segments.isEmpty { throw ComposerPluginError.invalidArguments }

    let composition = AVMutableComposition()
    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw ComposerPluginError.exportSessionUnavailable
    }
    var compositionAudioTrack: AVMutableCompositionTrack?
    var compositionVoiceTrack: AVMutableCompositionTrack?

    var cursor = CMTime.zero
    var renderSegments: [RenderSegment] = []
    for segment in segments {
      try ensureFileExists(segment.videoPath)
      let asset = AVAsset(url: URL(fileURLWithPath: segment.videoPath))
      let duration = try await loadDuration(asset)
      if !CMTimeGetSeconds(duration).isFinite || CMTimeCompare(duration, .zero) <= 0 {
        throw ComposerPluginError.invalidDuration(segment.videoPath)
      }
      guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        throw ComposerPluginError.noVideoTrack(segment.videoPath)
      }

      let timeRange = CMTimeRange(start: .zero, duration: duration)
      let compositionRange = CMTimeRange(start: cursor, duration: duration)
      renderSegments.append(
        RenderSegment(
          timeRange: compositionRange,
          transition: segment.transition,
          filterPreset: segment.filterPreset))
      try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)
      if let audioTrack = asset.tracks(withMediaType: .audio).first {
        if compositionAudioTrack == nil {
          compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid)
          if compositionAudioTrack == nil {
            throw ComposerPluginError.exportSessionUnavailable
          }
        }
        try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: cursor)
      }

      if let audioPath = segment.audioPath, !audioPath.isEmpty {
        try ensureFileExists(audioPath)
        let audioAsset = AVAsset(url: URL(fileURLWithPath: audioPath))
        let audioDuration = try await loadDuration(audioAsset)
        if !CMTimeGetSeconds(audioDuration).isFinite || CMTimeCompare(audioDuration, .zero) <= 0 {
          throw ComposerPluginError.invalidDuration(audioPath)
        }
        guard let voiceTrack = audioAsset.tracks(withMediaType: .audio).first else {
          throw ComposerPluginError.noAudioTrack(audioPath)
        }
        if compositionVoiceTrack == nil {
          compositionVoiceTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid)
          if compositionVoiceTrack == nil {
            throw ComposerPluginError.exportSessionUnavailable
          }
        }
        let voiceRange = CMTimeRange(start: .zero, duration: minTime(audioDuration, duration))
        try compositionVoiceTrack?.insertTimeRange(voiceRange, of: voiceTrack, at: cursor)
      }
      cursor = CMTimeAdd(cursor, duration)
    }

    let outputURL = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: output) {
      try FileManager.default.removeItem(at: outputURL)
    }

    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPreset1280x720)
    else {
      throw ComposerPluginError.exportSessionUnavailable
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    if let videoComposition = makeVideoComposition(
      asset: composition,
      renderSegments: renderSegments)
    {
      exportSession.videoComposition = videoComposition
    }
    try await export(exportSession)
  }

  private func makeVideoComposition(
    asset: AVAsset,
    renderSegments: [RenderSegment]
  ) -> AVMutableVideoComposition? {
    if !renderSegments.contains(where: { $0.transition != nil || $0.filterPreset != nil }) {
      return nil
    }
    return AVMutableVideoComposition(
      asset: asset,
      applyingCIFiltersWithHandler: { request in
        let source = request.sourceImage
        let segment = self.renderSegment(at: request.compositionTime, in: renderSegments)
        var image = self.filterImage(source, preset: segment?.filterPreset)
        let opacity = self.fadeOpacity(at: request.compositionTime, in: segment)
        if opacity < 0.999 {
          image = self.opacityImage(image, opacity: opacity)
        }
        request.finish(with: image.cropped(to: source.extent), context: nil)
      })
  }

  private func renderSegment(at time: CMTime, in segments: [RenderSegment]) -> RenderSegment? {
    segments.first { CMTimeRangeContainsTime($0.timeRange, time: time) }
  }

  private func filterImage(_ image: CIImage, preset: String?) -> CIImage {
    guard let preset = preset, !preset.isEmpty else { return image }
    switch preset {
    case "cinematic":
      return colorControls(image, saturation: 1.12, brightness: -0.02, contrast: 1.18)
    case "warm":
      return colorMatrix(image, red: 1.08, green: 1.02, blue: 0.94)
    case "cool":
      return colorMatrix(image, red: 0.94, green: 1.02, blue: 1.08)
    case "vintage":
      guard let sepia = CIFilter(name: "CISepiaTone") else { return image }
      sepia.setValue(image, forKey: kCIInputImageKey)
      sepia.setValue(0.35, forKey: kCIInputIntensityKey)
      return colorControls(sepia.outputImage ?? image, saturation: 0.9, brightness: 0.0, contrast: 1.05)
    default:
      return image
    }
  }

  private func colorControls(
    _ image: CIImage,
    saturation: Double,
    brightness: Double,
    contrast: Double
  ) -> CIImage {
    guard let filter = CIFilter(name: "CIColorControls") else { return image }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(saturation, forKey: kCIInputSaturationKey)
    filter.setValue(brightness, forKey: kCIInputBrightnessKey)
    filter.setValue(contrast, forKey: kCIInputContrastKey)
    return filter.outputImage ?? image
  }

  private func colorMatrix(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
    guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(x: red, y: 0, z: 0, w: 0), forKey: "inputRVector")
    filter.setValue(CIVector(x: 0, y: green, z: 0, w: 0), forKey: "inputGVector")
    filter.setValue(CIVector(x: 0, y: 0, z: blue, w: 0), forKey: "inputBVector")
    filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
    return filter.outputImage ?? image
  }

  private func fadeOpacity(at time: CMTime, in segment: RenderSegment?) -> CGFloat {
    guard let segment = segment, segment.transition == "fade" else { return 1.0 }
    let local = CMTimeSubtract(time, segment.timeRange.start)
    let duration = CMTimeGetSeconds(segment.timeRange.duration)
    let seconds = CMTimeGetSeconds(local)
    if !duration.isFinite || !seconds.isFinite || duration <= 0 { return 1.0 }
    let fadeSeconds = min(0.5, duration / 2.0)
    if fadeSeconds <= 0 { return 1.0 }
    if seconds < fadeSeconds {
      return CGFloat(max(0.0, min(1.0, seconds / fadeSeconds)))
    }
    if duration - seconds < fadeSeconds {
      return CGFloat(max(0.0, min(1.0, (duration - seconds) / fadeSeconds)))
    }
    return 1.0
  }

  private func opacityImage(_ image: CIImage, opacity: CGFloat) -> CIImage {
    colorMatrix(image, red: opacity, green: opacity, blue: opacity)
  }

  private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
  }

  private func loadDuration(_ asset: AVAsset) async throws -> CMTime {
    if #available(macOS 12.0, iOS 15.0, *) {
      return try await asset.load(.duration)
    }
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CMTime, Error>) in
      asset.loadValuesAsynchronously(forKeys: ["duration"]) {
        var error: NSError?
        let status = asset.statusOfValue(forKey: "duration", error: &error)
        switch status {
        case .loaded:
          continuation.resume(returning: asset.duration)
        case .failed, .cancelled:
          continuation.resume(throwing: error ?? ComposerPluginError.invalidDuration(""))
        default:
          continuation.resume(throwing: ComposerPluginError.invalidDuration(""))
        }
      }
    }
  }

  private func export(_ exportSession: AVAssetExportSession) async throws {
    let box = ExportSessionBox(exportSession)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      box.session.exportAsynchronously {
        switch box.session.status {
        case .completed:
          continuation.resume()
        case .failed, .cancelled:
          continuation.resume(throwing: box.session.error ?? ComposerPluginError.exportFailed)
        default:
          continuation.resume(throwing: box.session.error ?? ComposerPluginError.exportFailed)
        }
      }
    }
  }

  private func ensureFileExists(_ path: String) throws {
    if !FileManager.default.fileExists(atPath: path) {
      throw ComposerPluginError.fileMissing(path)
    }
  }

  private func stringArgument(_ arguments: Any?, key: String) throws -> String {
    guard let dict = arguments as? [String: Any],
          let value = dict[key] as? String,
          !value.isEmpty
    else {
      throw ComposerPluginError.invalidArguments
    }
    return value
  }

  private func stringArrayArgument(_ arguments: Any?, key: String) throws -> [String] {
    guard let dict = arguments as? [String: Any],
          let values = dict[key] as? [String],
          !values.isEmpty
    else {
      throw ComposerPluginError.invalidArguments
    }
    return values
  }

  private func composeSegmentsArgument(_ arguments: Any?, key: String) throws -> [ComposeSegment] {
    guard let dict = arguments as? [String: Any],
          let values = dict[key] as? [[String: Any]],
          !values.isEmpty
    else {
      throw ComposerPluginError.invalidArguments
    }
    return try values.map { value in
      guard let videoPath = value["videoPath"] as? String, !videoPath.isEmpty else {
        throw ComposerPluginError.invalidArguments
      }
      let rawAudioPath = value["audioPath"] as? String
      let audioPath = rawAudioPath?.isEmpty == true ? nil : rawAudioPath
      let rawTransition = value["transition"] as? String
      let transition = rawTransition?.isEmpty == true ? nil : rawTransition
      let rawFilterPreset = value["filterPreset"] as? String
      let filterPreset = rawFilterPreset?.isEmpty == true ? nil : rawFilterPreset
      return ComposeSegment(
        videoPath: videoPath,
        audioPath: audioPath,
        transition: transition,
        filterPreset: filterPreset)
    }
  }

  private func flutterError(_ error: Error) -> FlutterError {
    let nsError = error as NSError
    var message = nsError.localizedDescription
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      message += "：\(underlying.localizedDescription)"
    }
    if !nsError.domain.isEmpty {
      message += " [\(nsError.domain) \(nsError.code)]"
    }
    return FlutterError(
      code: "COMPOSER_ERROR",
      message: message,
      details: nsError.userInfo.description)
  }
}
