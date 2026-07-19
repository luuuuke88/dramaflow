# Appearance Theme Color And Font Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce ToonFlow `uiConfig.vue` fully: persistent custom theme color and the seven global font-size choices, without breaking DramaFlow desktop or mobile layouts.

**Architecture:** Keep preference validation in `EngineConfig` and `Engine`; keep color derivation in the existing theme layer; expose values through focused Riverpod notifiers. `DramaFlowApp` rebuilds `ThemeData` from the saved accent and installs one `MediaQuery` text scaler. Business screens continue consuming `context.df` and `Theme.of(context)`, never appearance state.

**Tech Stack:** Flutter Material 3, Riverpod, SQLite via existing `EngineConfig`, Flutter widget/engine tests, `gen_l10n`.

## Global Constraints

- Match ToonFlow's exact choices: primary presets `#000000 #0052D9 #2BA471 #ED7B2F #E34D59 #7B61FF #111111`; font sizes `12, 13, 14, 16, 18, 20, 22`; defaults `#0052D9` and `16`.
- Store only in existing local SQLite `o_setting`; never touch Keychain, `o_secret`, credential export, or any provider.
- Do not add a color-picker package. A validated HEX field is the cross-platform equivalent to the original custom picker.
- Keep images/video/TTS/text task paths and real-provider tests untouched.
- Test actual desktop and 390dp paths using only in-memory SQLite, fake gateways, and widget fixtures.

---

### Task 1: Typed Appearance Preferences And Theme Derivation

**Files:**
- Modify: `app/lib/src/engine/config.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/theme/tokens.dart`
- Modify: `app/lib/src/theme/theme.dart`
- Modify: `app/test/engine/config_test.dart`
- Modify: `app/test/engine/engine_facade_test.dart`
- Create: `app/test/theme/theme_test.dart`

**Interfaces:**
- `EngineConfig.themePrimaryColor` returns an uppercase `#RRGGBB`, falling back to `#0052D9`.
- `EngineConfig.themeFontSize` returns one allowed size, falling back to `16`.
- `Engine.getThemePrimaryColor()/setThemePrimaryColor(String)` and `Engine.getThemeFontSize()/setThemeFontSize(int)` are the only persistence APIs.
- `buildTheme(Brightness brightness, {Color primaryColor})` derives all primary-dependent Material and `DFColors` values from one color.

- [ ] **Step 1: Write failing tests**

Add engine tests that save `e34d59` and `22`, then assert a new config instance reads `#E34D59` and `22`. Assert `#FFF`, a non-hex value, and `15` each raise `EngineException`; assert corrupt stored values safely read as defaults.

Create `theme_test.dart` with light/dark `buildTheme(... primaryColor: Color(0xFFE34D59))` assertions: `ColorScheme.primary` and primary-derived `DFColors` differ from defaults, while danger remains the established semantic color.

- [ ] **Step 2: Verify RED**

```sh
cd app
flutter test test/engine/config_test.dart test/engine/engine_facade_test.dart test/theme/theme_test.dart
```

Expected: missing typed getters, Engine APIs, optional theme input, and test source make the new assertions fail or not compile.

- [ ] **Step 3: Implement the boundary**

Add `theme.primaryColor` and `theme.fontSize` to the allowed config defaults. Centralize the exact preset list, full six-hex normalization, and accepted font sizes in `EngineConfig`; do not let a UI write arbitrary config keys. Add validating Engine methods.

Make `DFColors.light/dark` accept the resolved primary and derive `primaryHover`, `primarySubtle`, `focusRing`, and `running` via HSL. Dark mode must choose a readable derivative, not reuse a low-luminance color. Preserve neutral backgrounds/text and semantic success/warning/danger tokens. Thread the same color through `ColorScheme` and `DFColors`.

- [ ] **Step 4: Verify green**

```sh
cd app
flutter analyze
flutter test --concurrency=1 test/engine/config_test.dart test/engine/engine_facade_test.dart test/theme/theme_test.dart
```

- [ ] **Step 5: Commit**

```sh
git add app/lib/src/engine/config.dart app/lib/src/engine/engine.dart \
  app/lib/src/theme/tokens.dart app/lib/src/theme/theme.dart \
  app/test/engine/config_test.dart app/test/engine/engine_facade_test.dart \
  app/test/theme/theme_test.dart
git commit -m "feat(theme): add persistent color and font preferences"
```

### Task 2: App-Level Providers And Responsive Settings Controls

**Files:**
- Modify: `app/lib/src/state/providers.dart`
- Modify: `app/lib/src/app.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_ja.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Modify: `app/test/widgets/settings_screen_test.dart`
- Create: `app/test/widgets/app_appearance_test.dart`

**Interfaces:**
- `themePrimaryColorProvider` exposes `Color`; `themeFontSizeProvider` exposes `int`. Both follow the existing notifier load, optimistic write, rollback pattern.
- `DramaFlowApp` watches both and wraps only the app child in `MediaQuery.copyWith(textScaler: TextScaler.linear(fontSize / 16))`.
- Stable control keys begin `settings-theme-`.

- [ ] **Step 1: Write failing widgets**

At `390 x 760`, select preset `#E34D59`, then apply custom `#2BA471`, select `22`, rebuild with the same Engine, and assert saved values plus selected controls. Apply `#FFF` and assert a localized error with no config mutation.

