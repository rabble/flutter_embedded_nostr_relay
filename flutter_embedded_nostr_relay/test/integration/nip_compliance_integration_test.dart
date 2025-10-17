// ABOUTME: NIP compliance integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests protocol compliance for NIP-01, NIP-09, NIP-11, NIP-65 and related features

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_info.dart';
import 'package:flutter_embedded_nostr_relay/src/core/constants.dart';
import 'package:flutter_embedded_nostr_relay/src/utils/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('NIP Compliance Integration Tests', () {
    late WebSocketServer server;
    late SubscriptionManager subscriptionManager;
    late EventStore eventStore;
    late DatabaseHelper databaseHelper;
    
    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    
    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      databaseHelper = DatabaseHelper.instance;
      eventStore = EventStore(databaseHelper: databaseHelper);
      subscriptionManager = SubscriptionManager();
      
      server = WebSocketServer(
        subscriptionManager: subscriptionManager,
        eventStore: eventStore,
      );
      
      await server.start(port: 0); // Use random available port
    });
    
    tearDown(() async {
      await server.stop();
      await subscriptionManager.close();
      await DatabaseHelper.reset();
    });

    group('NIP-01: Basic Protocol', () {
      test('should handle valid REQ message format', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // NIP-01: REQ message format: ["REQ", <subscription_id>, <filters...>]
        final reqMessage = json.encode([
          'REQ',
          'valid-sub-id',
          {'kinds': [1], 'limit': 10}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive EOSE
        expect(responses.length, greaterThanOrEqualTo(1));
        final eoseResponse = json.decode(responses.first) as List;
        expect(eoseResponse[0], equals('EOSE'));
        expect(eoseResponse[1], equals('valid-sub-id'));
        
        await client.sink.close();
      });

      test('should handle valid EVENT message format', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Create valid event according to NIP-01
        final baseEvent = NostrEvent.create(
          pubkey: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
          kind: 1,
          tags: [['t', 'nostr']],
          content: 'Hello NIP-01!',
        );
        
        final event = baseEvent.copyWith(
          sig: 'valid_test_signature_' + baseEvent.id.substring(0, 40),
        );
        
        // NIP-01: EVENT message format: ["EVENT", <event JSON>]
        final eventMessage = json.encode(['EVENT', event.toJson()]);
        client.sink.add(eventMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive OK response: ["OK", <event_id>, <true|false>, <message>]
        bool foundOkResponse = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == event.id) {
            foundOkResponse = true;
            expect(responseJson[2], isA<bool>());
            break;
          }
        }
        expect(foundOkResponse, isTrue);
        
        await client.sink.close();
      });

      test('should handle CLOSE message format', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Create subscription first
        final reqMessage = json.encode([
          'REQ',
          'closeable-sub',
          {'kinds': [1]}
        ]);
        client.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // NIP-01: CLOSE message format: ["CLOSE", <subscription_id>]
        final closeMessage = json.encode(['CLOSE', 'closeable-sub']);
        client.sink.add(closeMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Verify subscription is closed by sending an event that would match
        final event = NostrEvent.create(
          pubkey: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
          kind: 1,
          tags: [],
          content: 'Should not be routed to closed subscription',
        ).copyWith(
          sig: 'test_signature_123456789012345678901234567890',
        );
        
        client.sink.add(json.encode(['EVENT', event.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Count EVENT messages for closed subscription
        int eventMessagesForClosedSub = 0;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT' && responseJson[1] == 'closeable-sub') {
            eventMessagesForClosedSub++;
          }
        }
        
        expect(eventMessagesForClosedSub, equals(0));
        
        await client.sink.close();
      });

      test('should validate event structure according to NIP-01', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Test invalid event - missing required fields
        final invalidEvent = {
          'id': 'invalid-event-id',
          'pubkey': 'invalid-pubkey',
          // Missing: created_at, kind, tags, content, sig
        };
        
        final eventMessage = json.encode(['EVENT', invalidEvent]);
        client.sink.add(eventMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive OK response with false (rejected)
        bool foundRejection = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == 'invalid-event-id') {
            foundRejection = true;
            expect(responseJson[2], equals(false)); // Event rejected
            break;
          }
        }
        expect(foundRejection, isTrue);
        
        await client.sink.close();
      });

      test('should handle filters according to NIP-01 specification', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Store test events first
        final events = [
          NostrEvent.create(
            pubkey: 'author1111111111111111111111111111111111111111111111111111111111',
            kind: 1,
            tags: [['t', 'test']],
            content: 'Text note from author1',
          ).copyWith(sig: 'sig1' + '1' * 120),
          
          NostrEvent.create(
            pubkey: 'author2222222222222222222222222222222222222222222222222222222222',
            kind: 2,
            tags: [['r', 'wss://relay.example.com']],
            content: 'Relay recommendation',
          ).copyWith(sig: 'sig2' + '2' * 120),
          
          NostrEvent.create(
            pubkey: 'author1111111111111111111111111111111111111111111111111111111111',
            kind: 7,
            tags: [['e', 'referenced-event-id']],
            content: '+',
          ).copyWith(sig: 'sig3' + '3' * 120),
        ];
        
        for (final event in events) {
          client.sink.add(json.encode(['EVENT', event.toJson()]));
        }
        
        await Future.delayed(Duration(milliseconds: 200));
        responses.clear(); // Clear setup responses
        
        // Test complex filter according to NIP-01
        final complexFilter = {
          'kinds': [1, 7], // Multiple kinds
          'authors': ['author1111111111111111111111111111111111111111111111111111111111'], // Specific author
          'since': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, // Time filter
          'limit': 10
        };
        
        final reqMessage = json.encode(['REQ', 'complex-filter-test', complexFilter]);
        client.sink.add(reqMessage);
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Should receive EOSE and matching events
        int matchingEvents = 0;
        bool foundEose = false;
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EOSE') {
            foundEose = true;
          } else if (responseJson[0] == 'EVENT') {
            final eventData = responseJson[2] as Map<String, dynamic>;
            // Verify event matches filter
            expect([1, 7], contains(eventData['kind']));
            expect(eventData['pubkey'], equals('author1111111111111111111111111111111111111111111111111111111111'));
            matchingEvents++;
          }
        }
        
        expect(foundEose, isTrue);
        expect(matchingEvents, equals(2)); // Should match text note and reaction
        
        await client.sink.close();
      });
    });

    group('NIP-09: Event Deletion', () {
      test('should handle deletion events properly', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        final authorPubkey = 'author1111111111111111111111111111111111111111111111111111111111';
        
        // Create and store original event
        final originalEvent = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 1,
          tags: [],
          content: 'This will be deleted',
        ).copyWith(sig: 'original_sig' + '1' * 110);
        
        client.sink.add(json.encode(['EVENT', originalEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Create deletion event (kind 5) according to NIP-09
        final deletionEvent = NostrEvent.create(
          pubkey: authorPubkey, // Must be same author
          kind: RelayConstants.kindDeletion, // Kind 5
          tags: [['e', originalEvent.id]], // Reference deleted event
          content: 'These events were deleted due to spam',
        ).copyWith(sig: 'deletion_sig' + '2' * 110);
        
        client.sink.add(json.encode(['EVENT', deletionEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 200));
        
        // Verify deletion event was stored
        bool foundDeletionOk = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == deletionEvent.id) {
            foundDeletionOk = true;
            expect(responseJson[2], equals(true));
            break;
          }
        }
        expect(foundDeletionOk, isTrue);
        
        await client.sink.close();
      });

      test('should reject deletion events from different authors', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        final originalAuthor = 'author1111111111111111111111111111111111111111111111111111111111';
        final differentAuthor = 'author2222222222222222222222222222222222222222222222222222222222';
        
        // Create original event
        final originalEvent = NostrEvent.create(
          pubkey: originalAuthor,
          kind: 1,
          tags: [],
          content: 'Original event',
        ).copyWith(sig: 'original_sig' + '1' * 110);
        
        client.sink.add(json.encode(['EVENT', originalEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Try to delete with different author
        final invalidDeletionEvent = NostrEvent.create(
          pubkey: differentAuthor, // Different author - should be rejected
          kind: RelayConstants.kindDeletion,
          tags: [['e', originalEvent.id]],
          content: 'Trying to delete someone elses event',
        ).copyWith(sig: 'invalid_deletion_sig' + '3' * 100);
        
        client.sink.add(json.encode(['EVENT', invalidDeletionEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive OK with false (rejected)
        bool foundRejection = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == invalidDeletionEvent.id) {
            foundRejection = true;
            expect(responseJson[2], equals(false)); // Should be rejected
            break;
          }
        }
        expect(foundRejection, isTrue);
        
        await client.sink.close();
      });
    });

    group('NIP-11: Relay Information Document', () {
      test('should provide relay information via HTTP GET', () async {
        // Make HTTP GET request to relay's HTTP endpoint
        final httpClient = HttpClient();
        
        try {
          final request = await httpClient.get('localhost', server.port, '/');
          request.headers.set('Accept', 'application/nostr+json');
          
          final response = await request.close();
          
          expect(response.statusCode, equals(200));
          expect(response.headers.contentType?.mimeType, equals('application/json'));
          
          final responseBody = await response.transform(utf8.decoder).join();
          final relayInfo = json.decode(responseBody) as Map<String, dynamic>;
          
          // Verify required NIP-11 fields
          expect(relayInfo, containsPair('name', isA<String>()));
          expect(relayInfo, containsPair('description', isA<String>()));
          expect(relayInfo, containsPair('supported_nips', isA<List>()));
          expect(relayInfo, containsPair('software', isA<String>()));
          expect(relayInfo, containsPair('version', isA<String>()));
          
          // Verify supported NIPs list
          final supportedNips = relayInfo['supported_nips'] as List;
          expect(supportedNips, contains(1)); // NIP-01 should be supported
          
        } finally {
          httpClient.close();
        }
      });

      test('should handle OPTIONS request for CORS', () async {
        final httpClient = HttpClient();
        
        try {
          final request = await httpClient.open('OPTIONS', 'localhost', server.port, '/');
          final response = await request.close();
          
          expect(response.statusCode, equals(200));
          expect(response.headers.value('access-control-allow-origin'), equals('*'));
          expect(response.headers.value('access-control-allow-methods'), 
                 contains('GET'));
          
        } finally {
          httpClient.close();
        }
      });
    });

    group('NIP-65: Relay List Metadata', () {
      test('should handle relay list events (kind 10002)', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Create NIP-65 relay list event
        final relayListEvent = NostrEvent.create(
          pubkey: 'user1111111111111111111111111111111111111111111111111111111111111',
          kind: 10002, // NIP-65 relay list
          tags: [
            ['r', 'wss://relay1.example.com'],
            ['r', 'wss://relay2.example.com', 'write'],
            ['r', 'wss://relay3.example.com', 'read'],
          ],
          content: '',
        ).copyWith(sig: 'relay_list_sig' + '1' * 110);
        
        client.sink.add(json.encode(['EVENT', relayListEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive OK response
        bool foundOkResponse = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'OK' && responseJson[1] == relayListEvent.id) {
            foundOkResponse = true;
            expect(responseJson[2], equals(true));
            break;
          }
        }
        expect(foundOkResponse, isTrue);
        
        await client.sink.close();
      });

      test('should store and retrieve relay list events as replaceable', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        final userPubkey = 'user2222222222222222222222222222222222222222222222222222222222222';
        
        // Store first relay list
        final firstRelayList = NostrEvent.create(
          pubkey: userPubkey,
          kind: 10002,
          tags: [['r', 'wss://old-relay.example.com']],
          content: '',
        ).copyWith(
          createdAt: DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          sig: 'first_relay_list_sig' + '1' * 100,
        );
        
        client.sink.add(json.encode(['EVENT', firstRelayList.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Store newer relay list (should replace the first one)
        final newerRelayList = NostrEvent.create(
          pubkey: userPubkey,
          kind: 10002,
          tags: [['r', 'wss://new-relay.example.com']],
          content: '',
        ).copyWith(
          sig: 'newer_relay_list_sig' + '2' * 100,
        );
        
        client.sink.add(json.encode(['EVENT', newerRelayList.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        responses.clear();
        
        // Query for relay list events
        final reqMessage = json.encode([
          'REQ',
          'relay-list-query',
          {'kinds': [10002], 'authors': [userPubkey]}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should only receive the newer event (replaceable behavior)
        int relayListEventsCount = 0;
        String? receivedEventId;
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT') {
            final eventData = responseJson[2] as Map<String, dynamic>;
            if (eventData['kind'] == 10002) {
              relayListEventsCount++;
              receivedEventId = eventData['id'];
            }
          }
        }
        
        expect(relayListEventsCount, equals(1));
        expect(receivedEventId, equals(newerRelayList.id));
        
        await client.sink.close();
      });
    });

    group('Protocol Limits Compliance', () {
      test('should respect maximum subscription limits', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Create maximum allowed subscriptions
        for (int i = 0; i < RelayConstants.maxSubscriptions; i++) {
          final reqMessage = json.encode([
            'REQ',
            'sub-$i',
            {'kinds': [1], 'limit': 1}
          ]);
          client.sink.add(reqMessage);
        }
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Try to create one more subscription (should be rejected)
        final excessReqMessage = json.encode([
          'REQ',
          'excess-sub',
          {'kinds': [1], 'limit': 1}
        ]);
        client.sink.add(excessReqMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive NOTICE about too many subscriptions
        bool foundTooManyNotice = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'NOTICE' && 
              responseJson[1].toString().contains('too many')) {
            foundTooManyNotice = true;
            break;
          }
        }
        expect(foundTooManyNotice, isTrue);
        
        await client.sink.close();
      });

      test('should respect message size limits', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Create event with content exceeding maximum size
        final largeContent = 'x' * (RelayConstants.maxEventSize + 1000);
        final largeEvent = NostrEvent.create(
          pubkey: 'author1111111111111111111111111111111111111111111111111111111111',
          kind: 1,
          tags: [],
          content: largeContent,
        ).copyWith(sig: 'large_event_sig' + '1' * 110);
        
        final eventMessage = json.encode(['EVENT', largeEvent.toJson()]);
        client.sink.add(eventMessage);
        
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive OK with false (rejected) or NOTICE about size
        bool foundRejection = false;
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if ((responseJson[0] == 'OK' && responseJson[1] == largeEvent.id && responseJson[2] == false) ||
              (responseJson[0] == 'NOTICE' && responseJson[1].toString().contains('too large'))) {
            foundRejection = true;
            break;
          }
        }
        expect(foundRejection, isTrue);
        
        await client.sink.close();
      });
    });

    group('Replaceable Events Compliance', () {
      test('should handle replaceable events (kinds 10000-19999)', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        final userPubkey = 'user3333333333333333333333333333333333333333333333333333333333333';
        
        // Store first replaceable event
        final firstEvent = NostrEvent.create(
          pubkey: userPubkey,
          kind: 10000, // Replaceable event kind
          tags: [],
          content: 'First version',
        ).copyWith(
          createdAt: DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          sig: 'first_replaceable_sig' + '1' * 100,
        );
        
        client.sink.add(json.encode(['EVENT', firstEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Store newer replaceable event (should replace the first one)
        final newerEvent = NostrEvent.create(
          pubkey: userPubkey,
          kind: 10000,
          tags: [],
          content: 'Second version',
        ).copyWith(sig: 'newer_replaceable_sig' + '2' * 100);
        
        client.sink.add(json.encode(['EVENT', newerEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        responses.clear();
        
        // Query for replaceable events
        final reqMessage = json.encode([
          'REQ',
          'replaceable-query',
          {'kinds': [10000], 'authors': [userPubkey]}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should only receive the newer event
        int replaceableEventsCount = 0;
        String? receivedContent;
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT') {
            final eventData = responseJson[2] as Map<String, dynamic>;
            if (eventData['kind'] == 10000) {
              replaceableEventsCount++;
              receivedContent = eventData['content'];
            }
          }
        }
        
        expect(replaceableEventsCount, equals(1));
        expect(receivedContent, equals('Second version'));
        
        await client.sink.close();
      });

      test('should handle parameterized replaceable events (kinds 30000-39999)', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        final userPubkey = 'user4444444444444444444444444444444444444444444444444444444444444';
        
        // Store first parameterized replaceable event
        final firstParamEvent = NostrEvent.create(
          pubkey: userPubkey,
          kind: 30000, // Parameterized replaceable event kind
          tags: [['d', 'identifier1']],
          content: 'First parameterized version',
        ).copyWith(
          createdAt: DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          sig: 'first_param_sig' + '1' * 110,
        );
        
        client.sink.add(json.encode(['EVENT', firstParamEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Store newer parameterized replaceable event with same d-tag
        final newerParamEvent = NostrEvent.create(
          pubkey: userPubkey,
          kind: 30000,
          tags: [['d', 'identifier1']], // Same d-tag, should replace
          content: 'Second parameterized version',
        ).copyWith(sig: 'newer_param_sig' + '2' * 110);
        
        client.sink.add(json.encode(['EVENT', newerParamEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        // Store parameterized event with different d-tag (should coexist)
        final differentParamEvent = NostrEvent.create(
          pubkey: userPubkey,
          kind: 30000,
          tags: [['d', 'identifier2']], // Different d-tag
          content: 'Different identifier',
        ).copyWith(sig: 'different_param_sig' + '3' * 100);
        
        client.sink.add(json.encode(['EVENT', differentParamEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        responses.clear();
        
        // Query for parameterized replaceable events
        final reqMessage = json.encode([
          'REQ',
          'param-replaceable-query',
          {'kinds': [30000], 'authors': [userPubkey]}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should receive two events: newer version of identifier1 and identifier2
        int paramEventsCount = 0;
        final receivedContents = <String>[];
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT') {
            final eventData = responseJson[2] as Map<String, dynamic>;
            if (eventData['kind'] == 30000) {
              paramEventsCount++;
              receivedContents.add(eventData['content']);
            }
          }
        }
        
        expect(paramEventsCount, equals(2));
        expect(receivedContents, contains('Second parameterized version'));
        expect(receivedContents, contains('Different identifier'));
        expect(receivedContents, isNot(contains('First parameterized version')));
        
        await client.sink.close();
      });
    });

    group('Ephemeral Events Compliance', () {
      test('should not store ephemeral events (kinds 20000-29999)', () async {
        final client = await WebSocketChannel.connect(
          Uri.parse('ws://localhost:${server.port}'),
        );
        
        final responses = <String>[];
        client.stream.listen((message) {
          responses.add(message);
        });
        
        // Store ephemeral event
        final ephemeralEvent = NostrEvent.create(
          pubkey: 'user5555555555555555555555555555555555555555555555555555555555555',
          kind: 20000, // Ephemeral event kind
          tags: [],
          content: 'This should not be stored',
        ).copyWith(sig: 'ephemeral_sig' + '1' * 110);
        
        client.sink.add(json.encode(['EVENT', ephemeralEvent.toJson()]));
        await Future.delayed(Duration(milliseconds: 100));
        
        responses.clear();
        
        // Query for the ephemeral event - should not be found
        final reqMessage = json.encode([
          'REQ',
          'ephemeral-query',
          {'kinds': [20000], 'ids': [ephemeralEvent.id]}
        ]);
        
        client.sink.add(reqMessage);
        await Future.delayed(Duration(milliseconds: 100));
        
        // Should only receive EOSE, no events
        int eventCount = 0;
        bool foundEose = false;
        
        for (final response in responses) {
          final responseJson = json.decode(response) as List;
          if (responseJson[0] == 'EVENT') {
            eventCount++;
          } else if (responseJson[0] == 'EOSE') {
            foundEose = true;
          }
        }
        
        expect(eventCount, equals(0));
        expect(foundEose, isTrue);
        
        await client.sink.close();
      });
    });
  });
}