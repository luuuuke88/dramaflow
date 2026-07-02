@preconcurrency import AVFoundation
import FlutterMacOS
import Foundation

private enum ComposerPluginError: LocalizedError {
  case invalidArguments
  case fileMissing(String)
  case noVideoTrack(String)
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

  private func concat(paths: [String], output: String) async throws {
    if paths.isEmpty {
      throw ComposerPluginError.invalidArguments
    }

    let composition = AVMutableComposition()
    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw ComposerPluginError.exportSessionUnavailable
    }
    let compositionAudioTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid)

    var cursor = CMTime.zero
    for path in paths {
      try ensureFileExists(path)
      let asset = AVAsset(url: URL(fileURLWithPath: path))
      let duration = try await loadDuration(asset)
      if !CMTimeGetSeconds(duration).isFinite || CMTimeCompare(duration, .zero) <= 0 {
        throw ComposerPluginError.invalidDuration(path)
      }
      guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        throw ComposerPluginError.noVideoTrack(path)
      }

      let timeRange = CMTimeRange(start: .zero, duration: duration)
      try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)
      if let audioTrack = asset.tracks(withMediaType: .audio).first {
        try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: cursor)
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
    try await export(exportSession)
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

  private func flutterError(_ error: Error) -> FlutterError {
    let nsError = error as NSError
    return FlutterError(
      code: "COMPOSER_ERROR",
      message: nsError.localizedDescription,
      details: nil)
  }
}
