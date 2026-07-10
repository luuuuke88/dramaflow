# C1 Safety And Manual Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter application safe to upgrade and give every project one stable, bundled ToonFlow visual/director manual selection before adding more generation behavior.

**Architecture:** SQLite upgrades become additive and transactional instead of destructive. Provider metadata stays in SQLite while the actual secret is held by a credential-store abstraction backed by Keychain/Keystore in the application. Project records store manual directory IDs, and all visual context is resolved from that one source of truth rather than from a competing art-style library.

**Tech Stack:** Flutter/Dart 3.5, sqlite3, flutter_secure_storage 10.3.1, Flutter widget tests, existing ToonFlow manual-pack assets.

## Global Constraints

- Do not delete an existing database, WAL, SHM, media directory, project row, or task row while upgrading.
- macOS is the first acceptance platform; iOS/iPadOS and Android must continue to compile.
- Remote API keys must not appear in `o_vendorConfig.inputValues`, normal config exports, test failure messages, or normal application logs.
- SQLite keeps legacy tables such as `o_memoryVector` for migration compatibility, but default UI and stage bindings expose only text, image, video, and TTS.
- `o_project.artStyle` stores the visual manual `pack` ID until a dedicated schema rename is needed; `o_project.directorManual` stores the director manual `pack` ID.
- Bundled packs never overwrite a user-edited file and `o_artStyle` is not derived from those packs.
- Keep the existing dirty default-skill asset work, but revise it to meet these constraints instead of reverting it.

---

## File Structure

- `app/lib/src/engine/db.dart`: additive schema opening, pre-migration backup, ordered migration dispatcher.
- `app/lib/src/engine/credentials.dart`: small secret-storage interface, production secure implementation, and test memory implementation.
- `app/lib/src/engine/providers/resolve.dart`: resolve model metadata from SQLite and credentials from the credential store.
- `app/lib/src/engine/providers/gateway.dart`: await credential-aware model resolution before any adapter request.
- `app/lib/src/engine/engine.dart`: provider CRUD/import/export, legacy-secret migration, default provider setup, and removal of manual-to-art-style derivation.
- `app/lib/src/api/models.dart`: provider data exposed to the UI without a raw API key.
- `app/lib/src/bootstrap/bootstrap_io.dart`: idempotent per-pack default manual seeding.
- `app/lib/src/engine/manuals.dart`, `app/lib/src/engine/assets.dart`: stable pack-ID lookup and visual prompt context.
- `app/lib/src/screens/project/project_dialog.dart`, `app/lib/src/screens/manuals/manual_gallery.dart`: one visual selector, using pack IDs.
- `app/lib/src/screens/settings_screen.dart`: remove vector/vision binding controls and embedding model selection.
- Tests under `app/test/engine/` and `app/test/widgets/`: migration preservation, secret isolation, manual ID behavior, seed behavior, and settings/project UI behavior.

## Task 1: Replace Destructive Database Opening With Ordered Migrations

**Files:**
- Modify: `app/lib/src/engine/db.dart`
- Modify: `app/test/engine/db_v3_test.dart`

**Interfaces:**
- Produces `const schemaVersion = 9`.
- Produces `Database openEngineDb(String path, {DateTime Function()? clock})`.
- Produces `void migrateSchema(Database db, int fromVersion, int toVersion)`.
- Produces one backup file named `<database>.backup-v<oldVersion>.sqlite` before an on-disk migration.

- [x] **Step 1: Write preservation tests before changing the schema opener.**

  Replace the old delete-and-recreate expectation with tests that create a v8 file containing a project and a media reference, open it, and assert both values survive at v9. Add a v2 fixture with `legacy_data` and assert its row is still readable after schema completion. Add a failed-migration test using a future `PRAGMA user_version = 99` and assert the file remains untouched.

  ```dart
  test('v8 upgrade preserves project rows, media references, and creates backup', () {
    final old = sqlite3.open(dbPath);
    initSchema(old);
    old.execute('PRAGMA user_version = 8');
    old.execute("INSERT INTO o_project (name, artStyle) VALUES ('保留项目', 'ink_pack')");
    old.execute("INSERT INTO o_image (filePath) VALUES ('p1/role.png')");
    old.close();

    final db = openEngineDb(dbPath);
    expect(db.select('SELECT name,artStyle FROM o_project').single.values,
        ['保留项目', 'ink_pack']);
    expect(db.select('SELECT filePath FROM o_image').single['filePath'], 'p1/role.png');
    expect(File('$dbPath.backup-v8.sqlite').existsSync(), isTrue);
  });
  ```

