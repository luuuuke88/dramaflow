import 'package:sqlite3/sqlite3.dart';

import '../util.dart';

const stageKindByStage = {
  'script_gen': 'text',
  'asset_extract': 'text',
  'storyboard_gen': 'text',
  'asset_image': 'image',
  'shot_image': 'image',
  'shot_video': 'video',
  'tts': 'tts',
};

class ResolvedModel {
  final String providerId;
  final String protocol;
  final String baseUrl;
  final String apiKey;
  final String modelId;

  const ResolvedModel({
    required this.providerId,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
  });
}

String requiredKindForStage(String stage) {
  final kind = stageKindByStage[stage];
  if (kind == null) throw EngineException('未知环节 $stage');
  return kind;
}

ResolvedModel resolveStage(Database db, String stage) {
  requiredKindForStage(stage);
  final key = 'binding.$stage';
  final bindings = db.select('SELECT value FROM settings WHERE key=?', [key]);
  if (bindings.isEmpty || (bindings.first['value'] as String).trim().isEmpty) {
    throw EngineException('环节 $stage 未绑定模型，请到设置配置');
  }

  final value = bindings.first['value'] as String;
  final sep = value.indexOf(':');
  if (sep <= 0 || sep == value.length - 1) {
    throw EngineException('环节 $stage 绑定格式无效，请到设置配置');
  }
  final providerId = value.substring(0, sep);
  final modelId = value.substring(sep + 1);

  final providers = db.select(
      'SELECT id, protocol, baseUrl, apiKey FROM providers WHERE id=? AND enabled=1',
      [providerId]);
  if (providers.isEmpty) {
    throw EngineException('环节 $stage 绑定的供应商不存在或已停用，请到设置配置');
  }

  final models = db.select(
      'SELECT modelId FROM provider_models WHERE providerId=? AND modelId=? AND enabled=1',
      [providerId, modelId]);
  if (models.isEmpty) {
    throw EngineException('环节 $stage 绑定的模型不存在或已停用，请到设置配置');
  }

  final p = providers.first;
  return ResolvedModel(
    providerId: p['id'] as String,
    protocol: p['protocol'] as String,
    baseUrl: p['baseUrl'] as String,
    apiKey: p['apiKey'] as String,
    modelId: modelId,
  );
}
