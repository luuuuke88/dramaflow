import axios from "axios";
import { customAlphabet } from "nanoid";

export const newId = customAlphabet("0123456789abcdefghijklmnopqrstuvwxyz", 14);

/** 从 LLM 输出中提取 JSON（容忍 markdown 代码块、前后杂文） */
export function extractJson(raw: string): unknown {
  let text = raw.trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) text = fence[1].trim();
  // 直接尝试
  try {
    return JSON.parse(text);
  } catch {
    /* fallthrough */
  }
  // 找第一个 { 或 [ 到最后一个 } 或 ]
  const start = Math.min(
    ...["{", "["].map((c) => {
      const i = text.indexOf(c);
      return i === -1 ? Number.POSITIVE_INFINITY : i;
    }),
  );
  const end = Math.max(text.lastIndexOf("}"), text.lastIndexOf("]"));
  if (start !== Number.POSITIVE_INFINITY && end > start) {
    return JSON.parse(text.slice(start, end + 1));
  }
  throw new Error("输出中未找到有效 JSON");
}

/** 错误 → 人类可读消息。axios 错误附带上游响应体（生成失败必须能看到具体原因）。 */
export function errMessage(e: unknown): string {
  if (axios.isAxiosError(e)) {
    const status = e.response?.status;
    const data = e.response?.data;
    let detail = "";
    if (data != null) {
      try {
        detail = typeof data === "string" ? data : JSON.stringify(data);
      } catch {
        detail = String(data);
      }
    }
    return `HTTP ${status ?? "网络错误"} ${e.message}${detail ? `：${detail.slice(0, 500)}` : ""}`;
  }
  if (e instanceof Error) return e.message;
  return String(e);
}
