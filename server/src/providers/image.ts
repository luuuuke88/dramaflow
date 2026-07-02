import axios from "axios";
import fs from "node:fs";
import path from "node:path";
import { getSettings } from "../config.js";
import { MEDIA_DIR } from "../db.js";
import { newId } from "../util.js";

/**
 * azt /v1/images/generations（gpt-image-2 经 Codex OAuth）。
 * 已知行为（2026-06-30 实测）：
 * - 响应头等到生成完成才返回，全程可达 3-6 分钟 → timeout 必须够长（960s）
 * - size/quality 参数是建议性的，构图靠 prompt 内注入尺寸指令
 * 返回相对 media 路径，如 "proj123/img_xxx.png"。
 */
export async function generateImage(prompt: string, projectId: string): Promise<string> {
  const s = getSettings();
  const fullPrompt = `${prompt.trim()}\n\n${s.imageSizeDirective}`;
  const res = await axios.post(
    `${s.imageBaseUrl.replace(/\/+$/, "")}/images/generations`,
    {
      model: s.imageModel,
      prompt: fullPrompt,
      size: "1024x1024",
      quality: "low",
      response_format: "b64_json",
    },
    {
      headers: { Authorization: `Bearer ${s.imageApiKey}`, "Content-Type": "application/json" },
      timeout: 960_000,
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    },
  );
  const b64: string | undefined = res.data?.data?.[0]?.b64_json;
  if (!b64) {
    const urlAlt: string | undefined = res.data?.data?.[0]?.url;
    if (urlAlt) {
      // 兼容 url 返回模式
      const img = await axios.get(urlAlt, { responseType: "arraybuffer", timeout: 120_000 });
      return saveImage(Buffer.from(img.data), projectId);
    }
    throw new Error(`图片模型未返回图像数据: ${JSON.stringify(res.data).slice(0, 300)}`);
  }
  return saveImage(Buffer.from(b64, "base64"), projectId);
}

function saveImage(buf: Buffer, projectId: string): string {
  const rel = path.join(projectId, `img_${newId()}.png`);
  const abs = path.join(MEDIA_DIR, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, buf);
  return rel;
}
