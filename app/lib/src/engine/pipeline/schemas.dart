import '../util.dart';

/// LLM 结构化输出校验（对齐 server/src/pipeline/runners.ts 的 zod 定义，
/// 含 default('') 行为；kind 枚举扩展 prop）。

class EpisodeOut {
  final String title;
  final String synopsis;
  final List<Map<String, dynamic>> scenes;
  EpisodeOut(this.title, this.synopsis, this.scenes);
}

class ScriptOut {
  final List<EpisodeOut> episodes;
  ScriptOut(this.episodes);
}

String _str(dynamic v, {String fallback = ''}) =>
    v is String ? v : fallback;

ScriptOut parseScriptOut(dynamic json) {
  if (json is! Map) throw EngineException('episodes: 期望对象结构');
  final eps = json['episodes'];
  if (eps is! List || eps.isEmpty) {
    throw EngineException('episodes: 期望非空数组');
  }
  final out = <EpisodeOut>[];
  for (final (i, e) in eps.indexed) {
    if (e is! Map) throw EngineException('episodes[$i]: 期望对象');
    final title = e['title'];
    if (title is! String || title.isEmpty) {
      throw EngineException('episodes[$i].title: 期望非空字符串');
    }
    final scenes = e['scenes'];
    if (scenes is! List || scenes.isEmpty) {
      throw EngineException('episodes[$i].scenes: 期望非空数组');
    }
    final normScenes = <Map<String, dynamic>>[];
    for (final (j, s) in scenes.indexed) {
      if (s is! Map) throw EngineException('scenes[$j]: 期望对象');
      final location = s['location'];
      final action = s['action'];
      if (location is! String) {
        throw EngineException('scenes[$j].location: 期望字符串');
      }
      if (action is! String) {
        throw EngineException('scenes[$j].action: 期望字符串');
      }
      final dialogues = <Map<String, dynamic>>[];
      final rawD = s['dialogues'];
      if (rawD is List) {
        for (final d in rawD) {
          if (d is Map) {
            dialogues.add({
              'speaker': _str(d['speaker']),
              'line': _str(d['line']),
            });
          }
        }
      }
      normScenes.add({
        'location': location,
        'timeOfDay': _str(s['timeOfDay']),
        'action': action,
        'dialogues': dialogues,
      });
    }
    out.add(EpisodeOut(title, _str(e['synopsis']), normScenes));
  }
  return ScriptOut(out);
}

class AssetOut {
  final String kind;
  final String name;
  final String description;
  final String imagePrompt;
  AssetOut(this.kind, this.name, this.description, this.imagePrompt);
}

const _assetKinds = {'character', 'scene', 'prop'};

List<AssetOut> parseAssetsOut(dynamic json) {
  if (json is! Map) throw EngineException('assets: 期望对象结构');
  final list = json['assets'];
  if (list is! List || list.isEmpty) {
    throw EngineException('assets: 期望非空数组');
  }
  final out = <AssetOut>[];
  for (final (i, a) in list.indexed) {
    if (a is! Map) throw EngineException('assets[$i]: 期望对象');
    final kind = a['kind'];
    if (kind is! String || !_assetKinds.contains(kind)) {
      throw EngineException(
          'assets[$i].kind: 期望 character/scene/prop，收到 $kind');
    }
    final name = a['name'];
    if (name is! String || name.isEmpty) {
      throw EngineException('assets[$i].name: 期望非空字符串');
    }
    out.add(AssetOut(
        kind, name, _str(a['description']), _str(a['imagePrompt'])));
  }
  return out;
}

class ShotOut {
  final String description;
  final String camera;
  final String dialogue;
  final List<String> assetNames;
  final String imagePrompt;
  final String videoPrompt;
  ShotOut(this.description, this.camera, this.dialogue, this.assetNames,
      this.imagePrompt, this.videoPrompt);
}

List<ShotOut> parseShotsOut(dynamic json) {
  if (json is! Map) throw EngineException('shots: 期望对象结构');
  final list = json['shots'];
  if (list is! List || list.isEmpty) {
    throw EngineException('shots: 期望非空数组');
  }
  final out = <ShotOut>[];
  for (final (i, s) in list.indexed) {
    if (s is! Map) throw EngineException('shots[$i]: 期望对象');
    final imagePrompt = s['imagePrompt'];
    if (imagePrompt is! String || imagePrompt.isEmpty) {
      throw EngineException('shots[$i].imagePrompt: 期望非空字符串');
    }
    final names = <String>[];
    final rawNames = s['assetNames'];
    if (rawNames is List) {
      names.addAll(rawNames.map((e) => e.toString()));
    }
    out.add(ShotOut(_str(s['description']), _str(s['camera']),
        _str(s['dialogue']), names, imagePrompt, _str(s['videoPrompt'])));
  }
  return out;
}
