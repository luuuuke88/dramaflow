import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'errors.dart';

enum VideoMode {
  text('text'),
  firstFrame('first_frame'),
  firstLastFrame('first_last_frame'),
  multiReference('multi_reference');

  final String wireValue;

  const VideoMode(this.wireValue);

  static VideoMode? fromWireValue(Object? value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return null;
  }
}

class VideoReference {
  final String mediaType;
  final String role;
  final String localPath;

  const VideoReference({
    required this.mediaType,
    required this.role,
    required this.localPath,
  });

  Map<String, String> toJson() => {
        'mediaType': mediaType,
        'role': role,
        'localPath': localPath,
      };
}

class VideoGenerationRequest {
  final String modelBinding;
  final VideoMode mode;
  final String prompt;
  final List<VideoReference> references;
  final int duration;
  final String resolution;
  final String ratio;
  final bool generateAudio;
  final int projectId;
  final int storyboardId;
  final int videoTrackId;

  VideoGenerationRequest({
    required this.modelBinding,
    required this.mode,
    required this.prompt,
    required List<VideoReference> references,
    required this.duration,
    required this.resolution,
    required this.ratio,
    required this.generateAudio,
    required this.projectId,
    required this.storyboardId,
    required this.videoTrackId,
  }) : references = List.unmodifiable(references);

  VideoGenerationRequest copyWith({
    String? modelBinding,
    VideoMode? mode,
    String? prompt,
    List<VideoReference>? references,
    int? duration,
    String? resolution,
    String? ratio,
    bool? generateAudio,
    int? projectId,
    int? storyboardId,
    int? videoTrackId,
  }) =>
      VideoGenerationRequest(
        modelBinding: modelBinding ?? this.modelBinding,
        mode: mode ?? this.mode,
        prompt: prompt ?? this.prompt,
        references: references ?? this.references,
        duration: duration ?? this.duration,
        resolution: resolution ?? this.resolution,
        ratio: ratio ?? this.ratio,
        generateAudio: generateAudio ?? this.generateAudio,
        projectId: projectId ?? this.projectId,
        storyboardId: storyboardId ?? this.storyboardId,
        videoTrackId: videoTrackId ?? this.videoTrackId,
      );

  String fingerprintMaterial() => jsonEncode({
        'modelBinding': modelBinding,
        'mode': mode.wireValue,
        'prompt': prompt,
        'references': [for (final reference in references) reference.toJson()],
        'duration': duration,
        'resolution': resolution,
        'ratio': ratio,
        'generateAudio': generateAudio,
      });

  String fingerprint() =>
      sha256.convert(utf8.encode(fingerprintMaterial())).toString();
}

class VideoModelCapabilities {
  final Set<VideoMode> modes;
  final Map<String, int> referenceLimits;
  final Set<int> durations;
  final Set<String> resolutions;
  final Set<String> ratios;
  final String audio;
  final Map<VideoMode, String> promptTemplates;

  const VideoModelCapabilities({
    required this.modes,
    required this.referenceLimits,
    required this.durations,
    required this.resolutions,
    required this.ratios,
    required this.audio,
    required this.promptTemplates,
  });

