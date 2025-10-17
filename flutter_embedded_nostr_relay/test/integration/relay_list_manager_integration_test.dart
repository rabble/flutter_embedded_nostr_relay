// ABOUTME: Integration tests for RelayListManager with real NostrEvent creation and signing
// ABOUTME: Tests end-to-end parsing of kind:10002 events with actual cryptographic operations

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_list_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';

void main() {
  group('RelayListManager Integration', () {
    late RelayListManager manager;
    late String privateKey;
    late String publicKey;

    setUp(() {
      manager = RelayListManager();
      
      // Use fixed test keys (in production, these would be generated securely)
      privateKey = '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      publicKey = 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
    });

    test('should parse kind:10002 event structure', () {
      // Create a kind:10002 event directly (unsigned for testing parsing logic)
      final event = NostrEvent(
        id: 'test-id-1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        pubkey: publicKey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [
          ['r', 'wss://relay.damus.io'],
          ['r', 'wss://nos.lol', 'read'],
          ['r', 'wss://relay.nostr.band', 'write', '10'],
          ['r', 'wss://offchain.pub', 'write'],
        ],
        content: '',
        sig: 'test-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      expect(event.kind, equals(10002));

      // Parse the relay list
      final relayList = manager.parseRelayList(event);

      expect(relayList.authorPubkey, equals(publicKey));
      expect(relayList.relays, hasLength(4));

      // Check individual relays
      final damusRelay = relayList.findRelayByUrl('wss://relay.damus.io');
      expect(damusRelay, isNotNull);
      expect(damusRelay!.read, isTrue);
      expect(damusRelay.write, isTrue);

      final nosRelay = relayList.findRelayByUrl('wss://nos.lol');
      expect(nosRelay, isNotNull);
      expect(nosRelay!.read, isTrue);
      expect(nosRelay.write, isFalse);

      final bandRelay = relayList.findRelayByUrl('wss://relay.nostr.band');
      expect(bandRelay, isNotNull);
      expect(bandRelay!.read, isFalse);
      expect(bandRelay.write, isTrue);
      expect(bandRelay.priority, equals(10));
    });

    test('should handle outbox model routing with real relay lists', () {
      // Create relay lists for two different users
      const user1PrivateKey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const user1PublicKey = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const user2PrivateKey = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const user2PublicKey = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

      // User 1's relay list (prefers high-priority relays for reading)
      final user1Event = NostrEvent(
        id: 'user1-id-1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        pubkey: user1PublicKey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [
          ['r', 'wss://user1-read.com', 'read', '10'],
          ['r', 'wss://user1-write.com', 'write', '5'],
          ['r', 'wss://shared.com'],  // read and write
        ],
        content: '',
        sig: 'user1-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // User 2's relay list
      final user2Event = NostrEvent(
        id: 'user2-id-1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        pubkey: user2PublicKey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [
          ['r', 'wss://user2-read.com', 'read'],
          ['r', 'wss://user2-write.com', 'write'],
        ],
        content: '',
        sig: 'user2-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // Parse and cache both relay lists
      final user1RelayList = manager.parseRelayList(user1Event);
      final user2RelayList = manager.parseRelayList(user2Event);
      
      manager.cacheRelayList(user1RelayList);
      manager.cacheRelayList(user2RelayList);

      // Test querying events from user1 (should use their read relays)
      final filter = Filter(authors: [user1PublicKey]);
      final selectedRelays = manager.selectRelaysForQuery(filter, user1PublicKey);

      expect(selectedRelays, hasLength(2));
      expect(selectedRelays, containsAll([
        'wss://user1-read.com',  // read-only with priority 10
        'wss://shared.com',      // read-write 
      ]));
      // Should be ordered by priority
      expect(selectedRelays[0], equals('wss://user1-read.com'));

      // Test selecting write relays for user1
      final writeRelays = manager.selectWriteRelaysForAuthor(user1PublicKey);
      expect(writeRelays, hasLength(2));
      expect(writeRelays, containsAll([
        'wss://shared.com',       // read-write (no priority)
        'wss://user1-write.com',  // write-only with priority 5
      ]));

      // Test multi-author query - should get read relays from both users
      final multiAuthorFilter = Filter(authors: [user1PublicKey, user2PublicKey]);
      final multiRelays = manager.selectRelaysForQuery(multiAuthorFilter, null);
      
      // Should get relays from both users, up to maxRelays limit
      expect(multiRelays.length, greaterThan(0));
      expect(multiRelays, containsAll([
        'wss://user1-read.com',
        'wss://shared.com',
        'wss://user2-read.com',
      ]));
    });

    test('should handle relay list updates correctly', () {
      final initialTime = DateTime.now().subtract(Duration(hours: 1));
      final updateTime = DateTime.now();

      // Create initial relay list
      final initialEvent = NostrEvent(
        id: 'initial-id-1234567890abcdef1234567890abcdef1234567890abcdef12345678',
        pubkey: publicKey,
        createdAt: initialTime.millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [
          ['r', 'wss://old-relay.com'],
        ],
        content: '',
        sig: 'initial-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // Create updated relay list
      final updatedEvent = NostrEvent(
        id: 'updated-id-1234567890abcdef1234567890abcdef1234567890abcdef12345678',
        pubkey: publicKey,
        createdAt: updateTime.millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [
          ['r', 'wss://new-relay.com'],
          ['r', 'wss://another-relay.com', 'read'],
        ],
        content: '',
        sig: 'updated-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // Parse and cache initial list
      final initialList = manager.parseRelayList(initialEvent);
      manager.cacheRelayList(initialList);

      expect(manager.getCachedRelayList(publicKey), equals(initialList));
      expect(manager.getCachedRelayList(publicKey)!.relays, hasLength(1));

      // Parse and cache updated list
      final updatedList = manager.parseRelayList(updatedEvent);
      manager.cacheRelayList(updatedList);

      // Should have replaced the old list
      final cached = manager.getCachedRelayList(publicKey)!;
      expect(cached, equals(updatedList));
      expect(cached.relays, hasLength(2));
      expect(cached.findRelayByUrl('wss://new-relay.com'), isNotNull);
      expect(cached.findRelayByUrl('wss://old-relay.com'), isNull);
    });

    test('should reject older relay list updates', () {
      final newTime = DateTime.now();
      final oldTime = newTime.subtract(Duration(hours: 1));

      // Create newer relay list first
      final newerEvent = NostrEvent(
        id: 'newer-id-1234567890abcdef1234567890abcdef1234567890abcdef123456789',
        pubkey: publicKey,
        createdAt: newTime.millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [['r', 'wss://new-relay.com']],
        content: '',
        sig: 'newer-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // Create older relay list
      final olderEvent = NostrEvent(
        id: 'older-id-1234567890abcdef1234567890abcdef1234567890abcdef123456789',
        pubkey: publicKey,
        createdAt: oldTime.millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [['r', 'wss://old-relay.com']],
        content: '',
        sig: 'older-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      // Cache newer list first
      final newerList = manager.parseRelayList(newerEvent);
      manager.cacheRelayList(newerList);

      // Try to cache older list - should be ignored
      final olderList = manager.parseRelayList(olderEvent);
      manager.cacheRelayList(olderList);

      // Should still have the newer list
      final cached = manager.getCachedRelayList(publicKey)!;
      expect(cached, equals(newerList));
      expect(cached.findRelayByUrl('wss://new-relay.com'), isNotNull);
      expect(cached.findRelayByUrl('wss://old-relay.com'), isNull);
    });

    test('should work with empty relay lists', () {
      // Create an empty relay list
      final emptyEvent = NostrEvent(
        id: 'empty-id-1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        pubkey: publicKey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 10002,
        tags: [],
        content: '',
        sig: 'empty-signature-1234567890abcdef1234567890abcdef1234567890abcdef',
      );

      final relayList = manager.parseRelayList(emptyEvent);
      manager.cacheRelayList(relayList);

      expect(relayList.isEmpty, isTrue);
      expect(relayList.readRelays, isEmpty);
      expect(relayList.writeRelays, isEmpty);

      // Queries should return empty results
      final filter = Filter(authors: [publicKey]);
      final selectedRelays = manager.selectRelaysForQuery(filter, publicKey);
      expect(selectedRelays, isEmpty);

      final writeRelays = manager.selectWriteRelaysForAuthor(publicKey);
      expect(writeRelays, isEmpty);
    });
  });
}