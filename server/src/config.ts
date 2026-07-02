import { db } from "./db.js";

export interface Settings {
  apiToken: string;
  textBaseUrl: string;
  textApiKey: string;
  textModel: string;
  imageBaseUrl: string;
  imageApiKey: string;
  imageModel: string;
  imageSizeDirective: string;
  videoProvider: string;
  videoBaseUrl: string;
  videoApiKey: string;
  videoModel: string;
  videoResolution: string;
  videoDuration: number;
}

const DEFAULTS: Settings = {
  apiToken: "local-dev",
  textBaseUrl: "http://127.0.0.1:8787/v1",
  textApiKey: "local",
  textModel: "gpt-5.5",
  imageBaseUrl: "http://127.0.0.1:8787/v1",
  imageApiKey: "local",
  imageModel: "gpt-image-2",
  imageSizeDirective:
    "You MUST generate this image at exactly 1024x1024 resolution as a SQUARE 1:1 canvas. Do not add any text, watermark or border.",
  videoProvider: "volcengine",
  videoBaseUrl: "https://ark.cn-beijing.volces.com/api/v3",
  videoApiKey: "",
  videoModel: "doubao-seedance-2-0-mini-260615",
  videoResolution: "720p",
  videoDuration: 5,
};

const getStmt = db.prepare("SELECT value FROM settings WHERE key = ?");
const setStmt = db.prepare(
  "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
);

export function getSettings(): Settings {
  const out: Record<string, unknown> = { ...DEFAULTS };
  for (const key of Object.keys(DEFAULTS) as (keyof Settings)[]) {
    const row = getStmt.get(key) as { value: string } | undefined;
    if (row !== undefined) {
      out[key] = typeof DEFAULTS[key] === "number" ? Number(row.value) : row.value;
    }
  }
  return out as unknown as Settings;
}

export function updateSettings(patch: Partial<Settings>): Settings {
  for (const [key, value] of Object.entries(patch)) {
    if (!(key in DEFAULTS) || value === undefined) continue;
    setStmt.run(key, String(value));
  }
  return getSettings();
}

/** 需要打码的密钥字段（GET 打码返回；PUT 时空串或 **** 开头视为"不修改"） */
export const MASKED_KEYS = ["textApiKey", "imageApiKey", "videoApiKey", "apiToken"] as const;

/** 打码返回给客户端（密钥只显示尾部4位） */
export function maskedSettings(): Record<string, unknown> {
  const s = getSettings() as unknown as Record<string, unknown>;
  const mask = (v: string) => (v ? `****${v.slice(-4)}` : "");
  for (const key of MASKED_KEYS) s[key] = mask(String(s[key] ?? ""));
  return s;
}
