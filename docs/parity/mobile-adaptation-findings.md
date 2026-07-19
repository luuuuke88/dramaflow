# DramaFlow 移动端适配质量审计（Mobile-Adaptation Findings）

状态：只读审计结果，2026-07-18。这是一份与 W0 功能对齐审计（`docs/parity/master-checklist.md`，538/538，已完成，本文档不修改也不重复该文件的工作）**完全独立**的新调查：ToonFlow 本体是 Electron 桌面专属应用，没有移动端可供对比，因此本文档评估的是 DramaFlow **自身**在手机屏幕上的绝对可用性，而非与 ToonFlow 的功能对齐度。

方法：7 组 subagent 并行审阅了 `app/lib/src/screens/**` 下全部 31 个屏幕文件及 `widgets/shell.dart`、`df_canvas.dart`、`df_data_table.dart`、`df_adaptive_dialog.dart` 等共享组件，逐文件检查 5 类风险（溢出风险、触控目标尺寸、文本截断处理、桌面专属交互模式无触控兜底、既有手机视口测试覆盖），部分发现通过临时探针测试（probe test）在真实 390px 视口下实测验证，而非仅凭代码推断。

本文档最初只记录问题不做修复（按用户要求：卡住的地方先记录，之后由用户处理）。**后续用户明确要求全部处理，以下类别 A/B/D/E/F 的全部具体缺陷已于同一会话内修复并通过全量测试**（`flutter analyze` 0 issues，`flutter test` 613/613 全绿），详见每类描述后的"✅ 已修复"标注与 `.superpowers/sdd/progress.md` 对应条目。类别 C（触控目标尺寸，散落的次要项）中与 A/B/D/E/F 修复顺带覆盖的部分已修，未逐条清点剩余的孤立次要项——如需要可另行清点。W1/W2/W3 范围内容（画布重写/Agent 移植/NLE 新增能力）仍不在本文档修复范围内，按 spec 卡在 L0b 门槛前。

---

## 一、积极的架构性发现（先说好消息）

1. **无限画布的"体验不好"问题，在移动端已经被架构性地绕开了。** `production_screen.dart` 的 `_CanvasLayout`（真正基于 `InteractiveViewer` 的可平移画布 `DFCanvas`）被显式限定在 `constraints.maxWidth>=840` 才启用；840dp 以下改用 `_MobileTabsLayout`——纵向 Tab 切换取代画布平移，文件里甚至留有中文注释说明这是刻意决定："移动端<840：画布不适合窄屏平移操作，改为纵向Tab切换各节点内容"。这直接回应了本次调查最初的动机（"无限画布体验不好"）——不是把平移做好，而是在小屏幕上根本不用画布隐喻。
2. **`storyboard_canvas_node.dart` 的长按菜单是对 ToonFlow 原设计的真实改进**，不只是移植：文件头注释明确写道 ToonFlow 用悬停显示的"+"插入按钮，因为"触屏无hover"，DramaFlow 改为长按菜单——这是本次审计中发现的最佳移动端适配决策。
3. **`storyboard_gallery.dart`** 用 `InteractiveViewer`（捏合缩放）+ `PageView`（滑动切图）实现原生触控手势，写法正确，只是完全没有专属手机视口测试覆盖。
4. **`showDFAdaptiveDialog` 模式**被广泛使用，正确地把 840dp 以下的弹窗路由为全屏页面而非居中小弹窗（少数遗漏见下文）。
5. **`DFDataTable` 的 840dp 断点**（桌面 `DataTable` ↔ 移动 `ListView` 卡片）是良好的共享基础设施，虽然多处 `mobileCardBuilder` 的具体实现有数据/操作丢失问题（见下）。
6. `generate_image_dialog.dart` 的 40/60 分栏在手机全屏路由下（内容宽度 320-390px，远小于触发桌面双栏的 700px 阈值）**已经正确堆叠**，审计前的预设怀疑被证伪。
7. `video_request_dialog.dart` 是本次审计中表现最好的对话框：`showDFAdaptiveDialog` 正确全屏化，且被另一个文件的测试（`workbench_screen_test.dart:5057+`）在 390x900 下真实交互验证过。

---

## 二、真实缺陷：按缺陷类别分组（跨文件重复出现的问题优先）

### 类别 A — 悬停专属控件，触屏完全无法触达（功能性阻断，非美观问题）✅ 已修复

