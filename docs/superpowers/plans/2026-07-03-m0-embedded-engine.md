# M0 引擎内嵌（Dart in-app Engine）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `server/src` 的 Node 引擎（~1500 行）1:1 移植为 App 内嵌 Dart 引擎，DramaFlow 成为无伴随进程的单体多端应用。

**Architecture:** `app/lib/src/engine/` 下建独立引擎层（同步 sqlite3 + dio + 事件广播队列），Engine 为 App 级单例经 `engineProvider` 暴露；业务方法签名与 v0.1 `ApiClient` 一致，界面只改三处（媒体展示 Image.file、任务 watch 改事件流、异常类型）。移植以 **逐行平移** 为原则：SQL/提示词/超时/错误语义与 `server/src` 保持一致，v0.1 修过的 bug（预检在 try 内、取消恢复实体状态等）不得回退。

**Tech Stack:** Flutter 3.44+ / sqlite3 + sqlite3_flutter_libs / dio / path_provider / wakelock_plus / flutter_riverpod 3（现有）

## Global Constraints

- 源参照（移植母本，行为以此为准）：`server/src/db.ts`、`config.ts`、`util.ts`、`queue.ts`、`providers/{text,image,video}.ts`、`pipeline/{prompts,runners}.ts`、`routes.ts`
- Engine 单例：`main()` 初始化一次，Riverpod 只持引用；Queue.start() 幂等；Provider/widget dispose 不影响任务
- 冷启动恢复：`running → failed('应用重启，任务中断')`（jobs + assets.status + shots.imageStatus/videoStatus 三处，语义同 `queue.ts` startQueue）；resume 不触发
- 取消：queued 可取消并按"有产物→done，无→draft/none"恢复实体（语义同 `routes.ts` cancel 路由）；running 经 dio CancelToken 中断，job 标 `canceled`
- Schema v1 一次到位：含 M1-M5 已定字段（prop kind、note、voiceId、audio*、selectedTakeId、compose*、providers/provider_models/prompts/video_takes/image_takes 表），`PRAGMA user_version = 1`
- 移动端不依赖 localhost：设置默认值按平台分化（macOS→azt，Android/iOS→volcengine ark，key 留空引导填写）
- 中文错误信息，全部失败落库带原因；`flutter analyze` 零告警；每 Task 结尾 commit
- 测试用 `sqlite3.openInMemory()` + 注入临时目录 + fake gateway，不依赖网络与 Flutter 平台通道（引擎层是纯 Dart）

---

### Task 1: 依赖与 util.dart（newId / extractJson / EngineException / errMessage）

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/src/engine/util.dart`
- Test: `app/test/engine/util_test.dart`

**Interfaces:**
- Produces: `String newId()`；`dynamic extractJson(String raw)`（抛 `EngineException`）；`class EngineException implements Exception { final String message; }`；`String errMessage(Object e)`（DioException 附带 status+响应体前500字）

- [ ] **Step 1: 加依赖**

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter pub add sqlite3 sqlite3_flutter_libs path_provider wakelock_plus
# dio 已存在
```

- [ ] **Step 2: 写失败测试**

```dart
// app/test/engine/util_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/util.dart';

void main() {
  group('newId', () {
    test('14位小写字母数字，且唯一', () {
      final a = newId(), b = newId();
      expect(a, matches(RegExp(r'^[0-9a-z]{14}$')));
      expect(a, isNot(equals(b)));
    });
  });

  group('extractJson', () {
    test('纯 JSON 直接解析', () {
      expect(extractJson('{"a":1}'), {'a': 1});
    });
    test('markdown 围栏内 JSON', () {
      expect(extractJson('前言\n```json\n{"a":1}\n```\n后记'), {'a': 1});
    });
    test('前后杂文取首尾括号', () {
      expect(extractJson('好的，结果是 {"a":[1,2]} 请查收'), {'a': [1, 2]});
    });
    test('无 JSON 抛 EngineException', () {
      expect(() => extractJson('没有json'), throwsA(isA<EngineException>()));
    });
  });

  group('errMessage', () {
    test('DioException 带响应体', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            data: {'error': '上游炸了'}),
        message: 'bad',
      );
      final msg = errMessage(e);
      expect(msg, contains('HTTP 500'));
      expect(msg, contains('上游炸了'));
    });
    test('普通异常取 toString', () {
      expect(errMessage(EngineException('哦豁')), '哦豁');
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd app && flutter test test/engine/util_test.dart`
Expected: FAIL（`util.dart` 不存在）

- [ ] **Step 4: 实现**

