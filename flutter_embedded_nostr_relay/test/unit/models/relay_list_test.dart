// ABOUTME: Tests for RelayList model representing parsed kind:10002 events
// ABOUTME: Validates relay list structure, parsing, and access methods

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_list.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_metadata.dart';

void main() {
  group('RelayList', () {
    test('should create empty relay list', () {
      const authorPubkey = '1234567890abcdef';
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      
      expect(relayList.authorPubkey, equals(authorPubkey));
      expect(relayList.relays, isEmpty);
      expect(relayList.readRelays, isEmpty);
      expect(relayList.writeRelays, isEmpty);
    });
    
    test('should create relay list with mixed relay types', () {
      const authorPubkey = '1234567890abcdef';
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final relays = [
        RelayMetadata(url: 'wss://read-write.com'),  // both
        RelayMetadata(url: 'wss://read-only.com', read: true, write: false),
        RelayMetadata(url: 'wss://write-only.com', read: false, write: true),
      ];
      
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: updatedAt,
      );
      
      expect(relayList.relays, hasLength(3));
      expect(relayList.readRelays, hasLength(2));
      expect(relayList.writeRelays, hasLength(2));
      
      expect(relayList.readRelays.map((r) => r.url), containsAll([
        'wss://read-write.com',
        'wss://read-only.com',
      ]));
      
      expect(relayList.writeRelays.map((r) => r.url), containsAll([
        'wss://read-write.com', 
        'wss://write-only.com',
      ]));
    });
    
    test('should support equality comparison', () {
      const authorPubkey = '1234567890abcdef';
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final relays = [
        RelayMetadata(url: 'wss://relay.com'),
      ];
      
      final relayList1 = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: updatedAt,
      );
      
      final relayList2 = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: updatedAt,
      );
      
      final relayList3 = RelayList(
        authorPubkey: 'different-pubkey',
        relays: relays,
        updatedAt: updatedAt,
      );
      
      expect(relayList1, equals(relayList2));
      expect(relayList1, isNot(equals(relayList3)));
    });
    
    test('should serialize to and from JSON', () {
      const authorPubkey = '1234567890abcdef';
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final relays = [
        RelayMetadata(url: 'wss://relay1.com', read: true, write: false),
        RelayMetadata(url: 'wss://relay2.com', read: false, write: true, priority: 5),
      ];
      
      final originalList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: updatedAt,
      );
      
      final json = originalList.toJson();
      final deserializedList = RelayList.fromJson(json);
      
      expect(deserializedList, equals(originalList));
      expect(deserializedList.authorPubkey, equals(authorPubkey));
      expect(deserializedList.relays, hasLength(2));  
      expect(deserializedList.updatedAt, equals(updatedAt));
    });
    
    test('should find relay by URL', () {
      const authorPubkey = '1234567890abcdef';
      final relays = [
        RelayMetadata(url: 'wss://relay1.com'),
        RelayMetadata(url: 'wss://relay2.com'),
      ];
      
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: DateTime.now(),
      );
      
      final found = relayList.findRelayByUrl('wss://relay1.com');
      final notFound = relayList.findRelayByUrl('wss://nonexistent.com');
      
      expect(found, isNotNull);
      expect(found!.url, equals('wss://relay1.com'));
      expect(notFound, isNull);
    });
    
    test('should check if relay list contains URL', () {
      const authorPubkey = '1234567890abcdef';
      final relays = [
        RelayMetadata(url: 'wss://relay1.com'),
        RelayMetadata(url: 'wss://relay2.com'),
      ];
      
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: DateTime.now(),
      );
      
      expect(relayList.containsUrl('wss://relay1.com'), isTrue);
      expect(relayList.containsUrl('wss://nonexistent.com'), isFalse);
    });
    
    test('should get relays sorted by priority', () {
      const authorPubkey = '1234567890abcdef';
      final relays = [
        RelayMetadata(url: 'wss://low.com', priority: 1),
        RelayMetadata(url: 'wss://high.com', priority: 10),
        RelayMetadata(url: 'wss://medium.com', priority: 5),
        RelayMetadata(url: 'wss://no-priority.com'), // null priority
      ];
      
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: DateTime.now(),
      );
      
      final sortedRelays = relayList.relaysByPriority;
      
      // Should sort by priority descending, with null priorities last
      expect(sortedRelays[0].url, equals('wss://high.com'));
      expect(sortedRelays[1].url, equals('wss://medium.com'));
      expect(sortedRelays[2].url, equals('wss://low.com'));
      expect(sortedRelays[3].url, equals('wss://no-priority.com'));
    });
    
    test('should check if relay list is empty', () {
      const authorPubkey = '1234567890abcdef';
      
      final emptyList = RelayList(
        authorPubkey: authorPubkey,
        relays: [],
        updatedAt: DateTime.now(),
      );
      
      final nonEmptyList = RelayList(
        authorPubkey: authorPubkey,
        relays: [RelayMetadata(url: 'wss://relay.com')],
        updatedAt: DateTime.now(),
      );
      
      expect(emptyList.isEmpty, isTrue);
      expect(nonEmptyList.isEmpty, isFalse);
    });
    
    test('should have meaningful toString representation', () {
      const authorPubkey = '1234567890abcdef';
      final relays = [RelayMetadata(url: 'wss://relay.com')];
      
      final relayList = RelayList(
        authorPubkey: authorPubkey,
        relays: relays,
        updatedAt: DateTime.now(),
      );
      
      final toString = relayList.toString();
      expect(toString, contains(authorPubkey.substring(0, 8)));
      expect(toString, contains('1 relays'));
    });
  });
}