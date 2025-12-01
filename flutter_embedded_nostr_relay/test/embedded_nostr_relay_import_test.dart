// ABOUTME: Tests for EmbeddedNostrRelay.importEvents batch import functionality
// ABOUTME: Validates bulk event import from external sources into local storage

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:logging/logging.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    DatabaseHelper.enableTestMode(); // Use in-memory database for tests
  });

  group('EmbeddedNostrRelay.importEvents', () {
    late EmbeddedNostrRelay relay;

    setUp(() async {
      await DatabaseHelper.reset(); // Reset database between tests
      // Also delete the test database file to ensure a clean slate
      final testDbFile = File('/tmp/flutter_test/nostr_relay_test.db');
      if (await testDbFile.exists()) {
        await testDbFile.delete();
      }
      relay = EmbeddedNostrRelay();
      await relay.initialize(logLevel: Level.OFF);
    });

    tearDown(() async {
      await relay.shutdown();
    });

    test('imports list of events into storage', () async {
      final event1 = NostrEvent(
        id: 'abc123',
        pubkey: 'pubkey1',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 1,
        tags: [],
        content: 'Test event 1',
        sig: 'sig1',
      );
      final event2 = NostrEvent(
        id: 'def456',
        pubkey: 'pubkey1',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 1,
        tags: [],
        content: 'Test event 2',
        sig: 'sig2',
      );

      final storedCount = await relay.importEvents([event1, event2]);

      expect(storedCount, 2);

      // Verify events are queryable
      final results = await relay.queryEvents([Filter(ids: ['abc123', 'def456'])]);
      expect(results.length, 2);
    });

    test('deduplicates events with same ID', () async {
      final event = NostrEvent(
        id: 'duplicate123',
        pubkey: 'pubkey1',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 1,
        tags: [],
        content: 'Duplicate test',
        sig: 'sig1',
      );

      final firstImport = await relay.importEvents([event]);
      final secondImport = await relay.importEvents([event]);

      expect(firstImport, 1);
      expect(secondImport, 0); // Already exists
    });

    test('returns 0 for empty list', () async {
      final storedCount = await relay.importEvents([]);
      expect(storedCount, 0);
    });
  });
}