Pump `DramaFlowApp` after seeding `#E34D59` and `22`. From a descendant context, assert `Theme.of(context).colorScheme.primary == Color(0xFFE34D59)` and `MediaQuery.textScalerOf(context).textScaleFactor` is `22 / 16`. Switch dark mode and assert the primary remains a non-default readable derivative. No test may invoke a gateway.

- [ ] **Step 2: Verify RED**

```sh
cd app
flutter test test/widgets/settings_screen_test.dart test/widgets/app_appearance_test.dart
```

Expected: missing providers, settings controls, localizations, and app text-scaler wiring fail the new tests.

- [ ] **Step 3: Implement responsive UI**

Add the two notifiers and let `DramaFlowApp` rebuild its themes from the provider color while preserving routing, locale, and mode. Add a descendant `MediaQuery` linear scale exactly once; do not multiply `TextTheme` values as well.

In the appearance card, use a wrapping set of semantic/tooltip-equipped color swatches, a HEX field with current-color preview and an apply `IconButton`, and a wrapping set of seven discrete size choice controls. Persist only complete valid HEX input; leave the current theme active on invalid input. All labels/errors require zh/en/ja keys. At 390dp controls may wrap but may not overflow or require hover.

- [ ] **Step 4: Verify focused green**

```sh
cd app
flutter gen-l10n
flutter analyze
flutter test --concurrency=1 test/widgets/settings_screen_test.dart \
  test/widgets/app_appearance_test.dart test/l10n_test.dart
```

- [ ] **Step 5: Commit**

```sh
git add app/lib/src/state/providers.dart app/lib/src/app.dart \
  app/lib/src/screens/settings_screen.dart app/lib/l10n/app_*.arb \
  app/lib/l10n/app_localizations*.dart app/test/widgets/settings_screen_test.dart \
  app/test/widgets/app_appearance_test.dart
git commit -m "feat(settings): add theme color and font size controls"
```

### Task 3: Representative Layout Regression And Parity Closure

**Files:**
- Modify: `app/test/widgets/project_page_test.dart`
- Modify: `app/test/widgets/workbench_screen_test.dart`
- Modify: `docs/parity/ui-appearance-matrix.md`
- Modify: `docs/parity/settings-module-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: this plan

**Interfaces:**
- Consumes the persisted appearance values from Tasks 1–2.
- Produces evidence that the extreme valid setting is usable beyond the settings page.

- [ ] **Step 1: Write failing representative tests**

Seed green `#2BA471` and `22`, then cover one 390dp project-list/new-project path and one desktop workbench interaction. After each path, assert `tester.takeException()` is null and a selected/primary control consumes the configured color.

- [ ] **Step 2: Verify RED**

Run each named test before its fixture/wiring exists. Expected: test absence or failure because the app does not yet honor persisted appearance preferences.

- [ ] **Step 3: Correct only exposed layouts**

If the valid maximum scale exposes an overflow, make the affected row wrap, scroll, or use existing flexible constraints. Do not lower the maximum, disable scaling, or globally shrink text. Preserve usable touch targets.

- [ ] **Step 4: Run authoritative gates**

```sh
cd app
flutter analyze
flutter test --concurrency=1
flutter build macos --debug
cd ..
node tool/parity/check_no_orphans.js
git diff --check
```

Expected: all offline tests pass, no analyzer diagnostics, debug macOS build succeeds, inventory remains covered, and no whitespace errors occur.

- [ ] **Step 5: Update evidence and commit**

Mark `W6D-UI-001` and `W6E-LIB-THEME-001` verified only after Task 3 passes. Record custom HEX normalization, seven-choice text scaling, bright/dark contrast boundary, 390dp/desktop coverage, and that no video/provider calls ran.

```sh
git add app/test/widgets/project_page_test.dart app/test/widgets/workbench_screen_test.dart \
  docs/parity/ui-appearance-matrix.md docs/parity/settings-module-matrix.md \
  docs/parity/master-checklist.md docs/parity/feature-parity-execution-report.md \
  docs/superpowers/plans/2026-07-20-appearance-theme-color-and-font-size.md
git commit -m "docs(parity): verify appearance settings"
```

## Plan Self-Review

- **Spec coverage:** exact preset/custom color capability, exact font sizes, persistence, immediate theme application, desktop/390dp usability, and evidence gates are all mapped to tasks.
- **Scope:** View Transition animation is browser-specific and not a cross-platform capability. No provider, credential, or video behavior is in scope.
- **Consistency:** Task 1 defines the config/API/theme interfaces consumed by Tasks 2 and 3; no duplicate UI state or secondary color system is introduced.
