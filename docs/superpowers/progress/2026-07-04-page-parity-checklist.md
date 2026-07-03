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

Status: Verified

Desktop Evidence: `app/test/engine/scripts_test.dart` covers script CRUD, extraction, export, failure recovery, and batch script generation from selected events through the `script_gen` task runner. `app/test/widgets/script_screen_test.dart` covers desktop Markdown-style script editing with format tools and preview. `app/test/widgets/production_screen_test.dart` covers the production script node rendering Markdown preview and saving formatted script edits.

Mobile Evidence: `app/test/widgets/script_screen_test.dart` covers 390px batch-add parsing and persistence, existing script editing with live card refresh, event-to-script generation from the script page event picker, and Markdown-style format tools plus preview in the script editor.

Known Gaps: None at the current script-page scope. The implemented editor is Markdown-source editing with format buttons and rendered preview, matching ToonFlow's production `MdEditor`/`MdPreview` style rather than a full WYSIWYG document model.

Next Verification: If script editing changes, keep desktop/mobile Markdown editor smokes plus the event-to-script and batch-add flows together.

## 素材库

Status: Verified

Desktop Evidence: `app/test/engine/assets_test.dart`, `app/test/engine/art_style_test.dart`, `app/test/widgets/batch_generation_dialog_test.dart`, and `app/test/widgets/assets_tts_screen_test.dart` cover asset CRUD, child assets, prompt polishing, image generation parameters, art style library persistence, and desktop TTS creation.

Mobile Evidence: `app/test/widgets/assets_tts_screen_test.dart` covers 390px audio tab text-to-speech generation and card-list return. `app/test/widgets/assets_mobile_screen_test.dart` covers 390px role/tool/scene add/edit/delete plus child asset expansion. `app/test/widgets/batch_generation_dialog_test.dart` covers 390px batch prompt and batch image generation parameters. `app/test/widgets/project_page_test.dart` covers 390px art style library entry, new style creation, selection, and project persistence.

Known Gaps: None at the current v0.3 asset-library scope.

Next Verification: If asset-library UI changes, keep the 390px CRUD, child expansion, batch-generation parameter, art-style entry, and TTS smokes together.

## 制作画布

Status: Partial

Desktop Evidence: `app/test/widgets/production_screen_test.dart`, `app/test/widgets/script_plan_node_test.dart`, `app/test/widgets/storyboard_canvas_node_test.dart`, `app/test/widgets/canvas_chat_panel_test.dart`, and `app/test/widgets/df_widgets_test.dart` cover canvas entry, nodes, storyboard gallery, insertion, script editing, storyboard table editing, Agent panel basics, and 1000-node viewport culling for the reusable infinite canvas.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Tab-based production navigation, node-inspector bottom sheet switching, workbench entry, Agent entry, and offline UI chain access.

Known Gaps: No side-by-side ToonFlow screenshot checklist.

Next Verification: Add a page-level visual parity checklist entry with screenshots before claiming the production canvas page fully verified.

## 节点式图片编辑器

Status: Verified

Desktop Evidence: `app/test/widgets/image_flow_editor_test.dart` and `app/test/engine/image_flow_test.dart` cover graph persistence, reference image selection, generated node controls, flow image generation, line deletion, generated-image repaint/edit requests, and mask-brush local inpaint requests that pass the current result image, edit instruction, and generated mask image to the image provider.

Mobile Evidence: `app/test/widgets/image_flow_editor_test.dart` covers a dedicated 390px editor flow: the generated node is fit into the first mobile viewport, an upload node can replace its reference from the asset library, generated-node prompt/model/ratio/quality settings persist into `o_imageFlow`, and an already-generated node can perform mask-brush local inpaint with the mask passed to the image provider.

Known Gaps: None at the current node-based image-editor scope.

Next Verification: If image-editor UI changes, keep the desktop graph/edit/mask coverage and the 390px generated-node/reference/mask smokes together.

## 多轨工作台

Status: Partial

