import 'package:sqlite3/sqlite3.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

/// 打开引擎数据库（path=':memory:' 用于测试）。Schema v1 一次到位（含 M1-M5 已定字段）。
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
