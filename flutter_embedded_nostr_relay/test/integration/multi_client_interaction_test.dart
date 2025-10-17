// ABOUTME: Multi-client interaction integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests complex scenarios involving multiple WebSocket clients with concurrent operations

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestClient {
  final WebSocketChannel channel;  
  final String id;
  final List<String> responses = [];
  final Completer<void> _disconnectCompleter = Completer<void>();
  late StreamSubscription _subscription;
  
  TestClient(this.channel, this.id) {
    _subscription = channel.stream.listen(
      (message) {
        responses.add(message);
      },
      onDone: () {
        if (!_disconnectCompleter.isCompleted) {
          _disconnectCompleter.complete();
        }
      },
    );
  }
  
  void send(dynamic message) {
    channel.sink.add(json.encode(message));
  }
  
  Future<void> close() async {
    await channel.sink.close();
    await _subscription.cancel();
    if (!_disconnectCompleter.isCompleted) {
      _disconnectCompleter.complete();
    }
  }
  
  Future<void> waitForDisconnect() => _disconnectCompleter.future;
  
  List<Map<String, dynamic>> getEventResponses(String subscriptionId) {
    return responses
        .where((response) {
          final parsed = json.decode(response) as List;
          return parsed[0] == 'EVENT' && parsed[1] == subscriptionId;
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return parsed[2] as Map<String, dynamic>;
        })
        .toList();
  }
  
  List<Map<String, dynamic>> getOkResponses() {
    return responses
        .where((response) {
          final parsed = json.decode(response) as List;
          return parsed[0] == 'OK';
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return {
            'eventId': parsed[1],
            'accepted': parsed[2],
            'message': parsed.length > 3 ? parsed[3] : '',
          };
        })
        .toList();
  }
  
  bool hasReceivedEose(String subscriptionId) {
    return responses.any((response) {
      final parsed = json.decode(response) as List;
      return parsed[0] == 'EOSE' && parsed[1] == subscriptionId;
    });
  }
  
  void clearResponses() {
    responses.clear();
  }
}

