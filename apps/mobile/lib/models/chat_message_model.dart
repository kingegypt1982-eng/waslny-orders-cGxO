/// Message type enum
enum MessageType { text, image, file, system }

/// Chat message model
class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String role; // 'CLIENT' or 'CAPTAIN'
  final String content;
  final MessageType type;
  final DateTime createdAt;
  final String? readBy;
  final DateTime? readAt;
  final String? orderId;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.role,
    required this.content,
    required this.type,
    required this.createdAt,
    this.readBy,
    this.readAt,
    this.orderId,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      senderId: map['senderId']?.toString() ?? '',
      receiverId: map['receiverId']?.toString() ?? '',
      role: map['role']?.toString() ?? 'CLIENT',
      content: map['content']?.toString() ?? '',
      type: _stringToMessageType(map['type']?.toString() ?? 'text'),
      createdAt: DateTime.parse(map['createdAt'].toString()),
      readBy: map['readBy']?.toString(),
      readAt: map['readAt'] != null ? DateTime.parse(map['readAt'].toString()) : null,
      orderId: map['orderId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'role': role,
      'content': content,
      'type': type.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'readBy': readBy,
      'readAt': readAt?.toIso8601String(),
      'orderId': orderId,
    };
  }

  static MessageType _stringToMessageType(String type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.text;
    }
  }
}
