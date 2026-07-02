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

export function errMessage(e: unknown): string {
  if (e instanceof Error) return e.message;
  return String(e);
}
