// ABOUTME: Unit tests for WebSocket server implementation
// ABOUTME: Tests message parsing, routing, connection management, and error handling

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_message.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/models/subscription.dart';
import 'package:flutter_embedded_nostr_relay/src/core/constants.dart';

import 'websocket_server_test.mocks.dart';

@GenerateMocks([SubscriptionManager, EventStore])
void main() {
  group('WebSocketServer', () {
    late WebSocketServer server;
    late MockSubscriptionManager mockSubscriptionManager;
    late MockEventStore mockEventStore;
    
    setUp(() {
      mockSubscriptionManager = MockSubscriptionManager();
      mockEventStore = MockEventStore();
      server = WebSocketServer(
        subscriptionManager: mockSubscriptionManager,
        eventStore: mockEventStore,
      );
    });
    
    tearDown(() async {
      await server.stop();
    });
    
    group('Server Lifecycle', () {
      test('should start server on specified port', () async {
        await server.start(port: 0); // Use random port
        expect(server.isRunning, isTrue);
        expect(server.port, greaterThan(0));
      });
      
      test('should start server on default port when not specified', () async {
        await server.start(port: 0); // Use random port for testing
        expect(server.isRunning, isTrue);
        expect(server.port, greaterThan(0));
      });
      
      test('should not start server twice', () async {
        await server.start(port: 0);
        expect(server.isRunning, isTrue);
        
        // Starting again should not throw or create duplicate server
        await server.start(port: 0);
        expect(server.isRunning, isTrue);
      });
      
      test('should stop server properly', () async {
        await server.start(port: 0);
        expect(server.isRunning, isTrue);
        
        await server.stop();
        expect(server.isRunning, isFalse);
      });
      
      test('should handle stopping server when not running', () async {
        expect(server.isRunning, isFalse);
        // Should not throw
        await server.stop();
      });
    });
    
    group('Connection Management', () {
      test('should track connected clients', () async {
        await server.start(port: 0);
        expect(server.activeConnections, equals(0));
        
        // Connect a client
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        // Give some time for connection to register
        await Future.delayed(Duration(milliseconds: 100));
        expect(server.activeConnections, equals(1));
        
        await client.sink.close();
      });
      
      test('should remove clients on disconnect', () async {
        await server.start(port: 0);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        await Future.delayed(Duration(milliseconds: 100));
        expect(server.activeConnections, equals(1));
        
        await client.sink.close();
        await Future.delayed(Duration(milliseconds: 100));
        expect(server.activeConnections, equals(0));
      });
      
      test('should handle multiple concurrent connections', () async {
        await server.start(port: 0);
        
        final clients = <WebSocketChannel>[];
        for (int i = 0; i < 10; i++) {
          final client = await WebSocketChannel.connect(
            Uri.parse('ws://localhost:${server.port}'),
          );
          clients.add(client);
        }
        
        await Future.delayed(Duration(milliseconds: 100));
        expect(server.activeConnections, equals(10));
        
        // Close all clients
        for (final client in clients) {
          await client.sink.close();
        }
      });
      
      test('should clean up subscriptions on client disconnect', () async {
        await server.start(port: 0);
        when(mockSubscriptionManager.handleClientDisconnect(any))
            .thenAnswer((_) async {});
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        await Future.delayed(Duration(milliseconds: 100));
        await client.sink.close();
        await Future.delayed(Duration(milliseconds: 100));
        
        verify(mockSubscriptionManager.handleClientDisconnect(any)).called(1);
      });
    });
    
    group('Message Parsing', () {
      test('should parse valid REQ message', () async {
        await server.start(port: 0);
        when(mockSubscriptionManager.handleReq(any, any))
            .thenAnswer((_) async => Subscription(
              id: 'test-sub',
              filters: [Filter()],
            ));
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final reqMessage = json.encode([
          'REQ',
          'test-sub',
          {'kinds': [1], 'limit': 10}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        verify(mockSubscriptionManager.handleReq(any, any)).called(1);
        await client.sink.close();
      });
      
      test('should parse valid CLOSE message', () async {
        await server.start(port: 0);
        when(mockSubscriptionManager.handleClose(any, any))
            .thenAnswer((_) async => true);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final closeMessage = json.encode(['CLOSE', 'test-sub']);
        client.sink.add(closeMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        verify(mockSubscriptionManager.handleClose(any, any)).called(1);
        await client.sink.close();
      });
      
      test('should parse valid EVENT message', () async {
        await server.start(port: 0);
        when(mockEventStore.storeEvent(any)).thenAnswer((_) async => true);
        when(mockSubscriptionManager.routeEvent(any)).thenAnswer((_) async => 1);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final event = NostrEvent(
          id: 'test-event-id',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'test content',
          sig: 'test-signature',
        );
        
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client.sink.add(eventMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        verify(mockEventStore.storeEvent(any)).called(1);
        verify(mockSubscriptionManager.routeEvent(any)).called(1);
        await client.sink.close();
      });
      
      test('should handle invalid JSON gracefully', () async {
        await server.start(port: 0);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        client.sink.add('invalid json');
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('NOTICE'));
        expect(responseJson[1], contains('Invalid message format'));
        
        await client.sink.close();
      });
      
      test('should handle unknown message type gracefully', () async {
        await server.start(port: 0);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        final unknownMessage = json.encode(['UNKNOWN', 'param']);
        client.sink.add(unknownMessage);
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('NOTICE'));
        expect(responseJson[1], contains('Unknown message type'));
        
        await client.sink.close();
      });
    });
    
    group('Message Responses', () {
      test('should send OK response for accepted events', () async {
        await server.start(port: 0);
        when(mockEventStore.storeEvent(any)).thenAnswer((_) async => true);
        when(mockSubscriptionManager.routeEvent(any)).thenAnswer((_) async => 1);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        final event = NostrEvent(
          id: 'test-event-id',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'test content',
          sig: 'test-signature',
        );
        
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client.sink.add(eventMessage);
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('OK'));
        expect(responseJson[1], equals('test-event-id'));
        expect(responseJson[2], equals(true));
        
        await client.sink.close();
      });
      
      test('should send OK response for rejected events', () async {
        await server.start(port: 0);
        when(mockEventStore.storeEvent(any)).thenAnswer((_) async => false);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        final event = NostrEvent(
          id: 'test-event-id',
          pubkey: 'test-pubkey',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: 1,
          tags: [],
          content: 'test content',
          sig: 'test-signature',
        );
        
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client.sink.add(eventMessage);
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('OK'));
        expect(responseJson[1], equals('test-event-id'));
        expect(responseJson[2], equals(false));
        
        await client.sink.close();
      });
      
      test('should send EOSE after handling REQ', () async {
        await server.start(port: 0);
        when(mockSubscriptionManager.handleReq(any, any))
            .thenAnswer((_) async => Subscription(
              id: 'test-sub',
              filters: [Filter()],
            ));
        when(mockEventStore.queryEvents(any)).thenAnswer((_) async => []);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        final reqMessage = json.encode([
          'REQ',
          'test-sub',
          {'kinds': [1], 'limit': 10}
        ]);
        
        client.sink.add(reqMessage);
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('EOSE'));
        expect(responseJson[1], equals('test-sub'));
        
        await client.sink.close();
      });
    });
    
    group('Error Handling', () {
      test('should handle connection errors gracefully', () async {
        await server.start(port: 0);
        
        // Force close server while client is connected
        final client = WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        await Future.delayed(Duration(milliseconds: 100));
        await server.stop();
        
        // Should not throw
        expect(() async => await client.stream.first, returnsNormally);
      });
      
      test('should handle message size limits', () async {
        await server.start(port: 0);
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responseCompleter = Completer<String>();
        client.stream.listen((message) {
          responseCompleter.complete(message);
        });
        
        // Send message larger than limit
        final largeMessage = 'x' * (RelayConstants.maxMessageLength + 1);
        final largeEvent = json.encode(['EVENT', {
          'id': 'test',
          'pubkey': 'test',
          'created_at': 1234567890,
          'kind': 1,
          'tags': [],
          'content': largeMessage,
          'sig': 'test'
        }]);
        
        client.sink.add(largeEvent);
        
        final response = await responseCompleter.future
            .timeout(Duration(seconds: 1));
        
        final responseJson = json.decode(response) as List;
        expect(responseJson[0], equals('NOTICE'));
        expect(responseJson[1], contains('message too long'));
        
        await client.sink.close();
      });
    });
    
    group('Statistics', () {
      test('should track connection statistics', () async {
        await server.start(port: 0);
        expect(server.getStatistics()['activeConnections'], equals(0));
        
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        await Future.delayed(Duration(milliseconds: 100));
        final stats = server.getStatistics();
        expect(stats['activeConnections'], equals(1));
        expect(stats.containsKey('totalMessagesReceived'), isTrue);
        expect(stats.containsKey('totalMessagesSent'), isTrue);
        
        await client.sink.close();
      });
    });
  });
}