同一个架构性错误在至少 **3 个独立文件**中重复出现：`MouseRegion.onEnter/onExit` 控制编辑/删除按钮的显隐，触屏设备永远不会触发 hover，导致该功能在手机上**完全不可达**，不是体验差，是功能残缺。

| 文件 | 位置 | 受影响功能 |
|---|---|---|
| `manual_gallery.dart` | L143-161（`_ManualCell`） | 手册包的编辑/删除入口，手机上无法访问 |
| `art_style_library.dart` | L156-219（gate 189-202） | 画风的编辑/删除入口，手机上无法访问 |
| `script_screen.dart` | L453-462 / L500-510 | 单条剧本卡片的删除图标，手机上唯一可用删除路径退化为工具栏批量选择 |

三处均无任何测试覆盖这一交互，任何视口下都没有。**这是本次审计中最值得优先修复的缺陷类别**，因为它不是"体验打折扣"，而是把桌面才有的功能直接从手机端拿掉了。

**修复**：三处均改为 `showActions = _hover || compact(width<700dp)`，复用 `project_list_screen.dart` 已有的正确范式——窄屏下操作始终可见，宽屏保留 hover 便利。均新增了此前完全缺失的 widget 测试。详见 `.superpowers/sdd/progress.md` 对应条目。

### 类别 B — 确定/高置信度的横向溢出 ✅ 已修复

| 文件 | 位置 | 严重度 | 证据 |
|---|---|---|---|
| `script_screen.dart` | L467，`_ScriptCard` 固定 `width:400` | **数学上必然溢出** | 360-428pt 手机可用宽度均为 320-388px，400px 卡片在所有手机尺寸（含最宽的 428pt）上都装不下。全审计中置信度最高的溢出 bug。 |
| `event_tab.dart` | L89-118 工具栏 `Row` | **近乎确定溢出** | 2 个 `FilledButton.icon` + `Spacer` + 固定 `width:260` 的搜索框，无任何 `LayoutBuilder`/`Wrap`（对比同文件姊妹屏 `novel_screen.dart` 的同形状工具栏就有响应式处理），本征最小宽度约 550-560px，超过所有手机宽度。 |
| `corner_scape_screen.dart` | L236-286 列表行 | **已通过探针测试实测确认**（非推测） | Checkbox(48) + 220px 下拉框 + 角色名 `Expanded(Text)` 挤压到约 8px 宽——实测 10 字符角色名会逐字换行，整行膨胀到 210px 高，无报错但布局静默损坏。现有 3 个手机测试用例用的都是 3-4 字短名字，恰好绕开了这个坑。 |

两者均无测试覆盖，`event_tab.dart` 更是全文件零测试覆盖。

**修复**：`script_screen.dart` 卡片宽度改 `LayoutBuilder` 响应式 clamp；`event_tab.dart` 工具栏复用 `novel_screen.dart` 已有的 `compact<720` Row→Wrap 断点；`corner_scape_screen.dart` 复用文件自身已有的 `<420` Row→Column 断点。三处均新增回归测试，且均用"临时回退验证测试真的会失败"的方法核实过测试有效性。

### 类别 C — 触控目标尺寸低于约 44×44dp 指南（按严重程度排列）

最极端的几例：

- `workbench_screen.dart` L3507-3557 `_TimelineResizeHandle`：**14px 宽**的纯竖直裁剪手柄，`MouseRegion` 仅控制光标图标不控制功能，是典型"为鼠标精度设计、未考虑手指"的控件，且相邻片段的手柄彼此靠得很近。
- `image_flow_editor.dart` L1353-1375 `_HandleDot`（连线手柄）：12×12 圆点，是在节点图编辑器中创建参考图连接的**唯一**交互方式（非装饰性），有效命中区域最多约 24×24。
- `image_flow_editor.dart` L655-658/802-805 节点删除 "×" 按钮：约 14×14。
- `storyboard_canvas_node.dart` L443-449 `_miniIcon`：4 个操作图标在最小缩放（`_cellSize=90`）下 `spaceEvenly` 排布，每个约 22.5px，间距趋近于零。
- `settings_screen.dart` L1944-1966 `_SmallIconButton`：`VisualDensity.compact` 缩小到约 40×40，且用在移动端会话卡片上，4 个图标里就挨着一个删除操作。
- 另有多处 28×28～40×40 区间的次要实例（`production_screen.dart` 的 `_NodeHeader` 编辑按钮、`_StoryboardTableNode` 生成按钮、`manual_gallery.dart` 的 `_MiniIcon`、`project_list_screen.dart` 的编辑/删除图标等），完整清单见各分组原始笔记（`/private/tmp/.../scratchpad/mobile-audit/0{1-7}-*.md`，如需要我可以整理为一份扁平清单）。

