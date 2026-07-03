import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../api/models.dart';
import 'compose.dart';
import 'config.dart';
import 'db.dart';
import 'errors.dart';
import 'media.dart';
import 'prompts.dart' as prompt_defs;
import 'providers/gateway.dart';
import 'providers/resolve.dart';
import 'queue.dart';

class ProjectRow {
  final int id;
  final String? artStyle;
  final int? createTime;
  final String? directorManual;
  final String? imageModel;
  final String? imageQuality;
  final String? intro;
  final String? mode;
  final String? name;
  final String? projectType;
  final String? type;
  final int? userId;
  final String? videoModel;
  final String? videoRatio;

  const ProjectRow({
    required this.id,
    required this.artStyle,
    required this.createTime,
    required this.directorManual,
    required this.imageModel,
    required this.imageQuality,
    required this.intro,
    required this.mode,
    required this.name,
    required this.projectType,
    required this.type,
    required this.userId,
    required this.videoModel,
    required this.videoRatio,
  });

  factory ProjectRow.fromRow(Row row) => ProjectRow(
        id: row['id'] as int,
        artStyle: row['artStyle'] as String?,
        createTime: row['createTime'] as int?,
        directorManual: row['directorManual'] as String?,
        imageModel: row['imageModel'] as String?,
        imageQuality: row['imageQuality'] as String?,
        intro: row['intro'] as String?,
        mode: row['mode'] as String?,
        name: row['name'] as String?,
        projectType: row['projectType'] as String?,
        type: row['type'] as String?,
        userId: row['userId'] as int?,
        videoModel: row['videoModel'] as String?,
        videoRatio: row['videoRatio'] as String?,
      );
}

class Engine {
  static const version = '0.3.0-task3';

  final Database db;
  final MediaStore media;
  final ProviderGateway gateway;
  final EngineConfig config;
  late final JobQueue queue;

  Engine({
    required this.db,
    required this.media,
    required this.gateway,
    required this.config,
    VideoComposer? composer,
    Duration queueTick = const Duration(milliseconds: 500),
    TaskRunner? taskRunner,
  }) {
    queue = JobQueue(
      db,
      run: taskRunner ?? _unsupportedTaskRunner,
      tick: queueTick,
    );
  }

  static Future<Engine> boot({
    required String dataDir,
    required bool isMobile,
    VideoComposer? composer,
  }) async {
    Directory(dataDir).createSync(recursive: true);
    final db = openEngineDb(path.join(dataDir, 'dramaflow.sqlite'));
    final config = EngineConfig(db, isMobile: isMobile);
    _seedDefaults(db, config, isMobile: isMobile);
    final media = MediaStore(path.join(dataDir, 'media'));
    final engine = Engine(
      db: db,
      media: media,
      gateway: HttpProviderGateway(db, config, media),
      config: config,
      composer: composer,
    );
    engine.queue.recoverOnColdStart();
    engine.queue.start();
    return engine;
  }

  static Future<void> _unsupportedTaskRunner(
    TasksRow task,
    CancelToken token,
  ) {
    throw EngineException(errLlmFormat, {'taskClass': task.taskClass});
  }

