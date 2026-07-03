# 2026-07-04 ToonFlow Page Parity Checklist

Authority: `docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md`.

This checklist is evidence tracking, not a completion claim. `Verified` means a repeatable test or build currently covers the named path. `Partial` means the page exists and has coverage, but at least one v0.3-required ToonFlow capability still lacks proof or implementation. `Gap` means the v0.3-required capability is intentionally not proven yet.

## 项目列表 + 新建向导

Status: Partial

Desktop Evidence: `app/test/widgets/project_page_test.dart` covers the empty state and new-project entry; `app/test/engine/projects_test.dart` covers project CRUD fields.

Mobile Evidence: `app/test/widgets/project_page_test.dart` covers a 390px full-screen new-project wizard: project type, name, novel type, intro, image model, image quality, video model, video mode, video ratio, visual manual, and director manual are saved into `o_project`.

Known Gaps: Desktop edit/delete/stat card parity and mobile project card action coverage still need stronger proof.

Next Verification: Add desktop/mobile project card action tests for edit, delete, and project statistics display.

## 章节管理 + 事件

Status: Verified

Desktop Evidence: `app/test/widgets/novel_screen_test.dart` covers selected chapter event-generation enqueue on desktop width; engine tests cover novel CRUD, event generation, event analysis, and docx parsing.

Mobile Evidence: `app/test/widgets/novel_screen_test.dart` covers 390px import of two chapters, event-generation enqueue, and mobile card display.

Known Gaps: Event analysis has engine coverage, but the mobile event-analysis dialog path still needs a widget smoke.

Next Verification: Add a mobile event-analysis UI test that selects imported chapters and opens the analysis view with fake event data.

## 剧本

Status: Partial

Desktop Evidence: `app/test/engine/scripts_test.dart` covers script CRUD, extraction, export, and failure recovery.

Mobile Evidence: `app/test/widgets/script_screen_test.dart` covers 390px batch-add parsing and persistence.

Known Gaps: v0.3 asks for a rich-text editor and single/batch event-to-script generation proof. Current coverage verifies text editing and batch add, not rich-text formatting parity.

Next Verification: Add widget coverage for editing an existing script and a separate plan for rich-text editor parity or a documented scoped substitute.

## 素材库

Status: Partial

Desktop Evidence: `app/test/engine/assets_test.dart`, `app/test/widgets/batch_generation_dialog_test.dart`, and `app/test/widgets/assets_tts_screen_test.dart` cover asset CRUD, child assets, prompt polishing, image generation parameters, and desktop TTS creation.

Mobile Evidence: `app/test/widgets/assets_tts_screen_test.dart` covers 390px audio tab text-to-speech generation and card-list return.

Known Gaps: Mobile tests do not yet cover role/tool/scene add/edit, child asset expansion, batch prompt generation, batch image generation, or art style library entry.

Next Verification: Add mobile role/scene/tool asset CRUD smoke and a mobile batch-generation parameter smoke.

## 制作画布

Status: Partial

Desktop Evidence: `app/test/widgets/production_screen_test.dart`, `app/test/widgets/script_plan_node_test.dart`, `app/test/widgets/storyboard_canvas_node_test.dart`, and `app/test/widgets/canvas_chat_panel_test.dart` cover canvas entry, nodes, storyboard gallery, insertion, script editing, storyboard table editing, and Agent panel basics.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Tab-based production navigation, workbench entry, Agent entry, and offline UI chain access.

Known Gaps: No runtime performance proof for 1000-node canvas, no side-by-side ToonFlow screenshot checklist, and mobile node inspector parity remains partial.

Next Verification: Add a performance-oriented canvas smoke or documented manual profile, then add a page-level visual parity checklist entry with screenshots.

## 节点式图片编辑器

Status: Partial

Desktop Evidence: `app/test/widgets/image_flow_editor_test.dart` and `app/test/engine/image_flow_test.dart` cover graph persistence, reference image selection, generated node controls, flow image generation, and line deletion.

Mobile Evidence: Indirectly reachable from production mobile tests, but no dedicated 390px image-flow editor smoke is recorded.

Known Gaps: Local remove-line/inpaint UI parity and mobile image-flow manipulation are not fully proven.

Next Verification: Add a mobile image-flow smoke that opens the editor, selects an asset reference, and verifies generated-node settings remain usable.

## 多轨工作台

Status: Partial

Desktop Evidence: `app/test/widgets/workbench_screen_test.dart`, `app/test/engine/video_track_test.dart`, and `app/test/engine/compose_episode_test.dart` cover prompt editing, duration editing, selected video candidates, shot audio binding, and compose handoff.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px workbench entry through production tabs and the offline chain reaches compose.

Known Gaps: Full WebAV/NLE parity is not implemented: transitions, filters, multi-layer timeline editing, and drag-based clip editing are not proven.

Next Verification: Keep current sequential-shot workbench as the v1 baseline, and open a separate NLE/WebAV parity plan before claiming full ToonFlow workbench parity.

## 配音

Status: Verified

Desktop Evidence: `app/test/widgets/corner_scape_screen_test.dart` covers empty state, manual binding, auto-match enqueue, bound/unbound filters, search, select-all-unbound, and audition error handling.

Mobile Evidence: `app/test/widgets/corner_scape_screen_test.dart` covers 390px manual role-audio binding.

Known Gaps: Mobile AI auto-match and mobile audition playback are not separately covered, though desktop equivalents exist.

Next Verification: Add a 390px AI auto-match smoke and a mobile audition-missing-file smoke if this page changes again.

## 任务中心

Status: Partial

Desktop Evidence: `app/test/widgets/tasks_screen_test.dart` covers task listing, type filter, status filter, and historical task display.

Mobile Evidence: No dedicated mobile task-center smoke is recorded.

Known Gaps: Project filter, detail log view, retry, cancel, and mobile layout parity need stronger proof.

Next Verification: Add desktop and 390px tests for task detail, retry, and cancel actions using seeded `o_tasks` rows.

## Agent 体系页

Status: Partial

Desktop Evidence: `app/test/widgets/agent_chat_screen_test.dart`, `app/test/widgets/canvas_chat_panel_test.dart`, and `app/test/engine/agent_test.dart` cover basic persisted messages, tool dispatch, errors, and production panel entry.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Agent entry from production.

Known Gaps: Full ToonFlow multi-layer Agent + RAG memory, skill editing, deployment configuration, and custom JS skill execution are not fully replicated.

Next Verification: Treat full Agent parity as its own subsystem plan; add page tests for deployment mode persistence, skill list display, and memory management before claiming this page complete.

## 全套设置

Status: Partial

Desktop Evidence: `app/test/engine/engine_facade_test.dart`, `app/test/ui_i18n_static_test.dart`, and settings-related engine tests cover provider CRUD, model binding validation, config import/export, prompt seed/update/reset, theme and locale persistence, storage information, and static i18n checks.

Mobile Evidence: `app/test/widgets/settings_screen_test.dart` covers 390px settings flows: theme change, locale change, provider creation, prompt editor entry, provider model management, model binding, database info, and clear-data confirmation.

Known Gaps: Mobile provider edit flow, per-modality test UI, config import/export, open data folder, and about/storage secondary paths are not all proven by widget tests.

Next Verification: Add 390px settings tests for provider edit, per-modality provider test selection, config import/export error paths, and about panel.
