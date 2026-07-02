import axios from "axios";
import fs from "node:fs";
import path from "node:path";
import { getSettings } from "../config.js";
import { MEDIA_DIR } from "../db.js";
import { newId } from "../util.js";

/**
 * Volcengine Seedance 视频生成（从 ToonFlow volcengine vendor v2.4 移植）。
 * 流程：POST /contents/generations/tasks → 轮询 GET .../tasks/{id} → 下载 video_url。
 * ⚠️ 本通道已按 ToonFlow 同款参数接好，但尚未实际跑通测试（留给用户验证）。
 */
export async function generateVideo(
  prompt: string,
  firstFrameAbsPath: string,
  projectId: string,
): Promise<string> {
  const s = getSettings();
  if (!s.videoApiKey) throw new Error("未配置视频 API Key（设置 → videoApiKey）");
  const baseUrl = s.videoBaseUrl.replace(/\/+$/, "");
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${s.videoApiKey.replace(/^Bearer\s+/i, "")}`,
  };

  const imgB64 = fs.readFileSync(firstFrameAbsPath).toString("base64");
  const content: unknown[] = [
    { type: "text", text: prompt },
    {
      type: "image_url",
      image_url: { url: `data:image/png;base64,${imgB64}` },
      role: "first_frame",
    },
  ];

  const createRes = await axios.post(
    `${baseUrl}/contents/generations/tasks`,
    {
      model: s.videoModel,
      content,
      ratio: "1:1",
      duration: s.videoDuration,
      resolution: s.videoResolution,
      watermark: false,
      generate_audio: true,
    },
    { headers, timeout: 60_000 },
  );
  const taskId: string | undefined = createRes.data?.id;
  if (!taskId) throw new Error(`视频任务创建失败：未返回任务ID (${JSON.stringify(createRes.data).slice(0, 300)})`);

  const deadline = Date.now() + 30 * 60_000;
  for (;;) {
    if (Date.now() > deadline) throw new Error("视频生成轮询超时(30分钟)");
    await new Promise((r) => setTimeout(r, 10_000));
    const q = await axios.get(`${baseUrl}/contents/generations/tasks/${taskId}`, {
      headers,
      timeout: 30_000,
    });
    const status: string = q.data?.status;
    if (status === "succeeded") {
      const videoUrl: string | undefined = q.data?.content?.video_url;
      if (!videoUrl) throw new Error("任务成功但未返回视频URL");
      const dl = await axios.get(videoUrl, { responseType: "arraybuffer", timeout: 300_000 });
      const rel = path.join(projectId, `vid_${newId()}.mp4`);
      const abs = path.join(MEDIA_DIR, rel);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, Buffer.from(dl.data));
      return rel;
    }
    if (status === "failed") throw new Error(q.data?.error?.message || "视频生成失败");
    if (status === "expired") throw new Error("视频生成任务超时(上游)");
    if (status === "cancelled") throw new Error("视频生成任务已被上游取消");
    // queued / running → 继续轮询
  }
}
