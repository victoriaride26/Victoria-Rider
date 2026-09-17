import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Modal bottom sheet for live in-ride chat between rider and driver.
/// Scoped to the active `ride:{rideId}` room via Socket.IO.
class InRideChatSheet extends StatefulWidget {
  const InRideChatSheet({
    super.key,
    required this.rideId,
    this.driverName = 'Driver',
  });

  final String rideId;
  final String driverName;

  static void show(BuildContext context, {required String rideId, String driverName = 'Driver'}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InRideChatSheet(rideId: rideId, driverName: driverName),
    );
  }

  @override
  State<InRideChatSheet> createState() => _InRideChatSheetState();
}

class _InRideChatSheetState extends State<InRideChatSheet>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Ensure socket is joined to this ride room
    RiderSocketService.instance.subscribeToRideTracking(widget.rideId);

    // Restore chat history from backend on open
    _loadChatHistory();

    // Listen to real-time incoming messages
    _chatSub = RiderSocketService.instance.onChatMessage.listen((data) {
      final msgRideId = data['rideId']?.toString();
      if (msgRideId == null || msgRideId == widget.rideId) {
        final text = (data['message'] ?? data['text'])?.toString();
        final sender = data['sender']?.toString() ?? 'driver';
        if (text != null && text.isNotEmpty) {
          // Avoid duplicate local echoes
          if (sender == 'rider' &&
              _messages.isNotEmpty &&
              _messages.last.isMe &&
              _messages.last.text == text) {
            return;
          }
          setState(() {
            _messages.add(_ChatMessage(
              text: text,
              isMe: sender == 'rider',
              time: DateTime.now(),
            ));
          });
          _scrollToBottom();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app resumes from the background, restore the UI chat history
    if (state == AppLifecycleState.resumed) {
      _loadChatHistory();
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final response =
          await ApiClient.instance.get(ApiConfig.rideChat(widget.rideId));
      if (!mounted) return;

      dynamic listRaw;
      if (response is Map<String, dynamic>) {
        listRaw = response['data'] ??
            response['messages'] ??
            response['chat'] ??
            response['history'];
      } else if (response is List) {
        listRaw = response;
      }

      if (listRaw is List && listRaw.isNotEmpty) {
        final loaded = <_ChatMessage>[];
        for (final item in listRaw) {
          if (item is Map) {
            final text = (item['message'] ?? item['text'])?.toString();
            final sender = item['sender']?.toString() ?? 'driver';
            DateTime time = DateTime.now();
            if (item['timestamp'] is int) {
              time = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int);
            } else if (item['createdAt'] is String) {
              time =
                  DateTime.tryParse(item['createdAt'] as String) ?? DateTime.now();
            }
            if (text != null && text.isNotEmpty) {
              loaded.add(_ChatMessage(
                text: text,
                isMe: sender == 'rider',
                time: time,
              ));
            }
          }
        }
        if (loaded.isNotEmpty && mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(loaded);
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      // Quietly continue if offline or not implemented on server yet
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isMe: true,
        time: DateTime.now(),
      ));
    });
    _scrollToBottom();

    RiderSocketService.instance.sendChatMessage(
      rideId: widget.rideId,
      message: text,
      sender: 'rider',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7 + bottomInset,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryContainer,
                    child: Icon(Icons.person, color: AppColors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.driverName, style: theme.textTheme.titleMedium),
                        Text(
                          'Active Trip • Direct Chat',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Messages
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48, color: AppColors.outlineVariant),
                          const SizedBox(height: 8),
                          Text(
                            'Chat with ${widget.driverName}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Coordinate pickup points or special requests.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return Align(
                          alignment: msg.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: msg.isMe
                                  ? AppColors.primary
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                                bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                              ),
                            ),
                            child: Text(
                              msg.text,
                              style: TextStyle(
                                color: msg.isMe
                                    ? AppColors.onPrimary
                                    : AppColors.onSurface,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Input Bar
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border(top: BorderSide(color: AppColors.surfaceContainerHigh)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
  });

  final String text;
  final bool isMe;
  final DateTime time;
}
