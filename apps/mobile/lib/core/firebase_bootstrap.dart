import 'package:firebase_core/firebase_core.dart';

import 'chat_config.dart';
import 'firebase_options.dart';

/// Initializes Firebase only when chat is enabled, after the first frame and
/// with a hard timeout. Never logs error details (they may carry identifiers).
/// Returns true when Firebase is usable.
Future<bool> initializeChatFirebase() async {
  if (!kChatEnabled) return false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
    }
    return true;
  } catch (_) {
    return false;
  }
}
