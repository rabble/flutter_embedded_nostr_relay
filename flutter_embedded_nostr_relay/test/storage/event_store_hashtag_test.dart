// Test for hashtag filtering in event_store queryEvents

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';

void main() {
  late EventStore eventStore;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    // Enable test mode to use in-memory database
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    // Initialize the database
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    // Delete all events from the database between tests
    final db = await DatabaseHelper.instance.database;
    await db.delete('events');
    await db.delete('tags');
    await DatabaseHelper.reset();
  });

  test('queryEvents should return events matching hashtag filter', () async {
    // Create test events with hashtags
    final event1 = NostrEvent(
      id: 'test_event_1',
      pubkey: 'test_pubkey_1',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'lol'],
        ['t', 'funny'],
      ],
      content: 'Test video with lol hashtag',
      sig: 'test_sig_1',
    );

    final event2 = NostrEvent(
      id: 'test_event_2',
      pubkey: 'test_pubkey_2',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'music'],
      ],
      content: 'Test video with music hashtag',
      sig: 'test_sig_2',
    );

    final event3 = NostrEvent(
      id: 'test_event_3',
      pubkey: 'test_pubkey_3',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'lol'],
      ],
      content: 'Another test video with lol hashtag',
      sig: 'test_sig_3',
    );

    // Store the events
    await eventStore.storeEvent(event1);
    await eventStore.storeEvent(event2);
    await eventStore.storeEvent(event3);

    // Query for events with 'lol' hashtag using generic tags filter
    final filter = Filter(
      kinds: [34236],
      tags: {
        '#t': ['lol'],
      },
    );

    final results = await eventStore.queryEvents([filter]);

    // Should return event1 and event3
    expect(results.length, 2);
    expect(results.any((e) => e.id == 'test_event_1'), true);
    expect(results.any((e) => e.id == 'test_event_3'), true);
    expect(results.any((e) => e.id == 'test_event_2'), false);
  });

  test('queryEvents should return events matching multiple hashtag values', () async {
    // Create test events
    final event1 = NostrEvent(
      id: 'test_event_1',
      pubkey: 'test_pubkey_1',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'lol'],
      ],
      content: 'Test video with lol hashtag',
      sig: 'test_sig_1',
    );

    final event2 = NostrEvent(
      id: 'test_event_2',
      pubkey: 'test_pubkey_2',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'music'],
      ],
      content: 'Test video with music hashtag',
      sig: 'test_sig_2',
    );

    final event3 = NostrEvent(
      id: 'test_event_3',
      pubkey: 'test_pubkey_3',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 34236,
      tags: [
        ['t', 'funny'],
      ],
      content: 'Test video with funny hashtag',
      sig: 'test_sig_3',
    );

    // Store the events
    await eventStore.storeEvent(event1);
    await eventStore.storeEvent(event2);
    await eventStore.storeEvent(event3);

    // Query for events with 'lol' OR 'music' hashtag
    final filter = Filter(
      kinds: [34236],
      tags: {
        '#t': ['lol', 'music'],
      },
    );

    final results = await eventStore.queryEvents([filter]);

    // Should return event1 and event2
    expect(results.length, 2);
    expect(results.any((e) => e.id == 'test_event_1'), true);
    expect(results.any((e) => e.id == 'test_event_2'), true);
    expect(results.any((e) => e.id == 'test_event_3'), false);
  });
}
