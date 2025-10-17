// ABOUTME: Integration tests for hashtag navigation flow and relay subscriptions
// ABOUTME: Tests the complete user journey from timeline to hashtag screens

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/main.dart';
import 'package:riverpod_nostr_app/screens/timeline_view.dart';
import 'package:riverpod_nostr_app/screens/hashtag_screen.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Hashtag Navigation Integration Tests', () {
    late EmbeddedNostrRelay relay;
    
    setUp(() async {
      DatabaseHelper.enableTestMode();
      relay = EmbeddedNostrRelay();
      await relay.initialize(enableGarbageCollection: false);
    });
    
    tearDown(() async {
      await relay.shutdown();
      await DatabaseHelper.reset();
    });
    
    testWidgets('navigate from timeline to hashtag screen', (WidgetTester tester) async {
      // Create test event with hashtags
      final event = createTestEvent(
        kind: 32222,
        content: 'Integration test video',
        tags: [
          ['t', 'integration'],
          ['t', 'testing'],
          ['title', 'Integration Test'],
          ['imeta', 'url', 'https://example.com/video.mp4', 'image', 'https://example.com/thumb.jpg'],
        ],
      );
      
      await relay.publish(event);
      
      // Start app
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MyApp(),
        ),
      );
      
      // Wait for initial load
      await tester.pumpAndSettle();
      
      // Navigate to timeline if needed
      if (find.text('Video Events (Kind 32222)').evaluate().isEmpty) {
        // We're on identity screen, skip it
        await tester.tap(find.text('Generate New Identity'));
        await tester.pumpAndSettle();
      }
      
      // Wait for events to load in timeline
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Find and tap hashtag
      final integrationHashtag = find.text('#integration');
      expect(integrationHashtag, findsOneWidget);
      
      await tester.tap(integrationHashtag);
      await tester.pumpAndSettle();
      
      // Should be on hashtag screen
      expect(find.byType(HashtagScreen), findsOneWidget);
      expect(find.text('#integration'), findsOneWidget); // In app bar
      expect(find.text('Integration Test'), findsOneWidget); // Event title
    });
    
    testWidgets('navigate between multiple hashtag screens', (WidgetTester tester) async {
      // Create events with overlapping hashtags
      final event1 = createTestEvent(
        kind: 32222,
        content: 'First video',
        tags: [
          ['t', 'first'],
          ['t', 'common'],
          ['title', 'First Video'],
        ],
      );
      
      final event2 = createTestEvent(
        kind: 32222,
        content: 'Second video',
        tags: [
          ['t', 'second'],
          ['t', 'common'],
          ['title', 'Second Video'],
        ],
      );
      
      await relay.publish(event1);
      await relay.publish(event2);
      
      // Start on first hashtag screen
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'first'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should see first video
      expect(find.text('First Video'), findsOneWidget);
      
      // Tap on common hashtag
      final commonHashtag = find.text('#common');
      expect(commonHashtag, findsOneWidget);
      
      await tester.tap(commonHashtag);
      await tester.pumpAndSettle();
      
      // Should navigate to common hashtag screen
      expect(find.text('#common'), findsOneWidget); // In app bar
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should see both videos on common hashtag screen
      expect(find.text('First Video'), findsOneWidget);
      expect(find.text('Second Video'), findsOneWidget);
    });
    
    testWidgets('hashtag screen creates proper subscription', (WidgetTester tester) async {
      // Track subscription creation
      bool subscriptionCreated = false;
      String? capturedSubscriptionId;
      List<Filter>? capturedFilters;
      
      // Create a custom relay that captures subscriptions
      final testRelay = TestRelayWithCapture(
        onSubscribe: (id, filters) {
          subscriptionCreated = true;
          capturedSubscriptionId = id;
          capturedFilters = filters;
        },
      );
      
      DatabaseHelper.enableTestMode();
      await testRelay.initialize(enableGarbageCollection: false);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => testRelay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'subscription'),
          ),
        ),
      );
      
      // Wait for subscription to be created
      await tester.pump(const Duration(seconds: 1));
      
      // Verify subscription was created
      expect(subscriptionCreated, true);
      expect(capturedSubscriptionId, contains('hashtag_subscription'));
      expect(capturedFilters, isNotNull);
      expect(capturedFilters!.length, 1);
      
      final filter = capturedFilters!.first;
      expect(filter.kinds, contains(32222));
      expect(filter.tags, isNotNull);
      // Note: The actual tag filter format might need adjustment
      // based on the Nostr protocol specification
      
      await testRelay.shutdown();
      await DatabaseHelper.reset();
    });
    
    testWidgets('pull to refresh works on hashtag screen', (WidgetTester tester) async {
      // Create initial event
      final event1 = createTestEvent(
        kind: 32222,
        content: 'Initial video',
        tags: [
          ['t', 'refresh'],
          ['title', 'Initial Video'],
        ],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      );
      
      await relay.publish(event1);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'refresh'),
          ),
        ),
      );
      
      // Wait for initial load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Verify initial event is shown
      expect(find.text('Initial Video'), findsOneWidget);
      
      // Create new event while screen is open
      final event2 = createTestEvent(
        kind: 32222,
        content: 'New video',
        tags: [
          ['t', 'refresh'],
          ['title', 'New Video'],
        ],
      );
      
      await relay.publish(event2);
      
      // Pull to refresh
      await tester.drag(find.byType(GridView), const Offset(0, 300));
      await tester.pumpAndSettle();
      
      // Wait for refresh
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      
      // Should see both events
      expect(find.text('Initial Video'), findsOneWidget);
      expect(find.text('New Video'), findsOneWidget);
    });
    
    testWidgets('infinite scroll loads more events on hashtag screen', (WidgetTester tester) async {
      // Create many events with different timestamps
      for (int i = 0; i < 10; i++) {
        final event = createTestEvent(
          kind: 32222,
          content: 'Video $i',
          tags: [
            ['t', 'scroll'],
            ['title', 'Video $i'],
          ],
          createdAt: DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch ~/ 1000,
        );
        await relay.publish(event);
      }
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'scroll'),
          ),
        ),
      );
      
      // Wait for initial load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should see recent videos
      expect(find.text('Video 0'), findsOneWidget);
      expect(find.text('Video 1'), findsOneWidget);
      
      // Scroll down to trigger load more
      await tester.drag(find.byType(GridView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      
      // Should trigger load more
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      
      // Should see more videos loaded
      expect(find.text('Video 5'), findsOneWidget);
    });
  });
}

// Test helper class that captures subscription details
class TestRelayWithCapture extends EmbeddedNostrRelay {
  final void Function(String id, List<Filter> filters)? onSubscribe;
  
  TestRelayWithCapture({this.onSubscribe});
  
  @override
  Subscription subscribe({
    required List<Filter> filters,
    Function(NostrEvent)? onEvent,
    Function()? onEose,
    Function(String)? onError,
    String? subscriptionId,
  }) {
    final id = subscriptionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    onSubscribe?.call(id, filters);
    
    return super.subscribe(
      filters: filters,
      onEvent: onEvent,
      onEose: onEose,
      onError: onError,
      subscriptionId: id,
    );
  }
}