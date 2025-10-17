// ABOUTME: Basic unit tests for ExternalRelayClient without network connections
// ABOUTME: Tests basic functionality without attempting real WebSocket connections

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'dart:convert';

void main() {
  group('ExternalRelayClient Basic Tests', () {
    late ExternalRelayClient client;
    
    setUp(() {
      client = ExternalRelayClient(url: 'wss://relay.example.com');
    });
    
    test('initializes with correct URL', () {
      expect(client.url, 'wss://relay.example.com');
      expect(client.isConnected, false);
    });
    
    test('handles EVENT message parsing', () async {
      NostrEvent? receivedEvent;
      client.onEvent = (event) {
        receivedEvent = event;
      };
      
      final eventJson = json.encode([
        'EVENT',
        'sub1',
        {
          'id': 'test_id',
          'pubkey': 'test_pubkey',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'kind': 1,
          'tags': [],
          'content': 'Test content',
          'sig': 'test_sig',
        }
      ]);
      
      await client.handleMessage(eventJson);
      
      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.content, 'Test content');
      expect(receivedEvent!.kind, 1);
      expect(receivedEvent!.pubkey, 'test_pubkey');
    });
    
    test('handles EOSE message parsing', () async {
      String? eoseSubscription;
      client.onEose = (subId) {
        eoseSubscription = subId;
      };
      
      final eoseJson = json.encode(['EOSE', 'sub123']);
      await client.handleMessage(eoseJson);
      
      expect(eoseSubscription, 'sub123');
    });
    
    test('handles OK message parsing', () async {
      String? okEventId;
      bool? okStatus;
      String? okMessage;
      
      client.onOk = (eventId, status, message) {
        okEventId = eventId;
        okStatus = status;
        okMessage = message;
      };
      
      final okJson = json.encode(['OK', 'event123', true, 'Event accepted']);
      await client.handleMessage(okJson);
      
      expect(okEventId, 'event123');
      expect(okStatus, true);
      expect(okMessage, 'Event accepted');
    });
    
    test('handles OK message without reason', () async {
      String? okEventId;
      bool? okStatus;
      String? okMessage;
      
      client.onOk = (eventId, status, message) {
        okEventId = eventId;
        okStatus = status;
        okMessage = message;
      };
      
      final okJson = json.encode(['OK', 'event456', false]);
      await client.handleMessage(okJson);
      
      expect(okEventId, 'event456');
      expect(okStatus, false);
      expect(okMessage, isNull);
    });
    
    test('handles NOTICE message parsing', () async {
      String? noticeMessage;
      client.onNotice = (message) {
        noticeMessage = message;
      };
      
      final noticeJson = json.encode(['NOTICE', 'Rate limit exceeded']);
      await client.handleMessage(noticeJson);
      
      expect(noticeMessage, 'Rate limit exceeded');
    });
    
    test('ignores unknown message types', () async {
      // Should not throw
      await client.handleMessage(json.encode(['UNKNOWN', 'data']));
    });
    
    test('handles malformed messages gracefully', () async {
      // Should not throw
      await client.handleMessage('not json');
      await client.handleMessage(json.encode('not an array'));
      await client.handleMessage(json.encode([])); // empty array
    });
    
    test('sendRequest returns false when not connected', () async {
      final filter = Filter(kinds: [1], limit: 10);
      final result = await client.sendRequest('sub1', [filter]);
      expect(result, false);
    });
    
    test('sendEvent returns false when not connected', () async {
      final event = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 1,
        tags: [],
        content: 'Test',
      );
      final result = await client.sendEvent(event);
      expect(result, false);
    });
    
    test('closeSubscription returns false when not connected', () async {
      final result = await client.closeSubscription('sub1');
      expect(result, false);
    });
  });
}