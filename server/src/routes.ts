import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Context } from "hono";
import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { z } from "zod";
import { db, nowIso, MEDIA_DIR } from "./db.js";
import { newId, errMessage } from "./util.js";
import { getSettings, updateSettings, maskedSettings, MASKED_KEYS, type Settings } from "./config.js";
import { enqueueJob, hasActiveJob, type JobKind } from "./queue.js";

export const app = new Hono();

const VERSION = "0.1.0";
const startedAt = Date.now();

// ---------- helpers ----------

const ok = (c: Context, data: unknown) => c.json({ ok: true, data });
const fail = (c: Context, status: 400 | 401 | 404 | 409 | 416 | 500, error: string) =>
  c.json({ ok: false, error }, status);

// 未匹配路由与未捕获异常也保持 { ok:false } 信封
app.notFound((c) => c.json({ ok: false, error: "接口不存在" }, 404));
app.onError((err, c) => {
  console.error("[dramaflow] unhandled:", err);
  return c.json({ ok: false, error: `服务器内部错误：${errMessage(err).slice(0, 500)}` }, 500);
});

/** 解析并校验请求体；校验失败抛出带中文信息的 400（由调用方捕获返回） */
async function parseBody<T>(c: Context, schema: z.ZodType<T>): Promise<{ ok: true; data: T } | { ok: false; error: string }> {
  const raw = await c.req.json().catch(() => ({}));
  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return { ok: false, error: `参数错误 ${issue.path.join(".")}: ${issue.message}` };
  }
  return { ok: true, data: parsed.data };
}

function mediaUrl(rel: string | null): string | null {
  return rel ? `/media/${rel.split(path.sep).join("/")}` : null;
}

// Flutter Web 跨源访问需要 CORS（桌面/移动端不受影响；本地单用户场景放开）
app.use("/api/*", cors());
app.use("/media/*", cors());

// ---------- auth（/api/health 与 /media 之外的 /api/* 全部要求 token）----------

app.use("/api/*", async (c, next) => {
  if (c.req.path === "/api/health") return next();
  const token = getSettings().apiToken;
  const auth = c.req.header("Authorization");
  const given = auth?.replace(/^Bearer\s+/i, "") ?? c.req.query("token");
  if (given !== token) return fail(c, 401, "无效的 API Token");
  return next();
});

// ---------- health ----------

app.get("/api/health", (c) => {
  const s = getSettings();
  return ok(c, {
    version: VERSION,
    uptimeSec: Math.round((Date.now() - startedAt) / 1000),
    providers: {
      text: `${s.textBaseUrl} / ${s.textModel}`,
      image: `${s.imageBaseUrl} / ${s.imageModel}`,
      video: s.videoApiKey ? `configured (${s.videoModel})` : "unconfigured",
    },
  });
});

// ---------- projects ----------

function projectStats(projectId: string) {
  const one = (sql: string) => (db.prepare(sql).get(projectId) as { n: number }).n;
  return {
    episodes: one("SELECT COUNT(*) n FROM episodes WHERE projectId=?"),
    assets: one("SELECT COUNT(*) n FROM assets WHERE projectId=?"),
    assetsDone: one("SELECT COUNT(*) n FROM assets WHERE projectId=? AND status='done'"),
    shots: one("SELECT COUNT(*) n FROM shots WHERE projectId=?"),
    shotsImageDone: one("SELECT COUNT(*) n FROM shots WHERE projectId=? AND imageStatus='done'"),
    shotsVideoDone: one("SELECT COUNT(*) n FROM shots WHERE projectId=? AND videoStatus='done'"),
    hasNovel:
      (db.prepare("SELECT COUNT(*) n FROM novels WHERE projectId=? AND content != ''").get(projectId) as { n: number })
        .n > 0,
  };
}

app.get("/api/projects", (c) => {
  const rows = db.prepare("SELECT * FROM projects ORDER BY updatedAt DESC").all() as Record<string, unknown>[];
  return ok(
    c,
    rows.map((p) => ({ ...p, stats: projectStats(p.id as string) })),
  );
});

