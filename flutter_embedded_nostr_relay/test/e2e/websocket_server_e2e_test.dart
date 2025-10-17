// ABOUTME: End-to-end tests for WebSocket server with real connections
// ABOUTME: Tests complete Nostr protocol flow with actual WebSocket connections

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('WebSocket Server E2E', () {
    late WebSocketServer server;
    late SubscriptionManager subscriptionManager;
    late EventStore eventStore;

    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      final databaseHelper = DatabaseHelper.instance;
      eventStore = EventStore(databaseHelper: databaseHelper);
      subscriptionManager = SubscriptionManager();
      
      server = WebSocketServer(
        subscriptionManager: subscriptionManager,
        eventStore: eventStore,
      );
      
      await server.start(port: 0); // Use random available port
    });

    tearDown(() async {
      await server.stop();
      await subscriptionManager.close();
      await DatabaseHelper.reset();
    });

    test('should handle basic REQ and EVENT flow', () async {
      final client = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );

      final responses = <String>[];
      client.stream.listen((message) {
        responses.add(message);
        print('Received: $message');
      });

      // Send REQ message
      final reqMessage = json.encode([
        'REQ',
        'test-sub',
        {'kinds': [1], 'limit': 10}
      ]);
      
      print('Sending REQ: $reqMessage');
      client.sink.add(reqMessage);

      // Wait for EOSE
      await Future.delayed(Duration(milliseconds: 200));

      // Should receive EOSE message
      expect(responses.length, greaterThanOrEqualTo(1));
      final eoseResponse = json.decode(responses.first) as List;
      expect(eoseResponse[0], equals('EOSE'));
      expect(eoseResponse[1], equals('test-sub'));

      // Send an EVENT with a dummy signature for testing
      final baseEvent = NostrEvent.create(
        pubkey: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        kind: 1,
        tags: [],
        content: 'Hello Nostr!',
      );
      
      final event = baseEvent.copyWith(
        sig: 'test_signature_' + baseEvent.id.substring(0, 50), // Non-empty signature for testing
      );

      final eventMessage = json.encode(['EVENT', event.toJson()]);
      print('Sending EVENT: $eventMessage');
      client.sink.add(eventMessage);

      await Future.delayed(Duration(milliseconds: 200));

      // Should receive OK response and event broadcast
      print('Total responses: ${responses.length}');
      for (int i = 0; i < responses.length; i++) {
        print('Response $i: ${responses[i]}');
      }

      // Check for OK response
      bool foundOkResponse = false;
      for (final response in responses) {
        final responseJson = json.decode(response) as List;
        if (responseJson[0] == 'OK') {
          foundOkResponse = true;
          expect(responseJson[1], equals(event.id));
          break;
        }
      }
      expect(foundOkResponse, isTrue, reason: 'Should receive OK response for stored event');

      await client.sink.close();
    });

    test('should store and retrieve events', () async {
      final client = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );

      final responses = <String>[];
      client.stream.listen((message) {
        responses.add(message);
      });

      // Store an event first
      final baseEvent = NostrEvent.create(
        pubkey: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        kind: 1,
        tags: [],
        content: 'Test event for retrieval',
      );
      
      final event = baseEvent.copyWith(
        sig: 'test_signature_' + baseEvent.id.substring(0, 50),
      );

      final eventMessage = json.encode(['EVENT', event.toJson()]);
      client.sink.add(eventMessage);

      await Future.delayed(Duration(milliseconds: 200));

      // Clear previous responses
      responses.clear();

      // Now subscribe to get the stored event
      final reqMessage = json.encode([
        'REQ',
        'retrieve-sub',
        {'kinds': [1], 'limit': 10}
      ]);
      
      client.sink.add(reqMessage);
      await Future.delayed(Duration(milliseconds: 200));

      // Should receive the stored event plus EOSE
      print('Responses for retrieval: ${responses.length}');
      for (final response in responses) {
        print('Retrieval response: $response');
      }

      bool foundStoredEvent = false;
      for (final response in responses) {
        final responseJson = json.decode(response) as List;
        if (responseJson[0] == 'EVENT' && 
            responseJson[1] == 'retrieve-sub') {
          final eventData = responseJson[2] as Map<String, dynamic>;
          if (eventData['id'] == event.id) {
            foundStoredEvent = true;
            expect(eventData['content'], equals('Test event for retrieval'));
            break;
          }
        }
      }
      expect(foundStoredEvent, isTrue, reason: 'Should retrieve the stored event');

      await client.sink.close();
    });

    test('should handle multiple clients', () async {
      final client1 = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );
      final client2 = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );

      final client1Responses = <String>[];
      final client2Responses = <String>[];

      client1.stream.listen((message) {
        client1Responses.add(message);
      });

      client2.stream.listen((message) {
        client2Responses.add(message);
      });

      // Both clients subscribe
      final reqMessage = json.encode([
        'REQ',
        'multi-sub',
        {'kinds': [1]}
      ]);

      client1.sink.add(reqMessage);
      client2.sink.add(reqMessage);

      await Future.delayed(Duration(milliseconds: 200));

      // Send event from client1
      final baseEvent = NostrEvent.create(
        pubkey: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        kind: 1,
        tags: [],
        content: 'Multi-client test',
      );
      
      final event = baseEvent.copyWith(
        sig: 'test_signature_' + baseEvent.id.substring(0, 50),
      );

      client1.sink.add(json.encode(['EVENT', event.toJson()]));
      await Future.delayed(Duration(milliseconds: 200));

      expect(server.activeConnections, equals(2));

      // Both clients should have received responses
      expect(client1Responses.length, greaterThan(0));
      expect(client2Responses.length, greaterThan(0));

      await client1.sink.close();
      await client2.sink.close();
      
      await Future.delayed(Duration(milliseconds: 100));
      expect(server.activeConnections, equals(0));
    });
  });
}