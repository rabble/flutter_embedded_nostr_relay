// ABOUTME: Tests for published_events tracking approach
// ABOUTME: Verifies events are republished until successfully published to external relays

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  group('Published Events Tracking', () {
    late DatabaseHelper dbHelper;
    late EventStore eventStore;

    setUp(() async {
      DatabaseHelper.enableTestMode();
      dbHelper = DatabaseHelper.instance;
      await dbHelper.database; // Initialize
      eventStore = EventStore();
    });

    tearDown(() async {
      // Clean all tables before closing
      final db = await DatabaseHelper.instance.database;
      await db.delete('published_events');
      await db.delete('events');
      await db.delete('tags');
      await db.delete('sync_metadata');

      await DatabaseHelper.instance.close();
      await DatabaseHelper.reset();
    });

    group('Database Operations', () {
      test('should record event as published to relay', () async {
        const relayUrl = 'wss://relay.divine.video';
        const eventId = 'abc123';

        await dbHelper.recordPublishedEvent(relayUrl, eventId);

        final published = await dbHelper.getPublishedEventIds(relayUrl);
        expect(published, contains(eventId));
      });

      test('should handle duplicate publish records', () async {
        const relayUrl = 'wss://relay.divine.video';
        const eventId = 'abc123';

        // Record twice
        await dbHelper.recordPublishedEvent(relayUrl, eventId);
        await dbHelper.recordPublishedEvent(relayUrl, eventId);

        final published = await dbHelper.getPublishedEventIds(relayUrl);
        expect(published.length, equals(1));
        expect(published.first, equals(eventId));
      });

      test('should track published events separately per relay', () async {
        const relay1 = 'wss://relay1.com';
        const relay2 = 'wss://relay2.com';
        const eventId = 'abc123';

        await dbHelper.recordPublishedEvent(relay1, eventId);

        final published1 = await dbHelper.getPublishedEventIds(relay1);
        final published2 = await dbHelper.getPublishedEventIds(relay2);

        expect(published1, contains(eventId));
        expect(published2, isEmpty);
      });

      test('should return empty set for relay with no published events', () async {
        final published = await dbHelper.getPublishedEventIds('wss://new-relay.com');
        expect(published, isEmpty);
      });

      test('should get multiple published event IDs', () async {
        const relayUrl = 'wss://relay.divine.video';
        const eventIds = ['event1', 'event2', 'event3'];

        for (final id in eventIds) {
          await dbHelper.recordPublishedEvent(relayUrl, id);
        }

        final published = await dbHelper.getPublishedEventIds(relayUrl);
        expect(published.length, equals(3));
        expect(published, containsAll(eventIds));
      });
    });

    group('Unpublished Event Detection', () {
      test('should identify all events as unpublished when table is empty', () async {
        // Store some events locally
        final event1 = _createTestEvent('event1', 'pubkey1');
        final event2 = _createTestEvent('event2', 'pubkey1');

        await eventStore.storeEvent(event1);
        await eventStore.storeEvent(event2);

        // Get user's events
        final myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);

        // Check which are published
        const relayUrl = 'wss://relay.divine.video';
        final publishedIds = await dbHelper.getPublishedEventIds(relayUrl);

        // All should be unpublished
        final unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();
        expect(unpublished.length, equals(2));
      });

      test('should identify only unpublished events after some succeed', () async {
        // Store 3 events locally
        final event1 = _createTestEvent('event1', 'pubkey1');
        final event2 = _createTestEvent('event2', 'pubkey1');
        final event3 = _createTestEvent('event3', 'pubkey1');

        await eventStore.storeEvent(event1);
        await eventStore.storeEvent(event2);
        await eventStore.storeEvent(event3);

        // Mark event1 and event2 as published
        const relayUrl = 'wss://relay.divine.video';
        await dbHelper.recordPublishedEvent(relayUrl, 'event1');
        await dbHelper.recordPublishedEvent(relayUrl, 'event2');

        // Get user's events
        final myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);

        // Check which are published
        final publishedIds = await dbHelper.getPublishedEventIds(relayUrl);

        // Only event3 should be unpublished
        final unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();
        expect(unpublished.length, equals(1));
        expect(unpublished.first.id, equals('event3'));
      });

      test('should identify all events as unpublished for new relay', () async {
        // Store events and mark as published to relay1
        final event1 = _createTestEvent('event1', 'pubkey1');
        final event2 = _createTestEvent('event2', 'pubkey1');

        await eventStore.storeEvent(event1);
        await eventStore.storeEvent(event2);

        await dbHelper.recordPublishedEvent('wss://relay1.com', 'event1');
        await dbHelper.recordPublishedEvent('wss://relay1.com', 'event2');

        // For a new relay, all should be unpublished
        final myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);

        const newRelayUrl = 'wss://new-relay.com';
        final publishedIds = await dbHelper.getPublishedEventIds(newRelayUrl);

        final unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();
        expect(unpublished.length, equals(2));
      });
    });

    group('Republish Logic', () {
      test('should converge to no republishes after all events published', () async {
        // Store events
        final event1 = _createTestEvent('event1', 'pubkey1');
        final event2 = _createTestEvent('event2', 'pubkey1');

        await eventStore.storeEvent(event1);
        await eventStore.storeEvent(event2);

        const relayUrl = 'wss://relay.divine.video';

        // First pass - nothing published yet
        var myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);
        var publishedIds = await dbHelper.getPublishedEventIds(relayUrl);
        var unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();

        expect(unpublished.length, equals(2), reason: 'First pass should find 2 unpublished');

        // Simulate publishing event1
        await dbHelper.recordPublishedEvent(relayUrl, 'event1');

        // Second pass - event1 published
        myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);
        publishedIds = await dbHelper.getPublishedEventIds(relayUrl);
        unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();

        expect(unpublished.length, equals(1), reason: 'Second pass should find 1 unpublished');
        expect(unpublished.first.id, equals('event2'));

        // Simulate publishing event2
        await dbHelper.recordPublishedEvent(relayUrl, 'event2');

        // Third pass - all published
        myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);
        publishedIds = await dbHelper.getPublishedEventIds(relayUrl);
        unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();

        expect(unpublished, isEmpty, reason: 'Third pass should find 0 unpublished');
      });

      test('should handle events from multiple users correctly', () async {
        // Store events from different users
        final event1 = _createTestEvent('event1', 'pubkey1');
        final event2 = _createTestEvent('event2', 'pubkey2');
        final event3 = _createTestEvent('event3', 'pubkey1');

        await eventStore.storeEvent(event1);
        await eventStore.storeEvent(event2);
        await eventStore.storeEvent(event3);

        const relayUrl = 'wss://relay.divine.video';

        // Get only pubkey1's events
        final myEvents = await eventStore.queryEvents([
          Filter(authors: ['pubkey1']),
        ]);

        expect(myEvents.length, equals(2));

        final publishedIds = await dbHelper.getPublishedEventIds(relayUrl);
        final unpublished = myEvents.where((e) => !publishedIds.contains(e.id)).toList();

        expect(unpublished.length, equals(2));
        expect(unpublished.map((e) => e.id), containsAll(['event1', 'event3']));
      });
    });

    group('Cleanup', () {
      test('should clean up old published event records', () async {
        const relayUrl = 'wss://relay.divine.video';

        // Record some events with old timestamps
        final now = DateTime.now().millisecondsSinceEpoch;
        final oldTimestamp = now - (Duration.millisecondsPerDay * 100); // 100 days ago

        await dbHelper.recordPublishedEvent(relayUrl, 'old_event', timestamp: oldTimestamp);
        await dbHelper.recordPublishedEvent(relayUrl, 'recent_event');

        // Clean up records older than 90 days
        await dbHelper.cleanupOldPublishedRecords(days: 90);

        final published = await dbHelper.getPublishedEventIds(relayUrl);
        expect(published, contains('recent_event'));
        expect(published, isNot(contains('old_event')));
      });
    });
  });
}

NostrEvent _createTestEvent(String id, String pubkey) {
  return NostrEvent(
    id: id,
    pubkey: pubkey,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    kind: 1,
    tags: [],
    content: 'test content',
    sig: 'test_sig',
  );
}
