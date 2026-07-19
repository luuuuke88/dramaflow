// 多轨工作台（视频生成/挑选）：契约照抄 ToonFlow /api/production/workbench/*
// （详见 docs/reference/p4-workbench-brief.md §1/§2）。
// 数据模型澄清：o_videoTrack = 一个分镜的视频槽位（与 o_storyboard.trackId 一一对应，
// 与 P3 分镜=图片槽位同构）；o_video = 该槽位下的候选生成结果；
// selectVideoId = 用户选中的候选（videoId 字段保持同步写入，避免死字段）。
// 状态枚举为 DB 中文字符串（逐字）：未生成/生成中/已完成/生成失败。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'assets.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart' show stripThink;
import 'prompt_resolver.dart';
import 'queue.dart';
import 'video_request.dart';

const vtNotGenerated = '未生成';
const vtGenerating = '生成中';
const vtDone = '已完成';
const vtFailed = '生成失败';

class VideoReferenceSource {
  final String sourceType;
  final int sourceId;
  final String mediaType;
  final String role;

  const VideoReferenceSource({
    required this.sourceType,
    required this.sourceId,
    required this.mediaType,
    required this.role,
  });

  factory VideoReferenceSource.fromJson(Map<String, dynamic> json) =>
      VideoReferenceSource(
        sourceType: (json['sourceType'] as String?) ?? '',
        sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
        mediaType: (json['mediaType'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
      );

  Map<String, Object?> toJson() => {
        'sourceType': sourceType,
        'sourceId': sourceId,
        'mediaType': mediaType,
        'role': role,
      };
}

class VideoRequestDraft {
  final int version;
  final VideoMode mode;
  final List<VideoReferenceSource> references;
  final int duration;
  final String resolution;
  final String ratio;
  final bool generateAudio;

  VideoRequestDraft({
    required this.version,
    required this.mode,
    required List<VideoReferenceSource> references,
    required this.duration,
    required this.resolution,
    required this.ratio,
    required this.generateAudio,
  }) : references = List.unmodifiable(references);

  factory VideoRequestDraft.fromJson(
    Map<String, dynamic> json,
    VideoRequestDraft defaults,
  ) =>
      VideoRequestDraft(
        version: (json['version'] as num?)?.toInt() ?? defaults.version,
        mode: VideoMode.fromWireValue(json['mode']) ?? defaults.mode,
        references: json['references'] is List
            ? [
                for (final reference in json['references'] as List)
                  if (reference is Map)
                    VideoReferenceSource.fromJson(
                        Map<String, dynamic>.from(reference)),
              ]
            : defaults.references,
        duration: (json['duration'] as num?)?.toInt() ?? defaults.duration,
        resolution: (json['resolution'] as String?) ?? defaults.resolution,
        ratio: (json['ratio'] as String?) ?? defaults.ratio,
        generateAudio: json['generateAudio'] is bool
            ? json['generateAudio'] as bool
            : defaults.generateAudio,
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'mode': mode.wireValue,
        'references': [for (final reference in references) reference.toJson()],
        'duration': duration,
        'resolution': resolution,
        'ratio': ratio,
        'generateAudio': generateAudio,
      };
}

class VideoReferenceCandidate {
  final VideoReferenceSource source;
  final String label;
  final String localPath;

  const VideoReferenceCandidate({
    required this.source,
    required this.label,
    required this.localPath,
  });
}

class VideoRow {
  final int id;
  final int videoTrackId;
  final String? filePath;
  final String? state;
  final String? errorReason;
  final int? time;
  const VideoRow({
    required this.id,
    required this.videoTrackId,
    required this.filePath,
    required this.state,
    required this.errorReason,
    required this.time,
  });
}

class VideoTrackRow {
  final int id;
  final int projectId;
  final int scriptId;
  final String? prompt;
  final String? reason;
  final String? state;
  final int? duration;
  final String? transition;
  final String? filter;
  final int? selectVideoId;
  final List<VideoRow> candidates;
  const VideoTrackRow({
    required this.id,
    required this.projectId,
    required this.scriptId,
    required this.prompt,
    required this.reason,
    required this.state,
    required this.duration,
    required this.transition,
    required this.filter,
    required this.selectVideoId,
    required this.candidates,
  });
}

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension VideoTrackApi on Engine {
  void installVideoTrackPipeline() {
    taskRunners['video_generation'] = _runVideoGeneration;
    queue.registerRecover('video_generation', _recoverVideoGeneration);
    queue.registerColdStartResumer(
        'video_generation', _resumeVideoGenerationOnColdStart);
  }

  /// 懒建分镜对应的视频轨（trackId 未建时新建并回填 o_storyboard.trackId）。
  int ensureTrackForStoryboard(int storyboardId) {
    final row = db.select(
        'SELECT trackId,projectId,scriptId FROM o_storyboard WHERE id=?',
        [storyboardId]).firstOrNull;
    if (row == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final existing = row['trackId'] as int?;
    if (existing != null) return existing;
    db.execute(
      'INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,?)',
      [row['projectId'], row['scriptId'], vtNotGenerated],
    );
    final trackId = db.lastInsertRowId;
    db.execute('UPDATE o_storyboard SET trackId=? WHERE id=?',
        [trackId, storyboardId]);
    return trackId;
  }

  VideoTrackRow? track(int trackId) {
    final row = db
        .select('SELECT * FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (row == null) return null;
    return _trackFromRow(row);
  }

  VideoTrackRow _trackFromRow(Row row) {
    final candidates = db
        .select('SELECT * FROM o_video WHERE videoTrackId=? ORDER BY id',
            [row['id']])
        .map((r) => VideoRow(
              id: r['id'] as int,
              videoTrackId: (r['videoTrackId'] as int?) ?? 0,
              filePath: r['filePath'] as String?,
              state: r['state'] as String?,
              errorReason: r['errorReason'] as String?,
              time: r['time'] as int?,
            ))
        .toList();
    return VideoTrackRow(
      id: row['id'] as int,
      projectId: (row['projectId'] as int?) ?? 0,
      scriptId: (row['scriptId'] as int?) ?? 0,
      prompt: row['prompt'] as String?,
      reason: row['reason'] as String?,
      state: row['state'] as String?,
      duration: row['duration'] as int?,
      transition: row['transition'] as String?,
      filter: row['filterPreset'] as String?,
      selectVideoId: row['selectVideoId'] as int?,
      candidates: candidates,
    );
  }

  VideoRequestDraft videoRequestForTrack(int trackId) {
    final row = db.select(
        'SELECT v.videoRequest,p.videoModel,p.videoRatio FROM o_videoTrack v '
        'JOIN o_project p ON p.id=v.projectId WHERE v.id=?',
        [trackId]).firstOrNull;
    if (row == null) {
      throw EngineException(errPromptMissing, {'type': 'videoTrack'});
    }
    final storyboardId = db.select(
        'SELECT id FROM o_storyboard WHERE trackId=? LIMIT 1',
        [trackId]).firstOrNull?['id'] as int?;
    final defaults = _videoRequestDefaults(storyboardId, row);
    final raw = row['videoRequest'] as String?;
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return VideoRequestDraft.fromJson(
            Map<String, dynamic>.from(decoded), defaults);
      }
    } on FormatException {
      // Invalid legacy payloads use the same in-memory defaults as null rows.
    }
    return defaults;
  }

  /// 返回分镜当前或尚未持久化的视频请求默认值；预览参数时不创建视频轨。
  VideoRequestDraft videoRequestForStoryboard(int storyboardId) {
    final row = db.select(
      'SELECT s.trackId,p.videoModel,p.videoRatio FROM o_storyboard s '
      'JOIN o_project p ON p.id=s.projectId WHERE s.id=?',
      [storyboardId],
    ).firstOrNull;
    if (row == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final trackId = row['trackId'] as int?;
    if (trackId != null) return videoRequestForTrack(trackId);
    return _videoRequestDefaults(storyboardId, row);
  }

  VideoModelCapabilities? videoCapabilitiesForProject(int projectId) {
    final project = db
        .select('SELECT * FROM o_project WHERE id=?', [projectId]).firstOrNull;
    return project == null ? null : _videoCapabilities(project);
  }

  List<VideoReferenceCandidate> videoReferenceCandidates(
    int projectId,
    int storyboardId,
  ) {
    final rows = <VideoReferenceCandidate>[];

    void add({
      required String sourceType,
      required int sourceId,
      required String mediaType,
      required String role,
      required String label,
      required String? localPath,
    }) {
      if (localPath == null || localPath.isEmpty) return;
      if (!File(media.absPath(localPath)).existsSync()) return;
      rows.add(VideoReferenceCandidate(
        source: VideoReferenceSource(
          sourceType: sourceType,
          sourceId: sourceId,
          mediaType: mediaType,
          role: role,
        ),
        label: label,
        localPath: localPath,
      ));
    }

    final storyboard = db.select(
      'SELECT id,filePath FROM o_storyboard WHERE id=? AND projectId=?',
      [storyboardId, projectId],
    ).firstOrNull;
    if (storyboard != null) {
      add(
        sourceType: 'storyboard',
        sourceId: storyboard['id'] as int,
        mediaType: 'image',
        role: 'first_frame',
        label: 'Storyboard $storyboardId',
        localPath: storyboard['filePath'] as String?,
      );
    }
    for (final row in db.select(
      'SELECT a.id,a.name,a.type,i.filePath FROM o_assets2Storyboard l '
      'JOIN o_assets a ON a.id=l.assetId '
      'JOIN o_image i ON i.id=a.imageId WHERE l.storyboardId=? AND a.projectId=? '
      "AND i.filePath IS NOT NULL AND trim(i.filePath)<>''",
      [storyboardId, projectId],
    )) {
      final type = row['type'] as String? ?? '';
      final mediaType =
          type == 'audio' ? 'audio' : (type == 'clip' ? 'video' : 'image');
      final role = switch (mediaType) {
        'audio' => 'reference_audio',
        'video' => 'reference_video',
        _ => 'reference_image',
      };
      add(
        sourceType: 'asset',
        sourceId: row['id'] as int,
        mediaType: mediaType,
        role: role,
        label: row['name'] as String? ?? '',
        localPath: row['filePath'] as String?,
      );
    }
    for (final row in db.select(
      "SELECT id,filePath FROM o_video WHERE projectId=? AND state=? "
      "AND filePath IS NOT NULL AND trim(filePath)<>''",
      [projectId, vtDone],
    )) {
      add(
        sourceType: 'video',
        sourceId: row['id'] as int,
        mediaType: 'video',
        role: 'reference_video',
        label: 'Video ${row['id']}',
        localPath: row['filePath'] as String?,
      );
    }
    return rows;
  }

  void updateVideoRequest(int trackId, VideoRequestDraft draft) {
    db.execute('UPDATE o_videoTrack SET videoRequest=? WHERE id=?',
        [jsonEncode(draft.toJson()), trackId]);
  }

  VideoGenerationRequest buildVideoRequest({
    required int projectId,
    required int storyboardId,
    required int trackId,
  }) {
    final project = db
        .select('SELECT * FROM o_project WHERE id=?', [projectId]).firstOrNull;
    if (project == null) {
      throw EngineException(errPromptMissing, {'type': 'project'});
    }
    final storyboard = db.select(
        'SELECT projectId,trackId,prompt FROM o_storyboard WHERE id=?',
        [storyboardId]).firstOrNull;
    if (storyboard == null ||
        storyboard['projectId'] != projectId ||
        storyboard['trackId'] != trackId) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final capabilities = _videoCapabilities(project);
    if (capabilities == null) {
      throw const EngineException(
          errModelMissing, {'reason': 'missingVideoCapability'});
    }
    final draft = videoRequestForTrack(trackId);
    final request = VideoGenerationRequest(
      modelBinding: _videoModelBinding(project),
      mode: draft.mode,
      prompt: (track(trackId)?.prompt?.trim().isNotEmpty ?? false)
          ? track(trackId)!.prompt!.trim()
          : (storyboard['prompt'] as String? ?? '').trim(),
      references: [
        for (final source in draft.references)
          VideoReference(
            mediaType: source.mediaType,
            role: source.role,
            localPath: _referencePathForSource(projectId, source),
          ),
      ],
      duration: draft.duration,
      resolution: draft.resolution,
      ratio: draft.ratio,
      generateAudio: draft.generateAudio,
      projectId: projectId,
      storyboardId: storyboardId,
      videoTrackId: trackId,
    );
    capabilities.validate(request);
    return request;
  }

  String _referencePathForSource(
    int projectId,
    VideoReferenceSource source,
  ) {
    String? localPath;
    switch (source.sourceType) {
      case 'storyboard':
        localPath = db.select(
          "SELECT filePath FROM o_storyboard WHERE id=? AND projectId=? "
          "AND filePath IS NOT NULL AND trim(filePath)<>''",
          [source.sourceId, projectId],
        ).firstOrNull?['filePath'] as String?;
      case 'asset':
        localPath = db.select(
          'SELECT i.filePath FROM o_assets a JOIN o_image i ON i.id=a.imageId '
          "WHERE a.id=? AND a.projectId=? AND i.filePath IS NOT NULL AND trim(i.filePath)<>''",
          [source.sourceId, projectId],
        ).firstOrNull?['filePath'] as String?;
      case 'video':
        localPath = db.select(
          "SELECT filePath FROM o_video WHERE id=? AND projectId=? "
          "AND filePath IS NOT NULL AND trim(filePath)<>''",
          [source.sourceId, projectId],
        ).firstOrNull?['filePath'] as String?;
      case 'audio':
        localPath = db.select(
          'SELECT i.filePath FROM o_assets a JOIN o_image i ON i.id=a.imageId '
          "WHERE a.id=? AND a.projectId=? AND i.filePath IS NOT NULL AND trim(i.filePath)<>''",
          [source.sourceId, projectId],
        ).firstOrNull?['filePath'] as String?;
      default:
        break;
    }
    if (localPath == null || localPath.isEmpty) {
      throw EngineException(errPromptMissing, {'type': 'videoReference'});
    }
    if (!File(media.absPath(localPath)).existsSync()) {
      throw EngineException(errFileType, {'type': 'videoReference'});
    }
    return localPath;
  }

  VideoRequestDraft _videoRequestDefaults(int? storyboardId, Row project) {
    final capabilities = _videoCapabilities(project);
    final availableModes = capabilities?.modes.toList()
      ?..sort((a, b) => a.wireValue.compareTo(b.wireValue));
    final mode = capabilities?.supports(VideoMode.firstFrame) == true
        ? VideoMode.firstFrame
        : availableModes?.firstOrNull ?? VideoMode.firstFrame;
    final durations = capabilities?.durations.toList()?..sort();
    final resolutions = capabilities?.resolutions.toList()?..sort();
    final ratios = capabilities?.ratios.toList()?..sort();
    final configuredDuration = config.intOf('videoDuration');
    final configuredResolution = config.str('videoResolution');
    final projectRatio = (project['videoRatio'] as String?)?.trim() ?? '';
    return VideoRequestDraft(
      version: 1,
      mode: mode,
      references: mode == VideoMode.firstFrame && storyboardId != null
          ? [
              VideoReferenceSource(
                sourceType: 'storyboard',
                sourceId: storyboardId,
                mediaType: 'image',
                role: 'first_frame',
              ),
            ]
          : const [],
      duration: capabilities?.durations.contains(configuredDuration) == true
          ? configuredDuration
          : durations?.firstOrNull ?? configuredDuration,
      resolution:
          capabilities?.resolutions.contains(configuredResolution) == true
              ? configuredResolution
              : resolutions?.firstOrNull ?? configuredResolution,
      ratio: capabilities?.ratios.contains(projectRatio) == true
          ? projectRatio
          : (capabilities?.ratios.contains('16:9') == true
              ? '16:9'
              : ratios?.firstOrNull ?? '16:9'),
      generateAudio: capabilities?.audio == 'required',
    );
  }

  VideoModelCapabilities? _videoCapabilities(Row project) {
    final binding = _videoModelBinding(project);
    final separator = binding.indexOf(':');
    if (separator <= 0 || separator == binding.length - 1) return null;
    final providerId = binding.substring(0, separator);
    final modelId = binding.substring(separator + 1);
    final raw = db.select(
        'SELECT models FROM o_vendorConfig WHERE id=? LIMIT 1',
        [providerId]).firstOrNull?['models'] as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final models = jsonDecode(raw);
      if (models is! List) return null;
      for (final model in models.whereType<Map>()) {
        final candidate = Map<String, dynamic>.from(model);
        if (candidate['modelId'] == modelId &&
            candidate['kind'] == 'video' &&
            candidate['capabilities'] is Map) {
          return VideoModelCapabilities.fromJson(
              Map<String, dynamic>.from(candidate['capabilities'] as Map),
              legacyFirstFrame: true);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _videoModelBinding(Row project) {
    final projectBinding = (project['videoModel'] as String?)?.trim() ?? '';
    if (projectBinding.isNotEmpty) return projectBinding;
    return (db.select('SELECT value FROM o_setting WHERE key=? LIMIT 1',
                ['binding.shot_video']).firstOrNull?['value'] as String? ??
            '')
        .trim();
  }

  /// 同步生成运镜提示词（text 调用，非队列——与资产提示词润色同步语义一致）。
  /// 用户消息在画面描述/运镜说明之外，附带本分镜关联资产名称与时长做适度增强
  /// （o_assets2Storyboard→o_assets 取名字），让 LLM 知道镜头里有哪些角色/场景/道具、
  /// 该镜多长，产出更贴合的运镜词；不做过度堆料（只带名称，不带长描述与图片）。
  Future<String> generateVideoPrompt(int storyboardId) async {
    final sb = db.select(
        'SELECT projectId,prompt,videoDesc,duration '
        'FROM o_storyboard WHERE id=?',
        [storyboardId]).firstOrNull;
    if (sb == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final trackId = ensureTrackForStoryboard(storyboardId);
    final request = videoRequestForTrack(trackId);
    final assetNames = db
        .select(
          'SELECT a.name name FROM o_assets2Storyboard l '
          'JOIN o_assets a ON a.id=l.assetId '
          'WHERE l.storyboardId=? ORDER BY l.rowid',
          [storyboardId],
        )
        .map((r) => (r['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final trackDuration = (db.select(
        'SELECT duration FROM o_videoTrack WHERE id=?',
        [trackId]).firstOrNull?['duration'] as int?);
    // 时长优先取视频轨（用户手动编辑过的更权威），回退分镜时长文本。
    final durationText = trackDuration != null
        ? '$trackDuration'
        : (sb['duration'] as String?) ?? '';
    final project = db.select(
      'SELECT videoModel,videoRatio FROM o_project WHERE id=?',
      [sb['projectId']],
    ).first;
    final videoModelBinding = _videoModelBinding(project);
    final explicitModelPromptPath = boundModelPromptTemplatePathForBinding(
      videoModelBinding,
      kind: 'video',
    );
    final resolution = resolvePrompt(
      projectId: (sb['projectId'] as int?) ?? 0,
      basePromptKey: 'video_prompt_gen',
      visualSection: 'art_storyboard_video',
      modelStage: 'shot_video',
      modelBinding: videoModelBinding,
      modelPromptPath: explicitModelPromptPath ??
          _videoCapabilities(project)?.promptTemplates[request.mode],
    );
    final genericPrompt = await getPrompt('video_prompt_gen');
    final legacyModelPrompt = await getPromptForStageModel(
      'video_prompt_gen',
      'shot_video',
      modelBinding: videoModelBinding,
    );
    final hasExplicitModelTemplate =
        resolution.sources.any((source) => source.kind == 'model');
    final effectiveResolution =
        hasExplicitModelTemplate || legacyModelPrompt == genericPrompt
            ? resolution
            : _legacyVideoPromptResolution(
                resolution,
                legacyModelPrompt,
                videoModelBinding,
              );
    final system = effectiveResolution.system;
    final user = StringBuffer()
      ..writeln('画面描述：${sb['prompt'] ?? ''}')
      ..writeln('运镜/动作说明：${sb['videoDesc'] ?? ''}');
    if (assetNames.isNotEmpty) {
      user.writeln('关联资产：${assetNames.join('、')}');
    }
    if (durationText.isNotEmpty) {
      user.writeln('镜头时长（秒）：$durationText');
    }
    final res = await gateway.generateText(system, user.toString().trimRight(),
        stage: 'video_prompt_gen');
    final text = stripThink(res.content);
    db.execute(
      'UPDATE o_videoTrack SET prompt=?,promptProvenance=? WHERE id=?',
      [text, jsonEncode(effectiveResolution.toTaskJson()), trackId],
    );
    return text;
  }

  PromptResolution _legacyVideoPromptResolution(
    PromptResolution resolution,
    String modelPrompt,
    String modelBinding,
  ) {
    final sources = <PromptSource>[
      PromptSource(
        id: 'model:$modelBinding:video_prompt_gen',
        kind: 'model',
        version: promptContentHash(modelPrompt),
        content: modelPrompt,
      ),
      ...resolution.sources.where((source) => source.kind != 'base'),
    ];
    return PromptResolution(
      system: sources
          .map((source) => source.content)
          .where((content) => content.trim().isNotEmpty)
          .join('\n\n'),
      sources: sources,
    );
  }

  /// 手动编辑运镜提示词（覆盖写入 o_videoTrack.prompt）。
  void updateVideoPrompt(int trackId, String text) {
    db.execute('UPDATE o_videoTrack SET prompt=? WHERE id=?', [text, trackId]);
  }

  /// 编辑本镜时长（秒；写入 o_videoTrack.duration）。null 或非正值视为清空。
  void updateVideoDuration(int trackId, int? seconds) {
    final v = (seconds != null && seconds > 0) ? seconds : null;
    db.execute('UPDATE o_videoTrack SET duration=? WHERE id=?', [v, trackId]);
  }

  /// 编辑本镜转场预设。null/空字符串清空，具体渲染由 composer 平台实现解释。
  void updateVideoTransition(int trackId, String? transition) {
    db.execute('UPDATE o_videoTrack SET transition=? WHERE id=?',
        [_nleValue(transition), trackId]);
  }

  /// 编辑本镜滤镜预设。null/空字符串清空，具体渲染由 composer 平台实现解释。
  void updateVideoFilter(int trackId, String? filter) {
    db.execute('UPDATE o_videoTrack SET filterPreset=? WHERE id=?',
        [_nleValue(filter), trackId]);
  }

  /// 批量生成（队列任务，video lane，cap=1；任务内并发由 concurrentCount 控制，
  /// 与图片生成同一模式）。
  int batchGenerateVideos(int projectId, List<int> storyboardIds,
      {int concurrentCount = 2}) {
    if (storyboardIds.isEmpty) return 0;
    final trackIds = [
      for (final sbId in storyboardIds) ensureTrackForStoryboard(sbId),
    ];
    final requests = <int, VideoGenerationRequest>{
      for (var index = 0; index < storyboardIds.length; index++)
        trackIds[index]: buildVideoRequest(
          projectId: projectId,
          storyboardId: storyboardIds[index],
          trackId: trackIds[index],
        ),
    };
    final candidateIds = <int>[];
    for (final trackId in trackIds) {
      final request = requests[trackId]!;
      final trackRow = db.select(
          'SELECT scriptId FROM o_videoTrack WHERE id=?', [trackId]).first;
      db.execute(
        'INSERT INTO o_video '
        '(projectId,scriptId,videoTrackId,state,time,submissionState,'
        'modelBinding,requestFingerprint) '
        "VALUES (?,?,?,?,?,'prepared',?,?)",
        [
          projectId,
          trackRow['scriptId'],
          trackId,
          vtGenerating,
          DateTime.now().millisecondsSinceEpoch,
          request.modelBinding,
          request.fingerprint(),
        ],
      );
      candidateIds.add(db.lastInsertRowId);
    }
    db.execute(
      'UPDATE o_videoTrack SET state=? WHERE id IN (${_ph(trackIds)})',
      [vtGenerating, ...trackIds],
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'video_generation',
      describe: '视频生成',
      relatedObjects: {
        'kind': 'videoTrack',
        'trackIds': trackIds,
        'videoIds': candidateIds,
        'concurrentCount': concurrentCount,
      },
      model: requests.values.first.modelBinding,
    );
  }

  Future<void> _runVideoGeneration(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final trackIds = _taskIds(related['trackIds']);
    final videoIds = _taskIds(related['videoIds']);
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 2).clamp(1, 8);
    final projectId = task.projectId ?? 0;

    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= videoIds.length) return;
        final videoId = videoIds[i];
        final candidate = db.select(
            'SELECT * FROM o_video WHERE id=? AND projectId=?',
            [videoId, projectId]).firstOrNull;
        if (candidate == null) continue;
        final trackId = candidate['videoTrackId'] as int?;
        if (trackId == null || !trackIds.contains(trackId)) continue;
        try {
          final completed = await _runVideoCandidate(
            candidate,
            projectId: projectId,
            token: token,
          );
          if (completed) {
            _completeVideoTrack(trackId, videoId);
          }
          success++;
        } catch (e) {
          if (token.isCancelled) return;
          final ex = e is EngineException
              ? e
              : (e is DioException
                  ? EngineException(errNetwork, {'message': e.message})
                  : EngineException(errLlmFormat, {'message': '$e'}));
          firstFailure ??= ex;
          db.execute('UPDATE o_video SET state=?, errorReason=? WHERE id=?',
              [vtFailed, ex.toReasonJson(), videoId]);
          db.execute('UPDATE o_videoTrack SET state=?, reason=? WHERE id=?',
              [vtFailed, ex.toReasonJson(), trackId]);
        }
      }
    }

    await Future.wait(
        [for (var w = 0; w < min(concurrent, trackIds.length); w++) worker()]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
  }

  Future<bool> _runVideoCandidate(
    Row candidate, {
    required int projectId,
    required CancelToken token,
  }) async {
    final videoId = candidate['id'] as int;
    final trackId = candidate['videoTrackId'] as int;
    var submissionState = candidate['submissionState'] as String? ?? 'prepared';
    var modelBinding = candidate['modelBinding'] as String? ?? '';
    var upstreamTaskId = candidate['upstreamTaskId'] as String? ?? '';

    if (submissionState == 'prepared') {
      final storyboardId = db.select(
          'SELECT id FROM o_storyboard WHERE trackId=? LIMIT 1',
          [trackId]).firstOrNull?['id'] as int?;
      if (storyboardId == null) {
        throw EngineException(errPromptMissing, {'type': 'storyboard'});
      }
      final request = buildVideoRequest(
        projectId: projectId,
        storyboardId: storyboardId,
        trackId: trackId,
      );
      final storedFingerprint =
          candidate['requestFingerprint'] as String? ?? '';
      if (storedFingerprint != request.fingerprint() ||
          modelBinding != request.modelBinding) {
        throw const EngineException(
            errLlmFormat, {'reason': 'videoRequestChanged'});
      }
      db.execute(
        "UPDATE o_video SET submissionState='submitting' WHERE id=?",
        [videoId],
      );
      try {
        final submission = await gateway.submitVideo(
          request,
          stage: 'shot_video',
          cancelToken: token,
        );
        upstreamTaskId = submission.upstreamTaskId;
      } catch (_) {
        db.execute(
          "UPDATE o_video SET submissionState='uncertain' WHERE id=?",
          [videoId],
        );
        rethrow;
      }
      db.execute(
        "UPDATE o_video SET submissionState='accepted',upstreamTaskId=?,"
        "upstreamState='queued',upstreamUpdatedAt=? WHERE id=?",
        [upstreamTaskId, DateTime.now().millisecondsSinceEpoch, videoId],
      );
      submissionState = 'accepted';
      modelBinding = request.modelBinding;
    }

    if (submissionState != 'accepted' || upstreamTaskId.trim().isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': 'videoNotAccepted'});
    }
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    while (true) {
      if (token.isCancelled) throw const EngineException(errCanceled);
      final result = await gateway.pollVideo(
        upstreamTaskId,
        '$projectId',
        stage: 'shot_video',
        modelOverride: modelBinding,
        cancelToken: token,
      );
      if (token.isCancelled) throw const EngineException(errCanceled);
      db.execute(
          'UPDATE o_video SET upstreamState=?,upstreamUpdatedAt=? '
          'WHERE id=?',
          [
            result.upstreamState,
            DateTime.now().millisecondsSinceEpoch,
            videoId,
          ]);
      if (!result.isTerminal) {
        if (DateTime.now().isAfter(deadline)) {
          throw const EngineException(errNetwork, {'message': '上游任务超时'});
        }
        await Future<void>.delayed(const Duration(seconds: 10));
        continue;
      }
      if (result.upstreamState == 'succeeded' &&
          result.localVideoPath != null) {
        db.execute('UPDATE o_video SET state=?,filePath=? WHERE id=?',
            [vtDone, result.localVideoPath, videoId]);
        return true;
      }
      throw EngineException(
        result.errorMessage ?? '视频生成失败',
      );
    }
  }

  void _completeVideoTrack(int trackId, int videoId) {
    final selectedVideoId = db.select(
        'SELECT selectVideoId FROM o_videoTrack WHERE id=?',
        [trackId]).first['selectVideoId'] as int?;
    final hasDoneSelection = selectedVideoId != null &&
        db.select(
          'SELECT id FROM o_video WHERE id=? AND state=? LIMIT 1',
          [selectedVideoId, vtDone],
        ).isNotEmpty;
    db.execute(
      'UPDATE o_videoTrack SET state=?, reason=NULL'
      '${hasDoneSelection ? '' : ', selectVideoId=?, videoId=?'} WHERE id=?',
      hasDoneSelection
          ? [vtDone, trackId]
          : [vtDone, videoId, videoId, trackId],
    );
  }

  /// Builds retry task data without ever resubmitting an unknown upstream job.
  /// The caller owns the surrounding savepoint so candidate rows and the retry
  /// task either appear together or not at all.
  Map<String, dynamic> prepareVideoRetry(TasksRow task) {
    final projectId = task.projectId;
    if (projectId == null) {
      throw const EngineException(errPromptMissing, {'type': 'videoProject'});
    }
    final related = Map<String, dynamic>.from(task.relatedObjectsJson);
    var videoIds = _taskIds(related['videoIds']);
    final trackIds = _taskIds(related['trackIds']);
    if (videoIds.isEmpty && trackIds.isNotEmpty) {
      videoIds = db
          .select(
            'SELECT id FROM o_video WHERE id IN ('
            'SELECT MAX(id) FROM o_video '
            'WHERE videoTrackId IN (${_ph(trackIds)}) AND state=? '
            'GROUP BY videoTrackId'
            ') ORDER BY id',
            [...trackIds, vtFailed],
          )
          .map((row) => row['id'] as int)
          .toList();
    }
    if (videoIds.isEmpty) {
      throw const EngineException(errPromptMissing, {'type': 'videoRetry'});
    }

    final retryVideoIds = <int>[];
    final retryTrackIds = <int>{};
    for (final videoId in videoIds) {
      final candidate = db.select(
        'SELECT id,videoTrackId,submissionState,upstreamTaskId,upstreamState '
        'FROM o_video WHERE id=? AND projectId=? LIMIT 1',
        [videoId, projectId],
      ).firstOrNull;
      if (candidate == null) {
        throw EngineException(errPromptMissing, {'type': 'video:$videoId'});
      }
      final trackId = candidate['videoTrackId'] as int?;
      if (trackId == null) {
        throw EngineException(
            errPromptMissing, {'type': 'videoTrack:$videoId'});
      }
      final submissionState =
          (candidate['submissionState'] as String? ?? 'prepared').trim();
      final upstreamTaskId =
          (candidate['upstreamTaskId'] as String? ?? '').trim();
      final upstreamState =
          (candidate['upstreamState'] as String? ?? '').trim().toLowerCase();

      final retryVideoId = switch (submissionState) {
        'prepared' => _createRetryVideoCandidate(projectId, trackId),
        'accepted' when upstreamTaskId.isEmpty => _throwUncertainVideoRetry(),
        'accepted'
            when {'failed', 'canceled', 'cancelled'}.contains(upstreamState) =>
          _createRetryVideoCandidate(projectId, trackId),
        'accepted' => videoId,
        _ => _throwUncertainVideoRetry(),
      };
      if (retryVideoId == videoId) {
        db.execute(
          'UPDATE o_video SET state=?,errorReason=NULL WHERE id=?',
          [vtGenerating, videoId],
        );
      }
      db.execute(
        'UPDATE o_videoTrack SET state=?,reason=NULL WHERE id=?',
        [vtGenerating, trackId],
      );
      retryVideoIds.add(retryVideoId);
      retryTrackIds.add(trackId);
    }
    related['trackIds'] = retryTrackIds.toList(growable: false);
    related['videoIds'] = retryVideoIds;
    return related;
  }

  Never _throwUncertainVideoRetry() => throw const EngineException(
        errLlmFormat,
        {'reason': 'videoSubmissionUncertain'},
      );

  int _createRetryVideoCandidate(int projectId, int trackId) {
    final storyboardId = db.select(
      'SELECT id FROM o_storyboard WHERE trackId=? AND projectId=? LIMIT 1',
      [trackId, projectId],
    ).firstOrNull?['id'] as int?;
    if (storyboardId == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard:$trackId'});
    }
    final request = buildVideoRequest(
      projectId: projectId,
      storyboardId: storyboardId,
      trackId: trackId,
    );
    final scriptId = db.select(
      'SELECT scriptId FROM o_videoTrack WHERE id=? AND projectId=? LIMIT 1',
      [trackId, projectId],
    ).firstOrNull?['scriptId'] as int?;
    if (scriptId == null) {
      throw EngineException(errPromptMissing, {'type': 'videoTrack:$trackId'});
    }
    db.execute(
      'INSERT INTO o_video '
      '(projectId,scriptId,videoTrackId,state,time,submissionState,'
      'modelBinding,requestFingerprint) '
      "VALUES (?,?,?,?,?,'prepared',?,?)",
      [
        projectId,
        scriptId,
        trackId,
        vtGenerating,
        DateTime.now().millisecondsSinceEpoch,
        request.modelBinding,
        request.fingerprint(),
      ],
    );
    return db.lastInsertRowId;
  }

  Future<void> cancelVideoGenerationTask(int taskId) async {
    final task = db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?', [taskId]).firstOrNull;
    if (task == null) return;
    final raw = task['relatedObjects'] as String?;
    final related = raw == null || raw.trim().isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final trackIds = _taskIds(related['trackIds']);
    var videoIds = _taskIds(related['videoIds']);
    if (videoIds.isEmpty && trackIds.isNotEmpty) {
      videoIds = db
          .select(
            "SELECT id FROM o_video WHERE videoTrackId IN (${_ph(trackIds)}) "
            'AND state=?',
            [...trackIds, vtGenerating],
          )
          .map((row) => row['id'] as int)
          .toList();
    }
    if (videoIds.isEmpty) return;
    final candidates = db.select(
      'SELECT id,videoTrackId,upstreamTaskId,modelBinding,submissionState '
      'FROM o_video WHERE id IN (${_ph(videoIds)})',
      videoIds,
    );
    final cancelled = <String>{};
    for (final candidate in candidates) {
      final upstreamTaskId = candidate['upstreamTaskId'] as String? ?? '';
      final modelBinding = candidate['modelBinding'] as String? ?? '';
      if (candidate['submissionState'] != 'accepted' ||
          upstreamTaskId.trim().isEmpty ||
          !cancelled.add('$modelBinding:$upstreamTaskId')) {
        continue;
      }
      try {
        await gateway.cancelVideo(
          upstreamTaskId,
          stage: 'shot_video',
          modelOverride: modelBinding.isEmpty ? null : modelBinding,
        );
      } catch (_) {
        // Remote cancellation is best effort; local state must still settle.
      }
    }
    final reason = const EngineException(errCanceled).toReasonJson();
    db.execute(
      'UPDATE o_video SET state=?,errorReason=?,upstreamState=? '
      'WHERE id IN (${_ph(videoIds)}) AND state=?',
      [vtFailed, reason, 'cancelled', ...videoIds, vtGenerating],
    );
    final affectedTrackIds = candidates
        .map((candidate) => candidate['videoTrackId'] as int?)
        .whereType<int>()
        .toSet()
        .toList();
    if (affectedTrackIds.isNotEmpty) {
      db.execute(
        'UPDATE o_videoTrack SET state=?,reason=? '
        'WHERE id IN (${_ph(affectedTrackIds)}) AND state=?',
        [vtFailed, reason, ...affectedTrackIds, vtGenerating],
      );
    }
  }

  List<int> _taskIds(Object? value) => [
        for (final item in value is List ? value : const [])
          if (item is num) item.toInt(),
      ];

  void _recoverVideoGeneration(TasksRow task) {
    final trackIds = (task.relatedObjectsJson['trackIds'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (trackIds.isEmpty) return;
    final reason = const EngineException(errAppRestart).toReasonJson();
    db.execute(
      'UPDATE o_videoTrack SET state=?, reason=? '
      'WHERE id IN (${_ph(trackIds)}) AND state=?',
      [vtFailed, reason, ...trackIds, vtGenerating],
    );
    db.execute(
      'UPDATE o_video SET state=?, errorReason=? '
      'WHERE videoTrackId IN (${_ph(trackIds)}) AND state=?',
      [vtFailed, reason, ...trackIds, vtGenerating],
    );
  }

  ColdStartDisposition _resumeVideoGenerationOnColdStart(TasksRow task) {
    final trackIds = (task.relatedObjectsJson['trackIds'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (trackIds.isEmpty) return ColdStartDisposition.fail;
    final reason = const EngineException(errAppRestart).toReasonJson();
    db.execute(
      'UPDATE o_video SET state=?, errorReason=? '
      'WHERE videoTrackId IN (${_ph(trackIds)}) '
      "AND submissionState IN ('prepared','submitting','uncertain')",
      [vtFailed, reason, ...trackIds],
    );
    final accepted = db.select(
      'SELECT id FROM o_video WHERE videoTrackId IN (${_ph(trackIds)}) '
      "AND submissionState='accepted' "
      "AND trim(coalesce(upstreamTaskId,''))<>'' LIMIT 1",
      trackIds,
    );
    return accepted.isEmpty
        ? ColdStartDisposition.fail
        : ColdStartDisposition.resume;
  }

  /// 选择候选视频（更新 selectVideoId，videoId 同步写入避免死字段）。
  void selectVideo(int trackId, int videoId) {
    db.execute(
      'UPDATE o_videoTrack SET selectVideoId=?, videoId=? WHERE id=?',
      [videoId, videoId, trackId],
    );
  }

  /// 从素材库 clip 复用一个本地视频作为当前轨道候选，并立即选为正片。
  int attachClipToTrack(int trackId, int clipAssetId) {
    final trackRow = db
        .select('SELECT * FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (trackRow == null) {
      throw EngineException(errPromptMissing, {'type': 'videoTrack'});
    }
    final clipRow = db.select(
      'SELECT a.type type, i.filePath filePath '
      'FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=? AND a.projectId=?',
      [clipAssetId, trackRow['projectId']],
    ).firstOrNull;
    final rel = clipRow?['filePath'] as String?;
    if (clipRow == null ||
        clipRow['type'] != 'clip' ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'clip'});
    }
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state,time) '
      'VALUES (?,?,?,?,?,?)',
      [
        trackRow['projectId'],
        trackRow['scriptId'],
        trackId,
        rel,
        vtDone,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final videoId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_videoTrack SET state=?, reason=NULL, selectVideoId=?, videoId=? '
      'WHERE id=?',
      [vtDone, videoId, videoId, trackId],
    );
    return videoId;
  }

  /// 将某个工作台候选视频登记回素材库 clip，便于其他镜头复用。
  int saveVideoCandidateAsClip(int videoId, {String? name}) {
    final row = db.select(
      'SELECT projectId,filePath FROM o_video WHERE id=? AND state=?',
      [videoId, vtDone],
    ).firstOrNull;
    final rel = row?['filePath'] as String?;
    if (row == null ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'video'});
    }
    return registerClipAsset(
      projectId: (row['projectId'] as int?) ?? 0,
      name: name?.trim().isNotEmpty == true ? name!.trim() : '镜头候选 #$videoId',
      relPath: rel,
    );
  }

  void deleteVideo(int videoId) {
    final row = db.select(
        'SELECT videoTrackId,filePath FROM o_video WHERE id=?',
        [videoId]).firstOrNull;
    if (row == null) return;
    // 先删磁盘文件再删行（此前只删行，泄漏了候选视频 .mp4）。
    final rel = row['filePath'] as String?;
    if (rel != null && rel.isNotEmpty) {
      final stillReferencedByAsset = db.select(
          'SELECT id FROM o_image WHERE filePath=? LIMIT 1', [rel]).isNotEmpty;
      if (!stillReferencedByAsset) {
        final file = File(media.absPath(rel));
        if (file.existsSync()) file.deleteSync();
      }
    }
    db.execute(
      'UPDATE o_videoTrack SET selectVideoId=NULL, videoId=NULL '
      'WHERE id=? AND (selectVideoId=? OR videoId=?)',
      [row['videoTrackId'], videoId, videoId],
    );
    db.execute('DELETE FROM o_video WHERE id=?', [videoId]);
  }

  /// 删除整条视频轨：保留分镜行本身，但清空 storyboard.trackId，并删除该轨道
  /// 下所有候选视频。候选文件删除沿用 deleteVideo 的素材库引用保护逻辑。
  void deleteVideoTrack(int trackId) {
    final row = db.select(
        'SELECT id FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (row == null) return;
    final videoIds = db
        .select('SELECT id FROM o_video WHERE videoTrackId=? ORDER BY id',
            [trackId])
        .map((r) => r['id'] as int)
        .toList();
    for (final videoId in videoIds) {
      deleteVideo(videoId);
    }
    db.execute(
        'UPDATE o_storyboard SET trackId=NULL WHERE trackId=?', [trackId]);
    db.execute('DELETE FROM o_videoTrack WHERE id=?', [trackId]);
  }
}

String? _nleValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