const ProjectBody = z.object({ name: z.string().min(1, "项目名不能为空"), artStyle: z.string().optional() });

app.post("/api/projects", async (c) => {
  const parsed = ProjectBody.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) return fail(c, 400, parsed.error.issues[0].message);
  const id = newId();
  const now = nowIso();
  db.prepare("INSERT INTO projects (id, name, artStyle, createdAt, updatedAt) VALUES (?,?,?,?,?)").run(
    id,
    parsed.data.name,
    parsed.data.artStyle ?? "",
    now,
    now,
  );
  return ok(c, db.prepare("SELECT * FROM projects WHERE id=?").get(id));
});

app.get("/api/projects/:id", (c) => {
  const p = db.prepare("SELECT * FROM projects WHERE id=?").get(c.req.param("id"));
  if (!p) return fail(c, 404, "项目不存在");
  return ok(c, { ...(p as Record<string, unknown>), stats: projectStats(c.req.param("id")) });
});

const ProjectPatchBody = z.object({
  name: z.string().min(1, "项目名不能为空").optional(),
  artStyle: z.string().optional(),
});

app.patch("/api/projects/:id", async (c) => {
  const body = await parseBody(c, ProjectPatchBody);
  if (!body.ok) return fail(c, 400, body.error);
  const p = db.prepare("SELECT * FROM projects WHERE id=?").get(c.req.param("id"));
  if (!p) return fail(c, 404, "项目不存在");
  db.prepare("UPDATE projects SET name=COALESCE(?,name), artStyle=COALESCE(?,artStyle), updatedAt=? WHERE id=?").run(
    body.data.name ?? null,
    body.data.artStyle ?? null,
    nowIso(),
    c.req.param("id"),
  );
  return ok(c, db.prepare("SELECT * FROM projects WHERE id=?").get(c.req.param("id")));
});

app.delete("/api/projects/:id", (c) => {
  db.prepare("DELETE FROM projects WHERE id=?").run(c.req.param("id"));
  return ok(c, {});
});

// ---------- novel ----------

app.get("/api/projects/:id/novel", (c) => {
  const n = db.prepare("SELECT id, title, content FROM novels WHERE projectId=?").get(c.req.param("id"));
  return ok(c, n ?? null);
});

const NovelPutBody = z.object({
  title: z.string().optional(),
  content: z.string().min(1, "小说内容不能为空"),
});

app.put("/api/projects/:id/novel", async (c) => {
  const projectId = c.req.param("id");
  if (!db.prepare("SELECT id FROM projects WHERE id=?").get(projectId)) return fail(c, 404, "项目不存在");
  const parsed = await parseBody(c, NovelPutBody);
  if (!parsed.ok) return fail(c, 400, parsed.error);
  const body = parsed.data;
  if (!body.content.trim()) return fail(c, 400, "小说内容不能为空");
  const existing = db.prepare("SELECT id FROM novels WHERE projectId=?").get(projectId) as { id: string } | undefined;
  if (existing) {
    db.prepare("UPDATE novels SET title=?, content=?, updatedAt=? WHERE id=?").run(
      body.title ?? "",
      body.content,
      nowIso(),
      existing.id,
    );
  } else {
    db.prepare("INSERT INTO novels (id, projectId, title, content, updatedAt) VALUES (?,?,?,?,?)").run(
      newId(),
      projectId,
      body.title ?? "",
      body.content,
      nowIso(),
    );
  }
  db.prepare("UPDATE projects SET updatedAt=? WHERE id=?").run(nowIso(), projectId);
  return ok(c, db.prepare("SELECT id, title, content FROM novels WHERE projectId=?").get(projectId));
});

// ---------- script generation & episodes ----------

