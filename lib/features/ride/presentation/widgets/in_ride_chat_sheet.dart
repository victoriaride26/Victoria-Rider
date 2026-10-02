import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/services/rider_chat_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Mark this ride's thread read while the sheet is open — incoming
    // messages for it then land without bumping the badge.
    RiderChatService.instance.openChat(widget.rideId);
    RiderChatService.instance.addListener(_onMessagesChanged);

    // Ensure socket is joined to this ride room
    RiderSocketService.instance.subscribeToRideTracking(widget.rideId);

    // Restore chat history from backend on open
    _loadChatHistory();
  }

  void _onMessagesChanged() {
    if (mounted) setState(() {});
    _scrollToBottom();
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
        final loaded = <ChatMessage>[];
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
              loaded.add(ChatMessage(
                id: (item['id'] ?? item['_id'] ?? '')
                    .toString(),
                text: text,
                isMe: sender == 'rider',
                time: time,
                rideId: widget.rideId,
                read: true,
              ));
            }
          }
        }
        if (loaded.isNotEmpty && mounted) {
          RiderChatService.instance.addHistory(widget.rideId, loaded);
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
    RiderChatService.instance.sendMessage(widget.rideId, text);
    _scrollToBottom();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RiderChatService.instance.closeChat();
    RiderChatService.instance.removeListener(_onMessagesChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final service = RiderChatService.instance;
    final messages = service.messagesFor(widget.rideId);
    final peerTyping = service.isPeerTyping(widget.rideId);

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
              child: messages.isEmpty
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
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
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

            // Typing indicator + Input Bar
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border(top: BorderSide(color: AppColors.surfaceContainerHigh)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (peerTyping) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.driverName} is typing…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          onChanged: (value) {
                            if (value.trim().isEmpty) {
                              RiderChatService.instance
                                  .stopTyping(widget.rideId);
                            } else {
                              RiderChatService.instance
                                  .noteTyping(widget.rideId);
                            }
                          },
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
