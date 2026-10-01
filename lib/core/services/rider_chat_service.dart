import 'dart:async';
import 'package:flutter/foundation.dart';
import 'rider_socket_service.dart';

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;

  ChatMessage({required this.text, required this.isMe, required this.time});
}

class RiderChatService extends ChangeNotifier {
  RiderChatService._() {
    _chatSub = RiderSocketService.instance.onChatMessage.listen((data) {
      final text = (data['message'] ?? data['text'])?.toString();
      final sender = data['sender']?.toString() ?? 'driver';
      final isMe = sender == 'rider';
      
      if (text != null && text.isNotEmpty) {
        final recentlySent = messages.any((m) => 
            m.isMe && 
            m.text == text && 
            DateTime.now().difference(m.time).inSeconds < 10);
            
        if (!recentlySent) {
          messages.add(ChatMessage(
            text: text,
            isMe: isMe,
            time: DateTime.now(),
          ));
          if (!isMe && !isChatOpen) {
            unreadCount++;
          }
          notifyListeners();
        }
      }
    });
  }

  static final RiderChatService instance = RiderChatService._();

  List<ChatMessage> messages = [];
  int unreadCount = 0;
  bool isChatOpen = false;
  StreamSubscription? _chatSub;

  void markAsRead() {
    unreadCount = 0;
    notifyListeners();
  }

  void addHistory(List<ChatMessage> history) {
    // Only add history if empty, to avoid duplicates on reopen
    if (messages.isEmpty) {
      messages.addAll(history);
      notifyListeners();
    }
  }

  void sendMessage(String rideId, String text) {
    messages.add(ChatMessage(text: text, isMe: true, time: DateTime.now()));
    notifyListeners();
    RiderSocketService.instance.sendChatMessage(
      rideId: rideId,
      message: text,
      sender: 'rider',
    );
  }

  void disposeService() {
    _chatSub?.cancel();
    super.dispose();
  }
}
