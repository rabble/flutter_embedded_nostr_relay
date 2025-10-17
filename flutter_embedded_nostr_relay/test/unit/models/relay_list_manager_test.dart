// ABOUTME: Tests for RelayListManager class implementing NIP-65 relay list parsing and management
// ABOUTME: Validates kind:10002 event parsing, relay selection, and outbox model routing logic

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_list_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_list.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_metadata.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';

void main() {
  group('RelayListManager', () {
    late RelayListManager manager;

    setUp(() {
      manager = RelayListManager();
    });

    group('parseRelayList', () {
      test('should parse kind:10002 event with mixed relay types', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        const createdAt = 1700000000;
        
        final event = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 10002,
          tags: [
            ['r', 'wss://read-write.com'],
            ['r', 'wss://read-only.com', 'read'],
            ['r', 'wss://write-only.com', 'write'],
            ['r', 'wss://priority.com', 'write', '10'],  // with priority
          ],
          content: '',
          createdAt: createdAt,
        );
        
        final relayList = manager.parseRelayList(event);
        
        expect(relayList.authorPubkey, equals(authorPubkey));
        expect(relayList.relays, hasLength(4));
        expect(relayList.updatedAt, 
            equals(DateTime.fromMillisecondsSinceEpoch(createdAt * 1000)));
        
        // Check read-write relay (no marker)
        final readWriteRelay = relayList.findRelayByUrl('wss://read-write.com');
        expect(readWriteRelay, isNotNull);
        expect(readWriteRelay!.read, isTrue);
        expect(readWriteRelay.write, isTrue);
        
        // Check read-only relay
        final readOnlyRelay = relayList.findRelayByUrl('wss://read-only.com');
        expect(readOnlyRelay, isNotNull);
        expect(readOnlyRelay!.read, isTrue);
        expect(readOnlyRelay.write, isFalse);
        
        // Check write-only relay
        final writeOnlyRelay = relayList.findRelayByUrl('wss://write-only.com');
        expect(writeOnlyRelay, isNotNull);
        expect(writeOnlyRelay!.read, isFalse);
        expect(writeOnlyRelay.write, isTrue);
        
        // Check priority relay
        final priorityRelay = relayList.findRelayByUrl('wss://priority.com');
        expect(priorityRelay, isNotNull);
        expect(priorityRelay!.priority, equals(10));
      });
      
      test('should handle empty kind:10002 event', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final event = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 10002,
          tags: [],
          content: '',
        );
        
        final relayList = manager.parseRelayList(event);
        
        expect(relayList.authorPubkey, equals(authorPubkey));
        expect(relayList.relays, isEmpty);
      });
      
      test('should ignore non-r tags in kind:10002 event', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final event = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 10002,
          tags: [
            ['r', 'wss://valid-relay.com'],
            ['p', 'some-pubkey'],  // should be ignored
            ['e', 'some-event-id'],  // should be ignored
            ['t', 'some-topic'],  // should be ignored
          ],
          content: '',
        );
        
        final relayList = manager.parseRelayList(event);
        
        expect(relayList.relays, hasLength(1));
        expect(relayList.findRelayByUrl('wss://valid-relay.com'), isNotNull);
      });
      
      test('should handle malformed r tags gracefully', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final event = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 10002,
          tags: [
            ['r'],  // missing URL
            ['r', ''],  // empty URL
            ['r', 'invalid-url'],  // invalid URL format
            ['r', 'wss://valid-relay.com'],  // valid relay
          ],
          content: '',
        );
        
        final relayList = manager.parseRelayList(event);
        
        // Should only include the valid relay
        expect(relayList.relays, hasLength(1));
        expect(relayList.findRelayByUrl('wss://valid-relay.com'), isNotNull);
      });
      
      test('should throw ArgumentError for non-kind:10002 events', () {
        final event = NostrEvent.create(
          pubkey: '1234567890abcdef1234567890abcdef12345678',
          kind: 1,  // wrong kind
          tags: [],
          content: 'Hello world',
        );
        
        expect(() => manager.parseRelayList(event), 
            throwsA(isA<ArgumentError>()));
      });
    });

    group('selectRelaysForQuery', () {
      test('should select read relays for author-specific queries', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [
            RelayMetadata(url: 'wss://read-write.com'),
            RelayMetadata(url: 'wss://read-only.com', read: true, write: false),
            RelayMetadata(url: 'wss://write-only.com', read: false, write: true),
          ],
          updatedAt: DateTime.now(),
        );
        
        // Cache the relay list
        manager.cacheRelayList(relayList);
        
        final filter = Filter(authors: [authorPubkey]);
        final selectedRelays = manager.selectRelaysForQuery(filter, authorPubkey);
        
        expect(selectedRelays, hasLength(2));
        expect(selectedRelays, containsAll([
          'wss://read-write.com',
          'wss://read-only.com',
        ]));
        expect(selectedRelays, isNot(contains('wss://write-only.com')));
      });
      
      test('should select write relays for publishing events', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [
            RelayMetadata(url: 'wss://read-write.com'),
            RelayMetadata(url: 'wss://read-only.com', read: true, write: false),
            RelayMetadata(url: 'wss://write-only.com', read: false, write: true),
          ],
          updatedAt: DateTime.now(),
        );
        
        manager.cacheRelayList(relayList);
        
        final writeRelays = manager.selectWriteRelaysForAuthor(authorPubkey);
        
        expect(writeRelays, hasLength(2));
        expect(writeRelays, containsAll([
          'wss://read-write.com',
          'wss://write-only.com',
        ]));
        expect(writeRelays, isNot(contains('wss://read-only.com')));
      });
      
      test('should return empty list for unknown authors', () {
        final filter = Filter(authors: ['unknown-author']);
        final selectedRelays = manager.selectRelaysForQuery(filter, 'unknown-author');
        
        expect(selectedRelays, isEmpty);
      });
      
      test('should prefer relays by priority', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [
            RelayMetadata(url: 'wss://low-priority.com', priority: 1),
            RelayMetadata(url: 'wss://high-priority.com', priority: 10),
            RelayMetadata(url: 'wss://medium-priority.com', priority: 5),
          ],
          updatedAt: DateTime.now(),
        );
        
        manager.cacheRelayList(relayList);
        
        final selectedRelays = manager.selectRelaysForQuery(
          Filter(authors: [authorPubkey]), 
          authorPubkey,
        );
        
        // Should return relays in priority order (highest first)
        expect(selectedRelays, equals([
          'wss://high-priority.com',
          'wss://medium-priority.com', 
          'wss://low-priority.com',
        ]));
      });
      
      test('should limit number of selected relays', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: List.generate(10, (i) => 
            RelayMetadata(url: 'wss://relay$i.com')),
          updatedAt: DateTime.now(),
        );
        
        manager.cacheRelayList(relayList);
        
        final selectedRelays = manager.selectRelaysForQuery(
          Filter(authors: [authorPubkey]), 
          authorPubkey,
          maxRelays: 3,
        );
        
        expect(selectedRelays, hasLength(3));
      });
    });

    group('caching', () {
      test('should cache and retrieve relay lists', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [RelayMetadata(url: 'wss://relay.com')],
          updatedAt: DateTime.now(),
        );
        
        manager.cacheRelayList(relayList);
        
        final cached = manager.getCachedRelayList(authorPubkey);
        expect(cached, isNotNull);
        expect(cached, equals(relayList));
      });
      
      test('should return null for uncached authors', () {
        final cached = manager.getCachedRelayList('unknown-author');
        expect(cached, isNull);
      });
      
      test('should clear cache', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final relayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [RelayMetadata(url: 'wss://relay.com')],
          updatedAt: DateTime.now(),
        );
        
        manager.cacheRelayList(relayList);
        expect(manager.getCachedRelayList(authorPubkey), isNotNull);
        
        manager.clearCache();
        expect(manager.getCachedRelayList(authorPubkey), isNull);
      });
      
      test('should update existing cache entries', () {
        const authorPubkey = '1234567890abcdef1234567890abcdef12345678';
        
        final oldRelayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [RelayMetadata(url: 'wss://old-relay.com')],
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        
        final newRelayList = RelayList(
          authorPubkey: authorPubkey,
          relays: [RelayMetadata(url: 'wss://new-relay.com')],
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700001000000),
        );
        
        manager.cacheRelayList(oldRelayList);
        manager.cacheRelayList(newRelayList);
        
        final cached = manager.getCachedRelayList(authorPubkey);
        expect(cached, equals(newRelayList));
        expect(cached!.findRelayByUrl('wss://new-relay.com'), isNotNull);
        expect(cached.findRelayByUrl('wss://old-relay.com'), isNull);
      });
    });
  });
}