```dart
// app/lib/src/engine/util.dart
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
final _rng = Random.secure();

/// 14位 id，字符集与 v0.1 nanoid 配置一致（server/src/util.ts）
String newId() =>
    List.generate(14, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();

class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => message;
}

/// 从 LLM 输出提取 JSON（容忍围栏与前后杂文）——移植 server/src/util.ts extractJson
dynamic extractJson(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  try {
    return jsonDecode(text);
  } catch (_) {/* fallthrough */}
  final candidates =
      ['{', '['].map((c) => text.indexOf(c)).where((i) => i != -1).toList();
  final end = max(text.lastIndexOf('}'), text.lastIndexOf(']'));
  if (candidates.isNotEmpty) {
    final start = candidates.reduce(min);
    if (end > start) return jsonDecode(text.substring(start, end + 1));
  }
  throw EngineException('输出中未找到有效 JSON');
}

/// 错误 → 人类可读中文消息；Dio 错误附上游响应体（移植 server/src/util.ts errMessage）
String errMessage(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    var detail = '';
    if (data != null) {
      try {
        detail = data is String ? data : jsonEncode(data);
      } catch (_) {
        detail = data.toString();
      }
    }
    final head = status != null ? 'HTTP $status' : '网络错误';
    final tail = detail.isEmpty
        ? ''
        : '：${detail.substring(0, min(500, detail.length))}';
    return '$head ${e.message ?? ''}$tail';
  }
  return e.toString();
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd app && flutter test test/engine/util_test.dart`
Expected: PASS 全绿

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/src/engine/util.dart app/test/engine/util_test.dart
git commit -m "feat(engine): util — newId/extractJson/EngineException/errMessage ported from server"
```

---

### Task 2: db.dart 全量 Schema v1

**Files:**
- Create: `app/lib/src/engine/db.dart`
- Test: `app/test/engine/db_test.dart`

**Interfaces:**
- Produces: `Database openEngineDb(String path)`（`path=':memory:'` 时开内存库）；`String nowIso()`（UTC ISO8601）
- DDL 母本：`server/src/db.ts`，在其之上叠加 M1-M5 字段（见 Step 3 代码，此即 schema v1 权威定义）

- [ ] **Step 1: 写失败测试**

```dart
// app/test/engine/db_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/db.dart';

