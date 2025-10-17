// ABOUTME: Comprehensive tests for SubscriptionManager class
// ABOUTME: Tests REQ/CLOSE message handling, event routing, and performance
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_message.dart';
import 'package:flutter_embedded_nostr_relay/src/models/subscription.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';

void main() {
  group('SubscriptionManager', () {
    late SubscriptionManager subscriptionManager;
    
    setUp(() {
      subscriptionManager = SubscriptionManager();
    });
    
    tearDown(() async {
      await subscriptionManager.close();
    });
    
    group('REQ message handling', () {
      test('should create subscription for REQ message', () async {
        final clientId = 'client1';
        final reqMessage = ReqMessage(
          subscriptionId: 'sub1',
          filters: [
            Filter(kinds: [1], limit: 10),
          ],
        );
        
        final subscription = await subscriptionManager.handleReq(clientId, reqMessage);
        
        expect(subscription, isNotNull);
        expect(subscription.id, 'sub1');
        expect(subscription.filters.length, 1);
        expect(subscription.filters.first.kinds, [1]);
        expect(subscription.filters.first.limit, 10);
      });
      
      test('should update existing subscription on duplicate REQ', () async {
        final clientId = 'client1';
        final subscriptionId = 'sub1';
        
        // Create initial subscription
        final firstReq = ReqMessage(
          subscriptionId: subscriptionId,
          filters: [Filter(kinds: [1])],
        );
        final sub1 = await subscriptionManager.handleReq(clientId, firstReq);
        
        // Update with new filters
        final secondReq = ReqMessage(
          subscriptionId: subscriptionId,
          filters: [Filter(kinds: [1, 2], limit: 5)],
        );
        final sub2 = await subscriptionManager.handleReq(clientId, secondReq);
        
        expect(sub2.id, subscriptionId);
        expect(sub2.filters.length, 1);
        expect(sub2.filters.first.kinds, [1, 2]);
        expect(sub2.filters.first.limit, 5);
        
        // Should not have duplicate subscriptions
        final subscriptions = subscriptionManager.getSubscriptionsForClient(clientId);
        expect(subscriptions.length, 1);
        expect(subscriptions.first.id, subscriptionId);
      });
      
      test('should allow multiple subscriptions per client', () async {
        final clientId = 'client1';
        
        final req1 = ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        );
        final req2 = ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [2])],
        );
        
        await subscriptionManager.handleReq(clientId, req1);
        await subscriptionManager.handleReq(clientId, req2);
        
        final subscriptions = subscriptionManager.getSubscriptionsForClient(clientId);
        expect(subscriptions.length, 2);
        expect(subscriptions.map((s) => s.id), containsAll(['sub1', 'sub2']));
      });
      
      test('should isolate subscriptions between clients', () async {
        final req = ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        );
        
        await subscriptionManager.handleReq('client1', req);
        await subscriptionManager.handleReq('client2', req);
        
        final client1Subs = subscriptionManager.getSubscriptionsForClient('client1');
        final client2Subs = subscriptionManager.getSubscriptionsForClient('client2');
        
        expect(client1Subs.length, 1);
        expect(client2Subs.length, 1);
        expect(client1Subs.first.id, 'sub1');
        expect(client2Subs.first.id, 'sub1');
        expect(identical(client1Subs.first, client2Subs.first), false);
      });
    });
    
    group('CLOSE message handling', () {
      test('should remove subscription on CLOSE message', () async {
        final clientId = 'client1';
        final subscriptionId = 'sub1';
        
        // Create subscription
        final reqMessage = ReqMessage(
          subscriptionId: subscriptionId,
          filters: [Filter(kinds: [1])],
        );
        await subscriptionManager.handleReq(clientId, reqMessage);
        
        expect(subscriptionManager.getSubscriptionsForClient(clientId).length, 1);
        
        // Close subscription
        final closeMessage = CloseMessage(subscriptionId: subscriptionId);
        final closed = await subscriptionManager.handleClose(clientId, closeMessage);
        
        expect(closed, true);
        expect(subscriptionManager.getSubscriptionsForClient(clientId).length, 0);
      });
      
      test('should return false for non-existent subscription', () async {
        final clientId = 'client1';
        final closeMessage = CloseMessage(subscriptionId: 'nonexistent');
        
        final closed = await subscriptionManager.handleClose(clientId, closeMessage);
        
        expect(closed, false);
      });
      
      test('should only close subscription for correct client', () async {
        final subscriptionId = 'sub1';
        final req = ReqMessage(
          subscriptionId: subscriptionId,
          filters: [Filter(kinds: [1])],
        );
        
        // Create subscription for both clients
        await subscriptionManager.handleReq('client1', req);
        await subscriptionManager.handleReq('client2', req);
        
        // Close subscription for client1 only
        final closeMessage = CloseMessage(subscriptionId: subscriptionId);
        await subscriptionManager.handleClose('client1', closeMessage);
        
        expect(subscriptionManager.getSubscriptionsForClient('client1').length, 0);
        expect(subscriptionManager.getSubscriptionsForClient('client2').length, 1);
      });
    });
    
    group('Event routing', () {
      test('should route events to matching subscriptions', () async {
        final clientId = 'client1';
        final receivedEvents = <String, NostrEvent>{};
        
        // Create subscription with event handler
        final subscription = await subscriptionManager.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        
        // Listen to subscription events
        subscription.eventStream.listen((event) {
          receivedEvents[subscription.id] = event;
        });
        
        // Create matching event
        final event = NostrEvent.create(
          pubkey: '0' * 64,
          kind: 1,
          tags: [],
          content: 'Test event',
          createdAt: 1000,
        );
        
        // Route event
        final routedCount = await subscriptionManager.routeEvent(event);
        
        expect(routedCount, 1);
        await Future.delayed(Duration(milliseconds: 10)); // Allow async processing
        expect(receivedEvents.containsKey('sub1'), true);
        expect(receivedEvents['sub1']!.content, 'Test event');
      });
      
      test('should not route events to non-matching subscriptions', () async {
        final clientId = 'client1';
        final receivedEvents = <String, NostrEvent>{};
        
        // Create subscription for kind 2 events
        final subscription = await subscriptionManager.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [2])],
        ));
        
        subscription.eventStream.listen((event) {
          receivedEvents[subscription.id] = event;
        });
        
        // Create kind 1 event (doesn't match)
        final event = NostrEvent.create(
          pubkey: '0' * 64,
          kind: 1,
          tags: [],
          content: 'Test event',
          createdAt: 1000,
        );
        
        final routedCount = await subscriptionManager.routeEvent(event);
        
        expect(routedCount, 0);
        await Future.delayed(Duration(milliseconds: 10));
        expect(receivedEvents.isEmpty, true);
      });
      
      test('should route events to multiple matching subscriptions', () async {
        final receivedEvents = <String, NostrEvent>{};
        
        // Create multiple subscriptions for the same filter
        final sub1 = await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        
        final sub2 = await subscriptionManager.handleReq('client2', ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [1])],
        ));
        
        // Listen to both subscriptions
        sub1.eventStream.listen((event) => receivedEvents['sub1'] = event);
        sub2.eventStream.listen((event) => receivedEvents['sub2'] = event);
        
        final event = NostrEvent.create(
          pubkey: '0' * 64,
          kind: 1,
          tags: [],
          content: 'Test event',
          createdAt: 1000,
        );
        
        final routedCount = await subscriptionManager.routeEvent(event);
        
        expect(routedCount, 2);
        await Future.delayed(Duration(milliseconds: 10));
        expect(receivedEvents.length, 2);
        expect(receivedEvents['sub1']!.content, 'Test event');
        expect(receivedEvents['sub2']!.content, 'Test event');
      });
    });
    
    group('Client connection management', () {
      test('should remove all subscriptions when client disconnects', () async {
        final clientId = 'client1';
        
        // Create multiple subscriptions
        await subscriptionManager.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        await subscriptionManager.handleReq(clientId, ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [2])],
        ));
        
        expect(subscriptionManager.getSubscriptionsForClient(clientId).length, 2);
        
        // Disconnect client
        await subscriptionManager.handleClientDisconnect(clientId);
        
        expect(subscriptionManager.getSubscriptionsForClient(clientId).length, 0);
      });
      
      test('should not affect other clients when one disconnects', () async {
        // Create subscriptions for multiple clients
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        await subscriptionManager.handleReq('client2', ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [2])],
        ));
        
        // Disconnect client1
        await subscriptionManager.handleClientDisconnect('client1');
        
        expect(subscriptionManager.getSubscriptionsForClient('client1').length, 0);
        expect(subscriptionManager.getSubscriptionsForClient('client2').length, 1);
      });
      
      test('should return correct active clients count', () async {
        expect(subscriptionManager.getActiveClientsCount(), 0);
        
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        expect(subscriptionManager.getActiveClientsCount(), 1);
        
        await subscriptionManager.handleReq('client2', ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [2])],
        ));
        expect(subscriptionManager.getActiveClientsCount(), 2);
        
        // Multiple subscriptions from same client shouldn't increase count
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub3',
          filters: [Filter(kinds: [3])],
        ));
        expect(subscriptionManager.getActiveClientsCount(), 2);
        
        await subscriptionManager.handleClientDisconnect('client1');
        expect(subscriptionManager.getActiveClientsCount(), 1);
      });
    });
    
    group('Performance', () {
      test('should handle 1000 subscriptions efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Create 1000 subscriptions across 100 clients
        for (int clientIndex = 0; clientIndex < 100; clientIndex++) {
          final clientId = 'client$clientIndex';
          for (int subIndex = 0; subIndex < 10; subIndex++) {
            await subscriptionManager.handleReq(clientId, ReqMessage(
              subscriptionId: 'sub${clientIndex}_$subIndex',
              filters: [Filter(kinds: [1], authors: ['author$subIndex'])],
            ));
          }
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Setup should be fast
        
        // Test event routing performance
        final event = NostrEvent.create(
          pubkey: 'author5', // Will match 100 subscriptions (one from each client)
          kind: 1,
          tags: [],
          content: 'Performance test event',
          createdAt: 1000,
        );
        
        final routingStopwatch = Stopwatch()..start();
        final routedCount = await subscriptionManager.routeEvent(event);
        routingStopwatch.stop();
        
        expect(routedCount, 100); // Should match 100 subscriptions
        expect(routingStopwatch.elapsedMilliseconds, lessThan(10)); // <10ms requirement
      });
      
      test('should maintain performance with complex filters', () async {
        // Create subscriptions with complex filters
        for (int i = 0; i < 100; i++) {
          await subscriptionManager.handleReq('client$i', ReqMessage(
            subscriptionId: 'sub$i',
            filters: [
              Filter(
                kinds: [1, 2, 3, 4, 5],
                authors: List.generate(20, (index) => 'author${i}_$index'),
                since: 1000,
                until: 2000,
                eTags: ['event1', 'event2'],
                pTags: ['pubkey1', 'pubkey2'],
                limit: 50,
              ),
            ],
          ));
        }
        
        // Test with matching event
        final event = NostrEvent.create(
          pubkey: 'author50_10', // Will match subscription for client50
          kind: 3,
          tags: [
            ['e', 'event1'],
            ['p', 'pubkey1'],
          ],
          content: 'Complex filter test',
          createdAt: 1500,
        );
        
        final stopwatch = Stopwatch()..start();
        final routedCount = await subscriptionManager.routeEvent(event);
        stopwatch.stop();
        
        expect(routedCount, 1);
        expect(stopwatch.elapsedMilliseconds, lessThan(10));
      });
    });
    
    group('Statistics and monitoring', () {
      test('should provide accurate subscription statistics', () async {
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub2',
          filters: [Filter(kinds: [2])],
        ));
        await subscriptionManager.handleReq('client2', ReqMessage(
          subscriptionId: 'sub3',
          filters: [Filter(kinds: [1])],
        ));
        
        final stats = subscriptionManager.getStatistics();
        
        expect(stats['totalSubscriptions'], 3);
        expect(stats['activeClients'], 2);
        expect(stats['subscriptionsPerClient'], {
          'client1': 2,
          'client2': 1,
        });
      });
      
      test('should track event routing metrics', () async {
        await subscriptionManager.handleReq('client1', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));
        
        final event = NostrEvent.create(
          pubkey: '0' * 64,
          kind: 1,
          tags: [],
          content: 'Test event',
          createdAt: 1000,
        );
        
        await subscriptionManager.routeEvent(event);
        await subscriptionManager.routeEvent(event);
        
        final stats = subscriptionManager.getStatistics();
        
        expect(stats['totalEventsRouted'], 2);
        expect(stats['totalMatchingSubscriptions'], 2);
      });
    });
    
    group('Error handling', () {
      test('should handle invalid subscription IDs gracefully', () async {
        expect(() async {
          await subscriptionManager.handleReq('client1', ReqMessage(
            subscriptionId: '',
            filters: [Filter(kinds: [1])],
          ));
        }, throwsArgumentError);
      });
      
      test('should handle empty filters list', () async {
        expect(() async {
          await subscriptionManager.handleReq('client1', ReqMessage(
            subscriptionId: 'sub1',
            filters: [],
          ));
        }, throwsArgumentError);
      });
      
      test('should handle null client ID gracefully', () async {
        expect(() async {
          await subscriptionManager.handleReq('', ReqMessage(
            subscriptionId: 'sub1',
            filters: [Filter(kinds: [1])],
          ));
        }, throwsArgumentError);
      });
    });
  });
}