### 类别 D — 移动端卡片视图相对桌面表格丢数据/丢操作 ✅ 已修复

`DFDataTable` 的 840dp 断点架构是对的，但多处 `mobileCardBuilder` 的具体实现在移动端悄悄丢失了桌面版本本来有的信息或操作：

- `event_tab.dart` L202-212：移动卡片只显示名称+章节数，**桌面有的描述、创建时间、单条删除按钮全部消失**——由于移动卡片的 tap 行为是切换多选而非行内操作，手机上**没有任何方式删除单个事件**，只能走批量选择，这是全审计中最严重的功能性倒退之一。
- `novel_screen.dart` L367-383：移动卡片丢失章节内容预览列，手机用户无法从列表预览章节正文。
- `import_novel_dialog.dart` L229-236：同样丢失章节内容预览，而这个对话框的核心用途就是挑选要导入的章节。
- `batch_add_dialog.dart` L307-318：移动卡片标题 `Text` 缺少 `maxLines`/`overflow`，桌面同字段的单元格（L281-282）却正确设置了——移动端相对桌面退化。
- `batch_generation_dialog.dart` L431：同样，移动卡片标题缺少 `maxLines`/`overflow`，`assets_screen.dart` 的等价移动卡片却有。

**修复**：`event_tab.dart` 移动卡片补回单条删除（含二次确认）；`novel_screen.dart`/`import_novel_dialog.dart` 移动卡片补回章节内容预览；`batch_add_dialog.dart`/`batch_generation_dialog.dart` 移动卡片标题补齐 `maxLines`/`overflow` 对齐桌面。

### 类别 E — 非滚动容器 + 真实数据量 → 内容不可达 ✅ 已修复

- `assets_screen.dart` L430-552：840dp 以下的 `_MobileRows` 用 `ListView.separated(shrinkWrap:true, NeverScrollableScrollPhysics)`，链路上没有任何 `SingleChildScrollView` 祖先。默认分页 `_limit=10`，每张卡片约 90-120px 高，10 条约 1000-1300px，手机实际可用空间（去掉 shell 外壳+Tab 栏+工具栏后）通常只有 300-500px——**这不是边界情况，是任何资产数超过几个的项目的默认状态**。现有测试每个 Tab 只放 1-2 条数据，从未填满过一页，因此从未触发这个问题。
- `batch_generation_dialog.dart` L395-438：同样机制，表格区域硬编码固定 430px 且内部列表不可滚动，图片模式下控件+筛选+操作栏总需求高度约 850-900px，超过几乎所有手机竖屏可用高度。现有测试用 390×900（比 iPhone SE 的 667 或 13 mini 的 812 都高，掩盖了这个问题）且只放 2 条数据。

**修复**：`assets_screen.dart` 在 840dp 以下给移动列表包上 `SingleChildScrollView`（call-site 级修复，未动共享的 `DFDataTable` 本体，因为它还有 5 个其他调用方）；`batch_generation_dialog.dart` 固定高度改 `Expanded`+`SingleChildScrollView`。两处回归测试均改用真实 iPhone SE 尺寸（390×667）+ 满页真实数据量验证，不再用会掩盖问题的 390×900。

### 类别 F — 桌面/移动 Shell 双重 Chrome 叠加（本轮新发现，group 7）✅ 已修复

`agent_chat_screen.dart`（L149-186）自带 `Scaffold(appBar: AppBar(...))`，而它是作为 `ShellRoute` 子页面挂载在 `_MobileShell` 内的（`app.dart:46-49` 路由 `/p/:pid/scriptAgent`），`_MobileShell` 自己也有 `Scaffold(appBar: AppBar(...))` + 44dp 的项目 Tab 条（`shell.dart:338-349`）。结果是手机上每次进入剧本助手都会叠加**两层完整工具栏**（项目名 AppBar+Tab 条约100dp + 页面自己的 AppBar 约56dp）再加 64dp 底部导航栏，共约 220dp 的纯 chrome，占掉小屏手机将近三分之一的可视高度——聊天内容还没出现就先吃掉这么多空间。桌面端不会出现同样问题，因为 `_DesktopShell` 用的是轻量的非 `Scaffold` `_TopBar`（约50dp）。`agent_chat_screen_test.dart` 从未设置手机视口也从未把该屏幕包裹在 `AppShell` 内，`shell_test.dart` 的路由表也从未注册 `/p/:pid/...` 路由，这个交互完全没有测试网可以捕获。**这是本轮审计中除类别 A（悬停陷阱）和类别 B（确定溢出）之外，第三个值得优先修复的具体缺陷。**

