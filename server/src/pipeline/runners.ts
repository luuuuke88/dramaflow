import { z } from "zod";
import path from "node:path";
import { db, nowIso, MEDIA_DIR } from "../db.js";
import { newId, extractJson } from "../util.js";
import { generateText } from "../providers/text.js";
import { generateImage } from "../providers/image.js";
import { generateVideo } from "../providers/video.js";
import * as P from "./prompts.js";

// ---------- zod schemas for LLM output ----------

const DialogueSchema = z.object({ speaker: z.string(), line: z.string() });
const SceneSchema = z.object({
  location: z.string(),
  timeOfDay: z.string().default(""),
  action: z.string(),
  dialogues: z.array(DialogueSchema).default([]),
});
const ScriptOutSchema = z.object({
  episodes: z
    .array(
      z.object({
        title: z.string(),
        synopsis: z.string().default(""),
        scenes: z.array(SceneSchema).min(1),
      }),
    )
    .min(1),
});

const AssetsOutSchema = z.object({
  assets: z
    .array(
      z.object({
        kind: z.enum(["character", "scene"]),
        name: z.string().min(1),
        description: z.string().default(""),
        imagePrompt: z.string().default(""),
      }),
    )
    .min(1),
});

const ShotsOutSchema = z.object({
  shots: z
    .array(
      z.object({
        description: z.string(),
        camera: z.string().default(""),
        dialogue: z.string().default(""),
        assetNames: z.array(z.string()).default([]),
        imagePrompt: z.string().min(1),
        videoPrompt: z.string().default(""),
      }),
    )
    .min(1),
});

/** 调 LLM 并解析结构化输出；解析失败带错误反馈自愈重试一次 */
async function structuredText<T>(system: string, user: string, schema: z.ZodType<T>): Promise<T> {
  const first = await generateText(system, user);
  try {
    return schema.parse(extractJson(first.content));
  } catch (e1) {
    const err1 = e1 instanceof Error ? e1.message : String(e1);
    const second = await generateText(system, P.repairUser(user, first.content, err1.slice(0, 300)));
    try {
      return schema.parse(extractJson(second.content));
    } catch (e2) {
      const err2 = e2 instanceof Error ? e2.message : String(e2);
      throw new Error(
        `模型输出两次都无法解析。最后错误: ${err2.slice(0, 300)}。原始输出开头: ${second.content.slice(0, 200)}`,
      );
    }
  }
}

// ---------- job runners（每个对应一种 job.kind）----------

export type JobRow = {
  id: string;
  projectId: string;
  kind: string;
  targetId: string;
  payload: string;
};

function getProject(projectId: string) {
  const p = db.prepare("SELECT * FROM projects WHERE id=?").get(projectId) as
    | { id: string; name: string; artStyle: string }
    | undefined;
  if (!p) throw new Error("项目不存在（可能已被删除）");
  return p;
}

/** 小说 → 分集剧本。成功后替换该项目全部 episodes（及其 shots）。 */
export async function runScriptGen(job: JobRow): Promise<string> {
  const project = getProject(job.projectId);
  const payload = JSON.parse(job.payload) as { episodeCount?: number };
  const novel = db.prepare("SELECT * FROM novels WHERE projectId=?").get(job.projectId) as
    | { title: string; content: string }
    | undefined;
  if (!novel || !novel.content.trim()) throw new Error("请先导入小说");

  const episodeCount = Math.min(Math.max(payload.episodeCount ?? 3, 1), 12);
  const out = await structuredText(
    P.SCRIPT_GEN_SYSTEM,
    P.scriptGenUser(novel.title || project.name, novel.content, episodeCount),
    ScriptOutSchema,
  );

  const replace = db.transaction(() => {
    db.prepare("DELETE FROM episodes WHERE projectId=?").run(job.projectId);
    const ins = db.prepare(
      "INSERT INTO episodes (id, projectId, idx, title, synopsis, scriptJson, createdAt) VALUES (?,?,?,?,?,?,?)",
    );
    out.episodes.forEach((ep, i) => {
      ins.run(newId(), job.projectId, i + 1, ep.title, ep.synopsis, JSON.stringify(ep.scenes), nowIso());
    });
  });
  replace();
  return `生成 ${out.episodes.length} 集剧本`;
}

/** 全部剧本 → 角色/场景资产列表（不含图片）。按名称合并，已有的保留图片。 */
export async function runAssetExtract(job: JobRow): Promise<string> {
  const project = getProject(job.projectId);
  const episodes = db
    .prepare("SELECT title, synopsis, scriptJson FROM episodes WHERE projectId=? ORDER BY idx")
    .all(job.projectId) as { title: string; synopsis: string; scriptJson: string }[];
  if (episodes.length === 0) throw new Error("请先生成剧本");

  const summary = episodes
    .map((e, i) => `第${i + 1}集《${e.title}》：${e.synopsis}\n${e.scriptJson}`)
    .join("\n\n");
  const out = await structuredText(
    P.ASSET_EXTRACT_SYSTEM,
    P.assetExtractUser(summary, project.artStyle),
    AssetsOutSchema,
  );

  let added = 0;
  let updated = 0;
  const upsert = db.transaction(() => {
    for (const a of out.assets) {
      const existing = db
        .prepare("SELECT id FROM assets WHERE projectId=? AND name=? AND kind=?")
        .get(job.projectId, a.name, a.kind) as { id: string } | undefined;
      if (existing) {
        db.prepare("UPDATE assets SET description=?, imagePrompt=? WHERE id=?").run(
          a.description,
          a.imagePrompt,
          existing.id,
        );
        updated++;
      } else {
        db.prepare(
          "INSERT INTO assets (id, projectId, kind, name, description, imagePrompt, status, createdAt) VALUES (?,?,?,?,?,?,'draft',?)",
        ).run(newId(), job.projectId, a.kind, a.name, a.description, a.imagePrompt, nowIso());
        added++;
      }
    }
  });
  upsert();
  return `提取资产：新增 ${added} 个，更新 ${updated} 个`;
}

