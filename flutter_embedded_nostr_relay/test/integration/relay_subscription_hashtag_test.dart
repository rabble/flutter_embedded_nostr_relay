// ABOUTME: Integration test for hashtag subscription stream emission
// ABOUTME: Tests that subscribe() correctly emits events matching hashtag filters

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmbeddedNostrRelay hashtag subscription', () {
    late EmbeddedNostrRelay relay;

    setUp(() async {
      await DatabaseHelper.reset();
      DatabaseHelper.enableTestMode();
      relay = EmbeddedNostrRelay();
      await relay.initialize();
    });

    tearDown(() async {
      await relay.shutdown();
    });

    test('should emit events matching hashtag filter through subscription stream', () async {
      // Create test events with proper signatures (128 hex chars pass validation)
      final event1 = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 34236,
        tags: [
          ['t', 'lol'],
          ['t', 'funny'],
        ],
        content: 'Video with lol hashtag',
      ).copyWith(sig: '1' * 128);

      final event2 = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 34236,
        tags: [
          ['t', 'music'],
        ],
        content: 'Video with music hashtag',
      ).copyWith(sig: '2' * 128);

      final event3 = NostrEvent.create(
        pubkey: '0' * 64,
        kind: 34236,
        tags: [
          ['t', 'lol'],
        ],
        content: 'Another video with lol hashtag',
      ).copyWith(sig: '3' * 128);

      // Publish events to database
      final published1 = await relay.publish(event1);
      final published2 = await relay.publish(event2);
      final published3 = await relay.publish(event3);

      print('📤 Event1 published: $published1');
      print('📤 Event2 published: $published2');
      print('📤 Event3 published: $published3');

      expect(published1, true, reason: 'Event1 should be published');
      expect(published2, true, reason: 'Event2 should be published');
      expect(published3, true, reason: 'Event3 should be published');

      // NOW subscribe with hashtag filter
      final receivedEvents = <NostrEvent>[];
      var eoseReceived = false;

      final subscription = relay.subscribe(
        filters: [
          Filter(
            kinds: [34236],
            tags: {
              '#t': ['lol'],
            },
          ),
        ],
        onEvent: (event) {
          print('🎯 Received event: ${event.id}');
          receivedEvents.add(event);
        },
        onEose: () {
          print('✅ EOSE received');
          eoseReceived = true;
        },
      );

      // Wait for subscription to process
      await Future.delayed(Duration(milliseconds: 500));

      // Verify EOSE was received
      expect(eoseReceived, true, reason: 'EOSE should be received after stored events');

      // Verify events were emitted
      print('📊 Total events received: ${receivedEvents.length}');
      print('📊 Expected events: 2 (events with #lol hashtag)');

      expect(receivedEvents.length, 2, reason: 'Should receive 2 events with #lol hashtag');
      expect(receivedEvents.any((e) => e.id == event1.id), true);
      expect(receivedEvents.any((e) => e.id == event3.id), true);
      expect(receivedEvents.any((e) => e.id == event2.id), false);

      await relay.unsubscribe(subscription.id);
    });
  });
}