app.post("/api/projects/:id/generate-script", async (c) => {
  const projectId = c.req.param("id");
  if (!db.prepare("SELECT id FROM projects WHERE id=?").get(projectId)) return fail(c, 404, "项目不存在");
  const novel = db.prepare("SELECT content FROM novels WHERE projectId=?").get(projectId) as
    | { content: string }
    | undefined;
  if (!novel?.content.trim()) return fail(c, 400, "请先导入小说");
  if (hasActiveJob("script_gen", projectId)) return fail(c, 409, "剧本生成任务已在进行中");
  // 重写剧本会删除全部剧集与分镜，下游任务运行时禁止
  const downstream = db
    .prepare(
      "SELECT COUNT(*) n FROM jobs WHERE projectId=? AND state IN ('queued','running') AND kind IN ('storyboard_gen','shot_image','shot_video')",
    )
    .get(projectId) as { n: number };
  if (downstream.n > 0) return fail(c, 409, "有分镜/镜头图/视频任务进行中，请等待完成或取消后再重新生成剧本");
  const body = await parseBody(c, z.object({ episodeCount: z.number().int().min(1).max(12).optional() }));
  if (!body.ok) return fail(c, 400, body.error);
  const jobId = enqueueJob({
    projectId,
    kind: "script_gen",
    targetId: projectId,
    targetLabel: "剧本生成",
    payload: { episodeCount: body.data.episodeCount },
  });
  return ok(c, { jobId });
});

app.get("/api/projects/:id/episodes", (c) => {
  const rows = db
    .prepare("SELECT id, idx, title, synopsis, scriptJson FROM episodes WHERE projectId=? ORDER BY idx")
    .all(c.req.param("id")) as { id: string; idx: number; title: string; synopsis: string; scriptJson: string }[];
  return ok(
    c,
    rows.map((r) => ({
      id: r.id,
      idx: r.idx,
      title: r.title,
      synopsis: r.synopsis,
      sceneCount: (JSON.parse(r.scriptJson) as unknown[]).length,
      shotCount: (db.prepare("SELECT COUNT(*) n FROM shots WHERE episodeId=?").get(r.id) as { n: number }).n,
    })),
  );
});

app.get("/api/episodes/:id", (c) => {
  const r = db.prepare("SELECT * FROM episodes WHERE id=?").get(c.req.param("id")) as
    | Record<string, unknown>
    | undefined;
  if (!r) return fail(c, 404, "剧集不存在");
  return ok(c, { ...r, scenes: JSON.parse(r.scriptJson as string), scriptJson: undefined });
});

const EpisodePutBody = z.object({
  title: z.string().optional(),
  synopsis: z.string().optional(),
  scenes: z.array(z.record(z.string(), z.unknown())).optional(),
});

app.put("/api/episodes/:id", async (c) => {
  const r = db.prepare("SELECT id FROM episodes WHERE id=?").get(c.req.param("id"));
  if (!r) return fail(c, 404, "剧集不存在");
  const parsed = await parseBody(c, EpisodePutBody);
  if (!parsed.ok) return fail(c, 400, parsed.error);
  const body = parsed.data;
  db.prepare(
    "UPDATE episodes SET title=COALESCE(?,title), synopsis=COALESCE(?,synopsis), scriptJson=COALESCE(?,scriptJson) WHERE id=?",
  ).run(body.title ?? null, body.synopsis ?? null, body.scenes ? JSON.stringify(body.scenes) : null, c.req.param("id"));
  const updated = db.prepare("SELECT * FROM episodes WHERE id=?").get(c.req.param("id")) as Record<string, unknown>;
  return ok(c, { ...updated, scenes: JSON.parse(updated.scriptJson as string), scriptJson: undefined });
});

// ---------- assets ----------

app.post("/api/projects/:id/extract-assets", (c) => {
  const projectId = c.req.param("id");
  const epCount = (db.prepare("SELECT COUNT(*) n FROM episodes WHERE projectId=?").get(projectId) as { n: number }).n;
  if (epCount === 0) return fail(c, 400, "请先生成剧本");
  if (hasActiveJob("asset_extract", projectId)) return fail(c, 409, "资产提取任务已在进行中");
  const jobId = enqueueJob({ projectId, kind: "asset_extract", targetId: projectId, targetLabel: "素材提取" });
  return ok(c, { jobId });
});

