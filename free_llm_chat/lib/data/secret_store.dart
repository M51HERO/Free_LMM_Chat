import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secret storage so tests can use an in-memory fake.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// Production store: Windows Credential Locker / Android Keystore via flutter_secure_storage.
class FlutterSecretStore implements SecretStore {
  FlutterSecretStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _s.readAll();
}

/// In-memory store for tests.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map<String, String>.of(data);
}
