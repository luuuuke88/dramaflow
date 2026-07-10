import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const schemaVersion = 11;

String nowIso() => DateTime.now().toUtc().toIso8601String();

Database openEngineDb(String path) {
  final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
  _configure(db);
  final version = _userVersion(db);
  if (version > schemaVersion) {
    db.close();
    throw StateError(
      'Database version $version is newer than supported version $schemaVersion.',
    );
  }
  if (version == 0) {
    initSchema(db);
    _ensureV10Indexes(db);
    return db;
  }
  if (version < schemaVersion) {
    _backupBeforeMigration(db, path, version);
    db.execute('BEGIN IMMEDIATE');
    try {
      initSchema(db, setVersion: false);
      migrateSchema(db, version, schemaVersion);
      _ensureV10Indexes(db);
      db.execute('PRAGMA user_version = $schemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return db;
  }

  initSchema(db, setVersion: false);
  _ensureV10Indexes(db);
  return db;
}

void _configure(Database db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
}

int _userVersion(Database db) =>
    db.select('PRAGMA user_version').first.values.first as int;

void _backupBeforeMigration(Database db, String path, int version) {
  if (path == ':memory:') return;
  final source = File(path);
  if (!source.existsSync()) return;
  final backup = File('$path.backup-v$version.sqlite');
  if (backup.existsSync()) return;
  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  source.copySync(backup.path);
}

/// Runs the ordered schema steps between two known versions.
///
/// The early Flutter releases were destructively rebuilt on upgrade, so their
/// historical steps are intentionally additive: `initSchema` creates missing
/// tables/indexes and no step drops user data. Keeping this dispatcher explicit
/// gives later releases one safe place to add real versioned transformations.
void _addColumnIfMissing(Database db, String table, String definition) {
  final name = definition.trim().split(RegExp(r'\s+')).first;
  final columns = db
      .select('PRAGMA table_info($table)')
      .map((row) => row['name'] as String)
      .toSet();
  if (!columns.contains(name)) {
    db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }
}

void migrateSchema(Database db, int fromVersion, int toVersion) {
  for (var version = fromVersion; version < toVersion; version++) {
    switch (version) {
      case 8:
        // v8 -> v9 switches the opener to transactional, non-destructive
        // migrations. The schema itself is completed by initSchema below.
        break;
      case 9:
        _addColumnIfMissing(db, 'o_videoTrack', 'videoRequest TEXT');
        _addColumnIfMissing(db, 'o_videoTrack', 'promptProvenance TEXT');
        _addColumnIfMissing(db, 'o_video', 'modelBinding TEXT');
        _addColumnIfMissing(db, 'o_video', 'requestFingerprint TEXT');
        _addColumnIfMissing(db, 'o_video', 'submissionState TEXT');
        _addColumnIfMissing(db, 'o_video', 'upstreamTaskId TEXT');
        _addColumnIfMissing(db, 'o_video', 'upstreamState TEXT');
        _addColumnIfMissing(db, 'o_video', 'upstreamUpdatedAt INTEGER');
        break;
      default:
        // Versions before v8 have no published Flutter-only schema delta.
        // They are completed additively by initSchema without dropping tables.
        break;
    }
  }
}

void initSchema(Database db, {bool setVersion = true}) {
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
CREATE TABLE IF NOT EXISTS o_memoryVector (
  dimension INTEGER,
  isolationKey TEXT,
  memoryId TEXT PRIMARY KEY,
  model TEXT,
  provider TEXT,
  type TEXT,
  updatedAt INTEGER,
  vector TEXT,
  FOREIGN KEY(memoryId) REFERENCES memories(id) ON DELETE CASCADE
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
CREATE TABLE IF NOT EXISTS o_productionDependencyState (
  projectId INTEGER NOT NULL,
  scriptId INTEGER NOT NULL DEFAULT 0,
  key TEXT NOT NULL,
  sourceHash TEXT NOT NULL DEFAULT '',
  stale INTEGER NOT NULL DEFAULT 0,
  updateTime INTEGER NOT NULL,
  PRIMARY KEY (projectId, scriptId, key)
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
  modelBinding TEXT,
  projectId INTEGER,
  requestFingerprint TEXT,
  scriptId INTEGER,
  state TEXT,
  submissionState TEXT,
  time INTEGER,
  upstreamState TEXT,
  upstreamTaskId TEXT,
  upstreamUpdatedAt INTEGER,
  videoTrackId INTEGER
);
CREATE TABLE IF NOT EXISTS o_videoTrack (
  duration INTEGER,
  filterPreset TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  promptProvenance TEXT,
  projectId INTEGER,
  prompt TEXT,
  reason TEXT,
  scriptId INTEGER,
  selectVideoId INTEGER,
  state TEXT,
  transition TEXT,
  videoId INTEGER,
  videoRequest TEXT
);
CREATE INDEX IF NOT EXISTS idx_o_novel_project_chapter ON o_novel(projectId, chapterIndex);
CREATE INDEX IF NOT EXISTS idx_o_eventChapter_event ON o_eventChapter(eventId);
CREATE INDEX IF NOT EXISTS idx_o_eventChapter_novel ON o_eventChapter(novelId);
CREATE INDEX IF NOT EXISTS idx_o_scriptAssets_script ON o_scriptAssets(scriptId);
CREATE INDEX IF NOT EXISTS idx_o_tasks_project_state ON o_tasks(projectId, state);
CREATE INDEX IF NOT EXISTS idx_o_timelineClip_script ON o_timelineClip(scriptId, startMs, lane);
CREATE INDEX IF NOT EXISTS idx_o_memoryVector_scope ON o_memoryVector(isolationKey, type, provider, model);
''');
  if (setVersion) db.execute('PRAGMA user_version = $schemaVersion');
}

void _ensureV10Indexes(Database db) {
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_o_video_upstream ON o_video(upstreamTaskId)');
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_o_video_track_state ON o_video(videoTrackId, state)');
}
