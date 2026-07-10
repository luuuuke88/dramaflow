/// DramaFlow API 数据模型（对应 docs/API.md）。手写 fromJson，不依赖代码生成。
library;

import 'dart:convert';

Map<String, dynamic> _jsonMap(Object? value) {
  if (value == null) return const {};
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }
  return const {};
}

bool _jsonBool(Object? value, {bool defaultValue = true}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().toLowerCase();
  return s != '0' && s != 'false';
}

class ProjectStats {
  final int episodes;
  final int assets;
  final int assetsDone;
  final int shots;
  final int shotsImageDone;
  final int shotsVideoDone;
  final bool hasNovel;

  const ProjectStats({
    required this.episodes,
    required this.assets,
    required this.assetsDone,
    required this.shots,
    required this.shotsImageDone,
    required this.shotsVideoDone,
    required this.hasNovel,
  });

  factory ProjectStats.fromJson(Map<String, dynamic> j) => ProjectStats(
        episodes: j['episodes'] as int? ?? 0,
        assets: j['assets'] as int? ?? 0,
        assetsDone: j['assetsDone'] as int? ?? 0,
        shots: j['shots'] as int? ?? 0,
        shotsImageDone: j['shotsImageDone'] as int? ?? 0,
        shotsVideoDone: j['shotsVideoDone'] as int? ?? 0,
        hasNovel: j['hasNovel'] as bool? ?? false,
      );

  static const empty = ProjectStats(
    episodes: 0,
    assets: 0,
    assetsDone: 0,
    shots: 0,
    shotsImageDone: 0,
    shotsVideoDone: 0,
    hasNovel: false,
  );
}

class Project {
  final String id;
  final String name;
  final String artStyle;
  final String createdAt;
  final String updatedAt;
  final ProjectStats stats;

