// ignore_for_file: uri_does_not_exist, undefined_prefixed_name

import 'dart:convert';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart' as ffmpeg;
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart' as ffprobe;
import 'package:ffmpeg_kit_flutter_new/return_code.dart' as ffreturn;

import '../engine/compose.dart';
import '../engine/util.dart';

class FfmpegKitRunner implements FfmpegRunner {
  const FfmpegKitRunner();

  @override
  Future<MediaProbe> probe(String inputPath) async {
    final session = await ffprobe.FFprobeKit.execute(_joinArgs([
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      inputPath,
    ]));
    final returnCode = await session.getReturnCode();
    final output = await session.getOutput() ?? '';
    if (!ffreturn.ReturnCode.isSuccess(returnCode)) {
      throw EngineException('ffprobe 读取媒体信息失败：${_tail(output)}');
    }
    final json = jsonDecode(output) as Map<String, dynamic>;
    final streams = (json['streams'] as List? ?? const []);
    final hasAudio = streams.any((s) =>
        s is Map && (s['codec_type']?.toString().toLowerCase() == 'audio'));
    final format = json['format'];
    double? duration;
    if (format is Map) {
      duration = double.tryParse(format['duration']?.toString() ?? '');
    }
    duration ??= streams
        .whereType<Map>()
        .map((s) => double.tryParse(s['duration']?.toString() ?? ''))
        .whereType<double>()
        .fold<double?>(null, (maxDuration, value) {
      if (maxDuration == null) return value;
      return max(maxDuration, value);
    });
    return MediaProbe(durationSec: duration, hasAudio: hasAudio);
  }

  @override
  Future<FfmpegRunResult> run(List<String> args) async {
    final session = await ffmpeg.FFmpegKit.execute(_joinArgs(args));
    final returnCode = await session.getReturnCode();
    final output = await session.getOutput() ?? '';
    final failStack = await session.getFailStackTrace() ?? '';
    return FfmpegRunResult(
      success: ffreturn.ReturnCode.isSuccess(returnCode),
      stderr: failStack.isEmpty ? output : '$output\n$failStack',
    );
  }
}

String _joinArgs(List<String> args) => args.map(_quoteArg).join(' ');

String _quoteArg(String value) {
  if (value.isEmpty) return "''";
  if (!RegExp(r'''[\s'"\\]''').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}

String _tail(String value, {int maxChars = 500}) {
  if (value.length <= maxChars) return value;
  return value.substring(value.length - maxChars);
}