Desktop Evidence: `app/test/widgets/workbench_screen_test.dart`, `app/test/engine/video_track_test.dart`, `app/test/engine/compose_episode_test.dart`, `app/test/platform/apple_composer_static_test.dart`, and `app/test/platform/android_composer_static_test.dart` cover prompt editing, duration editing, per-shot transition/filter metadata editing, selected video candidates, shot audio binding, compose handoff with NLE metadata carried into `ComposeSegment`, native composer channel payload/parsing for those NLE fields, Apple AVFoundation/CoreImage rendering hooks for per-shot filters, fade-in/out transition rendering, cross-shot dissolve via layered video tracks plus opacity ramps, and Android Media3 Transformer export for video-only per-shot filters plus fade rendering. `flutter build apk --debug` also currently compiles the Android Media3 path.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px workbench entry through production tabs and the offline chain reaches compose.

Known Gaps: Full WebAV/NLE parity is not implemented: Android dissolve/whip-pan rendering, Android NLE rendering when per-shot external audio is mixed, Web transition/filter visual rendering, Web cross-shot dissolve, Apple combined dissolve plus CoreImage filter rendering, Apple/Android/Web whip-pan rendering, multi-layer timeline editing, and drag-based clip editing are not proven.

Next Verification: Keep current sequential-shot workbench as the v1 baseline, and open a separate NLE/WebAV parity plan before claiming full ToonFlow workbench parity.

## 配音

Status: Verified

Desktop Evidence: `app/test/widgets/corner_scape_screen_test.dart` covers empty state, manual binding, auto-match enqueue, bound/unbound filters, search, select-all-unbound, and audition error handling.

Mobile Evidence: `app/test/widgets/corner_scape_screen_test.dart` covers 390px manual role-audio binding, AI auto-match task enqueue, and missing-file audition feedback.

Known Gaps: None at the current dubbing-page scope.

Next Verification: If dubbing-page layout changes, keep the 390px manual binding, AI auto-match, and audition error smokes together.

## 任务中心

Status: Verified

Desktop Evidence: `app/test/widgets/tasks_screen_test.dart` covers task listing, type filter, status filter, historical task display, and read-only task detail with failure reason/related objects.

Mobile Evidence: `app/test/widgets/tasks_screen_test.dart` covers 390px task-center layout, project switching, detail dialog, failed-task retry, and pending-task cancellation with `errCanceled` persisted.

Known Gaps: None at the current task-center page scope. Long-running real queue cancellation is still covered at engine level by `app/test/engine/queue_test.dart`, not by a widget test with a live provider call.

Next Verification: If task-center UI changes, keep the 390px smoke and add a real processing-task cancel widget smoke around a fake long-running task runner.

## Agent 体系页

Status: Partial

Desktop Evidence: `app/test/widgets/agent_chat_screen_test.dart`, `app/test/widgets/canvas_chat_panel_test.dart`, and `app/test/engine/agent_test.dart` cover basic persisted messages, tool dispatch, errors, production panel entry, deployment-mode persistence, per-stage `o_agentDeploy` model/temperature/max-output configuration, Agent HTTP model resolution from deployment overrides, local `o_skillList` seeding, skill description editing, skill enable/disable filtering before LLM tool dispatch, short-term chat memory listing/clearing, local long-term memory CRUD in the Agent memory tab, local token-embedding generation/backfill in `memories.embedding`, long-term memory search, and injection of matched long-term memories into the Agent system prompt.

Mobile Evidence: `app/test/widgets/production_screen_test.dart` covers 390px Agent entry from production.

Known Gaps: Full ToonFlow multi-layer Agent orchestration, model/vector RAG recall/reranking, and custom JS skill execution are not fully replicated. Current long-term memory is a local, editable, token-embedding note store over the existing `memories` table.

Next Verification: Treat full Agent parity as its own subsystem plan; add engine/UI coverage for any accepted RAG/custom-skill scope before claiming this page complete.

## 全套设置

Status: Verified

Desktop Evidence: `app/test/engine/engine_facade_test.dart`, `app/test/ui_i18n_static_test.dart`, and settings-related engine tests cover provider CRUD, model binding validation, config import/export, prompt seed/update/reset, theme and locale persistence, storage information, and static i18n checks.

Mobile Evidence: `app/test/widgets/settings_screen_test.dart` covers 390px settings flows: theme change, locale change, provider creation, provider editing with refreshed cards, per-modality provider test selection for image/video models, prompt editor entry, provider model management, model binding, database info, clear-data confirmation, config import/export panel error visibility, open-data-folder failure handling with the resolved data path, and the about panel with app/engine version information.

Known Gaps: None at the current settings-page scope.

Next Verification: If settings storage/platform actions change, keep the file picker fake and data-folder opener fake tests together with the engine config import/export tests.
