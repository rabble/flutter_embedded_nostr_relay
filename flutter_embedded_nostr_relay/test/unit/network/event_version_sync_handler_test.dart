// ABOUTME: TDD tests for bidirectional event version synchronization
// ABOUTME: Tests event version comparison and relay push-back logic

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:flutter_embedded_nostr_relay/src/network/event_version_sync_handler.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/utils/crypto.dart';

import 'event_version_sync_handler_test.mocks.dart';

@GenerateMocks([EventStore, ExternalRelayClient])
void main() {
  group('EventVersionSyncHandler', () {
    late EventVersionSyncHandler syncHandler;
    late MockEventStore mockEventStore;
    late MockExternalRelayClient mockRelayClient;
    
    // Test keys
    final testPrivateKey = NostrCrypto.generatePrivateKey();
    final testPublicKey = NostrCrypto.getPublicKey(testPrivateKey);
    
    setUp(() {
      mockEventStore = MockEventStore();
      mockRelayClient = MockExternalRelayClient();
      syncHandler = EventVersionSyncHandler(
        eventStore: mockEventStore,
        relayClient: mockRelayClient,
      );
    });
    
    group('Regular Events (kind < 10000)', () {
      test('should store new event when we dont have it', () async {
        final newEvent = NostrEvent.create(
          pubkey: testPublicKey,
          kind: 1,
          content: 'Test note',
          tags: [],
        ).sign(testPrivateKey);
        
        when(mockEventStore.getEventById(newEvent.id))
            .thenAnswer((_) async => null);
        when(mockEventStore.storeEvent(newEvent))
            .thenAnswer((_) async => true);
        
        final result = await syncHandler.handleIncomingEvent(newEvent);
        
        expect(result.action, equals(SyncAction.stored));
        verify(mockEventStore.storeEvent(newEvent)).called(1);
        verifyNever(mockRelayClient.sendEvent(any));
      });
      
      test('should reject duplicate event with same ID', () async {
        final existingEvent = NostrEvent.create(
          pubkey: testPublicKey,
          kind: 1,
          content: 'Test note',
          tags: [],
        ).sign(testPrivateKey);
        
        when(mockEventStore.getEventById(existingEvent.id))
            .thenAnswer((_) async => existingEvent);
        
        final result = await syncHandler.handleIncomingEvent(existingEvent);
        
        expect(result.action, equals(SyncAction.duplicate));
        verifyNever(mockEventStore.storeEvent(any));
        verifyNever(mockRelayClient.sendEvent(any));
      });
    });
    
    group('Replaceable Events (kind 10000-19999)', () {
      test('should push back our newer version and reject older incoming', () async {
        final newerLocalEvent = NostrEvent.create(
          pubkey: testPublicKey,
          kind: 10000,
          content: 'Newer local version',
          tags: [],
          createdAt: 2000,
        ).sign(testPrivateKey);
        
        final olderIncomingEvent = NostrEvent.create(
          pubkey: testPublicKey,
          kind: 10000,
          content: 'Older incoming version',
          tags: [],
          createdAt: 1000,
        ).sign(testPrivateKey);
        
        when(mockEventStore.getEventById(olderIncomingEvent.id))
            .thenAnswer((_) async => null);
        when(mockEventStore.getLatestReplaceableEvent(10000, testPublicKey))
            .thenAnswer((_) async => newerLocalEvent);
        when(mockRelayClient.sendEvent(newerLocalEvent))
            .thenAnswer((_) async => true);
        
        final result = await syncHandler.handleIncomingEvent(olderIncomingEvent);
        
        expect(result.action, equals(SyncAction.pushedBackNewer));
        expect(result.reason, contains('pushed newer version'));
        verify(mockRelayClient.sendEvent(newerLocalEvent)).called(1);
        verifyNever(mockEventStore.storeEvent(olderIncomingEvent));
      });
    });
    
    group('Ephemeral Events (kind 20000-29999)', () {
      test('should not store ephemeral events but still process them', () async {
        final ephemeralEvent = NostrEvent.create(
          pubkey: testPublicKey,
          kind: 20000,
          content: 'Ephemeral message',
          tags: [],
        ).sign(testPrivateKey);
        
        final result = await syncHandler.handleIncomingEvent(ephemeralEvent);
        
        expect(result.action, equals(SyncAction.ephemeralProcessed));
        verifyNever(mockEventStore.storeEvent(any));
        verifyNever(mockRelayClient.sendEvent(any));
      });
    });
  });
}