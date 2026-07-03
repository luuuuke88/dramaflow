# 2026-07-04 ToonFlow Page Parity Checklist

Authority: `docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md`.

This checklist is evidence tracking, not a completion claim. `Verified` means a repeatable test or build currently covers the named path. `Partial` means the page exists and has coverage, but at least one v0.3-required ToonFlow capability still lacks proof or implementation. `Gap` means the v0.3-required capability is intentionally not proven yet.

## 项目列表 + 新建向导

Status: Verified

Desktop Evidence: `app/test/widgets/project_page_test.dart` covers the empty state, new-project entry, card navigation, hover edit/delete actions, and card statistics display. `app/test/engine/projects_test.dart` covers project CRUD fields and `projectStats()` aggregation.

Mobile Evidence: `app/test/widgets/project_page_test.dart` covers a 390px full-screen new-project wizard: project type, name, novel type, intro, image model, image quality, video model, video mode, video ratio, visual manual, and director manual are saved into `o_project`. It also covers 390px project-card edit/delete actions without hover.

Known Gaps: None at the current project-list/new-project page scope.

Next Verification: If project cards change, keep desktop hover and 390px no-hover action tests plus the local stats assertions.

## 章节管理 + 事件

Status: Verified

Desktop Evidence: `app/test/widgets/novel_screen_test.dart` covers selected chapter event-generation enqueue on desktop width; engine tests cover novel CRUD, event generation, event analysis, and docx parsing.

Mobile Evidence: `app/test/widgets/novel_screen_test.dart` covers 390px import of two chapters, event-generation enqueue, mobile card display, selected-chapter event analysis confirmation, and analysis result rendering.

Known Gaps: None at the current chapter/event page scope.

Next Verification: If chapter/event UI changes, keep selected event generation plus the 390px import and event-analysis smokes together.

## 剧本

Status: Partial

Desktop Evidence: `app/test/engine/scripts_test.dart` covers script CRUD, extraction, export, failure recovery, and batch script generation from selected events through the `script_gen` task runner.

Mobile Evidence: `app/test/widgets/script_screen_test.dart` covers 390px batch-add parsing and persistence, existing script editing with live card refresh, and event-to-script generation from the script page event picker.

Known Gaps: v0.3 asks for a rich-text editor. Current coverage verifies plain text editing and event-to-script generation, not rich-text formatting parity.

Next Verification: Create a separate rich-text editor parity plan or document a scoped plain-text substitute before claiming full script-page parity.

## 素材库

Status: Verified

Desktop Evidence: `app/test/engine/assets_test.dart`, `app/test/engine/art_style_test.dart`, `app/test/widgets/batch_generation_dialog_test.dart`, and `app/test/widgets/assets_tts_screen_test.dart` cover asset CRUD, child assets, prompt polishing, image generation parameters, art style library persistence, and desktop TTS creation.

Mobile Evidence: `app/test/widgets/assets_tts_screen_test.dart` covers 390px audio tab text-to-speech generation and card-list return. `app/test/widgets/assets_mobile_screen_test.dart` covers 390px role/tool/scene add/edit/delete plus child asset expansion. `app/test/widgets/batch_generation_dialog_test.dart` covers 390px batch prompt and batch image generation parameters. `app/test/widgets/project_page_test.dart` covers 390px art style library entry, new style creation, selection, and project persistence.

Known Gaps: None at the current v0.3 asset-library scope.

Next Verification: If asset-library UI changes, keep the 390px CRUD, child expansion, batch-generation parameter, art-style entry, and TTS smokes together.

## 制作画布

Status: Partial

Desktop Evidence: `app/test/widgets/production_screen_test.dart`, `app/test/widgets/script_plan_node_test.dart`, `app/test/widgets/storyboard_canvas_node_test.dart`, and `app/test/widgets/canvas_chat_panel_test.dart` cover canvas entry, nodes, storyboard gallery, insertion, script editing, storyboard table editing, and Agent panel basics.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Tab-based production navigation, workbench entry, Agent entry, and offline UI chain access.

Known Gaps: No runtime performance proof for 1000-node canvas, no side-by-side ToonFlow screenshot checklist, and mobile node inspector parity remains partial.

Next Verification: Add a performance-oriented canvas smoke or documented manual profile, then add a page-level visual parity checklist entry with screenshots.

## 节点式图片编辑器

Status: Partial

Desktop Evidence: `app/test/widgets/image_flow_editor_test.dart` and `app/test/engine/image_flow_test.dart` cover graph persistence, reference image selection, generated node controls, flow image generation, and line deletion.

Mobile Evidence: `app/test/widgets/image_flow_editor_test.dart` covers a dedicated 390px editor flow: the generated node is fit into the first mobile viewport, an upload node can replace its reference from the asset library, and generated-node prompt/model/ratio/quality settings persist into `o_imageFlow`.

Known Gaps: Local remove-line/inpaint UI parity is not fully proven.

Next Verification: Add a scoped local remove-line/inpaint parity plan before claiming full image-flow editor parity.

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

Status: Verified

Desktop Evidence: `app/test/widgets/tasks_screen_test.dart` covers task listing, type filter, status filter, historical task display, and read-only task detail with failure reason/related objects.

Mobile Evidence: `app/test/widgets/tasks_screen_test.dart` covers 390px task-center layout, project switching, detail dialog, failed-task retry, and pending-task cancellation with `errCanceled` persisted.

Known Gaps: None at the current task-center page scope. Long-running real queue cancellation is still covered at engine level by `app/test/engine/queue_test.dart`, not by a widget test with a live provider call.

Next Verification: If task-center UI changes, keep the 390px smoke and add a real processing-task cancel widget smoke around a fake long-running task runner.

## Agent 体系页

Status: Partial

Desktop Evidence: `app/test/widgets/agent_chat_screen_test.dart`, `app/test/widgets/canvas_chat_panel_test.dart`, and `app/test/engine/agent_test.dart` cover basic persisted messages, tool dispatch, errors, and production panel entry.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Agent entry from production.

Known Gaps: Full ToonFlow multi-layer Agent + RAG memory, skill editing, deployment configuration, and custom JS skill execution are not fully replicated.

Next Verification: Treat full Agent parity as its own subsystem plan; add page tests for deployment mode persistence, skill list display, and memory management before claiming this page complete.

## 全套设置

Status: Partial

Desktop Evidence: `app/test/engine/engine_facade_test.dart`, `app/test/ui_i18n_static_test.dart`, and settings-related engine tests cover provider CRUD, model binding validation, config import/export, prompt seed/update/reset, theme and locale persistence, storage information, and static i18n checks.

Mobile Evidence: `app/test/widgets/settings_screen_test.dart` covers 390px settings flows: theme change, locale change, provider creation, provider editing with refreshed cards, per-modality provider test selection for image/video models, prompt editor entry, provider model management, model binding, database info, clear-data confirmation, and the about panel with app/engine version information.

Known Gaps: Config import/export and open data folder paths are not yet proven by widget tests.

Next Verification: Add 390px settings tests for config import/export error paths and open-data-folder failure handling.