function assetView(a: Record<string, unknown>) {
  return { ...a, imageUrl: mediaUrl(a.imagePath as string | null), imagePath: undefined };
}

app.get("/api/projects/:id/assets", (c) => {
  const rows = db
    .prepare("SELECT * FROM assets WHERE projectId=? ORDER BY kind, createdAt")
    .all(c.req.param("id")) as Record<string, unknown>[];
  return ok(c, rows.map(assetView));
});

const AssetPatchBody = z.object({
  name: z.string().min(1, "名称不能为空").optional(),
  description: z.string().optional(),
  imagePrompt: z.string().optional(),
});

app.patch("/api/assets/:id", async (c) => {
  const a = db.prepare("SELECT id FROM assets WHERE id=?").get(c.req.param("id"));
  if (!a) return fail(c, 404, "资产不存在");
  const parsed = await parseBody(c, AssetPatchBody);
  if (!parsed.ok) return fail(c, 400, parsed.error);
  const body = parsed.data;
  db.prepare(
    "UPDATE assets SET name=COALESCE(?,name), description=COALESCE(?,description), imagePrompt=COALESCE(?,imagePrompt) WHERE id=?",
  ).run(body.name ?? null, body.description ?? null, body.imagePrompt ?? null, c.req.param("id"));
  return ok(c, assetView(db.prepare("SELECT * FROM assets WHERE id=?").get(c.req.param("id")) as Record<string, unknown>));
});

function enqueueAssetImage(c: Context, assetId: string): string | null {
  const a = db.prepare("SELECT * FROM assets WHERE id=?").get(assetId) as
    | { id: string; projectId: string; name: string; status: string }
    | undefined;
  if (!a) return null;
  if (hasActiveJob("asset_image", a.id)) return null;
  db.prepare("UPDATE assets SET status='queued', error=NULL WHERE id=?").run(a.id);
  return enqueueJob({ projectId: a.projectId, kind: "asset_image", targetId: a.id, targetLabel: `素材图·${a.name}` });
}

app.post("/api/assets/:id/generate-image", (c) => {
  const a = db.prepare("SELECT id FROM assets WHERE id=?").get(c.req.param("id"));
  if (!a) return fail(c, 404, "资产不存在");
  if (hasActiveJob("asset_image", c.req.param("id"))) return fail(c, 409, "该资产已有生成任务进行中");
  const jobId = enqueueAssetImage(c, c.req.param("id"));
  return ok(c, { jobId });
});

app.post("/api/projects/:id/generate-all-asset-images", (c) => {
  const rows = db
    .prepare("SELECT id FROM assets WHERE projectId=? AND status NOT IN ('done','queued','running')")
    .all(c.req.param("id")) as { id: string }[];
  const jobIds = rows.map((r) => enqueueAssetImage(c, r.id)).filter(Boolean);
  return ok(c, { jobIds });
});

// ---------- storyboard & shots ----------

app.post("/api/episodes/:id/generate-storyboard", (c) => {
  const ep = db.prepare("SELECT id, projectId, title FROM episodes WHERE id=?").get(c.req.param("id")) as
    | { id: string; projectId: string; title: string }
    | undefined;
  if (!ep) return fail(c, 404, "剧集不存在");
  if (hasActiveJob("storyboard_gen", ep.id)) return fail(c, 409, "分镜生成任务已在进行中");
  // 重新生成分镜会删除本集全部镜头，本集镜头图/视频任务运行时禁止
  const downstream = db
    .prepare(
      `SELECT COUNT(*) n FROM jobs WHERE state IN ('queued','running') AND kind IN ('shot_image','shot_video')
       AND targetId IN (SELECT id FROM shots WHERE episodeId=?)`,
    )
    .get(ep.id) as { n: number };
  if (downstream.n > 0) return fail(c, 409, "本集有镜头图/视频任务进行中，请等待完成或取消后再重新生成分镜");
  const jobId = enqueueJob({
    projectId: ep.projectId,
    kind: "storyboard_gen",
    targetId: ep.id,
    targetLabel: `分镜·${ep.title}`,
  });
  return ok(c, { jobId });
});

