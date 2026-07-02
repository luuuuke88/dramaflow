import { db, nowIso } from "./db.js";
import { newId, errMessage } from "./util.js";
import {
  runScriptGen,
  runAssetExtract,
  runStoryboardGen,
  runAssetImage,
  runShotImage,
  runShotVideo,
  type JobRow,
} from "./pipeline/runners.js";

export type JobKind =
  | "script_gen"
  | "asset_extract"
  | "storyboard_gen"
  | "asset_image"
  | "shot_image"
  | "shot_video";

/** 车道 = 资源类型。同车道内串行（azt/OAuth 路径脆弱，宁慢勿炸），不同车道并行。 */
const LANE_OF: Record<JobKind, "text" | "image" | "video"> = {
  script_gen: "text",
  asset_extract: "text",
  storyboard_gen: "text",
  asset_image: "image",
  shot_image: "image",
  shot_video: "video",
};

const LANE_CONCURRENCY: Record<string, number> = { text: 1, image: 1, video: 1 };

const RUNNER: Record<JobKind, (job: JobRow) => Promise<string>> = {
  script_gen: runScriptGen,
  asset_extract: runAssetExtract,
  storyboard_gen: runStoryboardGen,
  asset_image: runAssetImage,
  shot_image: runShotImage,
  shot_video: runShotVideo,
};

const runningByLane: Record<string, number> = { text: 0, image: 0, video: 0 };

export function enqueueJob(opts: {
  projectId: string;
  kind: JobKind;
  targetId?: string;
  targetLabel?: string;
  payload?: unknown;
  attempt?: number;
}): string {
  const id = newId();
  db.prepare(
    `INSERT INTO jobs (id, projectId, kind, targetId, targetLabel, state, attempt, payload, createdAt)
     VALUES (?,?,?,?,?, 'queued', ?, ?, ?)`,
  ).run(
    id,
    opts.projectId,
    opts.kind,
    opts.targetId ?? "",
    opts.targetLabel ?? "",
    opts.attempt ?? 1,
    JSON.stringify(opts.payload ?? {}),
    nowIso(),
  );
  return id;
}

/** 同一目标已有排队/运行中的同类 job → 幂等保护 */
export function hasActiveJob(kind: JobKind, targetId: string): boolean {
  const row = db
    .prepare("SELECT id FROM jobs WHERE kind=? AND targetId=? AND state IN ('queued','running') LIMIT 1")
    .get(kind, targetId);
  return !!row;
}

function claimNext(lane: string): JobRow | undefined {
  const kinds = (Object.keys(LANE_OF) as JobKind[]).filter((k) => LANE_OF[k] === lane);
  const placeholders = kinds.map(() => "?").join(",");
  const claim = db.transaction((): JobRow | undefined => {
    const row = db
      .prepare(
        `SELECT id, projectId, kind, targetId, payload FROM jobs
         WHERE state='queued' AND kind IN (${placeholders})
         ORDER BY createdAt ASC LIMIT 1`,
      )
      .get(...kinds) as JobRow | undefined;
    if (!row) return undefined;
    db.prepare("UPDATE jobs SET state='running', startedAt=? WHERE id=?").run(nowIso(), row.id);
    return row;
  });
  return claim();
}

async function execute(job: JobRow): Promise<void> {
  const lane = LANE_OF[job.kind as JobKind];
  runningByLane[lane]++;
  try {
    const result = await RUNNER[job.kind as JobKind](job);
    db.prepare("UPDATE jobs SET state='done', result=?, finishedAt=? WHERE id=? AND state='running'").run(
      result,
      nowIso(),
      job.id,
    );
  } catch (e) {
    db.prepare("UPDATE jobs SET state='failed', error=?, finishedAt=? WHERE id=? AND state='running'").run(
      errMessage(e).slice(0, 2000),
      nowIso(),
      job.id,
    );
    console.error(`[queue] job ${job.id} (${job.kind}) failed:`, errMessage(e));
  } finally {
    runningByLane[lane]--;
  }
}

let timer: ReturnType<typeof setInterval> | null = null;

export function startQueue(): void {
  // 启动恢复：上次进程死掉时 running 的 job 一律判失败（原因可见、可重试）
  const orphans = db
    .prepare("UPDATE jobs SET state='failed', error='服务重启，任务中断', finishedAt=? WHERE state='running'")
    .run(nowIso());
  if (orphans.changes > 0) console.log(`[queue] 恢复：${orphans.changes} 个中断任务标记为失败`);
  // 资产/镜头卡在 running 状态的也复位
  db.prepare("UPDATE assets SET status='failed', error='服务重启，任务中断' WHERE status='running'").run();
  db.prepare("UPDATE shots SET imageStatus='failed', imageError='服务重启，任务中断' WHERE imageStatus='running'").run();
  db.prepare("UPDATE shots SET videoStatus='failed', videoError='服务重启，任务中断' WHERE videoStatus='running'").run();

  timer = setInterval(() => {
    for (const lane of Object.keys(LANE_CONCURRENCY)) {
      while (runningByLane[lane] < LANE_CONCURRENCY[lane]) {
        const job = claimNext(lane);
        if (!job) break;
        void execute(job);
      }
    }
  }, 500);
  console.log("[queue] worker started");
}

export function stopQueue(): void {
  if (timer) clearInterval(timer);
  timer = null;
}
