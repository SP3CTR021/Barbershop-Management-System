import 'package:firebase_core/firebase_core.dart' as fc;

/// Selects which concrete backend repository implementation is wired into [sl].
enum BackendType {
  supabase,
  firebase,
}

/// Connection configuration for Supabase initialization.
/// Pass via constructor or `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
final class SupabaseConfig {
  const SupabaseConfig({
    required this.url,
    required this.anonKey,
  });

  const SupabaseConfig.fromEnvironment()
      : url = const String.fromEnvironment('SUPABASE_URL'),
        anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  final String url;
  final String anonKey;

  bool get isConfigured => url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}

/// Connection and emulator configuration for Firebase / Cloud Firestore init.
final class FirebaseConfig {
  const FirebaseConfig({
    this.options,
    this.enablePersistence = true,
    this.emulatorHost,
    this.firestoreEmulatorPort = 8080,
    this.authEmulatorPort = 9099,
  });

  final fc.FirebaseOptions? options;
  final bool enablePersistence;
  final String? emulatorHost;
  final int firestoreEmulatorPort;
  final int authEmulatorPort;
}