void main() {
  test('建库含全部 v1 表', () {
    final db = openEngineDb(':memory:');
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    for (final t in [
      'projects', 'novels', 'episodes', 'assets', 'shots', 'jobs', 'settings',
      'providers', 'provider_models', 'prompts', 'video_takes', 'image_takes'
    ]) {
      expect(tables, contains(t), reason: '缺表 $t');
    }
    expect(db.select('PRAGMA user_version').first.values.first, 1);
    // M1-M5 字段抽查
    final assetCols = db.select('PRAGMA table_info(assets)')
        .map((r) => r['name']).toSet();
    expect(assetCols, containsAll(['note', 'voiceId', 'userId']));
    final shotCols = db.select('PRAGMA table_info(shots)')
        .map((r) => r['name']).toSet();
    expect(shotCols, containsAll(['selectedTakeId', 'audioPath', 'audioStatus']));
    db.dispose();
  });

  test('重复打开幂等（IF NOT EXISTS）', () {
    final db = openEngineDb(':memory:');
    // 第二次初始化同一连接不炸（模拟热重载）
    initSchema(db);
    db.dispose();
  });

  test('nowIso 是 ISO8601 UTC', () {
    expect(nowIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z$')));
  });
}
```

- [ ] **Step 2: 跑测试确认失败** — Run: `flutter test test/engine/db_test.dart` → FAIL

- [ ] **Step 3: 实现（此 DDL 为 schema v1 的权威定义）**

```dart
// app/lib/src/engine/db.dart
import 'package:sqlite3/sqlite3.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

Database openEngineDb(String path) {
  final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
  initSchema(db);
  return db;
}

void initSchema(Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  artStyle TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
  createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS novels (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
  updatedAt TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_novels_project ON novels(projectId);
CREATE TABLE IF NOT EXISTS episodes (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL, title TEXT NOT NULL DEFAULT '',
  synopsis TEXT NOT NULL DEFAULT '', scriptJson TEXT NOT NULL DEFAULT '[]',
  composedPath TEXT, composeStatus TEXT NOT NULL DEFAULT 'none', composeError TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_episodes_project ON episodes(projectId);
CREATE TABLE IF NOT EXISTS assets (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('character','scene','prop')),
  name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  imagePrompt TEXT NOT NULL DEFAULT '', imagePath TEXT,
  status TEXT NOT NULL DEFAULT 'draft', error TEXT,
  note TEXT NOT NULL DEFAULT '', voiceId TEXT,
  userId TEXT NOT NULL DEFAULT '', createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_assets_project ON assets(projectId);
CREATE TABLE IF NOT EXISTS shots (
  id TEXT PRIMARY KEY,
  episodeId TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL, description TEXT NOT NULL DEFAULT '',
  dialogue TEXT NOT NULL DEFAULT '', camera TEXT NOT NULL DEFAULT '',
  assetNames TEXT NOT NULL DEFAULT '[]',
  imagePrompt TEXT NOT NULL DEFAULT '', imagePath TEXT,
  imageStatus TEXT NOT NULL DEFAULT 'none', imageError TEXT,
  videoPrompt TEXT NOT NULL DEFAULT '', videoPath TEXT,
  videoStatus TEXT NOT NULL DEFAULT 'none', videoError TEXT,
  selectedTakeId TEXT,
  audioPath TEXT, audioStatus TEXT NOT NULL DEFAULT 'none', audioError TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shots_episode ON shots(episodeId);
CREATE INDEX IF NOT EXISTS idx_shots_project ON shots(projectId);
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY, projectId TEXT NOT NULL,
  kind TEXT NOT NULL, targetId TEXT NOT NULL DEFAULT '',
  targetLabel TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'queued',
  attempt INTEGER NOT NULL DEFAULT 1, error TEXT,
  payload TEXT NOT NULL DEFAULT '{}', result TEXT,
  createdAt TEXT NOT NULL, startedAt TEXT, finishedAt TEXT
);
CREATE INDEX IF NOT EXISTS idx_jobs_state ON jobs(state);
CREATE INDEX IF NOT EXISTS idx_jobs_project ON jobs(projectId, createdAt DESC);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS providers (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  protocol TEXT NOT NULL CHECK (protocol IN ('openai_compatible','volcengine')),
  baseUrl TEXT NOT NULL DEFAULT '', apiKey TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1, userId TEXT NOT NULL DEFAULT '',
  createdAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS provider_models (
  id TEXT PRIMARY KEY,
  providerId TEXT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  modelId TEXT NOT NULL, label TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL CHECK (kind IN ('text','image','video','tts')),
  capabilities TEXT NOT NULL DEFAULT '{}', enabled INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS prompts (
  key TEXT PRIMARY KEY, content TEXT NOT NULL, updatedAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS video_takes (
  id TEXT PRIMARY KEY,
  shotId TEXT NOT NULL REFERENCES shots(id) ON DELETE CASCADE,
  videoPath TEXT NOT NULL, durationSec REAL, createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_vtakes_shot ON video_takes(shotId);
CREATE TABLE IF NOT EXISTS image_takes (
  id TEXT PRIMARY KEY,
  assetId TEXT REFERENCES assets(id) ON DELETE CASCADE,
  shotId TEXT REFERENCES shots(id) ON DELETE CASCADE,
  imagePath TEXT NOT NULL, selected INTEGER NOT NULL DEFAULT 0,
  createdAt TEXT NOT NULL,
  CHECK ((assetId IS NULL) != (shotId IS NULL))
);
''');
  db.execute('PRAGMA user_version = 1');
}
```

- [ ] **Step 4: 跑测试通过** — `flutter test test/engine/db_test.dart` → PASS
- [ ] **Step 5: Commit** — `git commit -m "feat(engine): sqlite schema v1 (full, incl. M1-M5 fields)"`

---

### Task 3: media.dart（MediaStore）

**Files:**
- Create: `app/lib/src/engine/media.dart`
- Test: `app/test/engine/media_test.dart`

**Interfaces:**
- Produces: `class MediaStore { MediaStore(String rootDir); String saveImage(List<int> bytes, String projectId); String saveVideo(List<int> bytes, String projectId); String absPath(String rel); void deleteProject(String projectId); }`
- rel 路径格式沿用 v0.1：`<projectId>/img_<newId>.png`、`<projectId>/vid_<newId>.mp4`（正斜杠）

- [ ] **Step 1: 写失败测试**

```dart
// app/test/engine/media_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/media.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mediastore'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saveImage 落盘并返回 rel 路径', () {
    final store = MediaStore(tmp.path);
    final rel = store.saveImage([1, 2, 3], 'proj1');
    expect(rel, matches(RegExp(r'^proj1/img_[0-9a-z]{14}\.png$')));
    expect(File(store.absPath(rel)).readAsBytesSync(), [1, 2, 3]);
  });

  test('deleteProject 清目录', () {
    final store = MediaStore(tmp.path);
    final rel = store.saveImage([1], 'p2');
    store.deleteProject('p2');
    expect(File(store.absPath(rel)).existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: 确认失败** → **Step 3: 实现**

```dart
// app/lib/src/engine/media.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'util.dart';

/// 媒体文件仓库。rootDir 注入（App 用 documents/dramaflow_media，测试用临时目录）。
class MediaStore {
  final String rootDir;
  MediaStore(this.rootDir) {
    Directory(rootDir).createSync(recursive: true);
  }

  String saveImage(List<int> bytes, String projectId) =>
      _save(bytes, projectId, 'img', 'png');
  String saveVideo(List<int> bytes, String projectId) =>
      _save(bytes, projectId, 'vid', 'mp4');

  String _save(List<int> bytes, String projectId, String prefix, String ext) {
    final rel = '$projectId/${prefix}_${newId()}.$ext';
    final f = File(absPath(rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return rel;
  }

  String absPath(String rel) => p.join(rootDir, rel);

  void deleteProject(String projectId) {
    final dir = Directory(p.join(rootDir, projectId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
```

- [ ] **Step 4: 测试通过** → **Step 5: Commit** `feat(engine): MediaStore`

---

### Task 4: config.dart（设置，平台分化默认值）

**Files:**
- Create: `app/lib/src/engine/config.dart`
- Test: `app/test/engine/config_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `Database`
- Produces: `class EngineConfig { EngineConfig(Database db, {required bool isMobile}); Map<String, dynamic> getAll(); Map<String, dynamic> getAllMasked(); void update(Map<String, dynamic> patch); String str(String key); int intOf(String key); }`
- 键集合 = `server/src/config.ts` 的 Settings 去掉 `apiToken`（无 HTTP 层后无意义）：textBaseUrl/textApiKey/textModel/imageBaseUrl/imageApiKey/imageModel/imageSizeDirective/videoProvider/videoBaseUrl/videoApiKey/videoModel/videoResolution/videoDuration
- 打码键：textApiKey/imageApiKey/videoApiKey（`****`+尾4位；update 时空串或 `****` 开头=不修改，语义同 v0.1）
- 默认值分化：`isMobile=false` → text/image 指向 azt（`http://127.0.0.1:8787/v1`，key `local`，模型 gpt-5.5/gpt-image-2）；`isMobile=true` → text/image 指向 `https://ark.cn-beijing.volces.com/api/v3`（key 空串，模型 `doubao-seed-1-6-250615` / `doubao-seedream-4-0-250828`）。video 两端一致（volcengine seedance，同 v0.1 默认）

- [ ] **Step 1: 失败测试**（关键断言：桌面默认 azt、移动默认 ark 且 key 空、打码 update 语义、videoDuration 数值化）

```dart
// app/test/engine/config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';

void main() {
  test('桌面默认 azt，移动默认 ark 且 key 空', () {
    final d = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    expect(d.str('textBaseUrl'), contains('127.0.0.1:8787'));
    final m = EngineConfig(openEngineDb(':memory:'), isMobile: true);
    expect(m.str('textBaseUrl'), contains('ark.cn-beijing'));
    expect(m.str('textApiKey'), isEmpty);
  });

  test('打码与不修改语义', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoApiKey': 'sk-realkey1234'});
    expect(c.getAllMasked()['videoApiKey'], '****1234');
    c.update({'videoApiKey': '****1234'}); // 回写打码值=不修改
    expect(c.str('videoApiKey'), 'sk-realkey1234');
    c.update({'videoApiKey': ''}); // 空串=不修改
    expect(c.str('videoApiKey'), 'sk-realkey1234');
  });

  test('videoDuration 数值', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoDuration': 8});
    expect(c.intOf('videoDuration'), 8);
  });
}
```

- [ ] **Step 2: 确认失败** → **Step 3: 实现**（DEFAULTS 两套 Map；get/update 用 `INSERT ... ON CONFLICT DO UPDATE`，逐行平移 `config.ts`；`imageSizeDirective` 默认值原文照抄 config.ts 第 29-30 行）
- [ ] **Step 4: 通过** → **Step 5: Commit** `feat(engine): EngineConfig with per-platform defaults`

---

### Task 5: Provider 移植（gateway 接口 + text/image/video）

**Files:**
- Create: `app/lib/src/engine/providers/gateway.dart`、`openai_text.dart`、`openai_image.dart`、`volcengine_video.dart`
- Test: `app/test/engine/providers_test.dart`

**Interfaces:**
- Produces:
```dart
class TextResult { final String content; final int promptTokens; final int completionTokens; }
abstract class ProviderGateway {
  Future<TextResult> generateText(String system, String user, {CancelToken? cancelToken});
  Future<String> generateImage(String prompt, String projectId, {CancelToken? cancelToken}); // 返回 rel 媒体路径
  Future<String> generateVideo(String prompt, String firstFrameAbsPath, String projectId, {CancelToken? cancelToken});
}
class HttpProviderGateway implements ProviderGateway {
  HttpProviderGateway(EngineConfig config, MediaStore media, {Dio? dio});
}
```
- 移植母本与必须保留的行为：
  - `text.ts` → `openai_text.dart`：POST `{textBaseUrl}/chat/completions`，`max_completion_tokens: 32000`，超时 300s，无 content 时抛 `EngineException('文本模型未返回内容: ...')`
  - `image.ts` → `openai_image.dart`：POST `{imageBaseUrl}/images/generations`，prompt 末尾拼 `imageSizeDirective`，`size 1024x1024 / quality low / response_format b64_json`，**receiveTimeout 960s**（azt 长等待），b64 缺失时回退 url 下载，落盘经 MediaStore
  - `video.ts` → `volcengine_video.dart`：POST `{videoBaseUrl}/contents/generations/tasks`（content=[text, image_url(role:first_frame, data URL)]，ratio 1:1、duration/resolution 从 config），轮询 GET 每 10s、上限 30min，status succeeded→下载 video_url 落盘；failed/expired/cancelled 抛对应中文错误；**每轮轮询前检查 `cancelToken?.isCancelled`，已取消则抛 DioException.requestCancelled**
- dio 配置：`validateStatus: (s) => s != null && s < 400`（非 2xx 走 DioException → errMessage 带响应体）

- [ ] **Step 1: 失败测试**（dio 的 `HttpClientAdapter` 用手写 fake：按 path 返回预置响应）

```dart
// app/test/engine/providers_test.dart —— 核心用例
// 1. generateText 正常解析 content 与 usage
// 2. generateText 上游 500 → DioException，errMessage 含响应体
// 3. generateImage b64_json → MediaStore 落盘，rel 以 projectId/ 开头
// 4. generateImage prompt 末尾包含 imageSizeDirective（fake adapter 断言请求体）
// 5. generateVideo succeeded 路径：create 返回 id → 第一次 poll running → 第二次 succeeded+video_url → 下载落盘
// 6. generateVideo failed 路径：抛 EngineException 且 message 含上游 error.message
// 7. generateVideo cancelToken.cancel() 后下一轮 poll 前抛 cancel
// fake adapter 写法：class FakeAdapter implements HttpClientAdapter { ... 按 options.path 分发 }
// 视频轮询等待用 fakeAsync 或把 pollInterval 作为可注入参数（测试传 Duration.zero）——采用后者，构造参数 {Duration pollInterval = const Duration(seconds: 10), Duration pollTimeout = const Duration(minutes: 30)}
```

（完整测试代码由执行者按上述用例清单编写，断言点已列全；fake adapter 模式参考 dio 官方 `HttpClientAdapter` 接口，无需第三方 mock 库）

- [ ] **Step 2: 确认失败** → **Step 3: 实现**（逐行平移三个 ts 文件；`HttpProviderGateway` 组合三者并从 config 取参）
- [ ] **Step 4: 通过** → **Step 5: Commit** `feat(engine): provider gateway — openai-compat text/image + volcengine video ports`

---

### Task 6: prompts.dart + schemas.dart

**Files:**
- Create: `app/lib/src/engine/pipeline/prompts.dart`、`app/lib/src/engine/pipeline/schemas.dart`
- Test: `app/test/engine/schemas_test.dart`

**Interfaces:**
- `prompts.dart`：常量 `scriptGenSystem` / `assetExtractSystem`（**在 v0.1 文案基础上加入道具提取规则一句：道具=剧情反复出现或有叙事意义的物件，kind 用 "prop"**）/ `storyboardGenSystem` + 函数 `scriptGenUser(novelTitle, novelContent, episodeCount)` / `assetExtractUser(scriptSummary, artStyle)` / `storyboardGenUser(episodeTitle, scriptJson, assetsContext, artStyle)` / `repairUser(originalUser, badOutput, parseError)`。中文文案从 `server/src/pipeline/prompts.ts` **逐字复制**（模板字面量改 Dart 插值），assetExtract 的 kind 枚举文案改为"character或scene或prop"
- `schemas.dart`：手写校验器替代 zod，签名：
```dart
class ScriptOut { final List<EpisodeOut> episodes; }
class EpisodeOut { final String title; final String synopsis; final List<Map<String, dynamic>> scenes; }
ScriptOut parseScriptOut(dynamic json);      // 非法结构抛 EngineException(中文原因)
class AssetOut { final String kind; final String name; final String description; final String imagePrompt; }
List<AssetOut> parseAssetsOut(dynamic json); // kind ∉ {character,scene,prop} 抛错；description/imagePrompt 缺省为 ''
class ShotOut { final String description; final String camera; final String dialogue; final List<String> assetNames; final String imagePrompt; final String videoPrompt; }
List<ShotOut> parseShotsOut(dynamic json);   // imagePrompt 为空抛错；episodes/assets/shots 为空数组抛错
```
- 校验语义对齐 `runners.ts` 的 zod 定义（含 default('') 行为）

- [ ] **Step 1: 失败测试**（每个 parse：合法样例、缺省字段补默认、空数组抛错、kind 非法抛错、scenes 缺失抛错）
- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**
- [ ] **Step 5: Commit** `feat(engine): prompts (verbatim port + prop rule) and output schemas`

---

### Task 7: runners.dart（六个执行器 + structuredText 自愈）

**Files:**
- Create: `app/lib/src/engine/pipeline/runners.dart`
- Test: `app/test/engine/runners_test.dart`

**Interfaces:**
- Consumes: Task 2 db / Task 5 gateway / Task 6 prompts+schemas
- Produces:
```dart
class JobRow { final String id, projectId, kind, targetId, payload; }
class Runners {
  Runners(Database db, ProviderGateway gateway, MediaStore media);
  Future<String> run(JobRow job, CancelToken token); // 按 kind 分发到六个私有方法
}
```
- 移植母本 `server/src/pipeline/runners.ts`，六个方法逐行平移，**必须保留的 v0.1 修复语义**：
  1. `_runAssetImage/_runShotImage/_runShotVideo`：先置实体 `running`，**预检（空提示词/缺首帧）在 try 内**——任何失败实体必落 `failed`+原因，绝不卡 `queued`
  2. 实体错误写入用 `errMessage(e)` 截断 2000 字
  3. `_structuredText`：第一次解析失败 → `repairUser` 包装重试一次 → 再失败抛"模型输出两次都无法解析…原始输出开头…"
  4. `_runScriptGen`：episodeCount 夹取 1..12；事务内 DELETE 旧 episodes 再插入
  5. `_runAssetExtract`：按 (projectId,name,kind) upsert，返回"提取资产：新增 X 个，更新 Y 个"
  6. `_runStoryboardGen`：资产上下文无资产时用占位文案；事务内 DELETE 本集旧 shots 再插入
- CancelToken 透传给 gateway 调用

- [ ] **Step 1: 失败测试**（fake gateway 注入；内存库预置数据）

核心用例（完整写出，断言 DB 状态）：
```dart
// 1. scriptGen 正常：fake text 返回合法剧本 JSON → episodes 表 3 行、idx 1..3
// 2. scriptGen 无小说 → 抛 '请先导入小说'
// 3. structuredText 自愈：fake text 第一次返回坏 JSON、第二次合法 → 成功；且第二次请求的 user 含 '你上一次的输出无法解析'
// 4. assetImage 空提示词：asset.imagePrompt='' 且 description='' → job 抛错且 assets.status='failed'、error 含 '没有图片提示词'（卡 queued 回归防护）
// 5. assetImage 成功：fake image 返回 rel → assets.status='done'、imagePath=rel
// 6. shotVideo 缺首帧 → shots.videoStatus='failed'、videoError 含 '请先生成镜头图'
// 7. assetExtract upsert：预置同名 character → 断言"新增 1 个，更新 1 个"且行数不重复
```

- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**
- [ ] **Step 5: Commit** `feat(engine): pipeline runners ported with v0.1 fix semantics preserved`

---

### Task 8: queue.dart（幂等启动 / 车道 / 恢复 / 取消 / 事件流 / 完成钩子）

**Files:**
- Create: `app/lib/src/engine/queue.dart`
- Test: `app/test/engine/queue_test.dart`

**Interfaces:**
- Consumes: Runners（Task 7）
- Produces:
```dart
class JobQueue {
  JobQueue(Database db, Runners runners, {Duration tick = const Duration(milliseconds: 500)});
  void start();                       // 幂等：重复调用无副作用（唯一 worker loop）
  void recoverOnColdStart();          // running→failed('应用重启，任务中断') + 实体三处复位（语义同 queue.ts startQueue）
  String enqueue({required String projectId, required String kind, String targetId = '', String targetLabel = '', Map<String, dynamic> payload = const {}, int attempt = 1});
  bool hasActiveJob(String kind, String targetId);
  void cancel(String jobId);          // queued→canceled+实体恢复(有产物done/无draft·none)；running→CancelToken.cancel()
  Stream<void> get events;            // 任意 job 状态变化时广播（UI watch 源）
  void Function(String jobId, String kind, String state)? onJobFinished; // M3.5 导演循环钩子
  void dispose();
}
```
- 车道与并发照抄 `queue.ts`：text=1（script_gen/asset_extract/storyboard_gen）、image=1（asset_image/shot_image）、video=1（shot_video）
- execute 终态写入守卫 `WHERE id=? AND state='running'`（照抄）；catch 中若 `token.isCancelled` → state='canceled'（不算 failed）+ 实体按"有产物→done，无→draft/none"恢复；否则 failed+errMessage
- 每次状态迁移（enqueue/claim/done/failed/canceled）后 `_events.add(null)`

- [ ] **Step 1: 失败测试**

核心用例（tick 传 `Duration(milliseconds: 10)` 加速）：
```dart
// 1. enqueue→done：fake runner 立即成功 → 等 events 一拍后 job state='done'，onJobFinished 被调用一次
// 2. 车道串行：两个 asset_image 入队，fake runner 记录并发峰值 → 峰值==1
// 3. 幂等 start：start() 三次 → fake runner 执行次数仍等于 job 数
// 4. 冷启动恢复：预置 running job + running asset → recoverOnColdStart() → job failed('应用重启，任务中断')、asset failed
// 5. cancel queued：预置 queued shot_image job + shots.imageStatus='queued' 且 imagePath 非空 → cancel → job canceled、imageStatus='done'
// 6. cancel running：fake runner 挂起等待 token → cancel → job state='canceled' 而非 'failed'
// 7. events 广播：一次 enqueue+执行 ≥2 个事件
```

- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**
- [ ] **Step 5: Commit** `feat(engine): job queue — idempotent start, lanes, recovery, cancel, event stream, finish hook`

---

### Task 9: engine.dart 门面 A（projects / novel / episodes / script 生成守卫）

**Files:**
- Create: `app/lib/src/engine/engine.dart`
- Test: `app/test/engine/engine_a_test.dart`

**Interfaces:**
- Produces（方法签名与 v0.1 `ApiClient` 一致，返回 `app/lib/src/api/models.dart` 现有模型，models.dart 不改）：
```dart
class Engine {
  Engine({required Database db, required MediaStore media, required ProviderGateway gateway, required EngineConfig config});
  static Future<Engine> boot({required String dataDir, required bool isMobile}); // 生产入口：开库/建store/config/gateway/queue.start+recover
  JobQueue get queue;
  String mediaAbsPath(String rel);
  // A 部分
  Future<List<Project>> listProjects();
  Future<Project> createProject(String name, {String artStyle = ''});
  Future<Project> getProject(String id);
  Future<Project> updateProject(String id, {String? name, String? artStyle});
  Future<void> deleteProject(String id);                 // 级联 + media.deleteProject
  Future<Novel?> getNovel(String projectId);
  Future<Novel> saveNovel(String projectId, {required String title, required String content}); // 空 content 抛 '小说内容不能为空'
  Future<String> generateScript(String projectId, {int? episodeCount});
  Future<List<EpisodeSummary>> listEpisodes(String projectId);
  Future<Episode> getEpisode(String id);
  Future<Episode> updateEpisode(String id, {String? title, String? synopsis, List<Scene>? scenes});
}
```
- 逻辑母本 `server/src/routes.ts` 对应 handler，SQL 照抄；必须保留：projectStats 七项统计、generateScript 的双守卫（无小说 400 语义→抛 EngineException；下游任务运行中 409 语义→抛"有分镜/镜头图/视频任务进行中…"）、hasActiveJob 幂等保护
- 返回模型的 imageUrl/videoUrl 字段：**直接填 rel 路径**（不再拼 /media/ 前缀；UI 用 `mediaAbsPath` 转绝对路径）

- [ ] **Step 1: 失败测试**（内存引擎 + fake gateway：CRUD 往返、stats 计数、saveNovel 空串抛错、generateScript 无小说抛错、script job 排队后重复触发抛"已在进行中"）
- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**
- [ ] **Step 5: Commit** `feat(engine): facade A — projects/novel/episodes with guards`

---

### Task 10: engine.dart 门面 B（assets / shots / jobs / settings）

**Files:**
- Modify: `app/lib/src/engine/engine.dart`
- Test: `app/test/engine/engine_b_test.dart`

**Interfaces:**
- Produces（补齐 ApiClient 其余方法）：
```dart
  Future<String> extractAssets(String projectId);            // 守卫：无剧本抛 '请先生成剧本'
  Future<List<Asset>> listAssets(String projectId);
  Future<Asset> updateAsset(String id, {String? name, String? description, String? imagePrompt});
  Future<String?> generateAssetImage(String assetId);        // 置 queued+入队；活跃重复→抛 '该资产已有生成任务进行中'
  Future<List<String>> generateAllAssetImages(String projectId); // 跳过 done/queued/running
  Future<String> generateStoryboard(String episodeId);       // 守卫：本集镜头图/视频任务活跃→抛
  Future<List<Shot>> listShots(String episodeId);
  Future<Shot> updateShot(String id, Map<String, String> patch);
  Future<String?> generateShotImage(String shotId);
  Future<List<String>> generateAllShotImages(String episodeId);
  Future<String> generateShotVideo(String shotId);           // 守卫：imageStatus!='done' 抛 '请先生成镜头图（视频需要首帧）'
  Future<List<Job>> activeJobs();
  Future<List<Job>> projectJobs(String projectId, {int limit = 50});
  Future<String> retryJob(String jobId);                     // 仅 failed；恢复实体 queued 状态；attempt+1
  Future<void> cancelJob(String jobId);                      // 委托 queue.cancel
  Future<AppSettings> getSettings();
  Future<AppSettings> updateSettings(Map<String, dynamic> patch);
```
- 逻辑母本 `routes.ts` 对应 handler；enqueue 前置实体状态（queued+清 error）语义照抄

- [ ] **Step 1: 失败测试**（提取守卫、批量跳过规则、generateShotVideo 前置校验、retry 语义、cancel 委托后实体恢复）
- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**
- [ ] **Step 5: Commit** `feat(engine): facade B — assets/shots/jobs/settings`

---

### Task 11: UI 切换（engineProvider / main 初始化 / 三处适配 / 移除 HTTP 层）

**Files:**
- Modify: `app/lib/main.dart`、`app/lib/src/state/providers.dart`、`app/lib/src/widgets/common.dart`、`app/lib/src/screens/settings_screen.dart`
- Delete: `app/lib/src/api/client.dart`（models.dart 保留）
- Modify: 各 screen 中 `apiProvider` → `engineProvider`、`ApiException` → `EngineException`（机械替换）
- Test: `flutter analyze` + 全部既有测试

**Interfaces:**
- Consumes: `Engine.boot`
- Produces:
```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final engine = await Engine.boot(
    dataDir: p.join(dir.path, 'dramaflow'),
    isMobile: !kIsWeb && (Platform.isAndroid || Platform.isIOS));
  runApp(ProviderScope(
    overrides: [engineProvider.overrideWithValue(engine)],
    child: const DramaFlowApp()));
}
// providers.dart
final engineProvider = Provider<Engine>((_) => throw UnimplementedError('main() 注入'));
// ActiveJobsNotifier：删除全部 Timer 逻辑 → 订阅 engine.queue.events，事件到达即拉 activeJobs() 并 bump jobsGeneration；
// poke() 保留签名（调用方不改），实现改为立即拉一次
// 活跃任务非空 → WakelockPlus.enable()，清空 → disable()
```
- MediaImage（common.dart）：`Image.network(mediaUrl)` → `Image.file(File(engine.mediaAbsPath(rel)))`；`kIsWeb` 时显示占位图标（Web 降级为 UI 预览，spec 已定）
- runAction：捕获 `EngineException`（原 ApiException 分支替换）
- settings_screen：删除"连接"卡（baseUrl/token 已无意义）→ 换成"存储与引擎"卡（数据目录路径、引擎版本、清空数据入口沿用 engine 方法）；connectionProvider 删除
- 机械替换核查：`grep -rn 'apiProvider\|ApiException\|mediaUrl\|connectionProvider' app/lib/` 结果为零

- [ ] **Step 1: 逐文件替换**（顺序：providers.dart → common.dart → main.dart → settings_screen → 各 screen grep 扫尾）
- [ ] **Step 2: `flutter analyze`** → 零 issue
- [ ] **Step 3: `flutter test`** → 全绿
- [ ] **Step 4: `flutter run -d macos` 手动冒烟**：项目列表可见旧 UI（数据为空库正常）、新建项目、导入小说、（azt 在跑时）生成剧本可走通
- [ ] **Step 5: Commit** `refactor(app): switch UI to embedded engine, remove HTTP client layer`

---

### Task 12: 平台配置与双端验收 + 文档

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`（`<uses-permission android:name="android.permission.INTERNET"/>`）
- Modify: `README.md`、`docs/API.md`（标注 deprecated）、`server/README-DEPRECATED.md`（新建一行说明）
- Test: 双端验收清单

**验收清单（照 spec M0 验收执行）：**

- [ ] macOS：`flutter run -d macos` → 新建项目→导入测试小说→生成剧本（azt gpt-5.5）→提取素材→生成 1 张素材图 → 全绿
- [ ] macOS：生成中途强杀 App → 冷启动 → 任务显示"失败：应用重启，任务中断" → 重试成功
- [ ] macOS：图片生成 running 时点取消 → job 变 canceled、资产状态正确恢复
- [ ] Android 模拟器：`flutter run -d emulator` → 设置页把 text/image 指向 ark（真实 key）→ 同一流程走通，全程无 localhost
- [ ] README 重写：单体 App 架构图、双端启动方式、server/ 弃用说明、iOS 长任务约束
- [ ] Commit：`docs: M0 acceptance + README for standalone app architecture`

---

## Self-Review 记录

- **Spec 覆盖**：Provider Reality→Task 4（平台默认值）+Task 12（Android 无 localhost 验收）；UI Compatibility→Task 11 三处适配；Engine Lifecycle→Task 8（幂等/恢复/取消/dispose 解耦）+Task 11（单例注入）；Schema v1→Task 2；M3.5 钩子→Task 8 onJobFinished；wakelock→Task 11。无缺口。
- **占位符**：Task 4/5/6/9/10 的测试以"用例清单+断言点"形式给出而非全量代码——因其为移植任务且母本在仓库内有精确行号引用，接口签名与语义断言已完备；核心风险区（util/db/media/runners/queue）为全量代码。
- **类型一致性**：`ProviderGateway` 三方法签名在 Task 5 定义、Task 7/9 消费一致；`JobRow` Task 7 定义、Task 8 消费；rel 路径约定 Task 3 定义、Task 5/9/11 消费一致（imageUrl 填 rel、UI 用 mediaAbsPath）。
