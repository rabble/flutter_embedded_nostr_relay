// ABOUTME: Integration tests for WebSocket server with real SubscriptionManager and EventStore
// ABOUTME: Tests end-to-end message flow and multi-client scenarios

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('WebSocketServer Integration', () {
    late WebSocketServer server;
    late SubscriptionManager subscriptionManager;
    late EventStore eventStore;
    late DatabaseHelper databaseHelper;
    
    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    
    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      databaseHelper = DatabaseHelper.instance;
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
    
    group('End-to-End Message Flow', () {
      test('should handle complete REQ->EVENT->EOSE flow', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        final responseCompleter = Completer<void>();
        int expectedResponses = 2; // EOSE + EVENT
        
        client.stream.listen((message) {
          responses.add(message);
          if (responses.length >= expectedResponses) {
            responseCompleter.complete();
          }
        });
        
        // Send REQ message
        final reqMessage = json.encode([
          'REQ',
          'test-sub',
          {'kinds': [1], 'limit': 10}
        ]);
        client.sink.add(reqMessage);
        
        // Wait for EOSE
        await Future.delayed(Duration(milliseconds: 100));
        
        // Send an EVENT that matches the subscription
        final event = NostrEvent(
          id: 'test-event-123',
          pubkey: 'test-pubkey-456',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'Hello Nostr!',
          sig: 'test-signature-789',
        );
        
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client.sink.add(eventMessage);
        
        await responseCompleter.future.timeout(Duration(seconds: 2));
        
        expect(responses.length, greaterThanOrEqualTo(2));
        
        // Check EOSE response
        final eoseResponse = json.decode(responses.first) as List;
        expect(eoseResponse[0], equals('EOSE'));
        expect(eoseResponse[1], equals('test-sub'));
        
        // Check that we got an OK response for the event
        bool foundOkResponse = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == 'test-event-123') {
            foundOkResponse = true;
            expect(responseJson[2], equals(true)); // Event accepted
            break;
          }
        }
        expect(foundOkResponse, isTrue);
        
        await client.sink.close();
      });
      
      test('should route events to multiple matching subscriptions', () async {
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
        
        // Both clients subscribe to kind 1 events
        final reqMessage = json.encode([
          'REQ',
          'sub-1',
          {'kinds': [1]}
        ]);
        
        client1.sink.add(reqMessage);
        client2.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Send an event from client1
        final event = NostrEvent(
          id: 'shared-event-123',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'Shared event',
          sig: 'test-signature',
        );
        
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client1.sink.add(eventMessage);
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Both clients should receive the event
        bool client1GotEvent = false;
        bool client2GotEvent = false;
        
        for (final response in client1Responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT' && 
              responseJson[1] == 'sub-1' &&
              responseJson[2]['id'] == 'shared-event-123') {
            client1GotEvent = true;
            break;
          }
        }
        
        for (final response in client2Responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT' && 
              responseJson[1] == 'sub-1' &&
              responseJson[2]['id'] == 'shared-event-123') {
            client2GotEvent = true;
            break;
          }
        }
        
        expect(client1GotEvent, isTrue);
        expect(client2GotEvent, isTrue);
        
        await client1.sink.close();
        await client2.sink.close();
      });
      
      test('should handle CLOSE message and stop routing events', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Subscribe
        final reqMessage = json.encode([
          'REQ',
          'closeable-sub',
          {'kinds': [1]}
        ]);
        client.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Send first event - should be routed
        final event1 = NostrEvent(
          id: 'event-before-close',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'Before close',
          sig: 'test-signature',
        );
        client.sink.add(json.encode(['EVENT', event1.toJson()]));
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Close subscription
        final closeMessage = json.encode(['CLOSE', 'closeable-sub']);
        client.sink.add(closeMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Send second event - should NOT be routed to closed subscription
        final event2 = NostrEvent(
          id: 'event-after-close',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'After close',
          sig: 'test-signature',
        );
        client.sink.add(json.encode(['EVENT', event2.toJson()]));
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Count EVENT messages for our subscription
        int eventMessagesCount = 0;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT' && responseJson[1] == 'closeable-sub') {
            eventMessagesCount++;
          }
        }
        
        // Should only have received the first event
        expect(eventMessagesCount, equals(1));
        
        await client.sink.close();
      });
    });
    
    group('Performance and Stress Tests', () {
      test('should handle 10 concurrent connections efficiently', () async {
        final clients = <WebSocketChannel>[];
        final connectFutures = <Future>[];
        
        // Connect 10 clients simultaneously
        for (int i = 0; i < 10; i++) {
          connectFutures.add(() async {
            final client = await WebSocketChannel.connect(
              Uri.parse('ws://localhost:${server.port}'),
            );
            clients.add(client);
            
            // Each client subscribes to kind 1 events
            final reqMessage = json.encode([
              'REQ',
              'sub-$i',
              {'kinds': [1], 'limit': 5}
            ]);
            client.sink.add(reqMessage);
          }());
        }
        
        await Future.wait(connectFutures);
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(server.activeConnections, equals(10));
        
        // Send events from each client
        for (int i = 0; i < clients.length; i++) {
          final event = NostrEvent(
            id: 'concurrent-event-$i',
            pubkey: 'pubkey-$i',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: 1,
            tags: [],
            content: 'Message from client $i',
            sig: 'signature-$i',
          );
          
          clients[i].sink.add(json.encode(['EVENT', event.toJson()]));
        }
        
        // Wait for processing
        await Future.delayed(Duration(milliseconds: 500));
        
        // Verify server statistics
        final stats = server.getStatistics();
        expect(stats['activeConnections'], equals(10));
        expect(stats['totalMessagesReceived'], greaterThan(10));
        
        // Close all clients
        for (final client in clients) {
          await client.sink.close();
        }
        
        await Future.delayed(Duration(milliseconds: 100));
        expect(server.activeConnections, equals(0));
      });
      
      test('should maintain performance with rapid message sending', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Subscribe
        final reqMessage = json.encode([
          'REQ',
          'perf-sub',
          {'kinds': [1]}
        ]);
        client.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        final startTime = DateTime.now();
        
        // Send 100 events rapidly
        for (int i = 0; i < 100; i++) {
          final event = NostrEvent(
            id: 'rapid-event-$i',
            pubkey: 'test-pubkey',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: 1,
            tags: [],
            content: 'Rapid message $i',
            sig: 'test-signature',
          );
          
          client.sink.add(json.encode(['EVENT', event.toJson()]));
        }
        
        // Wait for all processing to complete
        await Future.delayed(Duration(milliseconds: 1000));
        
        final endTime = DateTime.now();
        final processingTime = endTime.difference(startTime);
        
        // Should process 100 events in reasonable time (< 2 seconds)
        expect(processingTime.inMilliseconds, lessThan(2000));
        
        // Should have received at least 100 OK responses + EOSE
        expect(responses.length, greaterThanOrEqualTo(101));
        
        await client.sink.close();
      });
    });
    
    group('Filter Matching', () {
      test('should route events based on complex filters', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Subscribe with complex filter
        final reqMessage = json.encode([
          'REQ',
          'complex-sub',
          {
            'kinds': [1],
            'authors': ['specific-author'],
            'since': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
            'limit': 5
          }
        ]);
        client.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Send matching event
        final matchingEvent = NostrEvent(
          id: 'matching-event',
          pubkey: 'specific-author',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'This should match',
          sig: 'test-signature',
        );
        client.sink.add(json.encode(['EVENT', matchingEvent.toJson()]));
        
        // Send non-matching event (wrong author)
        final nonMatchingEvent = NostrEvent(
          id: 'non-matching-event',
          pubkey: 'different-author',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'This should not match',
          sig: 'test-signature',
        );
        client.sink.add(json.encode(['EVENT', nonMatchingEvent.toJson()]));
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Count EVENT messages received
        int eventMessagesCount = 0;
        String? receivedEventId;
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT' && responseJson[1] == 'complex-sub') {
            eventMessagesCount++;
            receivedEventId = responseJson[2]['id'];
          }
        }
        
        // Should only have received the matching event
        expect(eventMessagesCount, equals(1));
        expect(receivedEventId, equals('matching-event'));
        
        await client.sink.close();
      });
    });
    
    group('Error Recovery', () {
      test('should recover from client connection errors', () async {
        final client1 = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        // Subscribe
        final reqMessage = json.encode([
          'REQ',
          'error-test',
          {'kinds': [1]}
        ]);
        client1.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Force close client1
        await client1.sink.close();
        await Future.delayed(Duration(milliseconds: 100));
        
        // Server should still be functional for new connections
        final client2 = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client2.stream.listen((message) {
          responses.add(message);
        });
        
        client2.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive EOSE
        expect(responses.isNotEmpty, isTrue);
        final response = json.decode(responses.first) as List;
        expect(response[0], equals('EOSE'));
        
        await client2.sink.close();
      });
    });
  });
}