- [x] **Step 2: Run the focused database test and verify the legacy destructive test fails.**

  Run: `cd app && flutter test test/engine/db_v3_test.dart`

  Expected: FAIL because the current code deletes the v8 project row and no backup exists.

- [x] **Step 3: Implement the additive opening and migration dispatcher.**

  In `db.dart`, remove `_deleteDatabaseFiles`. Configure the opened database before inspecting it. Treat version `0` as a new database: run `initSchema` and set v9. For every version from 1 through 8, checkpoint WAL, copy the database to the deterministic backup path when it does not already exist, run `initSchema` (all statements are `CREATE ... IF NOT EXISTS`), execute explicit ordered migrations, then write `PRAGMA user_version = 9` inside one transaction. Reject a version higher than 9 without changing the file.

  ```dart
  const schemaVersion = 9;

  Database openEngineDb(String path, {DateTime Function()? clock}) {
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    _configure(db);
    final version = _userVersion(db);
    if (version > schemaVersion) {
      db.close();
      throw StateError('Database version $version is newer than $schemaVersion');
    }
    if (version == 0) {
      initSchema(db, setVersion: true);
      return db;
    }
    if (version < schemaVersion) {
      _backupBeforeMigration(db, path, version);
      db.execute('BEGIN IMMEDIATE');
      try {
        initSchema(db, setVersion: false);
        migrateSchema(db, version, schemaVersion);
        db.execute('PRAGMA user_version = $schemaVersion');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    } else {
      initSchema(db, setVersion: false);
    }
    return db;
  }
  ```

  `migrateSchema` must be an ordered `for` loop with a no-op compatibility step for `1..8`; schema completion is additive and no migration drops a table. `_backupBeforeMigration` must skip `:memory:`, run `PRAGMA wal_checkpoint(TRUNCATE)`, and `File(path).copySync('$path.backup-v$version.sqlite')` only if that backup does not yet exist.

- [x] **Step 4: Run all database tests and static analysis.**

  Run: `cd app && flutter test test/engine/db_v3_test.dart && flutter analyze`

  Expected: both commands pass; the tests demonstrate preserved project/media data, backup creation, and rejection of a newer schema.

- [x] **Step 5: Commit the migration safety change.**

  ```bash
  git add app/lib/src/engine/db.dart app/test/engine/db_v3_test.dart
  git commit -m "fix(db): migrate existing databases without deletion"
  ```

## Task 2: Move Provider Secrets Out Of SQLite And Normal Exports

**Files:**
- Create: `app/lib/src/engine/credentials.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/src/api/models.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/engine/providers/resolve.dart`
- Modify: `app/lib/src/engine/providers/gateway.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/test/engine/engine_facade_test.dart`
- Modify: `app/test/engine/providers_test.dart`

**Interfaces:**
- Produces `abstract interface class CredentialStore` with `read`, `write`, and `delete` methods.
- Produces `class InMemoryCredentialStore implements CredentialStore` for tests.
- Produces `class SecureCredentialStore implements CredentialStore` backed by `FlutterSecureStorage`.
- Changes `ProviderInfo.apiKey` to `ProviderInfo.hasCredential`.
- Changes `resolveStage`, `resolveAssistantStage`, and `resolveModelById` to return `Future<ResolvedModel>` and accept `CredentialStore credentials`.

- [x] **Step 1: Write secret-isolation tests.**

  Add a provider test that creates `sk-secret`, then asserts the provider table JSON and `exportConfig()` text do not contain it, `ProviderInfo.hasCredential` is true, and resolving the model still yields the secret only in memory. Add an import test that accepts an old export with `apiKey`, stores it in `InMemoryCredentialStore`, and writes a sanitized provider JSON. Add a delete test that removes the credential after a provider is removed.

  ```dart
  final credentials = InMemoryCredentialStore();
  final engine = Engine(..., credentials: credentials);
  final provider = await engine.createProvider(..., apiKey: 'sk-secret');
  final row = db.select('SELECT inputValues FROM o_vendorConfig WHERE id=?', [provider.id]).single;
  expect(row['inputValues'], isNot(contains('sk-secret')));
  expect(jsonEncode(await engine.exportConfig()), isNot(contains('sk-secret')));
  expect((await engine.listProviders()).single.hasCredential, isTrue);
  ```

- [x] **Step 2: Run secret-isolation tests and verify current behavior leaks the key.**

  Run: `cd app && flutter test test/engine/engine_facade_test.dart test/engine/providers_test.dart`

  Expected: FAIL because `inputValues` and exported provider records currently include `apiKey`.

