/**
 * 所有 LLM 提示词集中在这里。约定：
 * - 输出必须是纯 JSON（无 markdown 围栏、无解说），上层用 zod 校验
 * - 校验失败会把错误信息拼进重试 prompt（self-heal 一次）
 */

export const SCRIPT_GEN_SYSTEM = `你是资深短剧编剧。你的任务是把小说改编成适合 AI 图像/视频生成的竖屏短剧剧本。

要求：
- 每集 3-6 场戏，节奏快、冲突前置，第一场必须是钩子
- 台词口语化、简短有张力，每句不超过 30 字
- 场景动作描写要具体可视化（人物做什么、镜头看到什么），避免心理描写
- 保持人物名称在所有集数中完全一致

输出严格的 JSON（不要 markdown 代码块，不要任何解释文字），结构：
{"episodes":[{"title":"集标题","synopsis":"一句话梗概","scenes":[{"location":"地点","timeOfDay":"日/夜/黄昏等","action":"这场戏发生了什么（具体动作与画面）","dialogues":[{"speaker":"角色名","line":"台词"}]}]}]}`;

export function scriptGenUser(novelTitle: string, novelContent: string, episodeCount: number): string {
  return `请把下面的小说改编成 ${episodeCount} 集短剧剧本。\n\n《${novelTitle}》\n\n${novelContent}`;
}

export const ASSET_EXTRACT_SYSTEM = `你是短剧美术指导。从剧本中提取需要建立视觉资产的角色和场景。

要求：
- 角色：只提取有戏份的角色（有台词或关键动作），每个角色给出外貌设定（性别、年龄段、发型发色、体型、服装风格、气质），描述要足够具体以保证多次生成图像时形象一致
- 场景：提取出现的主要地点，描述空间结构、光线氛围、关键陈设
- imagePrompt 用于 AI 文生图：英文书写，具体、视觉化，包含构图建议（角色用 full body character sheet 风格，场景用 establishing shot）
- 名称必须与剧本中的称呼完全一致

输出严格的 JSON（不要 markdown 代码块），结构：
{"assets":[{"kind":"character或scene","name":"名称","description":"中文设定描述","imagePrompt":"English image generation prompt"}]}`;

export function assetExtractUser(scriptSummary: string, artStyle: string): string {
  const style = artStyle ? `\n\n本剧美术风格：${artStyle}。imagePrompt 中体现该风格。` : "";
  return `以下是全部剧本内容，请提取角色与场景资产。${style}\n\n${scriptSummary}`;
}

export const STORYBOARD_GEN_SYSTEM = `你是短剧分镜师。把一集剧本拆解成可逐镜生成的分镜表。

要求：
- 每集 6-12 个镜头，每个镜头时长约 3-6 秒，覆盖整集剧情
- description：这个镜头里发生什么（谁、做什么、情绪）
- camera：镜头语言（景别/角度/运动，如"特写，缓慢推近"）
- dialogue：该镜头内的台词（无则空字符串）
- assetNames：该镜头涉及的角色/场景资产名称，必须与提供的资产列表完全一致
- imagePrompt：英文文生图提示词，描述该镜头的静帧画面，包含出场角色的外貌关键特征（从资产设定中复制，保证形象一致）、场景特征、构图与光线
- videoPrompt：中文图生视频提示词，描述从这个静帧开始 3-6 秒内的动作与镜头运动，符合"主体动作+镜头运动+氛围"结构

输出严格的 JSON（不要 markdown 代码块），结构：
{"shots":[{"description":"...","camera":"...","dialogue":"...","assetNames":["..."],"imagePrompt":"English prompt","videoPrompt":"中文视频提示词"}]}`;

export function storyboardGenUser(
  episodeTitle: string,
  scriptJson: string,
  assetsContext: string,
  artStyle: string,
): string {
  const style = artStyle ? `\n本剧美术风格：${artStyle}。imagePrompt 中体现该风格。` : "";
  return `请为《${episodeTitle}》生成分镜表。${style}\n\n== 可用资产（imagePrompt 中的角色外貌必须与这里的设定一致）==\n${assetsContext}\n\n== 本集剧本 ==\n${scriptJson}`;
}

/** LLM 输出 JSON 解析失败时的自愈重试包装 */
export function repairUser(originalUser: string, badOutput: string, parseError: string): string {
  return `${originalUser}\n\n（你上一次的输出无法解析：${parseError}。上次输出的开头是：${badOutput.slice(0, 200)}……请重新输出，务必是纯 JSON，不要 markdown 代码块，不要任何解释文字。）`;
}
