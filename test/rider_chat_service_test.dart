import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vtrides/core/services/rider_chat_service.dart';
import 'package:vtrides/core/services/rider_socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock prefs must exist before the singletons are constructed, otherwise
  // their first hydration fails and no history is ever loaded.
  SharedPreferences.setMockInitialValues({});

  final socket = RiderSocketService.instance;
  final service = RiderChatService.instance;

  setUpAll(() async {
    await service.ensureStarted();
  });

  Future<void> flush() => pumpEventQueue();

  group('chat ingest', () {
    test('incoming message bumps only its own ride badge', () async {
      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-1',
        'message': 'I am outside',
        'sender': 'driver',
        'id': 'm1',
      });
      await flush();

      expect(service.unreadFor('rider-chat-1'), 1);
      expect(service.unreadFor('rider-chat-2'), 0);
      expect(service.totalUnread, 1);
      expect(service.messagesFor('rider-chat-1'), hasLength(1));
    });

    test('same message under another alias is stored once', () async {
      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-3',
        'message': 'Coming down now',
        'sender': 'driver',
        'id': 'm3',
      });
      await flush();
      socket.debugDispatchChatMessage({
        'ride_id': 'rider-chat-3',
        'text': 'Coming down now',
        'senderType': 'driver',
        'messageId': 'm3',
      });
      await flush();

      expect(service.messagesFor('rider-chat-3'), hasLength(1));
    });

    test('own echo is dropped and ride threads stay separate', () async {
      service.sendMessage('rider-chat-4', 'Where are you?');
      await flush();

      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-4',
        'message': 'Where are you?',
        'sender': 'rider',
      });
      await flush();

      // …and the same relay arriving with no sender field at all.
      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-4',
        'message': 'Where are you?',
      });
      await flush();

      expect(
        service.messagesFor('rider-chat-4').where((m) => m.text == 'Where are you?'),
        hasLength(1),
      );
      expect(service.messagesFor('rider-chat-5'), isEmpty);
    });
  });

  group('unread badges', () {
    test('opening the chat clears the badge and later messages stay read',
        () async {
      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-6',
        'message': 'First ping',
        'sender': 'driver',
        'id': 'm6',
      });
      await flush();
      expect(service.unreadFor('rider-chat-6'), 1);

      service.openChat('rider-chat-6');
      await flush();
      expect(service.unreadFor('rider-chat-6'), 0);

      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-6',
        'message': 'Second ping',
        'sender': 'driver',
        'id': 'm6b',
      });
      await flush();
      expect(service.unreadFor('rider-chat-6'), 0);
      expect(service.messagesFor('rider-chat-6'), hasLength(2));

      service.closeChat();
    });
  });

  group('persistence', () {
    test('messages are written to SharedPreferences', () async {
      socket.debugDispatchChatMessage({
        'rideId': 'rider-chat-7',
        'message': 'Persist me',
        'sender': 'driver',
        'id': 'm7',
      });
      await flush();
      // _persist() is fire-and-forget — give it a beat to land.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vr_rider_chat_messages');
      expect(raw, isNotNull);
      expect(raw, contains('Persist me'));
      expect(raw, contains('rider-chat-7'));
    });

    test('saved threads are rehydrated on a cold start', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vr_rider_chat_messages',
        jsonEncode([
          {
            'id': 'h1',
            'text': 'Saved thread',
            'isMe': false,
            'time': DateTime.now().toIso8601String(),
            'rideId': 'rider-chat-10',
            'read': false,
          },
        ]),
      );

      await service.reloadFromPrefs();

      expect(service.messagesFor('rider-chat-10').single.text, 'Saved thread');
      expect(service.unreadFor('rider-chat-10'), 1);
    });
  });

  group('typing indicator', () {
    test('driver typing is exposed and clears on stop', () async {
      socket.debugDispatchTyping({
        'rideId': 'rider-chat-8',
        'sender': 'driver',
        'typing': true,
      });
      await flush();
      expect(service.isPeerTyping('rider-chat-8'), isTrue);

      socket.debugDispatchTyping({
        'rideId': 'rider-chat-8',
        'sender': 'driver',
        'typing': false,
      });
      await flush();
      expect(service.isPeerTyping('rider-chat-8'), isFalse);
    });

    test('our own typing events are ignored', () async {
      socket.debugDispatchTyping({
        'rideId': 'rider-chat-9',
        'sender': 'rider',
        'typing': true,
      });
      await flush();
      expect(service.isPeerTyping('rider-chat-9'), isFalse);
    });
  });
}