  factory VideoModelCapabilities.fromJson(
    Map<String, dynamic> capabilities, {
    bool legacyFirstFrame = false,
  }) {
    final rawVideo = capabilities['video'];
    final video = rawVideo is Map
        ? Map<String, dynamic>.from(rawVideo)
        : <String, dynamic>{};
    final legacy = video.isEmpty && legacyFirstFrame;
    final modes = <VideoMode>{
      for (final value in (video['modes'] as List? ?? const []))
        if (VideoMode.fromWireValue(value) case final mode?) mode,
      if (legacy) VideoMode.firstFrame,
    };
    final limits = <String, int>{
      for (final type in const ['image', 'video', 'audio'])
        if (_positiveOrZero((video['references'] as Map?)?[type])
            case final limit?)
          type: limit,
    };
    final durations = <int>{
      for (final value in (video['durations'] as List? ??
          capabilities['durations'] as List? ??
          const []))
        if (_positiveInt(value) case final duration?) duration,
    };
    final resolutions = <String>{
      for (final value in (video['resolutions'] as List? ??
          capabilities['resolutions'] as List? ??
          const []))
        if (value is String && value.trim().isNotEmpty) value.trim(),
    };
    final ratios = <String>{
      for (final value in (video['ratios'] as List? ?? const []))
        if (value is String && value.trim().isNotEmpty) value.trim(),
      if (legacy) '16:9',
      if (legacy) '9:16',
    };
    final rawAudio = video['audio'];
    final audio = rawAudio is String &&
            const {'none', 'optional', 'required'}.contains(rawAudio)
        ? rawAudio
        : 'none';
    final templates = <VideoMode, String>{
      for (final entry
          in ((video['promptTemplates'] as Map?) ?? const {}).entries)
        if (VideoMode.fromWireValue(entry.key) case final mode?)
          if (entry.value is String &&
              (entry.value as String).trim().isNotEmpty)
            mode: (entry.value as String).trim(),
    };
    return VideoModelCapabilities(
      modes: Set.unmodifiable(modes),
      referenceLimits: Map.unmodifiable(limits),
      durations: Set.unmodifiable(durations),
      resolutions: Set.unmodifiable(resolutions),
      ratios: Set.unmodifiable(ratios),
      audio: audio,
      promptTemplates: Map.unmodifiable(templates),
    );
  }

  bool supports(VideoMode mode) => modes.contains(mode);

  void validate(VideoGenerationRequest request) {
    if (!supports(request.mode)) {
      _invalid('unsupportedMode:${request.mode.wireValue}');
    }
    if (!durations.contains(request.duration)) {
      _invalid('unsupportedDuration:${request.duration}');
    }
    if (!resolutions.contains(request.resolution)) {
      _invalid('unsupportedResolution:${request.resolution}');
    }
    if (!ratios.contains(request.ratio)) {
      _invalid('unsupportedRatio:${request.ratio}');
    }
    if (audio == 'none' && request.generateAudio) {
      _invalid('audioUnsupported');
    }
    if (audio == 'required' && !request.generateAudio) {
      _invalid('audioRequired');
    }
    for (final reference in request.references) {
      if (reference.localPath.trim().isEmpty ||
          path.isAbsolute(reference.localPath)) {
        _invalid('invalidReferencePath');
      }
    }

    switch (request.mode) {
      case VideoMode.text:
        if (request.references.isNotEmpty) _invalid('textHasReferences');
      case VideoMode.firstFrame:
        _requireExactRoles(request.references, const {'first_frame': 'image'});
      case VideoMode.firstLastFrame:
        _requireExactRoles(request.references, const {
          'first_frame': 'image',
          'last_frame': 'image',
        });
      case VideoMode.multiReference:
        if (request.references.isEmpty) _invalid('multiReferenceEmpty');
        for (final reference in request.references) {
          final expectedRole = switch (reference.mediaType) {
            'image' => 'reference_image',
            'video' => 'reference_video',
            'audio' => 'reference_audio',
            _ => '',
          };
          if (reference.role != expectedRole) {
            _invalid('invalidReferenceRole');
          }
        }
        for (final type in const ['image', 'video', 'audio']) {
          final count = request.references
              .where((reference) => reference.mediaType == type)
              .length;
          if (count > (referenceLimits[type] ?? 0)) {
            _invalid('referenceLimit:$type');
          }
        }
    }
  }

  void _requireExactRoles(
    List<VideoReference> references,
    Map<String, String> expected,
  ) {
    if (references.length != expected.length) _invalid('referenceCount');
    final byRole = {
      for (final reference in references) reference.role: reference
    };
    if (byRole.length != expected.length) _invalid('duplicateReferenceRole');
    for (final entry in expected.entries) {
      final reference = byRole[entry.key];
      if (reference == null || reference.mediaType != entry.value) {
        _invalid('missingReference:${entry.key}');
      }
    }
  }

  Never _invalid(String reason) =>
      throw EngineException(errLlmFormat, {'reason': reason});
}

int? _positiveInt(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

int? _positiveOrZero(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number >= 0 ? number : null;
}
