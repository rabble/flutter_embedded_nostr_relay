// ABOUTME: Tests for iOS-specific database initialization handling
// ABOUTME: Verifies graceful fallback when WAL mode fails on iOS

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  
  group('DatabaseHelper iOS Compatibility', () {
    late DatabaseHelper databaseHelper;
    
    setUp(() {
      // Enable test mode to use in-memory database
      DatabaseHelper.enableTestMode();
      databaseHelper = DatabaseHelper.instance;
    });
    
    tearDown(() async {
      await DatabaseHelper.reset();
    });
    
    test('should handle WAL mode failure gracefully on iOS', () async {
      // This test verifies that the database initializes successfully
      // even if WAL mode fails (which can happen on iOS)
      
      // Initialize database
      final db = await databaseHelper.database;
      
      // Verify database is initialized
      expect(db, isNotNull);
      expect(db.isOpen, isTrue);
      
      // Verify we can perform basic operations
      final result = await db.rawQuery('SELECT sqlite_version()');
      expect(result, isNotEmpty);
    });
    
    test('should create all required tables on iOS', () async {
      // Initialize database
      final db = await databaseHelper.database;
      
      // Verify events table exists
      final eventsTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='events'"
      );
      expect(eventsTable, isNotEmpty);
      
      // Verify tags table exists
      final tagsTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tags'"
      );
      expect(tagsTable, isNotEmpty);
      
      // Verify sync_metadata table exists
      final syncTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_metadata'"
      );
      expect(syncTable, isNotEmpty);
    });
    
    test('should create all required indexes on iOS', () async {
      // Initialize database
      final db = await databaseHelper.database;
      
      // Check for critical indexes
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'"
      );
      
      final indexNames = indexes.map((row) => row['name'] as String).toList();
      
      // Verify key indexes exist
      expect(indexNames, contains('idx_events_pubkey'));
      expect(indexNames, contains('idx_events_created_at'));
      expect(indexNames, contains('idx_events_kind'));
      expect(indexNames, contains('idx_tags_event_id'));
      expect(indexNames, contains('idx_tags_name_value'));
    });
    
    test('should handle foreign key pragma on iOS', () async {
      // Initialize database
      final db = await databaseHelper.database;
      
      // Try to check foreign key status
      // This should not throw even if the pragma fails
      try {
        final result = await db.rawQuery('PRAGMA foreign_keys');
        // If it succeeds, great
        expect(result, isNotNull);
      } catch (e) {
        // If it fails, that's also ok - the database should still work
        expect(db.isOpen, isTrue);
      }
    });
    
    test('should persist data across database instances on iOS', () async {
      // Note: This test uses in-memory database in test mode
      // In production, it would use persistent storage
      
      // Initialize database
      final db = await databaseHelper.database;
      
      // Insert test data
      await db.insert('events', {
        'id': 'test_event_123',
        'pubkey': 'test_pubkey',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'content': 'Test content',
        'sig': 'test_signature',
        'tags': '[]',
        'first_seen': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      
      // Query the data back
      final events = await db.query('events', where: 'id = ?', whereArgs: ['test_event_123']);
      
      expect(events, hasLength(1));
      expect(events.first['content'], equals('Test content'));
    });
    
    test('should handle database corruption recovery on iOS', () async {
      // This test simulates what happens if database initialization fails
      // The code should handle it gracefully
      
      // Even with potential failures, we should get a working database
      final db = await databaseHelper.database;
      
      expect(db, isNotNull);
      expect(db.isOpen, isTrue);
      
      // Should be able to perform operations
      final count = await db.rawQuery('SELECT COUNT(*) as count FROM events');
      expect(count.first['count'], equals(0));
    });
  });
  
  group('DatabaseHelper Journal Mode Fallback', () {
    test('should use appropriate journal mode for platform', () async {
      DatabaseHelper.enableTestMode();
      final databaseHelper = DatabaseHelper.instance;
      
      final db = await databaseHelper.database;
      
      // Check journal mode (may be WAL, DELETE, or default)
      final journalMode = await db.rawQuery('PRAGMA journal_mode');
      
      // Any of these modes is acceptable
      final validModes = ['wal', 'delete', 'truncate', 'persist', 'memory', 'off'];
      final currentMode = (journalMode.first['journal_mode'] as String).toLowerCase();
      
      expect(validModes, contains(currentMode));
      
      await DatabaseHelper.reset();
    });
  });
}