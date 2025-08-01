// ABOUTME: SQLite database helper for event storage and indexing
// ABOUTME: Creates and manages database schema with optimized indexes

import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants.dart';
import '../utils/logger.dart';

class DatabaseHelper {
  static Database? _database;
  static final DatabaseHelper instance = DatabaseHelper._();
  
  DatabaseHelper._();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, RelayConstants.databaseName);
    
    RelayLogger.db('init', 'Opening database at $path');
    
    return await openDatabase(
      path,
      version: RelayConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    RelayLogger.db('create', 'Creating database schema version $version');
    
    // Events table
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        pubkey TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        kind INTEGER NOT NULL,
        content TEXT NOT NULL,
        sig TEXT NOT NULL,
        deleted INTEGER DEFAULT 0,
        first_seen INTEGER NOT NULL,
        
        -- For replaceable events
        d_tag TEXT,
        
        -- JSON columns
        tags TEXT NOT NULL,
        
        -- Constraints
        UNIQUE(id)
      );
    ''');
    
    // Tags table (normalized for efficient queries)
    await db.execute('''
      CREATE TABLE tags (
        event_id TEXT NOT NULL,
        tag_name TEXT NOT NULL,
        tag_value TEXT NOT NULL,
        tag_index INTEGER NOT NULL,
        extra_data TEXT,
        
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
      );
    ''');
    
    // Sync metadata table
    await db.execute('''
      CREATE TABLE sync_metadata (
        peer_id TEXT PRIMARY KEY,
        last_sync INTEGER NOT NULL,
        events_synced INTEGER DEFAULT 0,
        sync_direction TEXT,
        transport_type TEXT,
        metadata TEXT
      );
    ''');
    
    // Create indexes
    await _createIndexes(db);
  }
  
  Future<void> _createIndexes(Database db) async {
    RelayLogger.db('index', 'Creating database indexes');
    
    // Event indexes
    await db.execute('CREATE INDEX idx_events_pubkey ON events(pubkey);');
    await db.execute('CREATE INDEX idx_events_created_at ON events(created_at DESC);');
    await db.execute('CREATE INDEX idx_events_kind ON events(kind);');
    await db.execute('CREATE INDEX idx_events_kind_pubkey ON events(kind, pubkey);');
    await db.execute('CREATE INDEX idx_events_deleted ON events(deleted);');
    
    // Replaceable event indexes
    await db.execute('CREATE INDEX idx_events_replaceable ON events(kind, pubkey) WHERE kind >= 10000 AND kind < 20000;');
    await db.execute('CREATE INDEX idx_events_param_replaceable ON events(kind, pubkey, d_tag) WHERE kind >= 30000 AND kind < 40000;');
    
    // Tag indexes
    await db.execute('CREATE INDEX idx_tags_event_id ON tags(event_id);');
    await db.execute('CREATE INDEX idx_tags_name_value ON tags(tag_name, tag_value);');
    await db.execute('CREATE INDEX idx_tags_value ON tags(tag_value);');
    
    // Compound indexes for common queries
    await db.execute('CREATE INDEX idx_tags_e ON tags(tag_name, tag_value) WHERE tag_name = "e";');
    await db.execute('CREATE INDEX idx_tags_p ON tags(tag_name, tag_value) WHERE tag_name = "p";');
    await db.execute('CREATE INDEX idx_tags_a ON tags(tag_name, tag_value) WHERE tag_name = "a";');
    await db.execute('CREATE INDEX idx_tags_d ON tags(tag_name, tag_value) WHERE tag_name = "d";');
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    RelayLogger.db('upgrade', 'Upgrading database from v$oldVersion to v$newVersion');
    
    // Handle future migrations here
    if (oldVersion < 2) {
      // Example migration
      // await db.execute('ALTER TABLE events ADD COLUMN new_field TEXT;');
    }
  }
  
  Future<void> _onOpen(Database db) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON;');
    
    // Optimize for performance
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');
    await db.execute('PRAGMA cache_size = -64000;'); // 64MB cache
    await db.execute('PRAGMA temp_store = MEMORY;');
    
    RelayLogger.db('open', 'Database opened with performance optimizations');
  }
  
  /// Run VACUUM to optimize database
  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM;');
    RelayLogger.db('vacuum', 'Database vacuumed');
  }
  
  /// Get database statistics
  Future<Map<String, int>> getStats() async {
    final db = await database;
    
    final eventCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM events WHERE deleted = 0')
    ) ?? 0;
    
    final tagCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tags')
    ) ?? 0;
    
    final dbSize = await _getDatabaseSize();
    
    return {
      'events': eventCount,
      'tags': tagCount,
      'size_bytes': dbSize,
    };
  }
  
  Future<int> _getDatabaseSize() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, RelayConstants.databaseName);
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      RelayLogger.error('Failed to get database size', e);
    }
    return 0;
  }
  
  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      RelayLogger.db('close', 'Database closed');
    }
  }
  
  /// Delete the database (for testing or reset)
  Future<void> deleteDatabase() async {
    await close();
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, RelayConstants.databaseName);
    await databaseFactory.deleteDatabase(path);
    RelayLogger.db('delete', 'Database deleted');
  }
}