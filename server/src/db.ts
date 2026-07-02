import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const DATA_DIR = path.resolve(__dirname, "../data");
export const MEDIA_DIR = path.join(DATA_DIR, "media");

fs.mkdirSync(MEDIA_DIR, { recursive: true });

export const db = new Database(path.join(DATA_DIR, "dramaflow.sqlite"));
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

db.exec(`
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  artStyle TEXT NOT NULL DEFAULT '',
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS novels (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  updatedAt TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_novels_project ON novels(projectId);

CREATE TABLE IF NOT EXISTS episodes (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  synopsis TEXT NOT NULL DEFAULT '',
  scriptJson TEXT NOT NULL DEFAULT '[]',
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_episodes_project ON episodes(projectId);

CREATE TABLE IF NOT EXISTS assets (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('character','scene')),
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  imagePrompt TEXT NOT NULL DEFAULT '',
  imagePath TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  error TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_assets_project ON assets(projectId);

CREATE TABLE IF NOT EXISTS shots (
  id TEXT PRIMARY KEY,
  episodeId TEXT NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  dialogue TEXT NOT NULL DEFAULT '',
  camera TEXT NOT NULL DEFAULT '',
  assetNames TEXT NOT NULL DEFAULT '[]',
  imagePrompt TEXT NOT NULL DEFAULT '',
  imagePath TEXT,
  imageStatus TEXT NOT NULL DEFAULT 'none',
  imageError TEXT,
  videoPrompt TEXT NOT NULL DEFAULT '',
  videoPath TEXT,
  videoStatus TEXT NOT NULL DEFAULT 'none',
  videoError TEXT,
  createdAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shots_episode ON shots(episodeId);
CREATE INDEX IF NOT EXISTS idx_shots_project ON shots(projectId);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  projectId TEXT NOT NULL,
  kind TEXT NOT NULL,
  targetId TEXT NOT NULL DEFAULT '',
  targetLabel TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'queued',
  attempt INTEGER NOT NULL DEFAULT 1,
  error TEXT,
  payload TEXT NOT NULL DEFAULT '{}',
  result TEXT,
  createdAt TEXT NOT NULL,
  startedAt TEXT,
  finishedAt TEXT
);
CREATE INDEX IF NOT EXISTS idx_jobs_state ON jobs(state);
CREATE INDEX IF NOT EXISTS idx_jobs_project ON jobs(projectId, createdAt DESC);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`);

export function nowIso(): string {
  return new Date().toISOString();
}
