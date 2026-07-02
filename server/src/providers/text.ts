import axios from "axios";
import { getSettings } from "../config.js";

export interface TextResult {
  content: string;
  usage: { promptTokens: number; completionTokens: number };
}

/**
 * OpenAI 兼容 chat completions（azt → Codex OAuth 路径）。
 * 注意：该路径不支持 response_format/json_schema，结构化输出靠 prompt 约定 + 上层校验。
 */
export async function generateText(system: string, user: string): Promise<TextResult> {
  const s = getSettings();
  const res = await axios.post(
    `${s.textBaseUrl.replace(/\/+$/, "")}/chat/completions`,
    {
      model: s.textModel,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      max_completion_tokens: 32000,
    },
    {
      headers: { Authorization: `Bearer ${s.textApiKey}`, "Content-Type": "application/json" },
      timeout: 300_000,
    },
  );
  const content: string | undefined = res.data?.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error(`文本模型未返回内容: ${JSON.stringify(res.data).slice(0, 300)}`);
  }
  return {
    content,
    usage: {
      promptTokens: res.data?.usage?.prompt_tokens ?? 0,
      completionTokens: res.data?.usage?.completion_tokens ?? 0,
    },
  };
}
