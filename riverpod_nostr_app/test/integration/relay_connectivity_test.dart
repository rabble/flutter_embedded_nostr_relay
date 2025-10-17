// ABOUTME: Integration tests for relay connectivity and StreamProvider updates
// ABOUTME: Tests real-time event streaming from external relays through Riverpod

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Relay Connectivity Integration Tests', () {
    late ProviderContainer container;
    
    setUp(() {
      DatabaseHelper.enableTestMode();
      container = ProviderContainer();
    });
    
    tearDown(() async {
      // Properly dispose of the container
      container.dispose();
      await DatabaseHelper.reset();
    });
    
    test('relayProvider initializes and connects to external relays', () async {
      // Get the relay
      final relay = await container.read(relayProvider.future);
      
      expect(relay, isNotNull);
      
      // Wait a bit for connections to establish
      await Future.delayed(const Duration(seconds: 2));
      
      // Check that we have connected relays
      expect(relay.connectedRelays, isNotEmpty);
      expect(relay.connectedRelays.length, greaterThan(0));
      
      // Verify specific relays are in the list
      expect(
        relay.connectedRelays.any((url) => url.contains('relay3.openvine.co')),
        isTrue,
        reason: 'Should connect to relay3.openvine.co',
      );
    });
    
    test('addressableEventStreamProvider receives kind 32222 events', () async {
      // Get the relay first
      final relay = await container.read(relayProvider.future);
      
      // Create a completer to wait for events
      final eventCompleter = Completer<NostrEvent>();
      
      // Listen to the stream provider
      final subscription = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            if (!eventCompleter.isCompleted) {
              eventCompleter.complete(next.value!);
            }
          }
        },
      );
      
      // Wait for relay connections
      await Future.delayed(const Duration(seconds: 2));
      
      // Create and publish a test event
      final testEvent = NostrEvent.create(
        pubkey: 'test_pubkey_' + DateTime.now().millisecondsSinceEpoch.toString(),
        kind: 32222,
        tags: [
          ['d', 'test_video_${DateTime.now().millisecondsSinceEpoch}'],
        ],
        content: '{"title": "Test Video", "url": "https://example.com/test.mp4"}',
      );
      
      // Sign with a test private key
      final privateKey = NostrCrypto.generatePrivateKey();
      final signedEvent = testEvent.sign(privateKey);
      
      // Publish the event
      await relay.publish(signedEvent);
      
      // Wait for the event to come through the stream
      final receivedEvent = await eventCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('No event received within timeout'),
      );
      
      expect(receivedEvent.kind, equals(32222));
      expect(receivedEvent.content.contains('Test Video'), isTrue);
      
      // Cleanup
      subscription.close();
    });
    
    test('eventListProvider accumulates events from stream', () async {
      // Get the relay
      final relay = await container.read(relayProvider.future);
      
      // Wait for connections
      await Future.delayed(const Duration(seconds: 2));
      
      // Initial list should be empty
      expect(container.read(eventListProvider), isEmpty);
      
      // Publish multiple test events
      final privateKey = NostrCrypto.generatePrivateKey();
      for (int i = 0; i < 3; i++) {
        final event = NostrEvent.create(
          pubkey: NostrCrypto.getPublicKey(privateKey),
          kind: 32222,
          tags: [
            ['d', 'test_video_$i'],
          ],
          content: '{"title": "Test Video $i"}',
        );
        
        final signedEvent = event.sign(privateKey);
        await relay.publish(signedEvent);
        
        // Small delay between events
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Wait for events to be processed
      await Future.delayed(const Duration(seconds: 3));
      
      // Check that events were accumulated
      final eventList = container.read(eventListProvider);
      expect(eventList.length, greaterThanOrEqualTo(3));
      
      // Verify they are in newest-first order
      if (eventList.length >= 2) {
        expect(eventList[0].createdAt, greaterThanOrEqualTo(eventList[1].createdAt));
      }
    });
    
    test('subscriptionProvider creates working subscriptions', () async {
      // Get the relay
      final relay = await container.read(relayProvider.future);
      
      // Wait for connections
      await Future.delayed(const Duration(seconds: 2));
      
      // Create a subscription with specific filter
      final filter = Filter(
        kinds: [1], // Text notes
        limit: 10,
      );
      
      final subscriptionAsync = container.read(
        subscriptionProvider([filter])
      );
      
      // Verify subscription is created
      subscriptionAsync.when(
        data: (subscription) {
          expect(subscription, isNotNull);
          expect(subscription.filters, contains(filter));
        },
        loading: () {},
        error: (e, _) => fail('Subscription creation failed: $e'),
      );
    });
    
    test('identityProvider manages Nostr identity', () async {
      final identityNotifier = container.read(identityProvider.notifier);
      
      // Initially should be null
      expect(container.read(identityProvider), isNull);
      
      // Generate new identity
      await identityNotifier.generateNewIdentity();
      
      final identity = container.read(identityProvider);
      expect(identity, isNotNull);
      expect(identity!.publicKey.length, equals(64));
      expect(identity.privateKey.length, equals(64));
      
      // Test logout
      identityNotifier.logout();
      expect(container.read(identityProvider), isNull);
      
      // Test import
      final testPrivateKey = NostrCrypto.generatePrivateKey();
      await identityNotifier.importIdentity(testPrivateKey);
      
      final importedIdentity = container.read(identityProvider);
      expect(importedIdentity, isNotNull);
      expect(importedIdentity!.privateKey, equals(testPrivateKey));
      expect(importedIdentity.publicKey, equals(NostrCrypto.getPublicKey(testPrivateKey)));
    });
    
    test('eventPublisherProvider publishes events successfully', () async {
      // Set up identity first
      final identityNotifier = container.read(identityProvider.notifier);
      await identityNotifier.generateNewIdentity();
      
      // Get the publisher
      final publisher = container.read(eventPublisherProvider);
      
      // Wait for relay to be ready
      await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      // Publish an addressable event
      final publishedEvent = await publisher.publishAddressableEvent(
        dTag: 'test_video_publish',
        content: {
          'title': 'Published Test Video',
          'url': 'https://example.com/published.mp4',
          'duration': 120,
        },
      );
      
      expect(publishedEvent, isNotNull);
      expect(publishedEvent!.kind, equals(32222));
      expect(publishedEvent.content.contains('Published Test Video'), isTrue);
      
      // Verify signature
      final identity = container.read(identityProvider)!;
      expect(publishedEvent.pubkey, equals(identity.publicKey));
      // For now, just verify the event has a signature
      expect(publishedEvent.sig, isNotEmpty);
    });
    
    test('relay stats provider returns statistics', () async {
      // Wait for relay to initialize
      await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      // Get stats
      final statsAsync = await container.read(relayStatsProvider.future);
      
      expect(statsAsync, isNotNull);
      expect(statsAsync.containsKey('eventCount'), isTrue);
      expect(statsAsync.containsKey('subscriptionCount'), isTrue);
      expect(statsAsync.containsKey('connectedRelays'), isTrue);
      expect(statsAsync['connectedRelays'], greaterThan(0));
    });
  });
}