/** 单集剧本 → 分镜镜头列表 */
export async function runStoryboardGen(job: JobRow): Promise<string> {
  const project = getProject(job.projectId);
  const episode = db.prepare("SELECT * FROM episodes WHERE id=?").get(job.targetId) as
    | { id: string; title: string; scriptJson: string }
    | undefined;
  if (!episode) throw new Error("剧集不存在");

  const assets = db
    .prepare("SELECT kind, name, description FROM assets WHERE projectId=?")
    .all(job.projectId) as { kind: string; name: string; description: string }[];
  const assetsContext =
    assets.length > 0
      ? assets.map((a) => `[${a.kind === "character" ? "角色" : "场景"}] ${a.name}：${a.description}`).join("\n")
      : "（尚未提取资产，请根据剧本自行保持角色外观一致）";

  const out = await structuredText(
    P.STORYBOARD_GEN_SYSTEM,
    P.storyboardGenUser(episode.title, episode.scriptJson, assetsContext, project.artStyle),
    ShotsOutSchema,
  );

  const replace = db.transaction(() => {
    db.prepare("DELETE FROM shots WHERE episodeId=?").run(episode.id);
    const ins = db.prepare(
      `INSERT INTO shots (id, episodeId, projectId, idx, description, dialogue, camera, assetNames, imagePrompt, videoPrompt, imageStatus, videoStatus, createdAt)
       VALUES (?,?,?,?,?,?,?,?,?,?,'none','none',?)`,
    );
    out.shots.forEach((sh, i) => {
      ins.run(
        newId(),
        episode.id,
        job.projectId,
        i + 1,
        sh.description,
        sh.dialogue,
        sh.camera,
        JSON.stringify(sh.assetNames),
        sh.imagePrompt,
        sh.videoPrompt,
        nowIso(),
      );
    });
  });
  replace();
  return `生成 ${out.shots.length} 个镜头`;
}

/** 素材图生成 */
export async function runAssetImage(job: JobRow): Promise<string> {
  const asset = db.prepare("SELECT * FROM assets WHERE id=?").get(job.targetId) as
    | { id: string; name: string; imagePrompt: string; description: string }
    | undefined;
  if (!asset) throw new Error("资产不存在");
  const prompt = asset.imagePrompt.trim() || asset.description.trim();
  if (!prompt) throw new Error("该资产没有图片提示词，请先填写");

  db.prepare("UPDATE assets SET status='running', error=NULL WHERE id=?").run(asset.id);
  try {
    const rel = await generateImage(prompt, job.projectId);
    db.prepare("UPDATE assets SET status='done', imagePath=?, error=NULL WHERE id=?").run(rel, asset.id);
    return rel;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    db.prepare("UPDATE assets SET status='failed', error=? WHERE id=?").run(msg, asset.id);
    throw e;
  }
}

/** 镜头静帧图生成 */
export async function runShotImage(job: JobRow): Promise<string> {
  const shot = db.prepare("SELECT * FROM shots WHERE id=?").get(job.targetId) as
    | { id: string; imagePrompt: string }
    | undefined;
  if (!shot) throw new Error("镜头不存在");
  if (!shot.imagePrompt.trim()) throw new Error("该镜头没有图片提示词");

  db.prepare("UPDATE shots SET imageStatus='running', imageError=NULL WHERE id=?").run(shot.id);
  try {
    const rel = await generateImage(shot.imagePrompt, job.projectId);
    db.prepare("UPDATE shots SET imageStatus='done', imagePath=?, imageError=NULL WHERE id=?").run(rel, shot.id);
    return rel;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    db.prepare("UPDATE shots SET imageStatus='failed', imageError=? WHERE id=?").run(msg, shot.id);
    throw e;
  }
}

/** 镜头视频生成（volcengine seedance，通道已接好、未实测） */
export async function runShotVideo(job: JobRow): Promise<string> {
  const shot = db.prepare("SELECT * FROM shots WHERE id=?").get(job.targetId) as
    | { id: string; imagePath: string | null; videoPrompt: string; description: string }
    | undefined;
  if (!shot) throw new Error("镜头不存在");
  if (!shot.imagePath) throw new Error("请先生成镜头图（视频需要首帧）");
  const prompt = shot.videoPrompt.trim() || shot.description.trim();
  if (!prompt) throw new Error("该镜头没有视频提示词");

  db.prepare("UPDATE shots SET videoStatus='running', videoError=NULL WHERE id=?").run(shot.id);
  try {
    const abs = path.join(MEDIA_DIR, shot.imagePath);
    const rel = await generateVideo(prompt, abs, job.projectId);
    db.prepare("UPDATE shots SET videoStatus='done', videoPath=?, videoError=NULL WHERE id=?").run(rel, shot.id);
    return rel;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    db.prepare("UPDATE shots SET videoStatus='failed', videoError=? WHERE id=?").run(msg, shot.id);
    throw e;
  }
}