  static void _seedDefaults(
    Database db,
    EngineConfig config, {
    required bool isMobile,
  }) {
    if ((db.select('SELECT COUNT(*) n FROM o_vendorConfig').first['n']
            as int) ==
        0) {
      void provider({
        required String id,
        required String name,
        required String protocol,
        required String baseUrl,
        required String apiKey,
        required List<Map<String, Object?>> models,
      }) {
        db.execute(
          'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
          [
            id,
            1,
            jsonEncode({
              'name': name,
              'protocol': protocol,
              'baseUrl': baseUrl,
              'apiKey': apiKey,
              'createdAt': nowIso(),
            }),
            jsonEncode(models),
          ],
        );
      }

      Map<String, Object?> model(
              String providerId, String modelId, String label, String kind,
              [Map<String, Object?> capabilities = const {}]) =>
          {
            'id': '$providerId:$modelId',
            'providerId': providerId,
            'modelId': modelId,
            'label': label,
            'kind': kind,
            'capabilities': capabilities,
            'enabled': true,
          };

      if (!isMobile) {
        provider(
          id: 'azt',
          name: 'azt',
          protocol: 'openai_compatible',
          baseUrl: 'http://127.0.0.1:8787/v1',
          apiKey: 'local',
          models: [
            for (final modelId in ['gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'])
              model('azt', modelId, modelId, 'text'),
            model('azt', 'gpt-image-2', 'gpt-image-2', 'image'),
          ],
        );
      }

      provider(
        id: 'volcengine',
        name: 'volcengine',
        protocol: 'volcengine',
        baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
        apiKey: isMobile ? '' : config.str('videoApiKey'),
        models: [
          model('volcengine', 'doubao-seed-1-6-250615',
              'doubao-seed-1-6-250615', 'text'),
          model('volcengine', 'doubao-seedream-4-0-250828',
              'doubao-seedream-4-0-250828', 'image'),
          model(
            'volcengine',
            'doubao-seedance-2-0-mini-260615',
            'doubao-seedance-2-0-mini-260615',
            'video',
            {
              'durations': [for (var i = 4; i <= 15; i++) i],
              'resolutions': ['480p', '720p'],
            },
          ),
        ],
      );
    }

    void binding(String stage, String value) {
      final key = 'binding.$stage';
      final rows = db.select('SELECT value FROM o_setting WHERE key=?', [key]);
      if (rows.isEmpty ||
          ((rows.first['value'] as String?) ?? '').trim().isEmpty) {
        db.execute(
          'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
          [key, value],
        );
      }
    }

    if (isMobile) {
      binding('script_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_extract', 'volcengine:doubao-seed-1-6-250615');
      binding('storyboard_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    } else {
      binding('script_gen', 'azt:gpt-5.5');
      binding('asset_extract', 'azt:gpt-5.5');
      binding('storyboard_gen', 'azt:gpt-5.5');
      binding('asset_image', 'azt:gpt-image-2');
      binding('shot_image', 'azt:gpt-image-2');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    }

    if ((db.select('SELECT COUNT(*) n FROM o_prompt').first['n'] as int) == 0) {
      final prompts = {
        ...prompt_defs.defaultSystemPrompts,
        prompt_defs.promptKeyImageSizeDirective:
            config.str('imageSizeDirective'),
      };
      for (final entry in prompts.entries) {
        db.execute(
          'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
          [entry.key, 'system', entry.value, entry.value],
        );
      }
    }
  }

  void dispose() {
    queue.dispose();
  }

  String mediaAbsPath(String rel) => media.absPath(rel);

  Future<Map<String, dynamic>> health() async => {
        'version': version,
        'providers': {
          for (final stage in ['text', 'image', 'video'])
            stage: _bindingSummary(stage),
        },
      };

  String _bindingSummary(String group) {
    final stage = switch (group) {
      'text' => 'script_gen',
      'image' => 'asset_image',
      'video' => 'shot_video',
      _ => group,
    };
    final rows = db
        .select('SELECT value FROM o_setting WHERE key=?', ['binding.$stage']);
    return rows.isEmpty ? '未配置' : rows.first['value'] as String;
  }

  List<ProjectRow> projects() => db
      .select(
          'SELECT * FROM o_project ORDER BY COALESCE(createTime,0) DESC, id DESC')
      .map(ProjectRow.fromRow)
      .toList();

  int addProject({
    required String projectType,
    required String name,
    String? intro,
    String? type,
    String? artStyle,
    String? directorManual,
    String? videoRatio,
    String? imageModel,
    String? videoModel,
    String? imageQuality,
    String? mode,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '项目名称不能为空'});
    }
    db.execute(
      '''
INSERT INTO o_project (
  projectType,name,intro,type,artStyle,directorManual,videoRatio,
  imageModel,videoModel,imageQuality,mode,createTime
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
''',
      [
        projectType,
        trimmed,
        intro,
        type,
        artStyle,
        directorManual,
        videoRatio,
        imageModel,
        videoModel,
        imageQuality,
        mode,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return db.lastInsertRowId;
  }

  void editProject(
    int id, {
    String? projectType,
    String? name,
    String? intro,
    String? type,
    String? artStyle,
    String? directorManual,
    String? videoRatio,
    String? imageModel,
    String? videoModel,
    String? imageQuality,
    String? mode,
  }) {
    _mustProject(id);
    db.execute(
      '''
UPDATE o_project SET
  projectType=COALESCE(?,projectType),
  name=COALESCE(?,name),
  intro=COALESCE(?,intro),
  type=COALESCE(?,type),
  artStyle=COALESCE(?,artStyle),
  directorManual=COALESCE(?,directorManual),
  videoRatio=COALESCE(?,videoRatio),
  imageModel=COALESCE(?,imageModel),
  videoModel=COALESCE(?,videoModel),
  imageQuality=COALESCE(?,imageQuality),
  mode=COALESCE(?,mode)
WHERE id=?
''',
      [
        projectType,
        name?.trim(),
        intro,
        type,
        artStyle,
        directorManual,
        videoRatio,
        imageModel,
        videoModel,
        imageQuality,
        mode,
        id,
      ],
    );
  }

  void deleteProject(int id) {
    _mustProject(id);
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM o_agentWorkData WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_novel WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_scriptAssets WHERE scriptId IN (SELECT id FROM o_script WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_script WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_assets2Storyboard WHERE storyboardId IN (SELECT id FROM o_storyboard WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_storyboard WHERE projectId=?', [id]);
      db.execute('UPDATE o_assets SET imageId=NULL WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_image WHERE assetsId IN (SELECT id FROM o_assets WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_assets WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_tasks WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_videoTrack WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_video WHERE projectId=?', [id]);
      db.execute('DELETE FROM memories WHERE isolationKey LIKE ?', ['$id:%']);
      db.execute('DELETE FROM o_project WHERE id=?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    media.deleteProject(id.toString());
    queue.notifyChanged();
  }

  ProjectRow _mustProject(int id) {
    final rows = db.select('SELECT * FROM o_project WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '项目不存在'});
    }
    return ProjectRow.fromRow(rows.first);
  }

  Future<List<ProjectRow>> listProjects() async => projects();

  Future<ProjectRow> getProject(int id) async => _mustProject(id);

  Future<ProjectRow> createProject(String name, {String artStyle = ''}) async {
    final id = addProject(
      projectType: 'drama',
      name: name,
      artStyle: artStyle,
    );
    return _mustProject(id);
  }

  Future<void> removeProject(int id) async => deleteProject(id);

  Future<List<TasksRow>> activeJobs() async => db
      .select(
        "SELECT * FROM o_tasks WHERE state IN ('pending','processing') ORDER BY id DESC",
      )
      .map(TasksRow.fromRow)
      .toList();

  Future<List<TasksRow>> projectJobs(int projectId, {int limit = 50}) async =>
      db
          .select(
            'SELECT * FROM o_tasks WHERE projectId=? ORDER BY id DESC LIMIT ?',
            [projectId, limit],
          )
          .map(TasksRow.fromRow)
          .toList();

  Future<int> retryJob(int taskId) async {
    final rows = db.select('SELECT * FROM o_tasks WHERE id=?', [taskId]);
    if (rows.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '任务不存在'});
    }
    final task = TasksRow.fromRow(rows.first);
    if (task.state != 'failed') {
      throw const EngineException(errLlmFormat, {'reason': '只有失败的任务可以重试'});
    }
    db.execute(
      "UPDATE o_tasks SET state='pending', reason=NULL, startTime=? WHERE id=?",
      [DateTime.now().millisecondsSinceEpoch, taskId],
    );
    queue.notifyChanged();
    return taskId;
  }

  Future<void> cancelJob(int taskId) async => queue.cancel(taskId);

  Future<AppSettings> getSettings() async =>
      AppSettings.fromJson(config.getAllMasked());

  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    config.update(patch);
    return getSettings();
  }

  Future<String> getThemeMode() async => config.str('themeMode');

  Future<void> setThemeMode(String themeMode) async {
    if (!{'light', 'dark', 'system'}.contains(themeMode)) {
      throw const EngineException(errLlmFormat, {'reason': '主题模式无效'});
    }
    config.update({'themeMode': themeMode});
  }

  Future<String> getAppLocale() async => config.str('app.locale');

  Future<void> setAppLocale(String locale) async {
    if (!{'', 'zh', 'en', 'ja'}.contains(locale)) {
      throw const EngineException(errLlmFormat, {'reason': '语言设置无效'});
    }
    config.update({'app.locale': locale});
  }

  Future<List<ProviderInfo>> listProviders() async => db
      .select('SELECT * FROM o_vendorConfig ORDER BY id')
      .map(_providerInfo)
      .toList();

  ProviderInfo _providerInfo(Row row) {
    final input = _jsonMap(row['inputValues']);
    return ProviderInfo.fromJson({
      'id': row['id'],
      'name': input['name'] ?? row['id'],
      'protocol': input['protocol'] ?? 'openai_compatible',
      'baseUrl': input['baseUrl'] ?? '',
      'apiKey': input['apiKey'] ?? '',
      'enabled': row['enable'] ?? 1,
      'createdAt': input['createdAt'] ?? '',
    });
  }

  Future<ProviderInfo> createProvider({
    required String name,
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    final id = _providerId(name);
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        id,
        1,
        jsonEncode({
          'name': name.trim(),
          'protocol': protocol,
          'baseUrl': baseUrl.trim(),
          'apiKey': apiKey,
          'createdAt': nowIso(),
        }),
        '[]',
      ],
    );
    return _providerInfo(
      db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]).first,
    );
  }

  Future<ProviderInfo> updateProvider(
    String id, {
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
  }) async {
    final row = _mustProvider(id);
    final input = _jsonMap(row['inputValues']);
    if (name != null) input['name'] = name.trim();
    if (baseUrl != null) input['baseUrl'] = baseUrl.trim();
    if (apiKey != null) input['apiKey'] = apiKey;
    db.execute(
      'UPDATE o_vendorConfig SET enable=COALESCE(?,enable), inputValues=? WHERE id=?',
      [enabled == null ? null : (enabled ? 1 : 0), jsonEncode(input), id],
    );
    return _providerInfo(
      db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]).first,
    );
  }

  Future<void> deleteProvider(String id) async {
    final bindings = await getBindings();
    if (bindings.values.any((value) => value.startsWith('$id:'))) {
      throw const EngineException(errProviderMissing, {'reason': '供应商正在使用'});
    }
    db.execute('DELETE FROM o_vendorConfig WHERE id=?', [id]);
  }

  Future<List<ProviderModelInfo>> listProviderModels(String providerId) async {
    final row = _mustProvider(providerId);
    return _models(row).map(ProviderModelInfo.fromJson).toList();
  }

  Future<void> saveProviderModels(
    String providerId,
    List<Map<String, dynamic>> models,
  ) async {
    _mustProvider(providerId);
    final normalized = [
      for (final model in models) _normalizeModel(providerId, model),
    ];
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [jsonEncode(normalized), providerId],
    );
  }

  Future<int> testProvider(String providerId, String modelId) async {
    final provider = _providerInfo(_mustProvider(providerId));
    final model = (await listProviderModels(providerId))
        .firstWhere((item) => item.modelId == modelId);
    if (model.kind != 'text') {
      throw const EngineException(errModelMissing, {'reason': '暂只支持文本模型连通测试'});
    }
    if (gateway is! HttpProviderGateway) {
      throw const EngineException(
          errProviderMissing, {'reason': '当前网关不支持连通测试'});
    }
    final resolved = ResolvedModel(
      providerId: provider.id,
      protocol: provider.protocol,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      modelId: model.modelId,
    );
    return (gateway as HttpProviderGateway).testTextModel(resolved);
  }

  void _writeSetting(String key, String value) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [key, value],
    );
  }

  Future<Map<String, String>> getBindings() async => {
        for (final row in db.select(
          "SELECT key,value FROM o_setting WHERE key LIKE 'binding.%'",
        ))
          (row['key'] as String).substring('binding.'.length):
              row['value'] as String,
      };

  Future<void> setBinding(
    String stage,
    String providerId,
    String modelId,
  ) async {
    final requiredKind = requiredKindForStage(stage);
    final models = await listProviderModels(providerId);
    ProviderModelInfo? model;
    for (final item in models) {
      if (item.modelId == modelId) {
        model = item;
        break;
      }
    }
    if (model == null) {
      throw const EngineException(errModelMissing, {'reason': '模型不存在'});
    }
    if (model.kind != requiredKind) {
      throw EngineException(errModelMissing, {
        'stage': stage,
        'requiredKind': requiredKind,
        'actualKind': model.kind,
      });
    }
    _writeSetting('binding.$stage', '$providerId:$modelId');
  }

  Future<List<Map<String, dynamic>>> listPrompts() async => db
      .select('SELECT * FROM o_prompt ORDER BY id')
      .map((row) => {
            'key': row['name'],
            'content': row['useData'] ?? row['data'] ?? '',
            'updatedAt': '',
          })
      .toList();

  Future<void> updatePrompt(String key, String content) async {
    final rows = db.select('SELECT id FROM o_prompt WHERE name=?', [key]);
    if (rows.isEmpty) {
      db.execute(
        'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
        [key, 'system', _defaultPrompt(key), content],
      );
    } else {
      db.execute('UPDATE o_prompt SET useData=? WHERE name=?', [content, key]);
    }
  }

  Future<void> resetPrompt(String key) async {
    final content = _defaultPrompt(key);
    final rows = db.select('SELECT id FROM o_prompt WHERE name=?', [key]);
    if (rows.isEmpty) {
      db.execute(
        'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
        [key, 'system', content, content],
      );
    } else {
      db.execute(
        'UPDATE o_prompt SET data=?, useData=? WHERE name=?',
        [content, content, key],
      );
    }
  }

  Future<Map<String, dynamic>> exportConfig() async => {
        'providers': [
          for (final provider in await listProviders())
            {
              'id': provider.id,
              'name': provider.name,
              'protocol': provider.protocol,
              'baseUrl': provider.baseUrl,
              'apiKey': provider.apiKey,
              'enabled': provider.enabled,
              'models': [
                for (final model in await listProviderModels(provider.id))
                  {
                    'id': model.id,
                    'modelId': model.modelId,
                    'label': model.label,
                    'kind': model.kind,
                    'capabilities': model.capabilities,
                    'enabled': model.enabled,
                  },
              ],
            },
        ],
        'bindings': await getBindings(),
        'prompts': await listPrompts(),
      };

  Future<void> importConfig(Map<String, dynamic> data) async {
    final providers = data['providers'];
    if (providers is List) {
      for (final raw in providers.whereType<Map>()) {
        final id =
            (raw['id'] ?? _providerId('${raw['name'] ?? ''}')).toString();
        final inputValues = {
          'name': (raw['name'] ?? id).toString(),
          'protocol': (raw['protocol'] ?? 'openai_compatible').toString(),
          'baseUrl': (raw['baseUrl'] ?? '').toString(),
          'apiKey': (raw['apiKey'] ?? '').toString(),
          'createdAt': nowIso(),
        };
        final models = [
          for (final model
              in (raw['models'] as List? ?? const []).whereType<Map>())
            _normalizeModel(id, Map<String, dynamic>.from(model)),
        ];
        db.execute(
          '''
INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)
ON CONFLICT(id) DO UPDATE SET enable=excluded.enable,inputValues=excluded.inputValues,models=excluded.models
''',
          [
            id,
            _boolish(raw['enabled']) ? 1 : 0,
            jsonEncode(inputValues),
            jsonEncode(models),
          ],
        );
      }
    }
    final bindings = data['bindings'];
    if (bindings is Map) {
      for (final entry in bindings.entries) {
        _writeSetting('binding.${entry.key}', entry.value.toString());
      }
    }
    final prompts = data['prompts'];
    if (prompts is List) {
      for (final prompt in prompts.whereType<Map>()) {
        final key = (prompt['key'] ?? '').toString();
        if (key.isEmpty) continue;
        await updatePrompt(key, (prompt['content'] ?? '').toString());
      }
    }
  }

  Row _mustProvider(String id) {
    final rows = db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const EngineException(errProviderMissing);
    }
    return rows.first;
  }

  List<Map<String, dynamic>> _models(Row row) {
    final decoded = _jsonList(row['models']);
    return [
      for (final item in decoded.whereType<Map>())
        Map<String, dynamic>.from(item),
    ];
  }

  Map<String, dynamic> _normalizeModel(
    String providerId,
    Map<String, dynamic> model,
  ) {
    final modelId = (model['modelId'] ?? '').toString().trim();
    if (modelId.isEmpty) {
      throw const EngineException(errModelMissing, {'reason': '模型 ID 不能为空'});
    }
    final kind = (model['kind'] ?? 'text').toString();
    if (!{'text', 'image', 'video', 'tts'}.contains(kind)) {
      throw const EngineException(errModelMissing, {'reason': '模型类型无效'});
    }
    return {
      'id': (model['id'] ?? '$providerId:$modelId').toString(),
      'providerId': providerId,
      'modelId': modelId,
      'label': (model['label'] ?? modelId).toString(),
      'kind': kind,
      'capabilities': model['capabilities'] is Map
          ? Map<String, dynamic>.from(model['capabilities'] as Map)
          : <String, dynamic>{},
      'enabled': _boolish(model['enabled']),
    };
  }

  String _defaultPrompt(String key) {
    if (key == prompt_defs.promptKeyImageSizeDirective) {
      return config.str('imageSizeDirective');
    }
    final content = prompt_defs.defaultSystemPrompts[key];
    if (content == null) {
      throw const EngineException(errLlmFormat, {'reason': '未知提示词'});
    }
    return content;
  }

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  List<dynamic> _jsonList(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
    }
    return const [];
  }

  bool _boolish(Object? value) =>
      value == null || value == true || value == 1 || value == '1';

  String _providerId(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty
        ? 'provider-${DateTime.now().microsecondsSinceEpoch}'
        : slug;
  }
}
