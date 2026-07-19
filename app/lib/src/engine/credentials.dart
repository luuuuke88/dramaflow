import 'package:sqlite3/sqlite3.dart';

/// Stores provider secrets (API keys) keyed by a credential ref.
abstract interface class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

String providerCredentialRef(String providerId) =>
    'dramaflow.provider.$providerId.api-key';

/// Stores secrets in the local SQLite `o_secret` table — the same database file
/// as the rest of the config, so behaviour is identical across macOS/iOS/
/// Android/Windows/Linux with no OS keychain and no native-plugin dependency.
///
/// Secrets are deliberately kept off two paths: [Engine.exportConfig] uses a
/// hand-written allowlist that never touches `o_secret`, and `clearAllData`
/// preserves `o_secret` alongside `o_vendorConfig` so a data wipe keeps a
/// provider's key next to the provider it belongs to.
class DbCredentialStore implements CredentialStore {
  final Database _db;

  DbCredentialStore(this._db);

  @override
  Future<String?> read(String key) async {
    final rows = _db.select('SELECT value FROM o_secret WHERE ref=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> write(String key, String value) async {
    _db.execute(
      'INSERT INTO o_secret (ref,value) VALUES (?,?) '
      'ON CONFLICT(ref) DO UPDATE SET value=excluded.value',
      [key, value],
    );
  }

  @override
  Future<void> delete(String key) async {
    _db.execute('DELETE FROM o_secret WHERE ref=?', [key]);
  }
}

/// Test-only credential store. Values live only for the lifetime of the
/// in-memory engine and never touch SQLite or an operating-system keychain.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, String> _values = <String, String>{};

  void seed(String key, String value) {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) => Future.value(_values[key]);

  @override
  Future<void> write(String key, String value) {
    _values[key] = value;
    return Future.value();
  }

  @override
  Future<void> delete(String key) {
    _values.remove(key);
    return Future.value();
  }
}
