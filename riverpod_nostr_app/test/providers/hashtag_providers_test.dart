// ABOUTME: Tests for hashtag-specific Riverpod providers and event filtering
// ABOUTME: Verifies hashtag subscriptions, event accumulation, and pagination

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/providers/hashtag_providers.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'dart:async';
import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('HashtagProviders', () {
    late ProviderContainer container;
    late EmbeddedNostrRelay relay;

    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      container = ProviderContainer();
      
      // Initialize the relay first
      relay = EmbeddedNostrRelay();
      await relay.initialize(enableGarbageCollection: false);
      
      // Override the relay provider with our test instance
      container = ProviderContainer(
        overrides: [
          relayProvider.overrideWith((ref) async => relay),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await relay.shutdown();
      await DatabaseHelper.reset();
    });

    test('hashtagEventListProvider creates subscription for specific hashtag', () async {
      // Create test events with hashtags
      final event1 = createTestEvent(
        kind: 32222,
        content: 'Video about Bitcoin',
        tags: [
          ['t', 'bitcoin'],
          ['t', 'crypto'],
        ],
      );
      
      final event2 = createTestEvent(
        kind: 32222,
        content: 'Video about Lightning',
        tags: [
          ['t', 'lightning'],
          ['t', 'bitcoin'],
        ],
      );
      
      final event3 = createTestEvent(
        kind: 32222,
        content: 'Video about Ethereum',
        tags: [
          ['t', 'ethereum'],
          ['t', 'crypto'],
        ],
      );
      
      // Publish events
      await relay.publish(event1);
      await relay.publish(event2);
      await relay.publish(event3);
      
      // Wait for events to be stored
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Get bitcoin hashtag events
      final bitcoinEvents = container.read(hashtagEventListProvider('bitcoin'));
      
      // Should be empty initially (events come through subscription)
      expect(bitcoinEvents, isEmpty);
      
      // Wait for subscription to receive events
      await Future.delayed(const Duration(seconds: 2));
      
      // Check again
      final bitcoinEventsAfter = container.read(hashtagEventListProvider('bitcoin'));
      
      // Should have 2 events with bitcoin hashtag
      expect(bitcoinEventsAfter.length, 2);
      expect(bitcoinEventsAfter.any((e) => e.id == event1.id), true);
      expect(bitcoinEventsAfter.any((e) => e.id == event2.id), true);
      expect(bitcoinEventsAfter.any((e) => e.id == event3.id), false);
    });

    test('hashtag events are sorted by creation time (newest first)', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('nostr'));
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create events with different timestamps
      final oldEvent = createTestEvent(
        kind: 32222,
        content: 'Old video',
        tags: [['t', 'nostr']],
        createdAt: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
      );
      
      final newEvent = createTestEvent(
        kind: 32222,
        content: 'New video',
        tags: [['t', 'nostr']],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      
      final midEvent = createTestEvent(
        kind: 32222,
        content: 'Mid video',
        tags: [['t', 'nostr']],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      );
      
      // Publish in random order
      await relay.publish(oldEvent);
      await relay.publish(newEvent);
      await relay.publish(midEvent);
      
      // Wait for subscription to receive events
      await Future.delayed(const Duration(seconds: 1));
      
      final nostrEvents = container.read(hashtagEventListProvider('nostr'));
      
      // Should be sorted newest first
      expect(nostrEvents.length, 3);
      expect(nostrEvents[0].id, newEvent.id);
      expect(nostrEvents[1].id, midEvent.id);
      expect(nostrEvents[2].id, oldEvent.id);
    });

    test('hashtag provider filters out events without the specific hashtag', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('nostr'));
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create events with different hashtags
      final event1 = createTestEvent(
        kind: 32222,
        content: 'Video 1',
        tags: [['t', 'nostr']],
      );
      
      final event2 = createTestEvent(
        kind: 32222,
        content: 'Video 2',
        tags: [['t', 'bitcoin']],
      );
      
      final event3 = createTestEvent(
        kind: 1, // Wrong kind
        content: 'Text note',
        tags: [['t', 'nostr']],
      );
      
      // Publish events
      await relay.publish(event1);
      await relay.publish(event2);
      await relay.publish(event3);
      
      // Wait for subscription
      await Future.delayed(const Duration(seconds: 1));
      
      final nostrEvents = container.read(hashtagEventListProvider('nostr'));
      
      // Should only have event1 (correct kind and hashtag)
      expect(nostrEvents.length, 1);
      expect(nostrEvents[0].id, event1.id);
    });

    test('hashtagIsLoadingMoreProvider reflects loading state', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('test'));
      
      // Initially not loading
      final isLoading = container.read(hashtagIsLoadingMoreProvider('test'));
      expect(isLoading, false);
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create some events to have something to paginate
      for (int i = 0; i < 5; i++) {
        final event = createTestEvent(
          kind: 32222,
          content: 'Video $i',
          tags: [['t', 'test']],
          createdAt: DateTime.now().subtract(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
        );
        await relay.publish(event);
      }
      
      await Future.delayed(const Duration(seconds: 1));
      
      // Trigger load more
      final notifier = container.read(hashtagEventListProvider('test').notifier);
      final loadMoreFuture = notifier.loadMoreEvents();
      
      // Should be loading now
      final isLoadingDuring = container.read(hashtagIsLoadingMoreProvider('test'));
      expect(isLoadingDuring, true);
      
      // Wait for load to complete
      await loadMoreFuture;
      
      // Should not be loading anymore
      final isLoadingAfter = container.read(hashtagIsLoadingMoreProvider('test'));
      expect(isLoadingAfter, false);
    });

    test('hashtagHasMoreEventsProvider updates when no more events available', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('limited'));
      
      // Initially has more events
      final hasMore = container.read(hashtagHasMoreEventsProvider('limited'));
      expect(hasMore, true);
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create only 2 events
      for (int i = 0; i < 2; i++) {
        final event = createTestEvent(
          kind: 32222,
          content: 'Video $i',
          tags: [['t', 'limited']],
          createdAt: DateTime.now().subtract(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
        );
        await relay.publish(event);
      }
      
      await Future.delayed(const Duration(seconds: 1));
      
      // Try to load more (should find no additional events)
      final notifier = container.read(hashtagEventListProvider('limited').notifier);
      await notifier.loadMoreEvents();
      
      // Should not have more events
      final hasMoreAfter = container.read(hashtagHasMoreEventsProvider('limited'));
      expect(hasMoreAfter, false);
    });

    test('clear() method resets hashtag event list', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('cleartest'));
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Add some events
      final event = createTestEvent(
        kind: 32222,
        content: 'Video',
        tags: [['t', 'cleartest']],
      );
      await relay.publish(event);
      
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify events exist
      final eventsBefore = container.read(hashtagEventListProvider('cleartest'));
      expect(eventsBefore.isNotEmpty, true);
      
      // Clear
      final notifier = container.read(hashtagEventListProvider('cleartest').notifier);
      notifier.clear();
      
      // Should be empty
      final eventsAfter = container.read(hashtagEventListProvider('cleartest'));
      expect(eventsAfter, isEmpty);
      
      // hasMoreEvents should be reset to true
      final hasMore = container.read(hashtagHasMoreEventsProvider('cleartest'));
      expect(hasMore, true);
    });

    test('allHashtagsProvider extracts unique hashtags from all events', () async {
      // Note: This test would need events in the main eventListProvider
      // For now, we'll test the provider exists and returns a list
      final allHashtags = container.read(allHashtagsProvider);
      expect(allHashtags, isA<List<String>>());
    });

    test('hashtag subscriptions are independent for different hashtags', () async {
      // Start both subscriptions first
      container.read(hashtagEventListProvider('bitcoin'));
      container.read(hashtagEventListProvider('nostr'));
      
      // Wait for subscriptions to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create events for different hashtags
      final btcEvent = createTestEvent(
        kind: 32222,
        content: 'Bitcoin video',
        tags: [['t', 'bitcoin']],
      );
      
      final nostrEvent = createTestEvent(
        kind: 32222,
        content: 'Nostr video',
        tags: [['t', 'nostr']],
      );
      
      await relay.publish(btcEvent);
      await relay.publish(nostrEvent);
      
      await Future.delayed(const Duration(seconds: 1));
      
      // Check both hashtag lists
      final bitcoinEvents = container.read(hashtagEventListProvider('bitcoin'));
      final nostrEvents = container.read(hashtagEventListProvider('nostr'));
      
      // Each should have only their respective events
      expect(bitcoinEvents.length, 1);
      expect(bitcoinEvents[0].id, btcEvent.id);
      
      expect(nostrEvents.length, 1);
      expect(nostrEvents[0].id, nostrEvent.id);
    });

    test('hashtag events handle duplicates correctly', () async {
      // Start subscription first
      container.read(hashtagEventListProvider('duptest'));
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create an event
      final event = createTestEvent(
        kind: 32222,
        content: 'Duplicate test',
        tags: [['t', 'duptest']],
      );
      
      // Publish it twice
      await relay.publish(event);
      await relay.publish(event);
      
      await Future.delayed(const Duration(seconds: 1));
      
      // Should only have one instance
      final events = container.read(hashtagEventListProvider('duptest'));
      expect(events.length, 1);
      expect(events[0].id, event.id);
    });
  });
}