void main() {
  group('Multi-Client Interaction Tests', () {
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

    Future<TestClient> createTestClient(String id) async {
      final channel = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );
      return TestClient(channel, id);
    }

    group('Concurrent Subscriptions', () {
      test('should handle multiple clients with overlapping subscriptions', () async {
        final clients = <TestClient>[];
        
        try {
          // Create 5 clients
          for (int i = 0; i < 5; i++) {
            clients.add(await createTestClient('client$i'));
          }
          
          // Each client subscribes to different but overlapping filters
          clients[0].send(['REQ', 'sub0', {'kinds': [1], 'limit': 100}]); // All text notes
          clients[1].send(['REQ', 'sub1', {'kinds': [1, 7], 'limit': 50}]); // Text notes and reactions
          clients[2].send(['REQ', 'sub2', {'authors': ['author1'], 'limit': 25}]); // Specific author
          clients[3].send(['REQ', 'sub3', {'#t': ['nostr'], 'limit': 30}]); // Specific tag
          clients[4].send(['REQ', 'sub4', {'kinds': [1], '#t': ['test'], 'limit': 20}]); // Text notes with test tag
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify all clients received EOSE
          for (int i = 0; i < 5; i++) {
            expect(clients[i].hasReceivedEose('sub$i'), isTrue);
          }
          
          // Send events that match different combinations of subscriptions
          final events = [
            // Matches clients 0, 1, 4
            NostrEvent.create(
              pubkey: 'author2',
              kind: 1,
              tags: [['t', 'test']],
              content: 'Text note with test tag',
            ).copyWith(sig: 'sig1' + '1' * 120),
            
            // Matches clients 0, 1, 2
            NostrEvent.create(
              pubkey: 'author1',
              kind: 1,
              tags: [['t', 'other']],
              content: 'Text note from author1',
            ).copyWith(sig: 'sig2' + '2' * 120),
            
            // Matches clients 1 only (reaction)
            NostrEvent.create(
              pubkey: 'author3',
              kind: 7,
              tags: [['e', 'some-event-id']],
              content: '+',
            ).copyWith(sig: 'sig3' + '3' * 120),
            
            // Matches clients 0, 1, 3
            NostrEvent.create(
              pubkey: 'author4',
              kind: 1,
              tags: [['t', 'nostr']],
              content: 'Text note about nostr',
            ).copyWith(sig: 'sig4' + '4' * 120),
          ];
          
          // Clear previous responses
          for (final client in clients) {
            client.clearResponses();
          }
          
          // Send events from different clients
          for (int i = 0; i < events.length; i++) {
            clients[i % clients.length].send(['EVENT', events[i].toJson()]);
          }
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Verify event distribution
          expect(clients[0].getEventResponses('sub0').length, equals(3)); // Text notes: events 0, 1, 3
          expect(clients[1].getEventResponses('sub1').length, equals(4)); // Text notes + reactions: all events
          expect(clients[2].getEventResponses('sub2').length, equals(1)); // author1: event 1
          expect(clients[3].getEventResponses('sub3').length, equals(1)); // nostr tag: event 3
          expect(clients[4].getEventResponses('sub4').length, equals(1)); // text + test tag: event 0
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });

      test('should handle subscription updates and closes from multiple clients', () async {
        final clients = <TestClient>[];
        
        try {
          // Create 3 clients
          for (int i = 0; i < 3; i++) {
            clients.add(await createTestClient('client$i'));
          }
          
          // Initial subscriptions
          for (int i = 0; i < 3; i++) {
            clients[i].send(['REQ', 'initial-sub', {'kinds': [1], 'limit': 10}]);
          }
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Client 0 updates subscription (same ID, new filter)
          clients[0].send(['REQ', 'initial-sub', {'kinds': [1, 7], 'limit': 20}]);
          
          // Client 1 closes subscription
          clients[1].send(['CLOSE', 'initial-sub']);
          
          // Client 2 creates additional subscription
          clients[2].send(['REQ', 'additional-sub', {'kinds': [2], 'limit': 5}]);
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Send test events
          final events = [
            NostrEvent.create(
              pubkey: 'author1',
              kind: 1,
              tags: [],
              content: 'Text note',
            ).copyWith(sig: 'sig1' + '1' * 120),
            
            NostrEvent.create(
              pubkey: 'author2',
              kind: 7,
              tags: [['e', 'event-id']],
              content: '+',
            ).copyWith(sig: 'sig2' + '2' * 120),
            
            NostrEvent.create(
              pubkey: 'author3',
              kind: 2,
              tags: [['r', 'wss://relay.example.com']],
              content: '',
            ).copyWith(sig: 'sig3' + '3' * 120),
          ];
          
          // Clear responses before sending events
          for (final client in clients) {
            client.clearResponses();
          }
          
          for (final event in events) {
            clients[0].send(['EVENT', event.toJson()]);
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify routing after subscription changes
          final client0Events = clients[0].getEventResponses('initial-sub');
          final client1Events = clients[1].getEventResponses('initial-sub');
          final client2InitialEvents = clients[2].getEventResponses('initial-sub');
          final client2AdditionalEvents = clients[2].getEventResponses('additional-sub');
          
          expect(client0Events.length, equals(2)); // Updated sub: text note + reaction
          expect(client1Events.length, equals(0)); // Closed subscription
          expect(client2InitialEvents.length, equals(1)); // Original sub: text note only
          expect(client2AdditionalEvents.length, equals(1)); // Additional sub: relay recommendation
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });
    });

    group('Event Broadcasting', () {
      test('should broadcast events to all matching subscriptions across clients', () async {
        final publisher = await createTestClient('publisher');
        final subscribers = <TestClient>[];
        
        try {
          // Create 10 subscriber clients
          for (int i = 0; i < 10; i++) {
            subscribers.add(await createTestClient('subscriber$i'));
          }
          
          // All subscribers listen to text notes
          for (int i = 0; i < subscribers.length; i++) {
            subscribers[i].send(['REQ', 'text-notes', {'kinds': [1], 'limit': 100}]);
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Clear setup responses
          for (final subscriber in subscribers) {
            subscriber.clearResponses();
          }
          
          // Publisher sends a text note
          final event = NostrEvent.create(
            pubkey: 'publisher123456789012345678901234567890123456789012345678901234',
            kind: 1,
            tags: [['t', 'broadcast-test']],
            content: 'This should reach all subscribers',
          ).copyWith(sig: 'broadcast_sig' + '1' * 110);
          
          publisher.send(['EVENT', event.toJson()]);
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Verify all subscribers received the event
          for (int i = 0; i < subscribers.length; i++) {
            final receivedEvents = subscribers[i].getEventResponses('text-notes');
            expect(receivedEvents.length, equals(1), 
                   reason: 'Subscriber $i should receive the broadcast event');
            expect(receivedEvents.first['id'], equals(event.id));
            expect(receivedEvents.first['content'], equals('This should reach all subscribers'));
          }
          
          // Verify publisher received OK response
          final okResponses = publisher.getOkResponses();
          expect(okResponses.length, equals(1));
          expect(okResponses.first['accepted'], equals(true));
          
        } finally {
          await publisher.close();
          for (final subscriber in subscribers) {
            await subscriber.close();
          }
        }
      });

      test('should handle selective broadcasting based on different filters', () async {
        final clients = <TestClient>[];
        
        try {
          // Create clients with different subscription patterns
          for (int i = 0; i < 4; i++) {
            clients.add(await createTestClient('client$i'));
          }
          
          // Different subscription filters
          clients[0].send(['REQ', 'all-kinds', {'limit': 100}]); // All events
          clients[1].send(['REQ', 'text-only', {'kinds': [1], 'limit': 50}]); // Text notes only  
          clients[2].send(['REQ', 'author-specific', {'authors': ['specific-author'], 'limit': 30}]); // Specific author
          clients[3].send(['REQ', 'tagged-events', {'#t': ['important'], 'limit': 20}]); // Specific tag
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Clear setup responses
          for (final client in clients) {
            client.clearResponses();
          }
          
          // Send various events
          final events = [
            // Should reach clients 0, 1 (text note, not from specific author, no important tag)
            NostrEvent.create(
              pubkey: 'random-author',
              kind: 1,
              tags: [['t', 'general']],
              content: 'General text note',
            ).copyWith(sig: 'sig1' + '1' * 120),
            
            // Should reach clients 0, 2 (from specific author, but not text note)
            NostrEvent.create(
              pubkey: 'specific-author',
              kind: 7,
              tags: [['e', 'some-event']],
              content: '+',
            ).copyWith(sig: 'sig2' + '2' * 120),
            
            // Should reach clients 0, 1, 2 (text note from specific author)
            NostrEvent.create(
              pubkey: 'specific-author',
              kind: 1,
              tags: [['t', 'general']],
              content: 'Text from specific author',
            ).copyWith(sig: 'sig3' + '3' * 120),
            
            // Should reach clients 0, 3 (has important tag, not text note)
            NostrEvent.create(
              pubkey: 'another-author',
              kind: 2,
              tags: [['t', 'important'], ['r', 'wss://relay.example.com']],
              content: '',
            ).copyWith(sig: 'sig4' + '4' * 120),
            
            // Should reach all clients (text note from specific author with important tag)
            NostrEvent.create(
              pubkey: 'specific-author',
              kind: 1,
              tags: [['t', 'important']],
              content: 'Important text from specific author',
            ).copyWith(sig: 'sig5' + '5' * 120),
          ];
          
          for (final event in events) {
            clients[0].send(['EVENT', event.toJson()]);
          }
          
          await Future.delayed(Duration(milliseconds: 400));
          
          // Verify selective distribution
          expect(clients[0].getEventResponses('all-kinds').length, equals(5)); // All events
          expect(clients[1].getEventResponses('text-only').length, equals(3)); // Events 0, 2, 4 (text notes)
          expect(clients[2].getEventResponses('author-specific').length, equals(3)); // Events 1, 2, 4 (from specific author)
          expect(clients[3].getEventResponses('tagged-events').length, equals(2)); // Events 3, 4 (important tag)
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });
    });

    group('Connection Management', () {
      test('should handle client disconnections gracefully', () async {
        final clients = <TestClient>[];
        
        try {
          // Create 5 clients
          for (int i = 0; i < 5; i++) {
            clients.add(await createTestClient('client$i'));
          }
          
          // All clients subscribe
          for (int i = 0; i < 5; i++) {
            clients[i].send(['REQ', 'test-sub', {'kinds': [1], 'limit': 10}]);
          }
          
          await Future.delayed(Duration(milliseconds: 100));
          expect(server.activeConnections, equals(5));
          
          // Disconnect 2 clients
          await clients[1].close();
          await clients[3].close();
          
          await Future.delayed(Duration(milliseconds: 100));
          expect(server.activeConnections, equals(3));
          
          // Send event - should only reach remaining clients
          for (final client in [clients[0], clients[2], clients[4]]) {
            client.clearResponses();
          }
          
          final event = NostrEvent.create(
            pubkey: 'sender123456789012345678901234567890123456789012345678901234567',
            kind: 1,
            tags: [],
            content: 'After disconnect test',
          ).copyWith(sig: 'disconnect_sig' + '1' * 110);
          
          clients[0].send(['EVENT', event.toJson()]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify only connected clients received the event
          expect(clients[0].getEventResponses('test-sub').length, equals(1));
          expect(clients[2].getEventResponses('test-sub').length, equals(1));
          expect(clients[4].getEventResponses('test-sub').length, equals(1));
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });

      test('should handle rapid connect/disconnect cycles', () async {
        const int cycleCount = 10;
        
        for (int cycle = 0; cycle < cycleCount; cycle++) {
          final client = await createTestClient('cycle-client-$cycle');
          
          try {
            // Subscribe
            client.send(['REQ', 'cycle-sub', {'kinds': [1], 'limit': 5}]);
            await Future.delayed(Duration(milliseconds: 50));
            
            // Send event
            final event = NostrEvent.create(
              pubkey: 'cycle-author',
              kind: 1,
              tags: [],
              content: 'Cycle $cycle message',
            ).copyWith(sig: 'cycle_sig_$cycle' + '1' * (120 - cycle.toString().length));
            
            client.send(['EVENT', event.toJson()]);
            await Future.delayed(Duration(milliseconds: 50));
            
            // Verify responses
            expect(client.hasReceivedEose('cycle-sub'), isTrue);
            final okResponses = client.getOkResponses();
            expect(okResponses.length, equals(1));
            expect(okResponses.first['accepted'], equals(true));
            
          } finally {
            await client.close();
          }
          
          // Brief pause between cycles
          await Future.delayed(Duration(milliseconds: 10));
        }
        
        // Server should be clean after all cycles
        expect(server.activeConnections, equals(0));
      });
    });

    group('Concurrent Event Publishing', () {
      test('should handle simultaneous event publishing from multiple clients', () async {
        final clients = <TestClient>[];
        const int clientCount = 10;
        const int eventsPerClient = 5;
        
        try {
          // Create clients
          for (int i = 0; i < clientCount; i++) {
            clients.add(await createTestClient('publisher$i'));
          }
          
          // One client subscribes to monitor all events
          final monitor = await createTestClient('monitor');
          monitor.send(['REQ', 'monitor-all', {'kinds': [1], 'limit': 1000}]);
          clients.add(monitor);
          
          await Future.delayed(Duration(milliseconds: 100));
          monitor.clearResponses();
          
          // All clients publish events simultaneously
          final publishFutures = <Future>[];
          
          for (int clientIndex = 0; clientIndex < clientCount; clientIndex++) {
            publishFutures.add(() async {
              for (int eventIndex = 0; eventIndex < eventsPerClient; eventIndex++) {
                final event = NostrEvent.create(
                  pubkey: 'publisher$clientIndex' + '0' * (64 - 'publisher$clientIndex'.length),
                  kind: 1,
                  tags: [['client', clientIndex.toString()], ['event', eventIndex.toString()]],
                  content: 'Message $eventIndex from client $clientIndex',
                ).copyWith(sig: 'sig_${clientIndex}_$eventIndex' + '1' * (120 - 'sig_${clientIndex}_$eventIndex'.length));
                
                clients[clientIndex].send(['EVENT', event.toJson()]);
                
                // Small random delay to simulate real-world timing
                await Future.delayed(Duration(milliseconds: Random().nextInt(50)));
              }
            }());
          }
          
          await Future.wait(publishFutures);
          await Future.delayed(Duration(milliseconds: 500)); // Allow processing
          
          // Verify all events were received by monitor
          final monitorEvents = monitor.getEventResponses('monitor-all');
          expect(monitorEvents.length, equals(clientCount * eventsPerClient));
          
          // Verify each client got OK responses for their events
          for (int i = 0; i < clientCount; i++) {
            final okResponses = clients[i].getOkResponses();
            expect(okResponses.length, equals(eventsPerClient));
            
            // All events should be accepted
            for (final okResponse in okResponses) {
              expect(okResponse['accepted'], equals(true));
            }
          }
          
          // Verify event uniqueness (no duplicates)
          final eventIds = monitorEvents.map((e) => e['id']).toSet();
          expect(eventIds.length, equals(clientCount * eventsPerClient));
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });

      test('should maintain event order consistency across clients', () async {
        final publisher = await createTestClient('publisher');
        final subscribers = <TestClient>[];
        
        try {
          // Create multiple subscribers
          for (int i = 0; i < 5; i++) {
            subscribers.add(await createTestClient('subscriber$i'));
          }
          
          // All subscribe to same filter
          for (int i = 0; i < subscribers.length; i++) {
            subscribers[i].send(['REQ', 'ordered-events', {'kinds': [1], 'limit': 100}]);
          }
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Clear setup responses
          for (final subscriber in subscribers) {
            subscriber.clearResponses();
          }
          
          // Publisher sends events in specific order
          final events = <NostrEvent>[];
          for (int i = 0; i < 10; i++) {
            final event = NostrEvent.create(
              pubkey: 'ordered-publisher' + '0' * (64 - 'ordered-publisher'.length),
              kind: 1,
              tags: [['sequence', i.toString()]],
              content: 'Ordered message $i',
            ).copyWith(
              createdAt: DateTime.now().add(Duration(seconds: i)).millisecondsSinceEpoch ~/ 1000,
              sig: 'ordered_sig_$i' + '1' * (120 - 'ordered_sig_$i'.length),
            );
            events.add(event);
            
            publisher.send(['EVENT', event.toJson()]);
            await Future.delayed(Duration(milliseconds: 10)); // Small delay between events
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify all subscribers received events in consistent order
          final firstSubscriberEvents = subscribers[0].getEventResponses('ordered-events');
          expect(firstSubscriberEvents.length, equals(10));
          
          // Extract sequence numbers to verify order
          final firstSubscriberSequence = firstSubscriberEvents
              .map((e) => int.parse((e['tags'] as List).firstWhere((tag) => tag[0] == 'sequence')[1]))
              .toList();
          
          // Verify all other subscribers have the same order
          for (int i = 1; i < subscribers.length; i++) {
            final subscriberEvents = subscribers[i].getEventResponses('ordered-events');
            expect(subscriberEvents.length, equals(10));
            
            final subscriberSequence = subscriberEvents
                .map((e) => int.parse((e['tags'] as List).firstWhere((tag) => tag[0] == 'sequence')[1]))
                .toList();
            
            expect(subscriberSequence, equals(firstSubscriberSequence),
                   reason: 'Subscriber $i should have same event order as subscriber 0');
          }
          
        } finally {
          await publisher.close();
          for (final subscriber in subscribers) {
            await subscriber.close();
          }
        }
      });
    });

    group('Resource Management', () {
      test('should handle maximum concurrent connections', () async {
        final clients = <TestClient>[];
        
        try {
          // Create many clients (but within reasonable limits for testing)
          const int maxTestClients = 50;
          
          for (int i = 0; i < maxTestClients; i++) {
            clients.add(await createTestClient('load-client$i'));
            
            // Each client creates a subscription
            clients[i].send(['REQ', 'load-sub$i', {'kinds': [1], 'limit': 1}]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Verify all connections are active
          expect(server.activeConnections, equals(maxTestClients));
          
          // Send a broadcast event that should reach all clients
          final broadcastEvent = NostrEvent.create(
            pubkey: 'broadcaster' + '0' * (64 - 'broadcaster'.length),
            kind: 1,
            tags: [],
            content: 'Load test broadcast',
          ).copyWith(sig: 'broadcast_load_sig' + '1' * 100);
          
          clients[0].send(['EVENT', broadcastEvent.toJson()]);
          
          await Future.delayed(Duration(milliseconds: 1000)); // Allow more time for processing
          
          // Verify a reasonable number of clients received the event
          int clientsWithEvent = 0;
          for (final client in clients) {
            if (client.getEventResponses('load-sub${clients.indexOf(client)}').isNotEmpty) {
              clientsWithEvent++;
            }
          }
          
          expect(clientsWithEvent, greaterThan(maxTestClients ~/ 2), 
                 reason: 'At least half of clients should receive the broadcast');
          
        } finally {
          // Clean up all clients
          final closeFutures = clients.map((client) => client.close()).toList();
          await Future.wait(closeFutures);
        }
        
        await Future.delayed(Duration(milliseconds: 200));
        expect(server.activeConnections, equals(0));
      });
    });
  });
}