- [x] **Step 3: Add the secure credential abstraction and dependency.**

  Add `flutter_secure_storage: ^10.3.1` to `pubspec.yaml`. Implement the interface with a deterministic provider reference:

  ```dart
  abstract interface class CredentialStore {
    Future<String?> read(String key);
    Future<void> write(String key, String value);
    Future<void> delete(String key);
  }

  String providerCredentialRef(String providerId) =>
      'dramaflow.provider.$providerId.api-key';
  ```

  `SecureCredentialStore` uses `const FlutterSecureStorage()` and forwards `read/write/delete`. `InMemoryCredentialStore` stores values in a private `Map<String, String>` and is only used in tests or direct non-boot engine construction.

- [x] **Step 4: Wire provider CRUD, legacy migration, model resolution, and UI.**

  Give `Engine` a required-or-defaulted `CredentialStore credentials` field. `Engine.boot` constructs `SecureCredentialStore`, runs `migrateLegacyProviderCredentials(db, credentials)` after `_seedDefaults`, then passes the same store to `Engine` and `HttpProviderGateway`. Provider metadata stores `credentialRef`, never `apiKey`; `createProvider`/`updateProvider` write a non-empty key to the store before updating metadata. `deleteProvider` deletes the referenced secret after confirming no bindings use the provider.

  Preserve backward compatibility only at import/boot: when legacy input JSON contains a nonempty `apiKey`, write it to `providerCredentialRef(id)`, remove `apiKey`, set `credentialRef`, and update the database. Normal `exportConfig()` emits `hasCredential` but omits `apiKey`; `importConfig()` ignores `hasCredential` and only imports a supplied legacy `apiKey` into secure storage.

  Change the resolver signatures and callers:

  ```dart
  Future<ResolvedModel> resolveStage(
    Database db,
    CredentialStore credentials,
    String stage,
  );
  ```

  It reads `credentialRef`, fetches the value with `await credentials.read(ref)`, and treats a missing non-loopback secret as `EngineException(errProviderMissing, {'reason': '未配置 API Key'})`. Update every `HttpProviderGateway` adapter call to await resolution. Keep `ResolvedModel.apiKey` as a short-lived in-memory request field only. In the settings edit dialog, start API-key input empty and show a "configured" hint from `hasCredential`; never prefill the secret.

- [x] **Step 5: Fetch dependencies, run focused tests, and verify no raw key remains in configuration paths.**

  Run: `cd app && flutter pub get && flutter test test/engine/engine_facade_test.dart test/engine/providers_test.dart && flutter analyze`

  Expected: all commands pass. Then run `rg -n "'apiKey': provider\.apiKey|input\['apiKey'\]|apiKey: input\['apiKey'\]" app/lib/src` and retain only the explicit legacy-migration/import compatibility reads.

- [x] **Step 6: Commit the credential isolation change.**

  ```bash
  git add app/pubspec.yaml app/pubspec.lock app/lib/src/api/models.dart app/lib/src/engine/credentials.dart app/lib/src/engine/engine.dart app/lib/src/engine/providers/resolve.dart app/lib/src/engine/providers/gateway.dart app/lib/src/screens/settings_screen.dart app/test/engine/engine_facade_test.dart app/test/engine/providers_test.dart
  git commit -m "fix(providers): store credentials outside sqlite"
  ```

## Task 3: Remove Dead Vector And Vision Configuration From First-Release UI

**Files:**
- Modify: `app/lib/src/engine/providers/resolve.dart`
- Modify: `app/lib/src/engine/providers/gateway.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/test/engine/engine_facade_test.dart`
- Modify: `app/test/engine/providers_test.dart`
- Modify: or create `app/test/widgets/settings_screen_test.dart`

**Interfaces:**
- `stageKindByStage` contains only production stages and no `agent_embedding` or `agent_vision` key.
- Provider model editing allows only `text`, `image`, `video`, and `tts`.
- Legacy `o_memoryVector` remains schema-only; no runtime code calls an embedding endpoint.

- [x] **Step 1: Write failing tests for the first-release stage registry and settings screen.**

  Assert `requiredKindForStage('agent_embedding')` throws `EngineException`, test provider model normalization rejects `embedding`, and pump the settings screen asserting its visible stage titles do not include Agent vector recall or Agent vision understanding.

  ```dart
  expect(
    () => requiredKindForStage('agent_embedding'),
    throwsA(isA<EngineException>()),
  );
  ```