**修复**：`AgentChatScreen.build()` 内用 `MediaQuery.sizeOf(context).width<840`（与全仓其他地方判断移动/桌面 shell 的断点一致）判断是否托管在 `_MobileShell` 内，是则不渲染自身 `Scaffold`/`AppBar`，actions 移入新增的 `_InlineActionsBar`；桌面 `_TopBar` 路径逐字节不变。修复中顺带发现并修了移除 `Scaffold` 后 `Switch` 缺 `Material` 祖先的连带问题。新增测试通过真实 `GoRouter`+`ShellRoute`+`AppShell` 挂载断言只有一个 `AppBar`，并用 git stash 回退验证测试确实能抓住原 bug。

---

## 三、测试覆盖的系统性缺口

- **完全零覆盖（任何视口）的文件**：`add_script_dialog.dart`、`asset_picker.dart`、`edit_novel_dialog.dart`、`event_tab.dart`（同时是本审计最严重 bug 的所在文件）、`add_audio_asset_dialog.dart`、`generate_image_dialog.dart`、`manual_editor.dart`。
- **测试辅助函数支持手机宽度参数，但从未真正传入过手机值**：`storyboard_canvas_node_test.dart`、`script_plan_node_test.dart`（`script_plan_node_test.dart` 更明确——代码注释说明选择桌面尺寸是为了"走对话框而非全屏页，便于就地断言"，属于刻意的测试编写便利，副作用是真实移动端渲染路径从未被验证）。
- **`agent_chat_screen_test.dart`**：从未设置 `physicalSize`，从未把屏幕挂载在 `AppShell` 内——不仅是"没测手机尺寸"，而是结构上不可能测出类别 F 的双 chrome 叠加问题。
- **系统性方法论缺口**：`assets_mobile_screen_test.dart`、`assets_tts_screen_test.dart`、`batch_generation_dialog_test.dart` 等目前"已在手机视口测试"的用例统一用 `390×900`——900 的高度比 iPhone SE（667）、13 mini（812）都高，接近大屏手机的**总**高度而非去除系统栏后的可用高度；同时测试数据普遍只有 0-3 条。这意味着类别 E（非滚动容器+真实数据量）这类问题即使有"手机视口测试"也不会被捕获，因为测试的高度和数据量都不真实。这个方法论缺口很可能不止影响本文档点名的两个文件，值得在补测试时通盘修正（更矮的高度如 667、更真实的种子数据行数）。

---

## 四、优先级建议（仅供参考，不代表实施顺序，由用户裁决）

按"用户可感知的破坏程度 × 修复成本低"排序：

1. **类别 A（悬停陷阱，3 处）**——功能性阻断，修复成本低（每处只需加一个触屏可见的按钮/菜单入口，`storyboard_canvas_node.dart` 的长按菜单已经提供了现成的架构范式可以复用）。
2. **类别 F（agent_chat_screen 双工具栏)**——用户每次进入 AI 助手都会看到，修复成本低（去掉自身 Scaffold/AppBar 或把 actions 移进 shell chrome）。
3. **类别 B 中的 `script_screen.dart:467`**——数学上保证触发，修复成本低（改用响应式宽度或 `LayoutBuilder`）。
4. **类别 D 中 `event_tab.dart` 的单条删除功能倒退**——手机端用户完全失去这个能力，修复成本中等（需要重新设计移动卡片的操作区）。
5. 其余类别 B/C/E 问题，以及测试覆盖缺口，按用户实际使用到的路径逐步补。

---

## 五、760–800dp 平板回归补充（2026-07-19）✅ 已验证

前述手机用例主要使用 390px 宽度，不能证明 700–839dp 的平板移动壳可用。本轮按 `AppShell` 的移动边界（`<840dp`）补了中等宽度测试，发现并关闭了两类真实问题：