function shotView(s: Record<string, unknown>) {
  return {
    ...s,
    assetNames: JSON.parse((s.assetNames as string) || "[]"),
    imageUrl: mediaUrl(s.imagePath as string | null),
    videoUrl: mediaUrl(s.videoPath as string | null),
    imagePath: undefined,
    videoPath: undefined,
  };
}

app.get("/api/episodes/:id/shots", (c) => {
  const rows = db
    .prepare("SELECT * FROM shots WHERE episodeId=? ORDER BY idx")
    .all(c.req.param("id")) as Record<string, unknown>[];
  return ok(c, rows.map(shotView));
});

const ShotPatchBody = z.object({
  description: z.string().optional(),
  dialogue: z.string().optional(),
  camera: z.string().optional(),
  imagePrompt: z.string().optional(),
  videoPrompt: z.string().optional(),
});

app.patch("/api/shots/:id", async (c) => {
  const s = db.prepare("SELECT id FROM shots WHERE id=?").get(c.req.param("id"));
  if (!s) return fail(c, 404, "镜头不存在");
  const parsed = await parseBody(c, ShotPatchBody);
  if (!parsed.ok) return fail(c, 400, parsed.error);
  const body = parsed.data;
  db.prepare(
    `UPDATE shots SET description=COALESCE(?,description), dialogue=COALESCE(?,dialogue), camera=COALESCE(?,camera),
     imagePrompt=COALESCE(?,imagePrompt), videoPrompt=COALESCE(?,videoPrompt) WHERE id=?`,
  ).run(
    body.description ?? null,
    body.dialogue ?? null,
    body.camera ?? null,
    body.imagePrompt ?? null,
    body.videoPrompt ?? null,
    c.req.param("id"),
  );
  return ok(c, shotView(db.prepare("SELECT * FROM shots WHERE id=?").get(c.req.param("id")) as Record<string, unknown>));
});

function enqueueShotImage(shotId: string): string | null {
  const s = db.prepare("SELECT id, projectId, idx FROM shots WHERE id=?").get(shotId) as
    | { id: string; projectId: string; idx: number }
    | undefined;
  if (!s) return null;
  if (hasActiveJob("shot_image", s.id)) return null;
  db.prepare("UPDATE shots SET imageStatus='queued', imageError=NULL WHERE id=?").run(s.id);
  return enqueueJob({ projectId: s.projectId, kind: "shot_image", targetId: s.id, targetLabel: `镜头图·#${s.idx}` });
}

app.post("/api/shots/:id/generate-image", (c) => {
  const s = db.prepare("SELECT id FROM shots WHERE id=?").get(c.req.param("id"));
  if (!s) return fail(c, 404, "镜头不存在");
  if (hasActiveJob("shot_image", c.req.param("id"))) return fail(c, 409, "该镜头已有生成任务进行中");
  return ok(c, { jobId: enqueueShotImage(c.req.param("id")) });
});

app.post("/api/episodes/:id/generate-all-shot-images", (c) => {
  const rows = db
    .prepare("SELECT id FROM shots WHERE episodeId=? AND imageStatus NOT IN ('done','queued','running')")
    .all(c.req.param("id")) as { id: string }[];
  return ok(c, { jobIds: rows.map((r) => enqueueShotImage(r.id)).filter(Boolean) });
});

