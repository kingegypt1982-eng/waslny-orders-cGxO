// Firebase configuration options for Waslny orders app.
// These values are provided via --dart-define during build:
//   flutter run --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_AUTH_DOMAIN=...
//               --dart-define=FIREBASE_DATABASE_URL=... --dart-define=FIREBASE_PROJECT_ID=...
//               --dart-define=FIREBASE_STORAGE_BUCKET=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
//               --dart-define=FIREBASE_APP_ID=...
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Platform-agnostic options used by `Firebase.initializeApp`.
///
/// FlutterFire normally generates one `DefaultFirebaseOptions.currentPlatform`
/// per target. This app uses a single web/Android configuration, exposed here
/// under the same name so bootstrap never has to build empty options by hand.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => defaultFirebaseOptions;
}

/// Creates FirebaseOptions from the default Waslny project configuration.
/// Use this as a fallback when dart-define is not used.
FirebaseOptions get defaultFirebaseOptions => FirebaseOptions(
      apiKey: const String.fromEnvironment('FIREBASE_API_KEY',
          defaultValue: 'AIzaSyC-CuSCiHGrls_Ho3bhLpml4X9BHwPPCk'),
      authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN',
          defaultValue: 'waslny-c6ffb.firebaseapp.com'),
      databaseURL: const String.fromEnvironment('FIREBASE_DATABASE_URL',
          defaultValue:
              'https://waslny-c6ffb-default-rtdb.europe-west1.firebasedatabase.app'),
      projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID',
          defaultValue: 'waslny-c6ffb'),
      storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET',
          defaultValue: 'waslny-c6ffb.firebasestorage.app'),
      messagingSenderId: const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: '999658624457'),
      appId: const String.fromEnvironment('FIREBASE_APP_ID',
          defaultValue: '1:999658624457:web:d16b77d780cd82521bc418'),
    );