import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const schemaVersion = 7;

String nowIso() => DateTime.now().toUtc().toIso8601String();

Database openEngineDb(String path) {
  if (path == ':memory:') {
    final db = sqlite3.openInMemory();
    _configure(db);
    initSchema(db);
    return db;
  }

  var db = sqlite3.open(path);
  final version = db.select('PRAGMA user_version').first.values.first as int;
  if (version < schemaVersion) {
    db.close();
    _deleteDatabaseFiles(path);
    db = sqlite3.open(path);
  }

  _configure(db);
  initSchema(db);
  return db;
}

void _configure(Database db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
}

void _deleteDatabaseFiles(String path) {
  for (final filePath in [path, '$path-wal', '$path-shm']) {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }
}

void initSchema(Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS memories (
  content TEXT,
  createTime INTEGER,
  embedding TEXT,
  id TEXT PRIMARY KEY,
  isolationKey TEXT,
  name TEXT,
  relatedMessageIds TEXT,
  role TEXT,
  summarized INTEGER,
  type TEXT
);
CREATE TABLE IF NOT EXISTS o_agentDeploy (
  desc TEXT,
  disabled INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT,
  maxOutputTokens INTEGER,
  model TEXT,
  modelName TEXT,
  name TEXT,
  temperature INTEGER,
  type TEXT,
  vendorId TEXT
);
CREATE TABLE IF NOT EXISTS o_agentWorkData (
  createTime INTEGER,
  data TEXT,
  episodesId INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT,
  projectId INTEGER,
  updateTime INTEGER
);
CREATE TABLE IF NOT EXISTS o_artStyle (
  fileUrl TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT,
  name TEXT,
  prompt TEXT
);
CREATE TABLE IF NOT EXISTS o_assets (
  assetsId INTEGER,
  audioBindState INTEGER,
  describe TEXT,
  flowId INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  imageId INTEGER,
  name TEXT,
  projectId INTEGER,
  prompt TEXT,
  promptErrorReason TEXT,
  promptState TEXT,
  remark TEXT,
  scriptId INTEGER,
  startTime INTEGER,
  type TEXT
);
CREATE TABLE IF NOT EXISTS o_assets2Storyboard (
  assetId INTEGER,
  storyboardId INTEGER,
  PRIMARY KEY (assetId, storyboardId)
);
CREATE TABLE IF NOT EXISTS o_assetsRole2Audio (
  assetsAudioId INTEGER,
  assetsRoleId INTEGER,
  PRIMARY KEY (assetsAudioId, assetsRoleId)
);
CREATE TABLE IF NOT EXISTS o_event (
  createTime INTEGER,
  detail TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT
);
CREATE TABLE IF NOT EXISTS o_eventChapter (
  eventId INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  novelId INTEGER
);
CREATE TABLE IF NOT EXISTS o_image (
  assetsId INTEGER,
  errorReason TEXT,
  filePath TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model TEXT,
  resolution TEXT,
  state TEXT,
  type TEXT
);
CREATE TABLE IF NOT EXISTS o_imageFlow (
  flowData TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT
);
CREATE TABLE IF NOT EXISTS o_modelPrompt (
  fileName TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model TEXT,
  path TEXT,
  prompt TEXT,
  vendorId TEXT
);
CREATE TABLE IF NOT EXISTS o_novel (
  chapter TEXT,
  chapterData TEXT,
  chapterIndex INTEGER,
  createTime INTEGER,
  errorReason TEXT,
  event TEXT,
  eventState INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projectId INTEGER,
  reel TEXT
);
CREATE TABLE IF NOT EXISTS o_project (
  artStyle TEXT,
  createTime INTEGER,
  directorManual TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  imageModel TEXT,
  imageQuality TEXT,
  intro TEXT,
  mode TEXT,
  name TEXT,
  projectType TEXT,
  type TEXT,
  userId INTEGER,
  videoModel TEXT,
  videoRatio TEXT
);
CREATE TABLE IF NOT EXISTS o_prompt (
  data TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  type TEXT,
  useData TEXT
);
CREATE TABLE IF NOT EXISTS o_script (
  content TEXT,
  createTime INTEGER,
  errorReason TEXT,
  extractState INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  projectId INTEGER
);
CREATE TABLE IF NOT EXISTS o_scriptAssets (
  assetId INTEGER,
  scriptId INTEGER,
  PRIMARY KEY (assetId, scriptId)
);
CREATE TABLE IF NOT EXISTS o_setting (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS o_skillAttribution (
  attribution TEXT,
  skillId TEXT,
  PRIMARY KEY (attribution, skillId)
);
CREATE TABLE IF NOT EXISTS o_skillList (
  createTime INTEGER,
  description TEXT,
  embedding TEXT,
  id TEXT PRIMARY KEY,
  md5 TEXT,
  name TEXT,
  path TEXT,
  state INTEGER,
  type TEXT,
  updateTime INTEGER
);
CREATE TABLE IF NOT EXISTS o_storyboard (
  audioAssetId INTEGER,
  audioError TEXT,
  audioPath TEXT,
  audioState TEXT,
  audioText TEXT,
  createTime INTEGER,
  duration TEXT,
  filePath TEXT,
  flowId INTEGER,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  "index" INTEGER,
  projectId INTEGER,
  prompt TEXT,
  reason TEXT,
  scriptId INTEGER,
  shouldGenerateImage INTEGER,
  state TEXT,
  track TEXT,
  trackId INTEGER,
  videoDesc TEXT
);
CREATE TABLE IF NOT EXISTS o_tasks (
  describe TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model TEXT,
  projectId INTEGER,
  reason TEXT,
  relatedObjects TEXT,
  startTime INTEGER,
  state TEXT,
  taskClass TEXT
);
CREATE TABLE IF NOT EXISTS o_timelineClip (
  assetId INTEGER,
  durationMs INTEGER,
  filePath TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lane INTEGER,
  name TEXT,
  opacity REAL DEFAULT 1.0,
  projectId INTEGER,
  scriptId INTEGER,
  startMs INTEGER
);
CREATE TABLE IF NOT EXISTS o_user (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  password TEXT
);
CREATE TABLE IF NOT EXISTS o_vendorConfig (
  enable INTEGER,
  id TEXT PRIMARY KEY,
  inputValues TEXT,
  models TEXT
);
CREATE TABLE IF NOT EXISTS o_video (
  errorReason TEXT,
  filePath TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projectId INTEGER,
  scriptId INTEGER,
  state TEXT,
  time INTEGER,
  videoTrackId INTEGER
);
CREATE TABLE IF NOT EXISTS o_videoTrack (
  duration INTEGER,
  filterPreset TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projectId INTEGER,
  prompt TEXT,
  reason TEXT,
  scriptId INTEGER,
  selectVideoId INTEGER,
  state TEXT,
  transition TEXT,
  videoId INTEGER
);
CREATE INDEX IF NOT EXISTS idx_o_novel_project_chapter ON o_novel(projectId, chapterIndex);
CREATE INDEX IF NOT EXISTS idx_o_eventChapter_event ON o_eventChapter(eventId);
CREATE INDEX IF NOT EXISTS idx_o_eventChapter_novel ON o_eventChapter(novelId);
CREATE INDEX IF NOT EXISTS idx_o_scriptAssets_script ON o_scriptAssets(scriptId);
CREATE INDEX IF NOT EXISTS idx_o_tasks_project_state ON o_tasks(projectId, state);
CREATE INDEX IF NOT EXISTS idx_o_timelineClip_script ON o_timelineClip(scriptId, startMs, lane);
''');
  db.execute('PRAGMA user_version = $schemaVersion');
}
