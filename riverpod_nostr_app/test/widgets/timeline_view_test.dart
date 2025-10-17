// ABOUTME: Widget tests for timeline view with Riverpod StreamProvider
// ABOUTME: Tests real-time UI updates from event stream

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/screens/timeline_view.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  testWidgets('TimelineView displays events from StreamProvider', (tester) async {
    // Create a test event
    final testEvent = NostrEvent(
      id: 'test_event_id',
      pubkey: 'test_pubkey',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 32222,
      tags: [['d', 'test_video']],
      content: '{"title": "Test Video", "url": "https://example.com/video.mp4"}',
      sig: 'test_signature',
    );
    
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addressableEventStreamProvider.overrideWith((ref) async* {
            yield testEvent;
          }),
          eventListProvider.overrideWith((ref) {
            return EventListNotifier(ref)..state = [testEvent];
          }),
        ],
        child: const MaterialApp(
          home: TimelineView(),
        ),
      ),
    );
    
    // Initially shows loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Wait for stream to emit
    await tester.pumpAndSettle();
    
    // Should now show the event
    expect(find.text('Test Video'), findsOneWidget);
    expect(find.text('https://example.com/video.mp4'), findsOneWidget);
  });
  
  testWidgets('TimelineView shows empty state when no events', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addressableEventStreamProvider.overrideWith((ref) async* {
            // Empty stream - yield nothing
          }),
          eventListProvider.overrideWith((ref) {
            return EventListNotifier(ref)..state = [];
          }),
        ],
        child: const MaterialApp(
          home: TimelineView(),
        ),
      ),
    );
    
    // Wait for stream to complete
    await tester.pumpAndSettle();
    
    // Should show empty state
    expect(find.text('No video events yet'), findsOneWidget);
    expect(find.byIcon(Icons.video_library), findsOneWidget);
  });
  
  testWidgets('TimelineView updates when new events arrive', (tester) async {
    // Create a stream controller to control event emission
    final streamController = StreamController<NostrEvent>();
    final events = <NostrEvent>[];
    
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addressableEventStreamProvider.overrideWith((ref) {
            ref.onDispose(() => streamController.close());
            return streamController.stream;
          }),
          eventListProvider.overrideWith((ref) {
            final notifier = EventListNotifier(ref);
            // Listen to stream and add to list
            streamController.stream.listen((event) {
              events.add(event);
              notifier.state = [...events];
            });
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: TimelineView(),
        ),
      ),
    );
    
    // Initially loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    
    // Emit first event
    final event1 = NostrEvent(
      id: 'event1',
      pubkey: 'pubkey1',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 32222,
      tags: [['d', 'video1']],
      content: '{"title": "First Video"}',
      sig: 'sig1',
    );
    streamController.add(event1);
    await tester.pumpAndSettle();
    
    expect(find.text('First Video'), findsOneWidget);
    
    // Emit second event
    final event2 = NostrEvent(
      id: 'event2',
      pubkey: 'pubkey2',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: 32222,
      tags: [['d', 'video2']],
      content: '{"title": "Second Video"}',
      sig: 'sig2',
    );
    streamController.add(event2);
    await tester.pumpAndSettle();
    
    // Both events should be visible
    expect(find.text('First Video'), findsOneWidget);
    expect(find.text('Second Video'), findsOneWidget);
  });
}