import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_config.dart';

/// Firebase identity is a chat-only bridge. It is minted by the NestJS API
/// (POST /firebase/token, JWT-guarded) with uid = Waslny userId and a role
/// claim. There is deliberately no anonymous sign-in.
///
/// Failures are swallowed: the NestJS session owns login, so a broken
/// Firebase setup only disables chat.
Future<void> signInFirebaseWithCustomToken(Dio dio, String jwt) async {
  if (!kChatEnabled) return;
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    final response = await dio.post<Map<String, dynamic>>(
      '/firebase/token',
      data: const <String, dynamic>{},
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    final token = response.data?['customToken'];
    if (token is! String || token.isEmpty) return;
    await auth.signInWithCustomToken(token);
  } catch (_) {
    // Chat stays unavailable; auth/orders/wallet are unaffected.
  }
}

/// Signs out of Firebase when the NestJS session is cleared.
Future<void> signOutFirebase() async {
  if (!kChatEnabled) return;
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) await auth.signOut();
  } catch (_) {
    // Firebase may never have been initialized.
  }
}
