import 'dart:async';

import 'package:flutter/material.dart';

import '../core/chat_config.dart';
import '../core/firebase_chat_service.dart';
import '../core/texts.dart';

/// Text-only chat for one order. Opened from the trip/tracking flow with the
/// counterpart's Waslny user id (the custom-token uid == userId).
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.orderId,
    required this.counterpartId,
    required this.counterpartRole,
    required this.counterpartName,
  });

  final String orderId;
  final String counterpartId;
  final String counterpartRole;
  final String counterpartName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseChatService _chatService = FirebaseChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final StreamSubscription<List<ChatMessage>> _messagesSubscription;
  List<ChatMessage> _messages = const [];
  String? _currentUid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUid = _chatService.getCurrentUserId();
    _messagesSubscription = _chatService.listenMessages(widget.orderId).listen(
      (messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
            _scrollToBottom();
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _error = _unavailableText);
      },
    );
  }

  @override
  void dispose() {
    _messagesSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _unavailableText => tr(
        ar: 'الدردشة غير متاحة حاليًا.',
        en: 'Chat is currently unavailable.',
      );

  String _localizedError(Object error) {
    if (error is ArgumentError) {
      return tr(
        ar: 'تعذر تحديد طرف المحادثة لهذا الطلب.',
        en: 'The chat counterpart for this order could not be determined.',
      );
    }
    return _unavailableText;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    try {
      await _chatService.sendMessage(
        content: content,
        orderId: widget.orderId,
        receiverId: widget.counterpartId,
      );
      _messageController.clear();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = _localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = kChatEnabled && _chatService.isReady;
    return Directionality(
      textDirection: deviceIsArabic() ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(
                widget.counterpartRole == 'CLIENT'
                    ? Icons.motorcycle
                    : Icons.person,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(widget.counterpartName,
                  style: const TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!ready || _error != null)
                Material(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error ?? _unavailableText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                ),
              Expanded(child: _buildMessagesList()),
              _buildInputBar(ready),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          tr(ar: 'لا توجد رسائل بعد', en: 'No messages yet'),
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _currentUid;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.indigo[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? tr(ar: 'أنا', en: 'Me') : widget.counterpartName,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(message.content,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800])),
                const SizedBox(height: 4),
                Text(_formatTime(message.createdAt),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour}:${p(date.minute)}';
    }
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${p(date.minute)}';
  }

  Widget _buildInputBar(bool ready) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: ready,
              decoration: InputDecoration(
                hintText: tr(ar: 'أدخل رسالة...', en: 'Type a message...'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onSubmitted: ready ? (_) => _sendMessage() : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.indigo),
            onPressed: ready ? _sendMessage : null,
          ),
        ],
      ),
    );
  }
}
