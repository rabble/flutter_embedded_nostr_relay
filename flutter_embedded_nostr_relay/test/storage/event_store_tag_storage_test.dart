// ABOUTME: Test that verifies hashtag tags are actually stored in the database
// ABOUTME: Checks both the tags table and the ability to query them back

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EventStore tag storage verification', () {
    late EventStore eventStore;

    setUp(() async {
      await DatabaseHelper.reset();
      DatabaseHelper.enableTestMode();
      eventStore = EventStore();
    });

    test('should store hashtag tags in tags table and be able to query them back', () async {
      // Create event with hashtag tags
      final event = NostrEvent.create(
        pubkey: '0000000000000000000000000000000000000000000000000000000000000000',
        kind: 34236,
        tags: [
          ['t', 'lol'],
          ['t', 'funny'],
          ['title', 'Test Video'],
        ],
        content: 'Video with hashtags',
      ).copyWith(sig: '1' * 128);

      // Store the event
      final stored = await eventStore.storeEvent(event);
      expect(stored, true, reason: 'Event should be stored successfully');

      // Directly query the tags table to verify tags were inserted
      final db = await DatabaseHelper.instance.database;
      final tagRows = await db.query(
        'tags',
        where: 'event_id = ?',
        whereArgs: [event.id],
      );

      print('Tags stored in database: $tagRows');

      expect(tagRows.length, 3, reason: 'Should have 3 tag rows (t, t, title)');

      // Verify the 't' tags are stored correctly
      final tTags = tagRows.where((row) => row['tag_name'] == 't').toList();
      expect(tTags.length, 2, reason: 'Should have 2 hashtag tags');

      final tagValues = tTags.map((row) => row['tag_value']).toSet();
      expect(tagValues, {'lol', 'funny'}, reason: 'Should store both hashtag values');

      // Now verify we can query the event back using hashtag filter
      final filter = Filter(
        kinds: [34236],
        tags: {
          '#t': ['lol'],
        },
      );

      final results = await eventStore.queryEvents([filter]);
      expect(results.length, 1, reason: 'Should find the event by hashtag');
      expect(results[0].id, event.id, reason: 'Should return the correct event');
    });

    test('should store multiple events with different hashtags and query correctly', () async {
      // Create multiple events with different hashtags
      final event1 = NostrEvent.create(
        pubkey: '0000000000000000000000000000000000000000000000000000000000000000',
        kind: 34236,
        tags: [
          ['t', 'lol'],
          ['t', 'funny'],
        ],
        content: 'Video 1',
      ).copyWith(sig: '1' * 128);

      final event2 = NostrEvent.create(
        pubkey: '0000000000000000000000000000000000000000000000000000000000000000',
        kind: 34236,
        tags: [
          ['t', 'music'],
        ],
        content: 'Video 2',
      ).copyWith(sig: '2' * 128);

      final event3 = NostrEvent.create(
        pubkey: '0000000000000000000000000000000000000000000000000000000000000000',
        kind: 34236,
        tags: [
          ['t', 'lol'],
        ],
        content: 'Video 3',
      ).copyWith(sig: '3' * 128);

      // Store all events
      await eventStore.storeEvent(event1);
      await eventStore.storeEvent(event2);
      await eventStore.storeEvent(event3);

      // Verify total tag count in database
      final db = await DatabaseHelper.instance.database;
      final allTags = await db.query('tags');
      print('Total tags in database: ${allTags.length}');
      print('All tags: $allTags');

      // Query for #lol hashtag
      final lolFilter = Filter(
        kinds: [34236],
        tags: {
          '#t': ['lol'],
        },
      );

      final lolResults = await eventStore.queryEvents([lolFilter]);
      expect(lolResults.length, 2, reason: 'Should find 2 events with #lol');
      expect(lolResults.any((e) => e.id == event1.id), true);
      expect(lolResults.any((e) => e.id == event3.id), true);
      expect(lolResults.any((e) => e.id == event2.id), false);

      // Query for #music hashtag
      final musicFilter = Filter(
        kinds: [34236],
        tags: {
          '#t': ['music'],
        },
      );

      final musicResults = await eventStore.queryEvents([musicFilter]);
      expect(musicResults.length, 1, reason: 'Should find 1 event with #music');
      expect(musicResults[0].id, event2.id);
    });
  });
}
