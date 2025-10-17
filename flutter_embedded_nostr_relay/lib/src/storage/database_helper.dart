// ABOUTME: SQLite database helper for event storage and indexing
// ABOUTME: Creates and manages database schema with optimized indexes

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart';
import '../utils/file_utils.dart';

// Conditional import for path_provider and Directory - stub on Web, real on non-Web
import 'database_helper_stub.dart'
    if (dart.library.io) 'database_helper_io.dart';

class DatabaseHelper {
  static Database? _database;
  static final DatabaseHelper instance = DatabaseHelper._();
  static bool _testMode = false;
  
  DatabaseHelper._();
  
  /// Enable test mode to use in-memory database
  static void enableTestMode() {
    _testMode = true;
  }
  
  /// Reset for testing
  static Future<void> reset() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    // Determine which database factory to use WITHOUT polluting global state
    DatabaseFactory factory;

    if (PlatformUtils.isDesktop || _testMode) {
      // Use FFI for desktop, but DON'T set global factory
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else if (PlatformUtils.isWeb) {
      // Use FFI for web
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      // Use default factory for iOS/Android
      factory = databaseFactory;
    }

    late String path;
    if (PlatformUtils.isWeb) {
      // Use in-memory database for Web platform (including tests)
      // Web doesn't support path_provider or file system access
      path = inMemoryDatabasePath;
      RelayLogger.db('init', 'Opening in-memory database for Web platform');
      if (_testMode) {
        RelayLogger.db('init', 'Test mode enabled - using in-memory database on Web');
      } else {
        RelayLogger.db('init', 'Note: Events will not persist across page reloads on Web');
      }
    } else if (_testMode) {
      // Use file-based database in /tmp for tests on non-web platforms
      // This enables WAL mode for concurrent reads/writes, matching production behavior
      final testDir = Directory('/tmp/flutter_test');
      if (!testDir.existsSync()) {
        testDir.createSync(recursive: true);
      }
      path = '${testDir.path}/nostr_relay_test.db';
      RelayLogger.db('init', 'Opening test database at $path (WAL mode enabled)');
    } else {
      final supportDirectory = await getApplicationSupportDirectory();

      // Use Application Support directory for database storage
      // This is the correct location for app data on all platforms
      // On macOS: ~/Library/Application Support/com.example.app/
      // On iOS: sandboxed app support directory
      // On Android: sandboxed app support directory
      path = join(supportDirectory.path, RelayConstants.databaseName);

      RelayLogger.db('init', 'Opening persistent database at $path');
      RelayLogger.db('init', 'Platform: ${PlatformUtils.operatingSystem}');
    }

    try {
      return await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: RelayConstants.databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onOpen: _onOpen,
        ),
      );
    } catch (e) {
      RelayLogger.error('Failed to open database', e);
      
      // On iOS, sometimes the database can be corrupted or have permission issues
      // Try to delete and recreate if this is not a test
      if (!_testMode && PlatformUtils.isIOS) {
        try {
          RelayLogger.db('init', 'Attempting to delete and recreate database on iOS');
          await databaseFactory.deleteDatabase(path);
          
          // Try again with a fresh database
          return await openDatabase(
            path,
            version: RelayConstants.databaseVersion,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
            onOpen: _onOpen,
          );
        } catch (retryError) {
          RelayLogger.error('Failed to recreate database', retryError);
          rethrow;
        }
      }
      
      rethrow;
    }
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
    // On iOS, WAL mode can fail in certain sandboxed environments
    // We need to handle this gracefully and fall back to default journal mode
    try {
      await db.execute('PRAGMA journal_mode = WAL;');
    } catch (e) {
      RelayLogger.db('open', 'Failed to set WAL mode (iOS compatibility): $e');
      // Fall back to DELETE mode which is more compatible
      try {
        await db.execute('PRAGMA journal_mode = DELETE;');
      } catch (_) {
        // Even DELETE mode might fail, just continue with default
        RelayLogger.db('open', 'Using default journal mode');
      }
    }
    
    // These pragmas are generally safe across platforms
    try {
      await db.execute('PRAGMA synchronous = NORMAL;');
      await db.execute('PRAGMA cache_size = -64000;'); // 64MB cache
      await db.execute('PRAGMA temp_store = MEMORY;');
    } catch (e) {
      RelayLogger.db('open', 'Some performance optimizations failed: $e');
      // Continue anyway, these are optimizations not requirements
    }
    
    RelayLogger.db('open', 'Database opened with available optimizations');
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
    // On web, we can't check file sizes
    if (kIsWeb) return 0;

    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final path = join(supportDirectory.path, RelayConstants.databaseName);
      return await FileUtils.getFileSize(path);
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

    // On web, we can't delete files
    if (kIsWeb) {
      RelayLogger.db('delete', 'Database deleted (in-memory on Web)');
      return;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final path = join(supportDirectory.path, RelayConstants.databaseName);
    await databaseFactory.deleteDatabase(path);
    RelayLogger.db('delete', 'Database deleted');
  }
}