| 范围 | 修复/验证 | 自动化证据 |
| --- | --- | --- |
| 项目卡片、手册画廊、画风库、剧本卡片 | 原先以 `<700dp` 判断“触控常显操作”，使 700–839dp 平板没有 hover 时无法编辑/删除；统一为 `<840dp`。 | `project_page_test.dart`、`manual_gallery_test.dart`、`art_style_library_test.dart`、`script_screen_test.dart` 的“移动壳平板宽度下”用例 |
| 剧本工具栏 | 760dp 可用宽度时七个操作与搜索框一行排布，实测溢出 327px；按实际内容宽度在 `<1040dp` 改为搜索框加 Wrap。 | `script_screen_test.dart` |
| 小说工具栏 | 760dp 可用宽度实测 `RenderFlex` 溢出 0.4px；与移动壳边界对齐，`<840dp` 使用纵向搜索加 Wrap。 | `novel_screen_test.dart` |
| 素材与事件工具栏 | 800dp 下分别实际渲染，无布局异常。 | `assets_mobile_screen_test.dart`、`event_tab_test.dart` |
| 新建项目向导测试 | 原用例点击内部 `Text`，会产生“目标不接收指针”的警告；改为点击真正的卡片 `GestureDetector`，并把该类警告设为失败，防止离屏交互被假绿掩盖。 | `project_page_test.dart` |

本节不是把 840dp 当成所有组件的万能阈值：操作可达性跟随移动壳，工具栏则按实际最小内容宽度换行。后续每个响应式组件都应同时覆盖手机窄屏、760–800dp 平板移动壳和桌面宽屏。

## 六、当前代码复核：时间线裁剪（2026-07-19）⚠️ 仍有体验风险

本节在前述审计与修复提交之后，重新直接核对当前 Flutter 源码和 widget 测试。结论需要分开说，不能把 14dp 拖拽手柄简单记为“移动端裁剪不可用”。

| 维度 | 当前证据 | 结论 |
| --- | --- | --- |
| 功能是否可达 | 片段选中后提供“裁剪素材层尾部”全屏数值表单，以及按播放头裁剪首/尾的命令；390px widget 回归实际完成多选、打开全屏页、输入时长并落库。 | **可达**，触屏用户不必命中边缘把手才能改时长。 |
| 直接拖动裁剪 | `_TimelineResizeHandle` 仍只有 14dp 宽，且两侧把手相邻时更难稳定命中；现有直接拖动测试没有设置移动视口。 | **未达移动端最佳实践**，属于精确拖拽体验风险，不应宣称已适配。 |
| 小屏高度 | 已有工作台移动回归多数使用 390×900；没有同等覆盖 390×667（iPhone SE 级可用高度）下的选中工具栏、数值裁剪页和候选管理。 | **证据不足**，不能用 900px 用例外推全部手机。 |

对应源码/测试证据：

- `app/lib/src/screens/production/workbench_screen.dart:733-862`：选中后数值裁剪与播放头裁剪，不依赖鼠标悬停。
- `app/lib/src/screens/production/workbench_screen.dart:3236-3253,3379-3427`：直接裁剪仍依赖 14dp 的横向拖拽把手。
- `app/test/widgets/workbench_screen_test.dart:3478-3588`：390px 下的批量裁剪全屏表单行为回归；同文件直接拖拽把手用例未设置移动视口。

后续实现的验收标准应是：在 390×667 和 760–800dp 两档移动壳中，单个片段可通过不小于 44dp 的触控入口完成首/尾精细裁剪，并保留桌面端的直接拖拽效率。实现前需先确定是扩大把手命中区，还是在片段菜单中加入明确的“裁剪首部/裁剪尾部”表单入口；两者都不能牺牲相邻片段的选择与拖动语义。

---

## 附：分组原始审计笔记

完整的逐文件、逐行证据（含未在本文档中摘录的 Minor 级发现）保存在：
`/private/tmp/claude-501/-Users-luke-Documents-aivideo/32c05c60-7be8-4f4d-8fec-9ff46fd45e55/scratchpad/mobile-audit/01-project-manuals.md` 至 `07-agent-settings-tasks.md`（7 个文件，覆盖全部 31 个屏幕文件）。这些是临时会话文件，如果这份调查有留存价值，建议后续把需要的部分迁移进正式仓库位置。
