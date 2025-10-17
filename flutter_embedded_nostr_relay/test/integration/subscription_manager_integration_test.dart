// ABOUTME: Integration tests for SubscriptionManager with EmbeddedNostrRelay
// ABOUTME: Tests REQ/CLOSE message flow and client connection management
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/core/embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_message.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Enable test mode for database
  setUpAll(() {
    DatabaseHelper.enableTestMode();
  });

  group('SubscriptionManager Integration', () {
    late EmbeddedNostrRelay relay;
    
    setUp(() async {
      await DatabaseHelper.reset(); // Reset database between tests
      relay = EmbeddedNostrRelay();
      await relay.initialize();
    });
    
    tearDown(() async {
      await relay.shutdown();
    });
    
    test('should handle REQ message and route events correctly', () async {
      final clientId = 'websocket_client_1';
      final receivedEvents = <NostrEvent>[];
      
      // Create REQ message
      final reqMessage = ReqMessage(
        subscriptionId: 'test_sub',
        filters: [
          Filter(kinds: [1], limit: 10),
        ],
      );
      
      // Handle REQ message
      final subscription = await relay.handleReq(clientId, reqMessage);
      
      // Listen to events
      subscription.eventStream.listen((event) {
        receivedEvents.add(event);
      });
      
      // Wait for initial query to complete
      await Future.delayed(Duration(milliseconds: 100));
      
      // Publish a matching event
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Integration test event',
        createdAt: 1000,
      );
      final signedEvent = event.copyWith(sig: 'test_signature');
      
      await relay.publish(signedEvent);
      
      // Wait for event routing
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(receivedEvents.length, 1);
      expect(receivedEvents.first.content, 'Integration test event');
      
      // Verify statistics
      final stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 1);
      expect(stats['activeClients'], 1);
      expect(stats['totalEventsRouted'], 1);
    });
    
    test('should handle CLOSE message correctly', () async {
      final clientId = 'websocket_client_1';
      
      // Create subscription
      final reqMessage = ReqMessage(
        subscriptionId: 'test_sub',
        filters: [Filter(kinds: [1])],
      );
      await relay.handleReq(clientId, reqMessage);
      
      // Verify subscription exists
      var stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 1);
      expect(stats['activeClients'], 1);
      
      // Close subscription
      final closeMessage = CloseMessage(subscriptionId: 'test_sub');
      final closed = await relay.handleClose(clientId, closeMessage);
      
      expect(closed, true);
      
      // Verify subscription removed
      stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 0);
      expect(stats['activeClients'], 0);
    });
    
    test('should handle client disconnect', () async {
      final clientId = 'websocket_client_1';
      
      // Create multiple subscriptions
      await relay.handleReq(clientId, ReqMessage(
        subscriptionId: 'sub1',
        filters: [Filter(kinds: [1])],
      ));
      await relay.handleReq(clientId, ReqMessage(
        subscriptionId: 'sub2',
        filters: [Filter(kinds: [2])],
      ));
      
      // Verify subscriptions exist
      var stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 2);
      expect(stats['activeClients'], 1);
      
      // Disconnect client
      await relay.handleClientDisconnect(clientId);
      
      // Verify all subscriptions removed
      stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 0);
      expect(stats['activeClients'], 0);
    });
    
    test('should isolate subscriptions between clients', () async {
      final receivedEventsClient1 = <NostrEvent>[];
      final receivedEventsClient2 = <NostrEvent>[];
      
      // Create subscriptions for different clients
      final sub1 = await relay.handleReq('client1', ReqMessage(
        subscriptionId: 'sub1',
        filters: [Filter(kinds: [1])],
      ));
      
      final sub2 = await relay.handleReq('client2', ReqMessage(
        subscriptionId: 'sub2',
        filters: [Filter(kinds: [2])],
      ));
      
      sub1.eventStream.listen((event) => receivedEventsClient1.add(event));
      sub2.eventStream.listen((event) => receivedEventsClient2.add(event));
      
      // Wait for initial queries
      await Future.delayed(Duration(milliseconds: 100));
      
      // Publish kind 1 event
      final event1 = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Kind 1 event',
        createdAt: 1000,
      );
      await relay.publish(event1.copyWith(sig: 'sig1'));
      
      // Publish kind 2 event
      final event2 = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 2,
        tags: [],
        content: 'Kind 2 event',
        createdAt: 1001,
      );
      await relay.publish(event2.copyWith(sig: 'sig2'));
      
      await Future.delayed(Duration(milliseconds: 100));
      
      // Verify correct routing
      expect(receivedEventsClient1.length, 1);
      expect(receivedEventsClient1.first.content, 'Kind 1 event');
      
      expect(receivedEventsClient2.length, 1);
      expect(receivedEventsClient2.first.content, 'Kind 2 event');
      
      // Verify statistics
      final stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 2);
      expect(stats['activeClients'], 2);
      expect(stats['totalEventsRouted'], 2);
      expect(stats['totalMatchingSubscriptions'], 2);
    });
    
    test('should maintain performance with multiple clients and subscriptions', () async {
      final stopwatch = Stopwatch()..start();
      
      // Create 50 clients with 2 subscriptions each
      for (int clientIndex = 0; clientIndex < 50; clientIndex++) {
        final clientId = 'client$clientIndex';
        
        await relay.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub1_$clientIndex',
          filters: [Filter(kinds: [1])],
        ));
        
        await relay.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub2_$clientIndex',
          filters: [Filter(kinds: [2])],
        ));
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Setup should be fast
      
      // Verify stats
      final stats = relay.getSubscriptionStats();
      expect(stats['totalSubscriptions'], 100);
      expect(stats['activeClients'], 50);
      
      // Test event routing performance
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Performance test event',
        createdAt: 1000,
      );
      
      final routingStopwatch = Stopwatch()..start();
      await relay.publish(event.copyWith(sig: 'perf_sig'));
      routingStopwatch.stop();
      
      // Should route to 50 subscriptions (one per client for kind 1)
      expect(routingStopwatch.elapsedMilliseconds, lessThan(50)); // Integration test allows more time for DB operations
      
      final finalStats = relay.getSubscriptionStats();
      expect(finalStats['totalEventsRouted'], 1);
      expect(finalStats['totalMatchingSubscriptions'], 50);
    });
    
    test('should work alongside legacy subscription API', () async {
      final legacyEvents = <NostrEvent>[];
      final managedEvents = <NostrEvent>[];
      
      // Create legacy subscription
      final legacySub = relay.subscribe(
        filters: [Filter(kinds: [1])],
        onEvent: (event) => legacyEvents.add(event),
      );
      
      // Create managed subscription
      final managedSub = await relay.handleReq('client1', ReqMessage(
        subscriptionId: 'managed_sub',
        filters: [Filter(kinds: [1])],
      ));
      
      managedSub.eventStream.listen((event) => managedEvents.add(event));
      
      // Wait for initial queries
      await Future.delayed(Duration(milliseconds: 100));
      
      // Publish event
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Dual API test',
        createdAt: 1000,
      );
      await relay.publish(event.copyWith(sig: 'dual_sig'));
      
      await Future.delayed(Duration(milliseconds: 100));
      
      // Both should receive the event
      expect(legacyEvents.length, 1);
      expect(managedEvents.length, 1);
      expect(legacyEvents.first.content, 'Dual API test');
      expect(managedEvents.first.content, 'Dual API test');
      
      // Verify statistics show both
      final stats = relay.getSubscriptionStats();
      expect(stats['internalSubscriptions'], 1); // Legacy subscription
      expect(stats['totalSubscriptions'], 1); // Managed subscription
    });
    
    test('should handle complex filter combinations', () async {
      final receivedEvents = <NostrEvent>[];
      
      // Create subscription with complex filter
      final subscription = await relay.handleReq('client1', ReqMessage(
        subscriptionId: 'complex_sub',
        filters: [
          Filter(
            kinds: [1, 2],
            authors: ['author1', 'author2'],
            since: 1000,
            until: 2000,
            eTags: ['event1'],
            limit: 20,
          ),
        ],
      ));
      
      subscription.eventStream.listen((event) => receivedEvents.add(event));
      
      await Future.delayed(Duration(milliseconds: 100));
      
      // Publish matching event
      final matchingEvent = NostrEvent.create(
        pubkey: 'author1',
        kind: 1,
        tags: [['e', 'event1']],
        content: 'Complex filter match',
        createdAt: 1500,
      );
      await relay.publish(matchingEvent.copyWith(sig: 'complex_sig'));
      
      // Publish non-matching event (wrong kind)
      final nonMatchingEvent = NostrEvent.create(
        pubkey: 'author1',
        kind: 3,
        tags: [['e', 'event1']],
        content: 'Should not match',
        createdAt: 1500,
      );
      await relay.publish(nonMatchingEvent.copyWith(sig: 'non_match_sig'));
      
      await Future.delayed(Duration(milliseconds: 100));
      
      // Only the matching event should be received
      expect(receivedEvents.length, 1);
      expect(receivedEvents.first.content, 'Complex filter match');
    });
  });
}