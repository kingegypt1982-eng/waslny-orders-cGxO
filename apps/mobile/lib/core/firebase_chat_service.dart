import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'chat_config.dart';

/// Text message stored under `chats/{orderId}/messages/{messageId}`.
///
/// Identity comes only from Firebase Auth: `senderId` is `auth.uid` (the
/// custom token mints uid = NestJS userId) and `role` comes from the token's
/// role claim. Nothing sent by the client is trusted as identity.
class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String role;
  final String content;
  final DateTime createdAt;
  final String? orderId;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.orderId,
  });

  factory ChatMessage.fromMap(Map<dynamic, dynamic> map, String id) => ChatMessage(
        id: id,
        senderId: map['senderId']?.toString() ?? '',
        receiverId: map['receiverId']?.toString() ?? '',
        role: map['role']?.toString() ?? '',
        content: map['content']?.toString() ?? '',
        createdAt: map['createdAt'] != null
            ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        orderId: map['orderId']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'receiverId': receiverId,
        'role': role,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'orderId': orderId,
      };
}

/// Firebase-backed chat. Disabled by default via [kChatEnabled]; every entry
/// point is guarded and degrades cleanly instead of throwing into the UI.
class FirebaseChatService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseDatabase get _db => FirebaseDatabase.instance;

  bool get isReady {
    if (!kChatEnabled) return false;
    try {
      return _auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  String? getCurrentUserId() {
    if (!isReady) return null;
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Role is read from the backend-minted custom token claim, never from UI.
  Future<String> _currentRole() async {
    final user = _auth.currentUser;
    if (user == null) return '';
    final result = await user.getIdTokenResult();
    return result.claims?['role']?.toString() ?? '';
  }

  Future<Map<String, dynamic>?> getOrderChatMeta(String orderId) async {
    if (!isReady || orderId.trim().isEmpty) return null;
    try {
      final snapshot = await _db.ref('chats/$orderId/meta').get();
      if (!snapshot.exists) return null;
      return Map<String, dynamic>.from(snapshot.value as Map);
    } catch (_) {
      return null;
    }
  }

  /// Sends a bounded text message. Throws [ArgumentError] for bad routing data
  /// and [StateError] when chat is unavailable so the UI can show a banner.
  Future<String?> sendMessage({
    required String content,
    required String orderId,
    required String receiverId,
  }) async {
    if (!kChatEnabled) throw StateError('Chat is disabled');
    if (orderId.trim().isEmpty) throw ArgumentError('orderId is required');
    if (receiverId.trim().isEmpty) throw ArgumentError('receiverId is required');
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError('content is required');
    if (trimmed.length > 2000) throw ArgumentError('content is too long');
    final uid = getCurrentUserId();
    if (uid == null) throw StateError('Firebase chat is unavailable');

    final meta = await getOrderChatMeta(orderId);
    if (meta == null || meta['status'] != 'ACTIVE') {
      throw StateError('Chat is not active for this order');
    }
    final role = await _currentRole();
    final messageId = _db.ref('chats/$orderId/messages').push().key;
    if (messageId == null) throw StateError('Could not create message id');

    await _db.ref('chats/$orderId/messages/$messageId').set(
          ChatMessage(
            id: messageId,
            senderId: uid,
            receiverId: receiverId,
            role: role,
            content: trimmed,
            createdAt: DateTime.now(),
            orderId: orderId,
          ).toMap(),
        );
    return messageId;
  }

  /// Real-time messages; emits an empty list when chat is unavailable.
  Stream<List<ChatMessage>> listenMessages(String orderId) {
    if (!isReady || orderId.trim().isEmpty) {
      return Stream<List<ChatMessage>>.value(const <ChatMessage>[]);
    }
    return _db.ref('chats/$orderId/messages').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return <ChatMessage>[];
      return data.entries.map((entry) {
        if (entry.value is! Map) {
          return ChatMessage(
            id: entry.key.toString(),
            senderId: '',
            receiverId: '',
            role: '',
            content: '',
            createdAt: DateTime.now(),
          );
        }
        return ChatMessage.fromMap(entry.value as Map, entry.key.toString());
      }).toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }).handleError((_) => <ChatMessage>[]);
  }
}
