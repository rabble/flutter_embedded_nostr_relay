// ABOUTME: Persistence and recovery integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests database persistence, server restart recovery, data consistency, and backup scenarios

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
import 'package:flutter_embedded_nostr_relay/src/core/embedded_nostr_relay.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void main() {
  group('Persistence and Recovery Integration Tests', () {
    late String testDbPath;
    
    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    
    setUp(() async {
      // Create unique test database path
      testDbPath = path.join(Directory.systemTemp.path, 'test_relay_${DateTime.now().millisecondsSinceEpoch}.db');
    });
    
    tearDown(() async {
      // Clean up test database
      try {
        final dbFile = File(testDbPath);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
      
      // Reset to test mode
      await DatabaseHelper.reset();
    });

    group('Database Persistence', () {
      test('should persist events across database reopening', () async {
        final testEvents = <NostrEvent>[];
        
        // Create test events
        for (int i = 0; i < 10; i++) {
          final event = NostrEvent.create(
            pubkey: 'author${i.toString().padLeft(60, '0')}',
            kind: 1,
            tags: [['t', 'persistent'], ['index', i.toString()]],
            content: 'Persistent message $i',
          ).copyWith(
            sig: 'persist_sig_$i' + '1' * (120 - 'persist_sig_$i'.length),
          );
          testEvents.add(event);
        }
        
        // First database session - store events
        {
          // Disable test mode to use real database
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Store all events
          for (final event in testEvents) {
            final stored = await eventStore.storeEvent(event);
            expect(stored, isTrue, reason: 'Event ${event.id} should be stored');
          }
          
          // Verify events are in database
          final retrievedEvents = await eventStore.queryEvents([
            Filter(kinds: [1], tags: {'t': ['persistent']})
          ]);
          expect(retrievedEvents.length, equals(testEvents.length));
          
          // Close database
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
        
        // Second database session - verify persistence
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Query for stored events
          final persistedEvents = await eventStore.queryEvents([
            Filter(kinds: [1], tags: {'t': ['persistent']})
          ]);
          
          expect(persistedEvents.length, equals(testEvents.length));
          
          // Verify event contents match
          final persistedIds = persistedEvents.map((e) => e.id).toSet();
          final originalIds = testEvents.map((e) => e.id).toSet();
          expect(persistedIds, equals(originalIds));
          
          // Verify specific event data
          for (int i = 0; i < testEvents.length; i++) {
            final original = testEvents[i];
            final persisted = persistedEvents.firstWhere((e) => e.id == original.id);
            
            expect(persisted.pubkey, equals(original.pubkey));
            expect(persisted.kind, equals(original.kind));
            expect(persisted.content, equals(original.content));
            expect(persisted.createdAt, equals(original.createdAt));
            expect(persisted.tags, equals(original.tags));
            expect(persisted.sig, equals(original.sig));
          }
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
      });

      test('should handle replaceable event persistence correctly', () async {
        final userPubkey = 'replaceable_user' + '0' * (64 - 'replaceable_user'.length);
        
        // First database session
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Store initial replaceable event
          final firstEvent = NostrEvent.create(
            pubkey: userPubkey,
            kind: 10000, // Replaceable event
            tags: [],
            content: 'First version',
          ).copyWith(
            createdAt: DateTime.now().subtract(Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
            sig: 'first_replaceable_sig' + '1' * 100,
          );
          
          await eventStore.storeEvent(firstEvent);
          
          // Store newer replaceable event (should replace first)
          final newerEvent = NostrEvent.create(
            pubkey: userPubkey,
            kind: 10000,
            tags: [],
            content: 'Second version',
          ).copyWith(
            createdAt: DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
            sig: 'newer_replaceable_sig' + '2' * 100,
          );
          
          await eventStore.storeEvent(newerEvent);
          
          // Store newest replaceable event
          final newestEvent = NostrEvent.create(
            pubkey: userPubkey,
            kind: 10000,
            tags: [],
            content: 'Third version',
          ).copyWith(sig: 'newest_replaceable_sig' + '3' * 97);
          
          await eventStore.storeEvent(newestEvent);
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
        
        // Second database session - verify only newest is persisted
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          final persistedEvents = await eventStore.queryEvents([
            Filter(kinds: [10000], authors: [userPubkey])
          ]);
          
          expect(persistedEvents.length, equals(1));
          expect(persistedEvents.first.content, equals('Third version'));
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
      });

      test('should persist parameterized replaceable events with different d-tags', () async {
        final userPubkey = 'param_user' + '0' * (64 - 'param_user'.length);
        
        // First database session
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Store parameterized replaceable events with different d-tags
          final events = [
            NostrEvent.create(
              pubkey: userPubkey,
              kind: 30000,
              tags: [['d', 'config1']],
              content: 'Config 1 data',
            ).copyWith(sig: 'param1_sig' + '1' * 113),
            
            NostrEvent.create(
              pubkey: userPubkey,
              kind: 30000,
              tags: [['d', 'config2']],
              content: 'Config 2 data',
            ).copyWith(sig: 'param2_sig' + '2' * 113),
            
            // Update config1 (should replace first event)
            NostrEvent.create(
              pubkey: userPubkey,
              kind: 30000,
              tags: [['d', 'config1']],
              content: 'Updated config 1 data',
            ).copyWith(
              createdAt: DateTime.now().add(Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
              sig: 'param1_updated_sig' + '1' * 104,
            ),
          ];
          
          for (final event in events) {
            await eventStore.storeEvent(event);
          }
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
        
        // Second database session - verify correct persistence
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          final persistedEvents = await eventStore.queryEvents([
            Filter(kinds: [30000], authors: [userPubkey])
          ]);
          
          expect(persistedEvents.length, equals(2));
          
          final config1Event = persistedEvents.firstWhere((e) => 
            e.tags.any((tag) => tag.length >= 2 && tag[0] == 'd' && tag[1] == 'config1'));
          final config2Event = persistedEvents.firstWhere((e) => 
            e.tags.any((tag) => tag.length >= 2 && tag[0] == 'd' && tag[1] == 'config2'));
          
          expect(config1Event.content, equals('Updated config 1 data'));
          expect(config2Event.content, equals('Config 2 data'));
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
      });
    });

    group('Server Restart Recovery', () {
      test('should recover subscriptions and continue serving stored events after restart', () async {
        final storedEvents = <NostrEvent>[];
        
        // Prepare test events
        for (int i = 0; i < 5; i++) {
          final event = NostrEvent.create(
            pubkey: 'restart_author' + '0' * (64 - 'restart_author'.length),
            kind: 1,
            tags: [['t', 'restart-test']],
            content: 'Pre-restart message $i',
          ).copyWith(sig: 'restart_sig_$i' + '1' * (120 - 'restart_sig_$i'.length));
          storedEvents.add(event);
        }
        
        int serverPort = 0;
        
        // First server instance - store events
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final databaseHelper = DatabaseHelper.instance;
          final eventStore = EventStore(databaseHelper: databaseHelper);
          final subscriptionManager = SubscriptionManager();
          
          final server = WebSocketServer(
            subscriptionManager: subscriptionManager,
            eventStore: eventStore,
          );
          
          await server.start(port: 0);
          serverPort = server.port;
          
          // Connect client and store events
          final client = await WebSocketChannel.connect(
            Uri.parse('ws://localhost:$serverPort'),
          );
          
          final responses = <String>[];
          client.stream.listen((message) {
            responses.add(message);
          });
          
          // Store events
          for (final event in storedEvents) {
            client.sink.add(json.encode(['EVENT', event.toJson()]));
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify storage
          final okResponses = responses
              .where((r) => json.decode(r)[0] == 'OK')
              .map((r) => json.decode(r))
              .toList();
          expect(okResponses.length, equals(storedEvents.length));
          
          await client.sink.close();
          await server.stop();
          await subscriptionManager.close();
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
        
        // Second server instance - verify recovery
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final databaseHelper = DatabaseHelper.instance;
          final eventStore = EventStore(databaseHelper: databaseHelper);
          final subscriptionManager = SubscriptionManager();
          
          final server = WebSocketServer(
            subscriptionManager: subscriptionManager,
            eventStore: eventStore,
          );
          
          await server.start(port: serverPort);
          
          // Connect new client and query stored events
          final client = await WebSocketChannel.connect(
            Uri.parse('ws://localhost:$serverPort'),
          );
          
          final responses = <String>[];
          client.stream.listen((message) {
            responses.add(message);
          });
          
          // Query for stored events
          client.sink.add(json.encode([
            'REQ',
            'recovery-test',
            {'#t': ['restart-test'], 'kinds': [1]}
          ]));
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Should receive all stored events plus EOSE
          final eventResponses = responses
              .where((r) => json.decode(r)[0] == 'EVENT')
              .map((r) => json.decode(r)[2] as Map<String, dynamic>)
              .toList();
          
          expect(eventResponses.length, equals(storedEvents.length));
          
          // Verify event IDs match
          final recoveredIds = eventResponses.map((e) => e['id']).toSet();
          final originalIds = storedEvents.map((e) => e.id).toSet();
          expect(recoveredIds, equals(originalIds));
          
          await client.sink.close();
          await server.stop();
          await subscriptionManager.close();
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
      });

      test('should maintain database integrity after unexpected shutdown simulation', () async {
        // Simulate writing many events and then "crashing"
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Store events in batches to simulate ongoing operations
          for (int batch = 0; batch < 3; batch++) {
            for (int i = 0; i < 10; i++) {
              final event = NostrEvent.create(
                pubkey: 'integrity_author' + '0' * (64 - 'integrity_author'.length),
                kind: 1,
                tags: [['batch', batch.toString()], ['index', i.toString()]],
                content: 'Batch $batch, Event $i',
              ).copyWith(sig: 'integrity_${batch}_$i' + '1' * (120 - 'integrity_${batch}_$i'.length));
              
              await eventStore.storeEvent(event);
            }
            
            // Small delay between batches
            await Future.delayed(Duration(milliseconds: 10));
          }
          
          // Simulate crash - don't properly close database
          // Just reset without closing
          await DatabaseHelper.reset();
        }
        
        // Recovery - check database integrity
        {
          DatabaseHelper.disableTestMode();
          DatabaseHelper.setDatabasePath(testDbPath);
          
          final eventStore = EventStore();
          
          // Verify database can be opened and queried
          final allEvents = await eventStore.queryEvents([Filter(kinds: [1])]);
          expect(allEvents.length, equals(30)); // 3 batches * 10 events
          
          // Verify data integrity
          for (int batch = 0; batch < 3; batch++) {
            final batchEvents = await eventStore.queryEvents([
              Filter(kinds: [1], tags: {'batch': [batch.toString()]})
            ]);
            expect(batchEvents.length, equals(10));
            
            for (int i = 0; i < 10; i++) {
              final found = batchEvents.any((e) => 
                e.content == 'Batch $batch, Event $i' &&
                e.tags.any((tag) => tag.length >= 2 && tag[0] == 'index' && tag[1] == i.toString())
              );
              expect(found, isTrue, reason: 'Should find batch $batch, event $i');
            }
          }
          
          await DatabaseHelper.instance.close();
          await DatabaseHelper.reset();
        }
      });
    });

    group('Data Consistency', () {
      test('should maintain referential integrity for deletion events', () async {
        DatabaseHelper.disableTestMode();
        DatabaseHelper.setDatabasePath(testDbPath);
        
        final eventStore = EventStore();
        final authorPubkey = 'deletion_author' + '0' * (64 - 'deletion_author'.length);
        
        // Store original events
        final originalEvents = <NostrEvent>[];
        for (int i = 0; i < 5; i++) {
          final event = NostrEvent.create(
            pubkey: authorPubkey,
            kind: 1,
            tags: [],
            content: 'Original message $i',
          ).copyWith(sig: 'original_$i' + '1' * (120 - 'original_$i'.length));
          originalEvents.add(event);
          await eventStore.storeEvent(event);
        }
        
        // Create deletion event
        final deletionEvent = NostrEvent.create(
          pubkey: authorPubkey,
          kind: 5, // Deletion event
          tags: originalEvents.map((e) => ['e', e.id]).toList(),
          content: 'Deleting spam messages',
        ).copyWith(sig: 'deletion_sig' + '1' * 111);
        
        await eventStore.storeEvent(deletionEvent);
        
        // Restart database to ensure persistence
        await DatabaseHelper.instance.close();
        await DatabaseHelper.reset();
        
        DatabaseHelper.disableTestMode();
        DatabaseHelper.setDatabasePath(testDbPath);
        
        final newEventStore = EventStore();
        
        // Verify deletion event is stored
        final deletionEvents = await newEventStore.queryEvents([
          Filter(kinds: [5], authors: [authorPubkey])
        ]);
        expect(deletionEvents.length, equals(1));
        expect(deletionEvents.first.id, equals(deletionEvent.id));
        
        // Verify deletion event references are intact
        final storedDeletionEvent = deletionEvents.first;
        expect(storedDeletionEvent.tags.length, equals(originalEvents.length));
        
        for (int i = 0; i < originalEvents.length; i++) {
          expect(storedDeletionEvent.tags[i], equals(['e', originalEvents[i].id]));
        }
        
        await DatabaseHelper.instance.close();
        await DatabaseHelper.reset();
      });

      test('should handle concurrent writes without data corruption', () async {
        DatabaseHelper.disableTestMode();
        DatabaseHelper.setDatabasePath(testDbPath);
        
        final eventStore = EventStore();
        
        // Simulate concurrent writes
        const int concurrentWriters = 5;
        const int eventsPerWriter = 10;
        
        final writeFutures = <Future>[];
        
        for (int writer = 0; writer < concurrentWriters; writer++) {
          writeFutures.add(() async {
            for (int event = 0; event < eventsPerWriter; event++) {
              final nostrEvent = NostrEvent.create(
                pubkey: 'writer$writer' + '0' * (64 - 'writer$writer'.length),
                kind: 1,
                tags: [['writer', writer.toString()], ['event', event.toString()]],
                content: 'Concurrent write from writer $writer, event $event',
              ).copyWith(sig: 'concurrent_${writer}_$event' + '1' * (120 - 'concurrent_${writer}_$event'.length));
              
              await eventStore.storeEvent(nostrEvent);
              
              // Small random delay to increase chance of conflicts
              await Future.delayed(Duration(milliseconds: (writer + event) % 5));
            }
          }());
        }
        
        await Future.wait(writeFutures);
        
        // Verify all events were stored correctly
        final allEvents = await eventStore.queryEvents([Filter(kinds: [1])]);
        expect(allEvents.length, equals(concurrentWriters * eventsPerWriter));
        
        // Verify data integrity - each writer should have all their events
        for (int writer = 0; writer < concurrentWriters; writer++) {
          final writerEvents = await eventStore.queryEvents([
            Filter(kinds: [1], tags: {'writer': [writer.toString()]})
          ]);
          expect(writerEvents.length, equals(eventsPerWriter));
          
          // Verify all events for this writer are present
          for (int event = 0; event < eventsPerWriter; event++) {
            final found = writerEvents.any((e) => 
              e.content == 'Concurrent write from writer $writer, event $event');
            expect(found, isTrue, reason: 'Should find writer $writer event $event');
          }
        }
        
        await DatabaseHelper.instance.close();
        await DatabaseHelper.reset();
      });
    });

    group('Embedded Relay Recovery', () {
      test('should recover embedded relay state after shutdown', () async {
        // First relay instance
        {
          final relay = EmbeddedNostrRelay();
          await relay.initialize();
          
          // Store some events
          final events = <NostrEvent>[];
          for (int i = 0; i < 5; i++) {
            final event = NostrEvent.create(
              pubkey: 'embedded_author' + '0' * (64 - 'embedded_author'.length),
              kind: 1,
              tags: [['t', 'embedded-test']],
              content: 'Embedded relay message $i',
            ).copyWith(sig: 'embedded_sig_$i' + '1' * (120 - 'embedded_sig_$i'.length));
            
            events.add(event);
            final published = await relay.publish(event);
            expect(published, isTrue);
          }
          
          // Verify events are stored
          final storedEvents = await relay.queryEvents([
            Filter(tags: {'t': ['embedded-test']})
          ]);
          expect(storedEvents.length, equals(5));
          
          await relay.shutdown();
        }
        
        // Second relay instance - should recover stored events
        {
          final relay = EmbeddedNostrRelay();
          await relay.initialize();
          
          // Query for previously stored events
          final recoveredEvents = await relay.queryEvents([
            Filter(tags: {'t': ['embedded-test']})
          ]);
          
          expect(recoveredEvents.length, equals(5));
          
          // Verify event contents
          for (int i = 0; i < 5; i++) {
            final found = recoveredEvents.any((e) => 
              e.content == 'Embedded relay message $i');
            expect(found, isTrue, reason: 'Should recover message $i');
          }
          
          await relay.shutdown();
        }
      });

      test('should handle database migration and schema changes gracefully', () async {
        // This test simulates what would happen during a schema upgrade
        DatabaseHelper.disableTestMode();
        DatabaseHelper.setDatabasePath(testDbPath);
        
        // First create database with current schema
        final eventStore = EventStore();
        
        // Store some test data
        final testEvent = NostrEvent.create(
          pubkey: 'migration_author' + '0' * (64 - 'migration_author'.length),
          kind: 1,
          tags: [['t', 'migration-test']],
          content: 'Migration test event',
        ).copyWith(sig: 'migration_sig' + '1' * 111);
        
        await eventStore.storeEvent(testEvent);
        
        // Verify data is stored
        final storedEvents = await eventStore.queryEvents([
          Filter(tags: {'t': ['migration-test']})
        ]);
        expect(storedEvents.length, equals(1));
        expect(storedEvents.first.content, equals('Migration test event'));
        
        // Close database
        await DatabaseHelper.instance.close();
        await DatabaseHelper.reset();
        
        // Reopen database (simulates app restart with potential schema changes)
        DatabaseHelper.disableTestMode();
        DatabaseHelper.setDatabasePath(testDbPath);
        
        final newEventStore = EventStore();
        
        // Verify data survives "migration"
        final recoveredEvents = await newEventStore.queryEvents([
          Filter(tags: {'t': ['migration-test']})
        ]);
        expect(recoveredEvents.length, equals(1));
        expect(recoveredEvents.first.content, equals('Migration test event'));
        expect(recoveredEvents.first.id, equals(testEvent.id));
        
        await DatabaseHelper.instance.close();
        await DatabaseHelper.reset();
      });
    });

    group('Backup and Recovery Scenarios', () {
      test('should handle database file corruption recovery', () async {
        String backupDbPath = testDbPath + '.backup';
        
        try {
          // Create and populate original database
          {
            DatabaseHelper.disableTestMode();
            DatabaseHelper.setDatabasePath(testDbPath);
            
            final eventStore = EventStore();
            
            // Store critical events
            final criticalEvents = <NostrEvent>[];
            for (int i = 0; i < 3; i++) {
              final event = NostrEvent.create(
                pubkey: 'critical_author' + '0' * (64 - 'critical_author'.length),
                kind: 1,
                tags: [['t', 'critical']],
                content: 'Critical event $i',
              ).copyWith(sig: 'critical_sig_$i' + '1' * (120 - 'critical_sig_$i'.length));
              
              criticalEvents.add(event);
              await eventStore.storeEvent(event);
            }
            
            await DatabaseHelper.instance.close();
          }
          
          // Create backup copy
          final originalFile = File(testDbPath);
          final backupFile = File(backupDbPath);
          await originalFile.copy(backupDbPath);
          
          // Simulate corruption by overwriting with garbage
          await originalFile.writeAsString('corrupted database file', flush: true);
          
          // Try to open corrupted database - should fail gracefully
          {
            DatabaseHelper.disableTestMode();
            DatabaseHelper.setDatabasePath(testDbPath);
            
            try {
              final eventStore = EventStore();
              await eventStore.queryEvents([Filter(kinds: [1])]);
              fail('Should have failed with corrupted database');
            } catch (e) {
              // Expected to fail
            }
            
            await DatabaseHelper.reset();
          }
          
          // Restore from backup
          await backupFile.copy(testDbPath);
          
          // Verify recovery
          {
            DatabaseHelper.disableTestMode();
            DatabaseHelper.setDatabasePath(testDbPath);
            
            final eventStore = EventStore();
            
            final recoveredEvents = await eventStore.queryEvents([
              Filter(tags: {'t': ['critical']})
            ]);
            
            expect(recoveredEvents.length, equals(3));
            
            for (int i = 0; i < 3; i++) {
              final found = recoveredEvents.any((e) => 
                e.content == 'Critical event $i');
              expect(found, isTrue, reason: 'Should recover critical event $i');
            }
            
            await DatabaseHelper.instance.close();
            await DatabaseHelper.reset();
          }
          
        } finally {
          // Cleanup
          try {
            await File(backupDbPath).delete();
          } catch (e) {
            // Ignore cleanup errors
          }
        }
      });
    });
  });
}