- [x] **Step 2: Run the focused tests and verify they fail against the exposed dead features.**

  Run: `cd app && flutter test test/engine/engine_facade_test.dart test/engine/providers_test.dart test/widgets/settings_screen_test.dart`

  Expected: FAIL because both stages and the embedding model kind are currently registered.

- [x] **Step 3: Remove the inactive runtime paths and default UI entries.**

  Delete `agent_embedding` and `agent_vision` from `stageKindByStage`, remove `generateEmbedding`, `openaiGenerateEmbedding`, and `testEmbeddingModel` usage, remove embedding from `_normalizeModel` accepted kinds and settings model type choices, and remove their stage metadata/title/description mapping entries. Do not drop `o_memoryVector` or its index from `db.dart`; no migration is needed for schema-only compatibility.

- [x] **Step 4: Run targeted tests and full static analysis.**

  Run: `cd app && flutter test test/engine/engine_facade_test.dart test/engine/providers_test.dart test/widgets/settings_screen_test.dart && flutter analyze`

  Expected: PASS, and `rg -n "agent_embedding|agent_vision|generateEmbedding" app/lib/src` returns no runtime use.

- [x] **Step 5: Commit the first-release settings reduction.**

  ```bash
  git add app/lib/src/engine/providers/resolve.dart app/lib/src/engine/providers/gateway.dart app/lib/src/engine/engine.dart app/lib/src/screens/settings_screen.dart app/test/engine/engine_facade_test.dart app/test/engine/providers_test.dart app/test/widgets/settings_screen_test.dart
  git commit -m "refactor(settings): remove inactive vector and vision bindings"
  ```

## Task 4: Make Bundled Manual Packs The Only Project Style Source

**Files:**
- Modify: `app/lib/src/bootstrap/bootstrap_io.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/engine/manuals.dart`
- Modify: `app/lib/src/engine/assets.dart`
- Modify: `app/lib/src/screens/manuals/manual_gallery.dart`
- Modify: `app/lib/src/screens/project/project_dialog.dart`
- Modify: `app/test/engine/engine_facade_test.dart`
- Modify: `app/test/engine/manuals_test.dart`
- Modify: `app/test/widgets/project_page_test.dart`

**Interfaces:**
- `ManualPack.pack` is the persisted stable ID; `ManualPack.name` is display-only.
- `ManualGallery` accepts `selectedPackId` and compares it with `pack.pack`.
- `seedBundledDefaultSkills(String dataDir, {AssetBundle? bundle})` adds missing individual bundled files without overwriting an existing local target.
- `Engine.boot` does not call `_seedArtStylesFromVisualManuals` and does not create `o_artStyle` rows from manual packs.

- [x] **Step 1: Write failing pack-ID and seeding tests.**

  Replace the existing "visual manual seed derives art style" test with one that starts from a pack directory and asserts `engine.visualManuals().single.pack == 'toonflow_default'` while `engine.artStyles()` stays empty. Add a seed test with a pre-existing custom art pack plus no default packs; after seeding, assert the default pack exists and the custom file content did not change. Add a project widget test that chooses a visual manual and director manual whose display names differ from their directory names, saves, and asserts the database stores the directory IDs.

  ```dart
  expect(engine.visualManuals().single.pack, 'toonflow_default');
  expect(engine.artStyles(), isEmpty);
  expect(engine.projects().single.artStyle, 'toonflow_default');
  expect(engine.projects().single.directorManual, 'fast_cut');
  ```

- [x] **Step 2: Run these tests and verify the old name/prompt-based behavior fails.**

  Run: `cd app && flutter test test/engine/engine_facade_test.dart test/engine/manuals_test.dart test/widgets/project_page_test.dart`

  Expected: FAIL because the current bootstrap skips every default kind when any custom pack exists and the project dialog stores names or raw art-style prompts.

- [x] **Step 3: Make bundled seeding per-file and remove derived art styles.**

  Keep the existing zip asset. In `seedBundledDefaultSkills`, iterate only `skills/art_skills/*` and `skills/story_skills/*` archive entries; create each target only when it does not exist. Do not use `_hasAnyPack` to skip a whole kind. Remove `_seedArtStylesFromVisualManuals`, `_readFirstExisting`, `_readManualDisplayName`, and `_copyFirstManualCover` from `Engine`, along with its boot call. Preserve user-created `o_artStyle` rows and the standalone library source as legacy data, but do not populate it from the packs.

