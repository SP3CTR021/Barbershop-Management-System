import 'package:barbershop_management_app/core/config/backend_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_core/firebase_core.dart' as fc;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Idempotent SDK initializer for both Supabase and Firebase backends.
abstract final class BackendInitializer {
  static bool _supabaseInitialized = false;
  static bool _firebaseConfigured = false;

  static Future<void> initialize({
    required BackendType backend,
    SupabaseConfig supabase = const SupabaseConfig.fromEnvironment(),
    FirebaseConfig firebase = const FirebaseConfig(),
    bool ensureFlutterBinding = true,
  }) async {
    if (ensureFlutterBinding) {
      WidgetsFlutterBinding.ensureInitialized();
    }

    switch (backend) {
      case BackendType.supabase:
        if (_supabaseInitialized) return;
        if (!supabase.isConfigured) {
          throw StateError(
            'SupabaseConfig is missing URL or anonKey. '
            'Provide --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... '
            'or pass a SupabaseConfig to RepositoryLocator.bootstrap().',
          );
        }
        await sb.Supabase.initialize(
          url: supabase.url.trim(),
          publishableKey: supabase.anonKey.trim(),
        );
        _supabaseInitialized = true;

      case BackendType.firebase:
        if (fc.Firebase.apps.isEmpty) {
          await fc.Firebase.initializeApp(options: firebase.options);
        }
        if (!_firebaseConfigured) {
          final firestore = fs.FirebaseFirestore.instance;
          // Apply persistence settings BEFORE `useFirestoreEmulator` because
          // `useFirestoreEmulator` mutates `settings` via `.copyWith(...)`.
          firestore.settings = fs.Settings(
            persistenceEnabled: firebase.enablePersistence,
          );
          final emulatorHost = firebase.emulatorHost?.trim();
          if (emulatorHost != null && emulatorHost.isNotEmpty) {
            firestore.useFirestoreEmulator(
              emulatorHost,
              firebase.firestoreEmulatorPort,
            );
            await fa.FirebaseAuth.instance.useAuthEmulator(
              emulatorHost,
              firebase.authEmulatorPort,
            );
          }
          _firebaseConfigured = true;
        }
    }
  }
}
