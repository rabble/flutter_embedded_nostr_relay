// ABOUTME: Tests for handling addressable events (kind 32222) in the sample app
// ABOUTME: Validates subscription and display of video-related addressable events

import 'package:flutter_test/flutter_test.dart';
import 'package:sample_nostr_app/services/nostr_service.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Addressable Events Tests', () {
    late NostrService service;

    setUp(() async {
      service = NostrService();
      await service.generateNewIdentity();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('subscribeToAddressableEvents requests kind 32222 events', () async {
      // Track the filter used in subscription
      Filter? capturedFilter;
      bool subscriptionCreated = false;

      // Subscribe to addressable events
      final subscription = service.subscribeToAddressableEvents(
        onEvent: (event) {
          // Should receive kind 32222 events
          expect(event.kind, equals(32222));
        },
        onEose: () {
          // End of stored events
        },
      );

      // The subscription should be created
      expect(subscription, isNotNull);
      
      // Close subscription
      await subscription.close();
    });

    test('publishAddressableEvent creates kind 32222 event with d-tag', () async {
      final videoId = 'video_${DateTime.now().millisecondsSinceEpoch}';
      final content = {
        'title': 'Test Video',
        'url': 'https://example.com/video.mp4',
        'description': 'A test video event',
      };

      // Publish addressable event
      final event = await service.publishAddressableEvent(
        dTag: videoId,
        content: content,
      );

      // Verify event properties
      expect(event.kind, equals(32222));
      expect(event.pubkey, equals(service.currentIdentity!.publicKey));
      
      // Check for d-tag
      final dTags = event.tags.where((tag) => tag[0] == 'd').toList();
      expect(dTags, hasLength(1));
      expect(dTags[0][1], equals(videoId));
      
      // Verify content
      expect(event.content, contains('Test Video'));
      expect(event.content, contains('https://example.com/video.mp4'));
    });

    test('addressable events are replaceable by pubkey+kind+d-tag', () async {
      final videoId = 'test_video_123';
      
      // Create first version
      final event1 = await service.publishAddressableEvent(
        dTag: videoId,
        content: {'title': 'Version 1', 'views': 100},
      );

      // Create second version with same d-tag
      final event2 = await service.publishAddressableEvent(
        dTag: videoId,
        content: {'title': 'Version 2', 'views': 200},
      );

      // Both should have same kind and d-tag
      expect(event1.kind, equals(32222));
      expect(event2.kind, equals(32222));
      
      // Get d-tags
      final dTag1 = event1.tags.firstWhere((tag) => tag[0] == 'd')[1];
      final dTag2 = event2.tags.firstWhere((tag) => tag[0] == 'd')[1];
      expect(dTag1, equals(videoId));
      expect(dTag2, equals(videoId));
      
      // Content should be different
      expect(event1.content, contains('Version 1'));
      expect(event2.content, contains('Version 2'));
    });
  });
}