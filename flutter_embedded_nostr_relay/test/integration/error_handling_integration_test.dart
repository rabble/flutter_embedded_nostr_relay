// ABOUTME: Error handling integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests various error scenarios, malformed messages, edge cases, and recovery mechanisms

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/core/constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ErrorTestClient {
  final WebSocketChannel channel;
  final String id;
  final List<String> responses = [];
  final List<String> errors = [];
  late StreamSubscription _subscription;
  bool _isClosed = false;

  ErrorTestClient(this.channel, this.id) {
    _subscription = channel.stream.listen(
      (message) {
        responses.add(message);
      },
      onError: (error) {
        errors.add(error.toString());
      },
      onDone: () {
        _isClosed = true;
      },
    );
  }

  void sendRaw(String message) {
    if (!_isClosed) {
      channel.sink.add(message);
    }
  }

  void sendJson(dynamic message) {
    if (!_isClosed) {
      channel.sink.add(json.encode(message));
    }
  }

  void sendBinary(Uint8List data) {
    if (!_isClosed) {
      channel.sink.add(data);
    }
  }

  Future<void> close() async {
    if (!_isClosed) {
      await channel.sink.close();
      await _subscription.cancel();
      _isClosed = true;
    }
  }

  List<Map<String, dynamic>> getNoticeMessages() {
    return responses
        .where((response) {
          try {
            final parsed = json.decode(response) as List;
            return parsed[0] == 'NOTICE';
          } catch (e) {
            return false;
          }
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return {
            'message': parsed[1],
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> getOkResponses() {
    return responses
        .where((response) {
          try {
            final parsed = json.decode(response) as List;
            return parsed[0] == 'OK';
          } catch (e) {
            return false;
          }
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return {
            'eventId': parsed[1],
            'accepted': parsed[2],
            'message': parsed.length > 3 ? parsed[3] : '',
          };
        })
        .toList();
  }

  bool get isClosed => _isClosed;
  bool get hasErrors => errors.isNotEmpty;
}

void main() {
  group('Error Handling Integration Tests', () {
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
      
      await server.start(port: 0);
    });
    
    tearDown(() async {
      await server.stop();
      await subscriptionManager.close();
      await DatabaseHelper.reset();
    });

    Future<ErrorTestClient> createErrorTestClient(String id) async {
      final channel = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );
      return ErrorTestClient(channel, id);
    }

    group('Malformed Message Handling', () {
      test('should handle invalid JSON gracefully', () async {
        final client = await createErrorTestClient('invalid-json');
        
        try {
          // Send various malformed JSON
          final invalidMessages = [
            'not json at all',
            '{"incomplete": json',
            '[1, 2, 3, }',
            '{"valid": "json", "but": "not array"}',
            'null',
            '42',
            '"just a string"',
            '',
            ' ',
            '\n\t',
          ];
          
          for (final invalidMessage in invalidMessages) {
            client.sendRaw(invalidMessage);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should receive NOTICE messages about invalid format
          final notices = client.getNoticeMessages();
          expect(notices.length, greaterThan(0),
                 reason: 'Should receive notices for malformed messages');
          
          // Server should still be responsive
          expect(server.activeConnections, equals(1));
          
          // Valid message should still work
          client.sendJson(['REQ', 'test-sub', {'kinds': [1], 'limit': 1}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          final hasEose = client.responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE' && parsed[1] == 'test-sub';
            } catch (e) {
              return false;
            }
          });
          expect(hasEose, isTrue, reason: 'Valid messages should still work after errors');
          
        } finally {
          await client.close();
        }
      });

      test('should handle invalid message structure', () async {
        final client = await createErrorTestClient('invalid-structure');
        
        try {
          // Send various structurally invalid messages
          final invalidStructures = [
            [], // Empty array
            [1], // Too short
            ['UNKNOWN'], // Unknown message type
            ['REQ'], // REQ without subscription ID
            ['REQ', 'sub'], // REQ without filters
            ['REQ', 'sub', 'not-an-object'], // REQ with invalid filter
            ['EVENT'], // EVENT without event data
            ['EVENT', {'invalid': 'event'}], // EVENT with incomplete event
            ['CLOSE'], // CLOSE without subscription ID
            ['REQ', null, {'kinds': [1]}], // Null subscription ID
            ['REQ', '', {'kinds': [1]}], // Empty subscription ID
            ['REQ', 'sub', null], // Null filter
          ];
          
          for (final invalidStructure in invalidStructures) {
            client.sendJson(invalidStructure);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should receive NOTICE messages about invalid structure
          final notices = client.getNoticeMessages();
          expect(notices.length, greaterThan(5),
                 reason: 'Should receive notices for structurally invalid messages');
          
          // Verify server is still responsive
          client.sendJson(['REQ', 'valid-sub', {'kinds': [1], 'limit': 1}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          final hasValidResponse = client.responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE' && parsed[1] == 'valid-sub';
            } catch (e) {
              return false;
            }
          });
          expect(hasValidResponse, isTrue);
          
        } finally {
          await client.close();
        }
      });

      test('should handle oversized messages', () async {
        final client = await createErrorTestClient('oversized');
        
        try {
          // Create oversized message
          final largeContent = 'x' * (RelayConstants.maxMessageLength + 1000);
          final oversizedEvent = {
            'id': 'oversized-event-id',
            'pubkey': 'a' * 64,
            'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'kind': 1,
            'tags': [],
            'content': largeContent,
            'sig': 'b' * 128,
          };
          
          client.sendJson(['EVENT', oversizedEvent]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Should receive rejection
          final okResponses = client.getOkResponses();
          final notices = client.getNoticeMessages();
          
          expect(okResponses.isNotEmpty || notices.isNotEmpty, isTrue,
                 reason: 'Should receive rejection for oversized message');
          
          if (okResponses.isNotEmpty) {
            expect(okResponses.first['accepted'], equals(false));
          }
          
        } finally {
          await client.close();
        }
      });
    });

    group('Invalid Event Handling', () {
      test('should reject events with invalid signatures', () async {
        final client = await createErrorTestClient('invalid-sig');
        
        try {
          // Create event with invalid signature
          final invalidEvent = {
            'id': 'valid-looking-id-1234567890abcdef1234567890abcdef12345678',
            'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
            'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'kind': 1,
            'tags': [],
            'content': 'Event with invalid signature',
            'sig': 'invalid_signature_that_does_not_match_the_event_data_at_all_1234567890abcdef',
          };
          
          client.sendJson(['EVENT', invalidEvent]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Should receive OK with false
          final okResponses = client.getOkResponses();
          expect(okResponses.length, equals(1));
          expect(okResponses.first['accepted'], equals(false));
          expect(okResponses.first['eventId'], equals(invalidEvent['id']));
          
        } finally {
          await client.close();
        }
      });

      test('should reject events with missing required fields', () async {
        final client = await createErrorTestClient('missing-fields');
        
        try {
          final incompleteEvents = [
            // Missing ID
            {
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 'Missing ID',
              'sig': 'a' * 128,
            },
            // Missing pubkey
            {
              'id': 'missing-pubkey-id',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 'Missing pubkey',
              'sig': 'b' * 128,
            },
            // Missing created_at
            {
              'id': 'missing-created-at-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'kind': 1,
              'tags': [],
              'content': 'Missing created_at',
              'sig': 'c' * 128,
            },
            // Missing kind
            {
              'id': 'missing-kind-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'tags': [],
              'content': 'Missing kind',
              'sig': 'd' * 128,
            },
            // Missing tags
            {
              'id': 'missing-tags-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'content': 'Missing tags',
              'sig': 'e' * 128,
            },
            // Missing content
            {
              'id': 'missing-content-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'sig': 'f' * 128,
            },
            // Missing signature
            {
              'id': 'missing-sig-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 'Missing signature',
            },
          ];
          
          for (final incompleteEvent in incompleteEvents) {
            client.sendJson(['EVENT', incompleteEvent]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should receive rejections for all incomplete events
          final okResponses = client.getOkResponses();
          expect(okResponses.length, equals(incompleteEvents.length));
          
          for (final okResponse in okResponses) {
            expect(okResponse['accepted'], equals(false),
                   reason: 'Incomplete events should be rejected');
          }
          
        } finally {
          await client.close();
        }
      });

      test('should reject events with invalid field types', () async {
        final client = await createErrorTestClient('invalid-types');
        
        try {
          final invalidTypeEvents = [
            // ID as number instead of string
            {
              'id': 12345,
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 'ID as number',
              'sig': 'a' * 128,
            },
            // created_at as string instead of number
            {
              'id': 'string-created-at-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': 'not-a-timestamp',
              'kind': 1,
              'tags': [],
              'content': 'created_at as string',
              'sig': 'b' * 128,
            },
            // kind as string instead of number
            {
              'id': 'string-kind-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 'text-note',
              'tags': [],
              'content': 'kind as string',
              'sig': 'c' * 128,
            },
            // tags as string instead of array
            {
              'id': 'string-tags-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': 'not-an-array',
              'content': 'tags as string',
              'sig': 'd' * 128,
            },
            // content as number instead of string
            {
              'id': 'number-content-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 42,
              'sig': 'e' * 128,
            },
          ];
          
          for (final invalidEvent in invalidTypeEvents) {
            client.sendJson(['EVENT', invalidEvent]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should handle type errors gracefully
          final okResponses = client.getOkResponses();
          final notices = client.getNoticeMessages();
          
          expect(okResponses.length + notices.length, greaterThan(0),
                 reason: 'Should respond to invalid type events');
          
          // All OK responses should be rejections
          for (final okResponse in okResponses) {
            expect(okResponse['accepted'], equals(false));
          }
          
        } finally {
          await client.close();
        }
      });
    });

    group('Subscription Error Handling', () {
      test('should handle invalid filter syntax', () async {
        final client = await createErrorTestClient('invalid-filters');
        
        try {
          final invalidFilters = [
            // Invalid kinds (not array)
            {'kinds': 1},
            // Invalid authors (not array)
            {'authors': 'single-author'},
            // Invalid since (not number)
            {'since': 'yesterday'},
            // Invalid until (not number)
            {'until': 'tomorrow'},
            // Invalid limit (not number)
            {'limit': 'many'},
            // Invalid tag filter format
            {'#t': 'single-tag'},
            // Negative limit
            {'limit': -10},
            // Zero limit
            {'limit': 0},
            // Excessive limit
            {'limit': RelayConstants.maxQueryLimit + 1000},
          ];
          
          for (int i = 0; i < invalidFilters.length; i++) {
            client.sendJson(['REQ', 'invalid-filter-$i', invalidFilters[i]]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should receive NOTICE messages about invalid filters
          final notices = client.getNoticeMessages();
          expect(notices.length, greaterThan(0),
                 reason: 'Should receive notices for invalid filters');
          
          // Server should still be responsive to valid requests
          client.sendJson(['REQ', 'valid-filter', {'kinds': [1], 'limit': 10}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          final hasValidEose = client.responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE' && parsed[1] == 'valid-filter';
            } catch (e) {
              return false;
            }
          });
          expect(hasValidEose, isTrue);
          
        } finally {
          await client.close();
        }
      });

      test('should handle subscription ID conflicts', () async {
        final client = await createErrorTestClient('sub-conflicts');
        
        try {
          // Create initial subscription
          client.sendJson(['REQ', 'conflicted-sub', {'kinds': [1], 'limit': 10}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          // Create another subscription with same ID (should update the existing one)
          client.sendJson(['REQ', 'conflicted-sub', {'kinds': [7], 'limit': 5}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          // Should receive EOSE for both (the second replaces the first)
          final eoseCount = client.responses.where((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE' && parsed[1] == 'conflicted-sub';
            } catch (e) {
              return false;
            }
          }).length;
          
          expect(eoseCount, greaterThanOrEqualTo(1),
                 reason: 'Should handle subscription ID reuse');
          
          // Test closing non-existent subscription
          client.sendJson(['CLOSE', 'non-existent-sub']);
          await Future.delayed(Duration(milliseconds: 100));
          
          // Should not crash or cause issues
          expect(client.isClosed, isFalse);
          
        } finally {
          await client.close();
        }
      });

      test('should handle excessive subscription counts', () async {
        final client = await createErrorTestClient('excessive-subs');
        
        try {
          // Create maximum allowed subscriptions
          for (int i = 0; i < RelayConstants.maxSubscriptions; i++) {
            client.sendJson(['REQ', 'sub-$i', {'kinds': [1], 'limit': 1}]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Try to create one more (should be rejected)
          client.sendJson(['REQ', 'excess-sub', {'kinds': [1], 'limit': 1}]);
          await Future.delayed(Duration(milliseconds: 200));
          
          // Should receive notice about too many subscriptions
          final notices = client.getNoticeMessages();
          final hasExcessNotice = notices.any((notice) =>
              notice['message'].toString().toLowerCase().contains('too many') ||
              notice['message'].toString().toLowerCase().contains('limit'));
          
          expect(hasExcessNotice, isTrue,
                 reason: 'Should notify about subscription limits');
          
        } finally {
          await client.close();
        }
      });
    });

    group('Connection Error Handling', () {
      test('should handle abrupt client disconnections', () async {
        final clients = <ErrorTestClient>[];
        
        try {
          // Create multiple clients with active subscriptions
          for (int i = 0; i < 5; i++) {
            final client = await createErrorTestClient('disconnect-test-$i');
            clients.add(client);
            client.sendJson(['REQ', 'sub-$i', {'kinds': [1], 'limit': 10}]);
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          expect(server.activeConnections, equals(5));
          
          // Abruptly close some clients
          await clients[1].close();
          await clients[3].close();
          
          await Future.delayed(Duration(milliseconds: 200));
          expect(server.activeConnections, equals(3));
          
          // Remaining clients should still work
          final testEvent = NostrEvent.create(
            pubkey: 'disconnect_test_author' + '0' * (64 - 'disconnect_test_author'.length),
            kind: 1,
            tags: [],
            content: 'Test after disconnections',
          ).copyWith(sig: 'disconnect_test_sig' + '1' * 102);
          
          clients[0].sendJson(['EVENT', testEvent.toJson()]);
          await Future.delayed(Duration(milliseconds: 200));
          
          // Remaining clients should receive the event
          final receivedEvent = clients[0].responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EVENT' && 
                     parsed[2]['content'] == 'Test after disconnections';
            } catch (e) {
              return false;
            }
          });
          
          expect(receivedEvent, isTrue,
                 reason: 'Remaining clients should continue to work after disconnections');
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });

      test('should handle binary data gracefully', () async {
        final client = await createErrorTestClient('binary-data');
        
        try {
          // Send various binary payloads
          final binaryPayloads = [
            Uint8List.fromList([0x00, 0x01, 0x02, 0x03]), // Simple binary
            Uint8List.fromList(List.generate(1000, (i) => i % 256)), // Large binary
            Uint8List.fromList([0xFF, 0xFE, 0xFD]), // High bytes
          ];
          
          for (final payload in binaryPayloads) {
            client.sendBinary(payload);
          }
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Connection should remain stable
          expect(client.isClosed, isFalse);
          
          // Should still accept valid JSON messages
          client.sendJson(['REQ', 'binary-test', {'kinds': [1], 'limit': 1}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          final hasEose = client.responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE' && parsed[1] == 'binary-test';
            } catch (e) {
              return false;
            }
          });
          expect(hasEose, isTrue,
                 reason: 'Should recover from binary data and accept valid messages');
          
        } finally {
          await client.close();
        }
      });
    });

    group('Database Error Recovery', () {
      test('should handle database constraint violations gracefully', () async {
        final client = await createErrorTestClient('db-constraints');
        
        try {
          // Create event with same ID (should trigger duplicate constraint)
          final duplicateEvent = NostrEvent.create(
            pubkey: 'constraint_test_author' + '0' * (64 - 'constraint_test_author'.length),
            kind: 1,
            tags: [],
            content: 'Duplicate event test',
          ).copyWith(
            id: 'duplicate-event-id-1234567890abcdef1234567890abcdef12345678',
            sig: 'constraint_test_sig' + '1' * 103,
          );
          
          // Send same event twice
          client.sendJson(['EVENT', duplicateEvent.toJson()]);
          client.sendJson(['EVENT', duplicateEvent.toJson()]);
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Should receive OK responses for both attempts
          final okResponses = client.getOkResponses();
          expect(okResponses.length, equals(2));
          
          // First should be accepted, second should be rejected (duplicate)
          final firstResponse = okResponses.first;
          final secondResponse = okResponses.last;
          
          expect(firstResponse['accepted'], equals(true));
          expect(secondResponse['accepted'], equals(false));
          
          // Server should remain stable
          expect(server.activeConnections, equals(1));
          
        } finally {
          await client.close();
        }
      });

      test('should handle storage errors without crashing', () async {
        final client = await createErrorTestClient('storage-errors');
        
        try {
          // Create many events to potentially trigger storage issues
          final events = <Map<String, dynamic>>[];
          
          for (int i = 0; i < 100; i++) {
            final event = {
              'id': 'storage-test-id-$i' + '0' * (64 - 'storage-test-id-$i'.length),
              'pubkey': 'storage_test_author' + '0' * (64 - 'storage_test_author'.length),
              'created_at': DateTime.now().add(Duration(seconds: i)).millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [['index', i.toString()]],
              'content': 'Storage test event $i with content',
              'sig': 'storage_sig_$i' + '1' * (120 - 'storage_sig_$i'.length),
            };
            events.add(event);
            
            client.sendJson(['EVENT', event]);
            
            // Send rapidly to stress storage
            if (i % 10 == 0) {
              await Future.delayed(Duration(milliseconds: 10));
            }
          }
          
          await Future.delayed(Duration(seconds: 2));
          
          // Should receive OK responses for most events
          final okResponses = client.getOkResponses();
          expect(okResponses.length, equals(events.length));
          
          // Most should be accepted (allowing for some storage failures)
          final acceptedCount = okResponses.where((r) => r['accepted'] == true).length;
          expect(acceptedCount, greaterThan(events.length * 0.8),
                 reason: 'Most events should be stored despite potential storage stress');
          
          // Server should remain responsive
          client.responses.clear();
          client.sendJson(['REQ', 'storage-test-query', {'kinds': [1], 'limit': 50}]);
          await Future.delayed(Duration(milliseconds: 300));
          
          final hasResponse = client.responses.isNotEmpty;
          expect(hasResponse, isTrue,
                 reason: 'Server should remain responsive after storage stress');
          
        } finally {
          await client.close();
        }
      });
    });

    group('Resource Exhaustion Handling', () {
      test('should handle memory pressure gracefully', () async {
        final clients = <ErrorTestClient>[];
        
        try {
          // Create many clients to simulate memory pressure
          const int clientCount = 20;
          
          for (int i = 0; i < clientCount; i++) {
            final client = await createErrorTestClient('memory-pressure-$i');
            clients.add(client);
            
            // Each subscribes to different patterns
            client.sendJson(['REQ', 'memory-sub-$i', {
              'kinds': [1, 7],
              'limit': 100 + i * 10,
            }]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Send events that will be broadcast to all clients
          final broadcasterClient = clients.first;
          
          for (int i = 0; i < 50; i++) {
            final event = NostrEvent.create(
              pubkey: 'memory_pressure_author' + '0' * (64 - 'memory_pressure_author'.length),
              kind: 1,
              tags: [],
              content: 'Memory pressure test event $i',
            ).copyWith(sig: 'memory_pressure_sig_$i' + '1' * (120 - 'memory_pressure_sig_$i'.length));
            
            broadcasterClient.sendJson(['EVENT', event.toJson()]);
            
            if (i % 10 == 0) {
              await Future.delayed(Duration(milliseconds: 50));
            }
          }
          
          await Future.delayed(Duration(seconds: 2));
          
          // Verify server is still stable
          expect(server.activeConnections, equals(clientCount));
          
          // Most clients should have received events
          int clientsWithEvents = 0;
          for (final client in clients) {
            final eventMessages = client.responses.where((response) {
              try {
                final parsed = json.decode(response) as List;
                return parsed[0] == 'EVENT';
              } catch (e) {
                return false;
              }
            }).length;
            
            if (eventMessages > 0) {
              clientsWithEvents++;
            }
          }
          
          expect(clientsWithEvents, greaterThan(clientCount * 0.7),
                 reason: 'Most clients should receive events despite memory pressure');
          
        } finally {
          for (final client in clients) {
            await client.close();
          }
        }
      });
    });

    group('Edge Case Recovery', () {
      test('should recover from temporary network issues', () async {
        final client = await createErrorTestClient('network-recovery');
        
        try {
          // Establish initial connection and subscription
          client.sendJson(['REQ', 'recovery-sub', {'kinds': [1], 'limit': 10}]);
          await Future.delayed(Duration(milliseconds: 100));
          
          expect(client.responses.isNotEmpty, isTrue);
          client.responses.clear();
          
          // Simulate network issues by sending malformed messages
          for (int i = 0; i < 10; i++) {
            client.sendRaw('network-error-simulation-$i');
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Clear error responses
          client.responses.clear();
          
          // Should recover and handle valid messages
          final testEvent = NostrEvent.create(
            pubkey: 'recovery_test_author' + '0' * (64 - 'recovery_test_author'.length),
            kind: 1,
            tags: [],
            content: 'Recovery test event',
          ).copyWith(sig: 'recovery_test_sig' + '1' * 105);
          
          client.sendJson(['EVENT', testEvent.toJson()]);
          await Future.delayed(Duration(milliseconds: 200));
          
          // Should receive proper responses
          final okResponses = client.getOkResponses();
          expect(okResponses.length, equals(1));
          expect(okResponses.first['accepted'], equals(true));
          
        } finally {
          await client.close();
        }
      });

      test('should handle mixed valid and invalid message streams', () async {
        final client = await createErrorTestClient('mixed-messages');
        
        try {
          final messages = [
            // Valid REQ
            ['REQ', 'mixed-sub', {'kinds': [1], 'limit': 5}],
            // Invalid JSON
            'invalid-json-{',
            // Valid EVENT
            ['EVENT', {
              'id': 'mixed-test-event-id',
              'pubkey': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
              'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'kind': 1,
              'tags': [],
              'content': 'Mixed stream test',
              'sig': 'mixed_test_sig' + '1' * 110,
            }],
            // Invalid structure
            ['INVALID', 'structure'],
            // Valid CLOSE
            ['CLOSE', 'mixed-sub'],
            // Binary data
            null,
            // Valid REQ again
            ['REQ', 'mixed-sub-2', {'kinds': [7], 'limit': 3}],
          ];
          
          for (final message in messages) {
            if (message == null) {
              client.sendBinary(Uint8List.fromList([0x00, 0xFF]));
            } else if (message is String) {
              client.sendRaw(message);
            } else {
              client.sendJson(message);
            }
            
            await Future.delayed(Duration(milliseconds: 20));
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Should handle valid messages despite invalid ones
          final okResponses = client.getOkResponses();
          final hasEose = client.responses.any((response) {
            try {
              final parsed = json.decode(response) as List;
              return parsed[0] == 'EOSE';
            } catch (e) {
              return false;
            }
          });
          
          expect(okResponses.length, greaterThanOrEqualTo(1),
                 reason: 'Should process valid events');
          expect(hasEose, isTrue,
                 reason: 'Should process valid subscriptions');
          expect(client.isClosed, isFalse,
                 reason: 'Connection should remain open despite invalid messages');
          
        } finally {
          await client.close();
        }
      });
    });
  });
}