  const Project({
    required this.id,
    required this.name,
    required this.artStyle,
    required this.createdAt,
    required this.updatedAt,
    required this.stats,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        artStyle: j['artStyle'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? '',
        updatedAt: j['updatedAt'] as String? ?? '',
        stats: j['stats'] != null
            ? ProjectStats.fromJson(j['stats'] as Map<String, dynamic>)
            : ProjectStats.empty,
      );
}

class Novel {
  final String id;
  final String title;
  final String content;

  const Novel({required this.id, required this.title, required this.content});

  factory Novel.fromJson(Map<String, dynamic> j) => Novel(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
      );
}

class Dialogue {
  final String speaker;
  final String line;

  const Dialogue({required this.speaker, required this.line});

  factory Dialogue.fromJson(Map<String, dynamic> j) => Dialogue(
        speaker: j['speaker'] as String? ?? '',
        line: j['line'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'speaker': speaker, 'line': line};
}

class Scene {
  final String location;
  final String timeOfDay;
  final String action;
  final List<Dialogue> dialogues;

  const Scene({
    required this.location,
    required this.timeOfDay,
    required this.action,
    required this.dialogues,
  });

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        location: j['location'] as String? ?? '',
        timeOfDay: j['timeOfDay'] as String? ?? '',
        action: j['action'] as String? ?? '',
        dialogues: (j['dialogues'] as List? ?? [])
            .map((d) => Dialogue.fromJson(d as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'location': location,
        'timeOfDay': timeOfDay,
        'action': action,
        'dialogues': dialogues.map((d) => d.toJson()).toList(),
      };
}

class EpisodeSummary {
  final String id;
  final int idx;
  final String title;
  final String synopsis;
  final int sceneCount;
  final int shotCount;

  const EpisodeSummary({
    required this.id,
    required this.idx,
    required this.title,
    required this.synopsis,
    required this.sceneCount,
    required this.shotCount,
  });

  factory EpisodeSummary.fromJson(Map<String, dynamic> j) => EpisodeSummary(
        id: j['id'] as String,
        idx: j['idx'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        synopsis: j['synopsis'] as String? ?? '',
        sceneCount: j['sceneCount'] as int? ?? 0,
        shotCount: j['shotCount'] as int? ?? 0,
      );
}

class Episode {
  final String id;
  final String projectId;
  final int idx;
  final String title;
  final String synopsis;
  final List<Scene> scenes;
  final String? composedPath;
  final String composeStatus;
  final String? composeError;

  const Episode({
    required this.id,
    required this.projectId,
    required this.idx,
    required this.title,
    required this.synopsis,
    required this.scenes,
    required this.composedPath,
    required this.composeStatus,
    required this.composeError,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as String,
        projectId: j['projectId'] as String? ?? '',
        idx: j['idx'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        synopsis: j['synopsis'] as String? ?? '',
        scenes: (j['scenes'] as List? ?? [])
            .map((s) => Scene.fromJson(s as Map<String, dynamic>))
            .toList(),
        composedPath: j['composedPath'] as String?,
        composeStatus: j['composeStatus'] as String? ?? 'none',
        composeError: j['composeError'] as String?,
      );
}

class Asset {
  final String id;
  final String projectId;
  final String kind; // character | scene | prop
  final String name;
  final String description;
  final String imagePrompt;
  final String note;
  final String? imageUrl;
  final String status; // draft | queued | running | done | failed
  final String? error;

  const Asset({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.name,
    required this.description,
    required this.imagePrompt,
    required this.note,
    required this.imageUrl,
    required this.status,
    required this.error,
  });

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
        id: j['id'] as String,
        projectId: j['projectId'] as String? ?? '',
        kind: j['kind'] as String? ?? 'character',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        imagePrompt: j['imagePrompt'] as String? ?? '',
        note: j['note'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        status: j['status'] as String? ?? 'draft',
        error: j['error'] as String?,
      );
}

class Shot {
  final String id;
  final String episodeId;
  final int idx;
  final String description;
  final String dialogue;
  final String camera;
  final List<String> assetNames;
  final String imagePrompt;
  final String? imageUrl;
  final String imageStatus; // none | queued | running | done | failed
  final String? imageError;
  final String videoPrompt;
  final String? videoUrl;
  final String videoStatus;
  final String? videoError;
  final String? selectedTakeId;

  const Shot({
    required this.id,
    required this.episodeId,
    required this.idx,
    required this.description,
    required this.dialogue,
    required this.camera,
    required this.assetNames,
    required this.imagePrompt,
    required this.imageUrl,
    required this.imageStatus,
    required this.imageError,
    required this.videoPrompt,
    required this.videoUrl,
    required this.videoStatus,
    required this.videoError,
    required this.selectedTakeId,
  });

  factory Shot.fromJson(Map<String, dynamic> j) => Shot(
        id: j['id'] as String,
        episodeId: j['episodeId'] as String? ?? '',
        idx: j['idx'] as int? ?? 0,
        description: j['description'] as String? ?? '',
        dialogue: j['dialogue'] as String? ?? '',
        camera: j['camera'] as String? ?? '',
        assetNames:
            (j['assetNames'] as List? ?? []).map((e) => e.toString()).toList(),
        imagePrompt: j['imagePrompt'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        imageStatus: j['imageStatus'] as String? ?? 'none',
        imageError: j['imageError'] as String?,
        videoPrompt: j['videoPrompt'] as String? ?? '',
        videoUrl: j['videoUrl'] as String?,
        videoStatus: j['videoStatus'] as String? ?? 'none',
        videoError: j['videoError'] as String?,
        selectedTakeId: j['selectedTakeId'] as String?,
      );
}

class VideoTake {
  final String id;
  final String shotId;
  final String videoPath;
  final double? durationSec;
  final String createdAt;

  const VideoTake({
    required this.id,
    required this.shotId,
    required this.videoPath,
    required this.durationSec,
    required this.createdAt,
  });

  factory VideoTake.fromJson(Map<String, dynamic> j) => VideoTake(
        id: j['id'] as String,
        shotId: j['shotId'] as String? ?? '',
        videoPath: j['videoPath'] as String? ?? '',
        durationSec: (j['durationSec'] as num?)?.toDouble(),
        createdAt: j['createdAt'] as String? ?? '',
      );
}

class ImageTake {
  final String id;
  final String? assetId;
  final String? shotId;
  final String imagePath;
  final bool selected;
  final String createdAt;

  const ImageTake({
    required this.id,
    required this.assetId,
    required this.shotId,
    required this.imagePath,
    required this.selected,
    required this.createdAt,
  });

  factory ImageTake.fromJson(Map<String, dynamic> j) => ImageTake(
        id: j['id'] as String,
        assetId: j['assetId'] as String?,
        shotId: j['shotId'] as String?,
        imagePath: j['imagePath'] as String? ?? '',
        selected: _jsonBool(j['selected'], defaultValue: false),
        createdAt: j['createdAt'] as String? ?? '',
      );
}

class Job {
  final String id;
  final String projectId;
  final String kind;
  final String targetId;
  final String targetLabel;
  final String state; // queued | running | done | failed | canceled
  final int attempt;
  final String? error;
  final String? result;
  final String createdAt;
  final String? startedAt;
  final String? finishedAt;
  final int? durationMs;

  const Job({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.targetId,
    required this.targetLabel,
    required this.state,
    required this.attempt,
    required this.error,
    required this.result,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        projectId: j['projectId'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        targetId: j['targetId'] as String? ?? '',
        targetLabel: j['targetLabel'] as String? ?? '',
        state: j['state'] as String? ?? '',
        attempt: j['attempt'] as int? ?? 1,
        error: j['error'] as String?,
        result: j['result'] as String?,
        createdAt: j['createdAt'] as String? ?? '',
        startedAt: j['startedAt'] as String?,
        finishedAt: j['finishedAt'] as String?,
        durationMs: j['durationMs'] as int?,
      );
}

class DirectorState {
  final String mode; // auto | off
  final String scope; // all
  final String pausedReason;
  final String currentStage;
  final bool finished;
  final String? finishedAt;

  const DirectorState({
    required this.mode,
    required this.scope,
    required this.pausedReason,
    required this.currentStage,
    required this.finished,
    required this.finishedAt,
  });

  static const off = DirectorState(
    mode: 'off',
    scope: 'all',
    pausedReason: '',
    currentStage: '',
    finished: false,
    finishedAt: null,
  );

  bool get isAuto => mode == 'auto';
  bool get isPaused => mode == 'auto' && pausedReason.isNotEmpty;
  bool get isRunning => mode == 'auto' && pausedReason.isEmpty;

  factory DirectorState.fromJson(Map<String, dynamic> j) {
    final mode = j['mode'] == 'auto' ? 'auto' : 'off';
    return DirectorState(
      mode: mode,
      scope: j['scope'] as String? ?? 'all',
      pausedReason: j['pausedReason'] as String? ?? '',
      currentStage: j['currentStage'] as String? ?? '',
      finished: _jsonBool(j['finished'], defaultValue: false),
      finishedAt: j['finishedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'scope': scope,
        'pausedReason': pausedReason,
        'currentStage': currentStage,
        'finished': finished,
        if (finishedAt != null) 'finishedAt': finishedAt,
      };

  DirectorState copyWith({
    String? mode,
    String? scope,
    String? pausedReason,
    String? currentStage,
    bool? finished,
    String? finishedAt,
  }) =>
      DirectorState(
        mode: mode ?? this.mode,
        scope: scope ?? this.scope,
        pausedReason: pausedReason ?? this.pausedReason,
        currentStage: currentStage ?? this.currentStage,
        finished: finished ?? this.finished,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

class AppSettings {
  final String textBaseUrl;
  final String textModel;
  final String imageBaseUrl;
  final String imageModel;
  final String videoProvider;
  final String videoModel;
  final String videoResolution;
  final int videoDuration;

  const AppSettings({
    required this.textBaseUrl,
    required this.textModel,
    required this.imageBaseUrl,
    required this.imageModel,
    required this.videoProvider,
    required this.videoModel,
    required this.videoResolution,
    required this.videoDuration,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        textBaseUrl: j['textBaseUrl'] as String? ?? '',
        textModel: j['textModel'] as String? ?? '',
        imageBaseUrl: j['imageBaseUrl'] as String? ?? '',
        imageModel: j['imageModel'] as String? ?? '',
        videoProvider: j['videoProvider'] as String? ?? '',
        videoModel: j['videoModel'] as String? ?? '',
        videoResolution: j['videoResolution'] as String? ?? '',
        videoDuration: (j['videoDuration'] as num?)?.toInt() ?? 5,
      );
}

class ProviderInfo {
  final String id;
  final String name;
  final String protocol;
  final String baseUrl;
  final bool hasCredential;
  final bool enabled;
  final String createdAt;

  const ProviderInfo({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.hasCredential,
    required this.enabled,
    required this.createdAt,
  });

  factory ProviderInfo.fromJson(Map<String, dynamic> j) => ProviderInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        protocol: j['protocol'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
        hasCredential: _jsonBool(j['hasCredential']),
        enabled: _jsonBool(j['enabled']),
        createdAt: j['createdAt'] as String? ?? '',
      );
}

class ProviderModelInfo {
  final String id;
  final String providerId;
  final String modelId;
  final String label;
  final String kind;
  final Map<String, dynamic> capabilities;
  final bool enabled;

  const ProviderModelInfo({
    required this.id,
    required this.providerId,
    required this.modelId,
    required this.label,
    required this.kind,
    required this.capabilities,
    required this.enabled,
  });

  factory ProviderModelInfo.fromJson(Map<String, dynamic> j) =>
      ProviderModelInfo(
        id: j['id'] as String,
        providerId: j['providerId'] as String? ?? '',
        modelId: j['modelId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        capabilities: _jsonMap(j['capabilities']),
        enabled: _jsonBool(j['enabled']),
      );
}
