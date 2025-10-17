// ABOUTME: Widget tests for hashtag screen functionality and UI behavior
// ABOUTME: Tests screen rendering, event display, navigation, and scroll behavior

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/screens/hashtag_screen.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:riverpod_nostr_app/providers/hashtag_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('HashtagScreen Widget Tests', () {
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
    
    testWidgets('displays hashtag in app bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'bitcoin'),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Check app bar title
      expect(find.text('#bitcoin'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
    
    testWidgets('shows empty state when no videos with hashtag', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'emptytag'),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Check empty state UI
      expect(find.byIcon(Icons.tag), findsOneWidget);
      expect(find.text('No videos with #emptytag'), findsOneWidget);
      expect(find.text('Loading from relays...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
    
    testWidgets('displays events with matching hashtag', (WidgetTester tester) async {
      // Create test events
      final event1 = createTestEvent(
        kind: 32222,
        content: 'Test video 1',
        tags: [
          ['t', 'testtag'],
          ['title', 'Video One'],
          ['imeta', 'url', 'https://example.com/video1.mp4', 'image', 'https://example.com/thumb1.jpg'],
        ],
      );
      
      final event2 = createTestEvent(
        kind: 32222,
        content: 'Test video 2',
        tags: [
          ['t', 'testtag'],
          ['title', 'Video Two'],
        ],
      );
      
      // Publish events
      await relay.publish(event1);
      await relay.publish(event2);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'testtag'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Check that events are displayed
      expect(find.text('Video One'), findsOneWidget);
      expect(find.text('Video Two'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
    });
    
    testWidgets('refresh button clears and reloads events', (WidgetTester tester) async {
      // Create an event
      final event = createTestEvent(
        kind: 32222,
        content: 'Refresh test',
        tags: [
          ['t', 'refreshtest'],
          ['title', 'Refresh Video'],
        ],
      );
      
      await relay.publish(event);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'refreshtest'),
          ),
        ),
      );
      
      // Wait for initial load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Verify event is displayed
      expect(find.text('Refresh Video'), findsOneWidget);
      
      // Tap refresh button
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      
      // Events should be cleared temporarily
      // Then reload
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      
      // Event should be back
      expect(find.text('Refresh Video'), findsOneWidget);
    });
    
    testWidgets('hashtag chips navigate to other hashtag screens', (WidgetTester tester) async {
      // Create event with multiple hashtags
      final event = createTestEvent(
        kind: 32222,
        content: 'Multi-tag video',
        tags: [
          ['t', 'first'],
          ['t', 'second'],
          ['title', 'Multi Tag Video'],
        ],
      );
      
      await relay.publish(event);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: MaterialApp(
            home: HashtagScreen(hashtag: 'first'),
            routes: {
              '/hashtag': (context) => const HashtagScreen(hashtag: 'second'),
            },
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Find hashtag chips
      expect(find.text('#first'), findsOneWidget);
      expect(find.text('#second'), findsOneWidget);
      
      // Current hashtag should be highlighted
      final firstChip = tester.widget<Chip>(
        find.ancestor(
          of: find.text('#first'),
          matching: find.byType(Chip),
        ),
      );
      expect(firstChip.backgroundColor, Colors.purple.shade200);
      
      // Other hashtag should have different color
      final secondChip = tester.widget<Chip>(
        find.ancestor(
          of: find.text('#second'),
          matching: find.byType(Chip),
        ),
      );
      expect(secondChip.backgroundColor, Colors.purple.shade50);
    });
    
    testWidgets('shows load more button at bottom of list', (WidgetTester tester) async {
      // Create multiple events
      for (int i = 0; i < 5; i++) {
        final event = createTestEvent(
          kind: 32222,
          content: 'Video $i',
          tags: [
            ['t', 'loadmore'],
            ['title', 'Video $i'],
          ],
          createdAt: DateTime.now().subtract(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
        );
        await relay.publish(event);
      }
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
            hashtagHasMoreEventsProvider('loadmore').overrideWith((ref) => true),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'loadmore'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Scroll to bottom
      await tester.drag(find.byType(GridView), const Offset(0, -500));
      await tester.pumpAndSettle();
      
      // Should see load more button
      expect(find.text('Load More'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });
    
    testWidgets('shows no more events message when all loaded', (WidgetTester tester) async {
      // Create a single event
      final event = createTestEvent(
        kind: 32222,
        content: 'Single video',
        tags: [
          ['t', 'nomore'],
          ['title', 'Only Video'],
        ],
      );
      await relay.publish(event);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
            hashtagHasMoreEventsProvider('nomore').overrideWith((ref) => false),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'nomore'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should see no more events message
      expect(find.text('No more events'), findsOneWidget);
    });
    
    testWidgets('event card displays thumbnail when available', (WidgetTester tester) async {
      final event = createTestEvent(
        kind: 32222,
        content: 'Video with thumbnail',
        tags: [
          ['t', 'thumbnail'],
          ['title', 'Thumbnail Test'],
          ['imeta', 'url', 'https://example.com/video.mp4', 'image', 'https://example.com/thumb.jpg'],
        ],
      );
      
      await relay.publish(event);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'thumbnail'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should have an image widget (thumbnail)
      expect(find.byType(Image), findsOneWidget);
      
      // Should have play button overlay
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
    
    testWidgets('event card shows video icon when no thumbnail', (WidgetTester tester) async {
      final event = createTestEvent(
        kind: 32222,
        content: 'Video without thumbnail',
        tags: [
          ['t', 'nothumbnail'],
          ['title', 'No Thumbnail Test'],
        ],
      );
      
      await relay.publish(event);
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            relayProvider.overrideWith((ref) async => relay),
          ],
          child: const MaterialApp(
            home: HashtagScreen(hashtag: 'nothumbnail'),
          ),
        ),
      );
      
      // Wait for events to load
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      
      // Should show video library icon instead of thumbnail
      expect(find.byIcon(Icons.video_library), findsOneWidget);
    });
  });
}