app.post("/api/shots/:id/generate-video", (c) => {
  const s = db.prepare("SELECT id, projectId, idx, imagePath, imageStatus FROM shots WHERE id=?").get(
    c.req.param("id"),
  ) as { id: string; projectId: string; idx: number; imagePath: string | null; imageStatus: string } | undefined;
  if (!s) return fail(c, 404, "镜头不存在");
  if (s.imageStatus !== "done" || !s.imagePath) return fail(c, 400, "请先生成镜头图（视频需要首帧）");
  if (hasActiveJob("shot_video", s.id)) return fail(c, 409, "该镜头已有视频任务进行中");
  db.prepare("UPDATE shots SET videoStatus='queued', videoError=NULL WHERE id=?").run(s.id);
  const jobId = enqueueJob({ projectId: s.projectId, kind: "shot_video", targetId: s.id, targetLabel: `视频·#${s.idx}` });
  return ok(c, { jobId });
});

// ---------- jobs ----------

app.get("/api/jobs/active", (c) => {
  const rows = db
    .prepare(
      "SELECT id, projectId, kind, targetId, targetLabel, state, attempt, createdAt, startedAt FROM jobs WHERE state IN ('queued','running') ORDER BY createdAt",
    )
    .all();
  return ok(c, rows);
});

app.get("/api/projects/:id/jobs", (c) => {
  const limit = Math.min(Number(c.req.query("limit") ?? 50), 200);
  const rows = db
    .prepare("SELECT * FROM jobs WHERE projectId=? ORDER BY createdAt DESC LIMIT ?")
    .all(c.req.param("id"), limit) as Record<string, unknown>[];
  return ok(
    c,
    rows.map((j) => ({
      ...j,
      payload: undefined,
      durationMs:
        j.startedAt && j.finishedAt
          ? new Date(j.finishedAt as string).getTime() - new Date(j.startedAt as string).getTime()
          : null,
    })),
  );
});

app.post("/api/jobs/:id/retry", (c) => {
  const j = db.prepare("SELECT * FROM jobs WHERE id=?").get(c.req.param("id")) as
    | { id: string; projectId: string; kind: JobKind; targetId: string; targetLabel: string; payload: string; attempt: number; state: string }
    | undefined;
  if (!j) return fail(c, 404, "任务不存在");
  if (j.state !== "failed") return fail(c, 400, "只有失败的任务可以重试");
  if (hasActiveJob(j.kind, j.targetId)) return fail(c, 409, "同目标已有任务进行中");
  // 恢复目标的排队状态显示
  if (j.kind === "asset_image") db.prepare("UPDATE assets SET status='queued', error=NULL WHERE id=?").run(j.targetId);
  if (j.kind === "shot_image")
    db.prepare("UPDATE shots SET imageStatus='queued', imageError=NULL WHERE id=?").run(j.targetId);
  if (j.kind === "shot_video")
    db.prepare("UPDATE shots SET videoStatus='queued', videoError=NULL WHERE id=?").run(j.targetId);
  const jobId = enqueueJob({
    projectId: j.projectId,
    kind: j.kind,
    targetId: j.targetId,
    targetLabel: j.targetLabel,
    payload: JSON.parse(j.payload),
    attempt: j.attempt + 1,
  });
  return ok(c, { jobId });
});

app.post("/api/jobs/:id/cancel", (c) => {
  const j = db.prepare("SELECT id, kind, targetId, state FROM jobs WHERE id=?").get(c.req.param("id")) as
    | { id: string; kind: JobKind; targetId: string; state: string }
    | undefined;
  if (!j) return fail(c, 404, "任务不存在");
  if (j.state !== "queued") return fail(c, 400, "只有排队中的任务可以取消（运行中的任务将自然结束）");
  db.prepare("UPDATE jobs SET state='canceled', finishedAt=? WHERE id=? AND state='queued'").run(nowIso(), j.id);
  // 恢复实体状态：已有产物则回到 done（取消"重新生成"不应把已完成的降级）
  if (j.kind === "asset_image")
    db.prepare(
      "UPDATE assets SET status = CASE WHEN imagePath IS NOT NULL THEN 'done' ELSE 'draft' END WHERE id=? AND status='queued'",
    ).run(j.targetId);
  if (j.kind === "shot_image")
    db.prepare(
      "UPDATE shots SET imageStatus = CASE WHEN imagePath IS NOT NULL THEN 'done' ELSE 'none' END WHERE id=? AND imageStatus='queued'",
    ).run(j.targetId);
  if (j.kind === "shot_video")
    db.prepare(
      "UPDATE shots SET videoStatus = CASE WHEN videoPath IS NOT NULL THEN 'done' ELSE 'none' END WHERE id=? AND videoStatus='queued'",
    ).run(j.targetId);
  return ok(c, {});
});