- [x] **Step 4: Persist and consume stable pack IDs.**

  Rename `ManualGallery.selectedName` to `selectedPackId`; selection/deselection compares `pack.pack`. In `ProjectDialog`, remove imports, state, and widgets for `art_style.dart`/`art_style_library.dart`; `_artStyle` may remain as the schema-compatible local variable but is only assigned `p?.pack`. Assign `_directorManual = p?.pack`, and clear values by matching `pack.pack` after deletion.

  In `assets.dart`, find visual packs with `p.pack == artStyle`. Replace the raw "画风风格: <pack-id>" image prompt line with a display/prefix context derived from the selected pack, for example:

  ```dart
  final visualContext = _visualPackContext(projectId);
  return '请根据以下参数生成${cfg.promptTitle}：\n\n'
      '$visualContext\n\n'
      '**${cfg.label}设定：**\n';
  ```

  `_visualPackContext` must return the pack's `prefix` when present and otherwise its display name; it must never render the opaque pack ID as a user-facing style prompt.

- [x] **Step 5: Run focused tests, full tests, and static analysis.**

  Run: `cd app && flutter test test/engine/engine_facade_test.dart test/engine/manuals_test.dart test/widgets/project_page_test.dart && flutter test && flutter analyze`

  Expected: all pass. `rg -n "_seedArtStylesFromVisualManuals|selectedName|_artStyleSection" app/lib/src` returns no matches.

- [x] **Step 6: Commit the single-source manual foundation.**

  ```bash
  git add app/assets app/pubspec.yaml app/lib/src/bootstrap/bootstrap_io.dart app/lib/src/engine/engine.dart app/lib/src/engine/manuals.dart app/lib/src/engine/assets.dart app/lib/src/screens/manuals/manual_gallery.dart app/lib/src/screens/project/project_dialog.dart app/test/engine/engine_facade_test.dart app/test/engine/manuals_test.dart app/test/widgets/project_page_test.dart
  git commit -m "feat(project): use bundled manual packs as style source"
  ```

## Task 5: Review C1 As A Releaseable Foundation

**Files:**
- Modify: `docs/superpowers/specs/2026-07-10-toonflow-core-parity-convergence-design.md` only if an implementation decision differs from the approved contract.
- Modify: `docs/superpowers/plans/2026-07-10-c1-safety-and-manual-foundation.md` by checking completed boxes during execution.

**Interfaces:**
- C2 can assume database upgrades preserve current rows, `Engine` has a credential store, and projects reference `ManualPack.pack`.

- [x] **Step 1: Run the C1 verification suite.**

  Run: `cd app && flutter test && flutter analyze`

  Expected: all test files pass and analysis has no diagnostics.

- [x] **Step 2: Inspect the three release invariants directly.**

  Run:

  ```bash
  rg -n "_deleteDatabaseFiles|DELETE FROM o_project|DELETE FROM o_vendorConfig" app/lib/src/engine
  rg -n "apiKey.*export|apiKey.*inputValues|provider\.apiKey" app/lib/src
  rg -n "agent_embedding|agent_vision|_seedArtStylesFromVisualManuals|selectedName" app/lib/src
  ```

  Expected: no destructive upgrade code, no normal secret export/storage code, and no first-release vector/vision or duplicate manual-selector implementation.

- [x] **Step 3: Review the actual C1 diff before progressing to C2.**

  Run: `git diff 85f5a77..HEAD -- app/lib/src app/test app/pubspec.yaml`

  Expected: the diff only touches the planned safety, provider, pack, and UI boundaries. Do not begin Seedance or director-plan work until this review passes.

- [x] **Step 4: Commit only a corrected plan/spec when necessary.**

  ```bash
  git add docs/superpowers/specs/2026-07-10-toonflow-core-parity-convergence-design.md docs/superpowers/plans/2026-07-10-c1-safety-and-manual-foundation.md
  git commit -m "docs(plan): record C1 verification evidence"
  ```

## C2-C5 Follow-On Plan Boundaries

Create separate detailed plans after C1 verification, in this order:

1. `2026-07-10-c2-prompt-packs-and-provenance.md`: bundled model prompt templates, deterministic stage resolver, persisted prompt sources.
2. `2026-07-10-c3-seedance-capability-video.md`: structured request, capability validation, Volcengine translation, controls, and task recovery.
3. `2026-07-10-c4-production-dependencies.md`: director plan/table generation, stale tracking, structured shots, script assistant command.
4. `2026-07-10-c5-composition-and-real-acceptance.md`: selected candidates, audio/transitions, native composition, real provider Mac run, restart recovery, and the user's acceptance gate.

Every follow-on plan must use the stable manual pack IDs, sanitized provider metadata, and non-destructive schema migration established here.
