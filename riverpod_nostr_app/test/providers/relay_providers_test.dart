// ABOUTME: Tests for Riverpod providers that manage relay state and event streams
// ABOUTME: Validates StreamProvider integration with embedded Nostr relay

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Relay Providers Tests', () {
    late ProviderContainer container;
    
    setUp(() {
      container = ProviderContainer();
    });
    
    tearDown(() {
      container.dispose();
    });
    
    test('relayProvider initializes and connects to relay', () async {
      // Get the relay from provider
      final relay = await container.read(relayProvider.future);
      
      // Verify relay is initialized
      expect(relay, isNotNull);
      expect(relay, isA<EmbeddedNostrRelay>());
    });
    
    test('addressableEventStreamProvider filters kind 32222 events', () async {
      // Get the relay first
      final relay = await container.read(relayProvider.future);
      
      // Listen to stream provider updates
      final completer = Completer<NostrEvent>();
      final listener = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          next.whenData((event) {
            if (!completer.isCompleted) {
              completer.complete(event);
            }
          });
        },
      );
      
      // Create a test event of kind 1 (should be filtered out)
      final textEvent = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 1,
        content: 'This should not appear',
        tags: [],
      ).sign('test_private_key');
      
      // Create a test event of kind 32222 (should pass through)
      final videoEvent = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 32222,
        content: '{"title": "Test Video"}',
        tags: [['d', 'test_video_id']],
      ).sign('test_private_key');
      
      // Publish events
      await relay.publish(textEvent);
      await relay.publish(videoEvent);
      
      // Wait for the kind 32222 event
      final receivedEvent = await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('No event received'),
      );
      
      // Should only receive the kind 32222 event
      expect(receivedEvent.kind, equals(32222));
      expect(receivedEvent.content, contains('Test Video'));
      
      listener.close();
    });
    
    test('eventListProvider accumulates events from stream', () async {
      // Initial state should be empty
      final initialEvents = container.read(eventListProvider);
      expect(initialEvents, isEmpty);
      
      // Get the relay and publish an event
      final relay = await container.read(relayProvider.future);
      
      final event = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 32222,
        content: '{"title": "Accumulated Event"}',
        tags: [['d', 'accumulated_id']],
      ).sign('test_private_key');
      
      await relay.publish(event);
      
      // Wait for processing
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Check that event was accumulated
      final events = container.read(eventListProvider);
      expect(events.length, equals(1));
      expect(events[0].kind, equals(32222));
    });
    
    test('identityProvider manages Nostr identity', () async {
      // Initial state should have no identity
      final initialIdentity = container.read(identityProvider);
      expect(initialIdentity, isNull);
      
      // Generate new identity
      await container.read(identityProvider.notifier).generateNewIdentity();
      
      // Should now have identity
      final identity = container.read(identityProvider);
      expect(identity, isNotNull);
      expect(identity!.publicKey, isNotEmpty);
      expect(identity.privateKey, isNotEmpty);
    });
    
    test('externalRelaysProvider connects to default relays', () async {
      // Get relay connections
      final relays = await container.read(externalRelaysProvider.future);
      
      // Should connect to relay3.openvine.co as primary
      expect(relays, contains('wss://relay3.openvine.co'));
      expect(relays.first, equals('wss://relay3.openvine.co'));
    });
  });
}