// ---------- settings ----------

app.get("/api/settings", (c) => ok(c, maskedSettings()));

const SettingsPutBody = z.object({
  apiToken: z.string().optional(),
  textBaseUrl: z.string().optional(),
  textApiKey: z.string().optional(),
  textModel: z.string().optional(),
  imageBaseUrl: z.string().optional(),
  imageApiKey: z.string().optional(),
  imageModel: z.string().optional(),
  imageSizeDirective: z.string().optional(),
  videoProvider: z.string().optional(),
  videoBaseUrl: z.string().optional(),
  videoApiKey: z.string().optional(),
  videoModel: z.string().optional(),
  videoResolution: z.enum(["480p", "720p", "1080p"]).optional(),
  videoDuration: z.coerce.number().int().min(4).max(15).optional(),
});

app.put("/api/settings", async (c) => {
  const parsed = await parseBody(c, SettingsPutBody);
  if (!parsed.ok) return fail(c, 400, parsed.error);
  const body = parsed.data as Partial<Settings>;
  // 全部打码字段：传空或打码值 = 不修改（防止客户端把打码值回写成真密钥）
  for (const key of MASKED_KEYS) {
    const v = body[key];
    if (typeof v === "string" && (v === "" || v.startsWith("****"))) delete body[key];
  }
  updateSettings(body);
  return ok(c, maskedSettings());
});

// ---------- media（token 经 query 或 header，防目录穿越）----------

app.get("/media/*", (c) => {
  const token = getSettings().apiToken;
  const auth = c.req.header("Authorization");
  const given = auth?.replace(/^Bearer\s+/i, "") ?? c.req.query("token");
  if (given !== token) return fail(c, 401, "无效的 API Token");

  let rel: string;
  try {
    rel = decodeURIComponent(c.req.path.replace(/^\/media\//, ""));
  } catch {
    return fail(c, 400, "非法路径");
  }
  const abs = path.resolve(MEDIA_DIR, rel);
  if (!abs.startsWith(path.resolve(MEDIA_DIR) + path.sep)) return fail(c, 400, "非法路径");
  if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) return fail(c, 404, "文件不存在");

  const ext = path.extname(abs).toLowerCase();
  const mime =
    ext === ".png" ? "image/png" : ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : ext === ".mp4" ? "video/mp4" : "application/octet-stream";
  const size = fs.statSync(abs).size;
  const baseHeaders = {
    "Content-Type": mime,
    "Cache-Control": "private, max-age=31536000, immutable",
    "Accept-Ranges": "bytes",
  };

  // Range 支持：视频拖动播放必需
  const range = c.req.header("Range");
  if (range) {
    const m = range.match(/^bytes=(\d*)-(\d*)$/);
    if (!m || (m[1] === "" && m[2] === "")) return fail(c, 416, "无效的 Range");
    const start = m[1] === "" ? Math.max(size - Number(m[2]), 0) : Number(m[1]);
    const end = m[1] !== "" && m[2] !== "" ? Math.min(Number(m[2]), size - 1) : size - 1;
    if (start >= size || start > end) {
      return c.body(null, 416, { "Content-Range": `bytes */${size}` });
    }
    const stream = Readable.toWeb(fs.createReadStream(abs, { start, end })) as ReadableStream;
    return c.body(stream, 206, {
      ...baseHeaders,
      "Content-Range": `bytes ${start}-${end}/${size}`,
      "Content-Length": String(end - start + 1),
    });
  }

  const stream = Readable.toWeb(fs.createReadStream(abs)) as ReadableStream;
  return c.body(stream, 200, { ...baseHeaders, "Content-Length": String(size) });
});
