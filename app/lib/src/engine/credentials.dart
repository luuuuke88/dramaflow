import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores provider secrets outside the SQLite configuration database.
abstract interface class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

String providerCredentialRef(String providerId) =>
    'dramaflow.provider.$providerId.api-key';

class SecureCredentialStore implements CredentialStore {
  final FlutterSecureStorage _storage;

  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(
                usesDataProtectionKeychain: kReleaseMode,
              ),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
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
