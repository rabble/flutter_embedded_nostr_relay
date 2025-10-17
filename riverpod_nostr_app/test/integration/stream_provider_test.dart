// ABOUTME: Tests for StreamProvider real-time event updates from external relays
// ABOUTME: Verifies that events flow from external relays through embedded relay to UI

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  group('StreamProvider Real-time Update Tests', () {
    late ProviderContainer container;
    
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      container = ProviderContainer();
    });
    
    tearDown(() async {
      container.dispose();
    });
    
    test('StreamProvider emits events in real-time as they arrive', () async {
      // Initialize relay
      final relay = await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      // Collect events from the stream
      final receivedEvents = <NostrEvent>[];
      final streamSubscription = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            receivedEvents.add(next.value!);
          }
        },
      );
      
      // Generate and publish events with delays
      final privateKey = NostrCrypto.generatePrivateKey();
      final pubkey = NostrCrypto.getPublicKey(privateKey);
      
      for (int i = 0; i < 5; i++) {
        final event = NostrEvent.create(
          pubkey: pubkey,
          kind: 32222,
          tags: [
            ['d', 'realtime_test_$i'],
          ],
          content: '{"title": "Real-time Event $i", "timestamp": ${DateTime.now().millisecondsSinceEpoch}}',
        );
        
        final signedEvent = event.sign(privateKey);
        await relay.publish(signedEvent);
        
        // Wait to ensure ordering
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      // Wait for all events to be received
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify we received the events
      expect(receivedEvents.length, equals(5));
      
      // Verify they arrived in order
      for (int i = 0; i < receivedEvents.length; i++) {
        expect(receivedEvents[i].content.contains('Real-time Event $i'), isTrue);
      }
      
      streamSubscription.close();
    });
    
    test('StreamProvider filters only kind 32222 events', () async {
      // Initialize relay
      final relay = await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      // Track received events
      final receivedEvents = <NostrEvent>[];
      final streamSubscription = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            receivedEvents.add(next.value!);
          }
        },
      );
      
      // Publish mixed event kinds
      final privateKey = NostrCrypto.generatePrivateKey();
      
      // Publish kind 1 (text note) - should NOT be received
      final textNote = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 1,
        tags: [],
        content: 'This is a text note',
      ).sign(privateKey);
      await relay.publish(textNote);
      
      // Publish kind 32222 - SHOULD be received
      final videoEvent = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 32222,
        tags: [['d', 'filtered_video']],
        content: '{"title": "Filtered Video"}',
      ).sign(privateKey);
      await relay.publish(videoEvent);
      
      // Publish kind 0 (metadata) - should NOT be received
      final metadata = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 0,
        tags: [],
        content: '{"name": "Test User"}',
      ).sign(privateKey);
      await relay.publish(metadata);
      
      // Wait for events
      await Future.delayed(const Duration(seconds: 2));
      
      // Should only receive the kind 32222 event
      expect(receivedEvents.length, equals(1));
      expect(receivedEvents[0].kind, equals(32222));
      expect(receivedEvents[0].content.contains('Filtered Video'), isTrue);
      
      streamSubscription.close();
    });
    
    test('Multiple StreamProvider listeners receive same events', () async {
      // Initialize relay
      final relay = await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      // Create multiple listeners
      final listener1Events = <NostrEvent>[];
      final listener2Events = <NostrEvent>[];
      
      final subscription1 = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            listener1Events.add(next.value!);
          }
        },
      );
      
      final subscription2 = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            listener2Events.add(next.value!);
          }
        },
      );
      
      // Publish an event
      final privateKey = NostrCrypto.generatePrivateKey();
      final event = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 32222,
        tags: [['d', 'multi_listener_test']],
        content: '{"title": "Multi-listener Test"}',
      ).sign(privateKey);
      
      await relay.publish(event);
      
      // Wait for propagation
      await Future.delayed(const Duration(seconds: 2));
      
      // Both listeners should receive the same event
      expect(listener1Events.length, equals(1));
      expect(listener2Events.length, equals(1));
      expect(listener1Events[0].id, equals(listener2Events[0].id));
      
      subscription1.close();
      subscription2.close();
    });
    
    test('StreamProvider continues after relay reconnection', () async {
      // This test would require mocking relay disconnection/reconnection
      // For now, we'll test that the stream stays active over time
      
      final relay = await container.read(relayProvider.future);
      await Future.delayed(const Duration(seconds: 2));
      
      final receivedEvents = <NostrEvent>[];
      final streamSubscription = container.listen(
        addressableEventStreamProvider,
        (previous, next) {
          if (next.hasValue && next.value != null) {
            receivedEvents.add(next.value!);
          }
        },
      );
      
      final privateKey = NostrCrypto.generatePrivateKey();
      
      // Publish first event
      final event1 = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 32222,
        tags: [['d', 'persistence_test_1']],
        content: '{"title": "Event 1"}',
      ).sign(privateKey);
      await relay.publish(event1);
      
      // Wait longer to simulate time passing
      await Future.delayed(const Duration(seconds: 3));
      
      // Publish second event after delay
      final event2 = NostrEvent.create(
        pubkey: NostrCrypto.getPublicKey(privateKey),
        kind: 32222,
        tags: [['d', 'persistence_test_2']],
        content: '{"title": "Event 2"}',
      ).sign(privateKey);
      await relay.publish(event2);
      
      // Wait for second event
      await Future.delayed(const Duration(seconds: 2));
      
      // Should receive both events despite time gap
      expect(receivedEvents.length, equals(2));
      expect(receivedEvents[0].content.contains('Event 1'), isTrue);
      expect(receivedEvents[1].content.contains('Event 2'), isTrue);
      
      streamSubscription.close();
    });
  });
}