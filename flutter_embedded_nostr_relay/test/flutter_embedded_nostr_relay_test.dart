// ABOUTME: Basic unit tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests core functionality including event storage and retrieval

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Enable test mode for database
  setUpAll(() {
    DatabaseHelper.enableTestMode();
  });
  group('NostrEvent', () {
    test('creates valid event', () {
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Hello Nostr!',
      );
      
      expect(event.id.length, 64);
      expect(event.pubkey, '0' * 64);
      expect(event.kind, 1);
      expect(event.content, 'Hello Nostr!');
      expect(event.tags, isEmpty);
      expect(event.sig, isEmpty); // Not signed yet
    });
    
    test('identifies replaceable events correctly', () {
      final regular = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'test',
      );
      expect(regular.isReplaceable, false);
      
      final replaceable = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 10002,
        tags: [],
        content: 'test',
      );
      expect(replaceable.isReplaceable, true);
      
      final parameterized = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 30023,
        tags: [['d', 'identifier']],
        content: 'test',
      );
      expect(parameterized.isParameterizedReplaceable, true);
      expect(parameterized.dTagValue, 'identifier');
    });
  });
  
  group('Filter', () {
    test('matches events correctly', () {
      final filter = Filter(
        kinds: [1],
        authors: ['pubkey1', 'pubkey2'],
        since: 1000,
        until: 2000,
      );
      
      final matchingEvent = {
        'id': 'test',
        'pubkey': 'pubkey1',
        'created_at': 1500,
        'kind': 1,
        'tags': [],
        'content': 'test',
        'sig': 'sig',
      };
      
      expect(filter.matches(matchingEvent), true);
      
      final nonMatchingEvent = {
        'id': 'test2',
        'pubkey': 'pubkey3',
        'created_at': 1500,
        'kind': 1,
        'tags': [],
        'content': 'test',
        'sig': 'sig',
      };
      
      expect(filter.matches(nonMatchingEvent), false);
    });
    
    test('handles tag filters', () {
      final filter = Filter(
        eTags: ['event1', 'event2'],
      );
      
      final matchingEvent = {
        'id': 'test',
        'pubkey': 'pubkey',
        'created_at': 1500,
        'kind': 1,
        'tags': [['e', 'event1']],
        'content': 'test',
        'sig': 'sig',
      };
      
      expect(filter.matches(matchingEvent), true);
    });
  });
  
  group('EmbeddedNostrRelay', () {
    late EmbeddedNostrRelay relay;
    
    setUp(() async {
      await DatabaseHelper.reset(); // Reset database between tests
      relay = EmbeddedNostrRelay();
      await relay.initialize();
    });
    
    tearDown(() async {
      await relay.shutdown();
    });
    
    test('initializes successfully', () async {
      expect(relay.getRelayInfo().name, 'Flutter Embedded Nostr Relay');
    });
    
    test('publishes and retrieves events', () async {
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Test event',
      );
      
      // Add dummy signature for test
      final signedEvent = event.copyWith(sig: 'test_signature');
      
      final published = await relay.publish(signedEvent);
      expect(published, true);
      
      final retrieved = await relay.getEvent(signedEvent.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, signedEvent.id);
      expect(retrieved.content, 'Test event');
    });
    
    test('queries events with filters', () async {
      // Publish test events
      for (int i = 0; i < 5; i++) {
        final event = NostrEvent.create(
          pubkey: '0' * 64,
          kind: 1,
          tags: [],
          content: 'Event $i',
          createdAt: 1000 + i,
        );
        // Add dummy signature for test
        final signedEvent = event.copyWith(sig: 'test_signature_$i');
        await relay.publish(signedEvent);
      }
      
      // Query with filter
      final events = await relay.queryEvents([
        Filter(
          kinds: [1],
          since: 1002,
          limit: 2,
        ),
      ]);
      
      expect(events.length, 2);
      expect(events.first.createdAt, greaterThanOrEqualTo(1002));
    });
    
    test('handles subscriptions', () async {
      final receivedEvents = <NostrEvent>[];
      var eoseReceived = false;
      
      final subscription = relay.subscribe(
        filters: [Filter(kinds: [1])],
        onEvent: (event) => receivedEvents.add(event),
        onEose: () => eoseReceived = true,
      );
      
      // Wait for EOSE
      await Future.delayed(Duration(milliseconds: 100));
      expect(eoseReceived, true);
      
      // Publish new event
      final event = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 1,
        tags: [],
        content: 'Live event',
      );
      // Add dummy signature for test
      final signedEvent = event.copyWith(sig: 'test_signature_live');
      await relay.publish(signedEvent);
      
      // Wait for event propagation
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(receivedEvents.any((e) => e.content == 'Live event'), true);
      
      await relay.unsubscribe(subscription.id);
    });
  });
}
