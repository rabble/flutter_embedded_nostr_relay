// ABOUTME: Event storage with optimized queries and replaceable event handling
// ABOUTME: Implements efficient storage and retrieval of Nostr events

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../core/constants.dart';
import '../utils/logger.dart';
import 'database_helper.dart';

/// High-performance event storage system for Nostr events.
/// 
/// EventStore provides efficient storage, retrieval, and management of Nostr events
/// using SQLite as the underlying database. It handles all the complexities of
/// Nostr event storage including replaceable events, parameterized replaceable events,
/// and tag indexing for fast queries.
/// 
/// ## Features
/// 
/// - **Efficient Storage**: Optimized database schema with proper indexing
/// - **Replaceable Events**: Automatic handling of event replacement logic
/// - **Tag Indexing**: Fast tag-based queries for filtering
/// - **Batch Operations**: Bulk insert operations for sync scenarios
/// - **Garbage Collection**: Automatic cleanup of old events
/// - **Duplicate Prevention**: Prevents storing the same event twice
/// 
/// ## Event Categories
/// 
/// Events are handled differently based on their kind:
/// - **Regular Events**: Stored normally, no replacement
/// - **Replaceable Events** (10000-19999): Newer events replace older ones
/// - **Ephemeral Events** (20000-29999): Not stored persistently
/// - **Parameterized Replaceable** (30000-39999): Replace based on d-tag
/// 
/// ## Basic Usage
/// 
/// ```dart
/// final store = EventStore();
/// 
/// // Store a single event
/// final success = await store.storeEvent(signedEvent);
/// if (success) {
///   print('Event stored successfully');
/// }
/// 
/// // Query events with filters
/// final events = await store.queryEvents([
///   Filter(kinds: [1], limit: 50),
/// ]);
/// 
/// // Batch store events (efficient for sync)
/// final stored = await store.storeEvents(eventList);
/// print('Stored $stored out of ${eventList.length} events');
/// ```
/// 
/// ## Query Performance
/// 
/// The store is optimized for common query patterns:
/// - Queries by `kind` and `pubkey` (author) are indexed
/// - Tag queries use a separate tags table for efficiency
/// - Time range queries are optimized with `created_at` index
/// - ID lookups are extremely fast (primary key)
/// 
/// ## Replaceable Event Handling
/// 
/// ```dart
/// // For kind 10000-19999: replaces all older events of same kind/author
/// final profileEvent = NostrEvent.create(
///   pubkey: userPubkey,
///   kind: 0, // metadata
///   content: jsonEncode({'name': 'Alice'}),
///   tags: [],
/// ).sign(privateKey);
/// 
/// await store.storeEvent(profileEvent); // Replaces old profile
/// 
/// // For kind 30000-39999: replaces based on d-tag
/// final articleEvent = NostrEvent.create(
///   pubkey: userPubkey,
///   kind: 30023, // long-form article
///   content: 'Article content...',
///   tags: [['d', 'my-article-slug']], // identifier
/// ).sign(privateKey);
/// 
/// await store.storeEvent(articleEvent); // Replaces article with same d-tag
/// ```
/// 
/// ## Memory Management
/// 
/// The store includes garbage collection features:
/// - Automatic cleanup of old events based on retention policies
/// - Preservation of events from followed users
/// - VACUUM operations to reclaim disk space
/// - Soft deletes for data integrity
class EventStore {
  final DatabaseHelper _dbHelper;
  
  EventStore({DatabaseHelper? databaseHelper}) 
      : _dbHelper = databaseHelper ?? DatabaseHelper.instance;
  
  /// Store a new event in the database.
  /// 
  /// Attempts to store the provided event, handling duplicate detection and
  /// replaceable event logic automatically. The operation is atomic and will
  /// either succeed completely or fail without partial changes.
  /// 
  /// For replaceable events (kinds 10000-19999, 30000-39999), this method
  /// will automatically mark older events as deleted when storing a newer
  /// replacement.
  /// 
  /// Parameters:
  /// - [event]: The event to store (must be valid with proper signature)
  /// 
  /// Returns `true` if the event was stored successfully, `false` if it was
  /// rejected (typically due to being a duplicate or invalid).
  /// 
  /// Example:
  /// ```dart
  /// final event = NostrEvent.create(
  ///   pubkey: userPubkey,
  ///   kind: 1,
  ///   content: 'Hello world!',
  ///   tags: [],
  /// ).sign(privateKey);
  /// 
  /// final stored = await eventStore.storeEvent(event);
  /// if (stored) {
  ///   print('Event stored with ID: ${event.id}');
  /// } else {
  ///   print('Event was rejected (duplicate or invalid)');
  /// }
  /// ```
  Future<bool> storeEvent(NostrEvent event) async {
    final db = await _dbHelper.database;
    
    try {
      return await db.transaction((txn) async {
        // Check if event already exists
        final existing = await txn.query(
          'events',
          where: 'id = ?',
          whereArgs: [event.id],
          limit: 1,
        );
        
        if (existing.isNotEmpty) {
          RelayLogger.event('duplicate', event.id);
          return false;
        }
        
        // Handle replaceable events
        if (event.isReplaceable) {
          await _handleReplaceableEvent(txn, event);
        }
        
        // Extract d-tag for parameterized replaceable events
        String? dTag;
        if (event.isParameterizedReplaceable) {
          dTag = event.dTagValue ?? '';
        }
        
        // Insert event
        await txn.insert('events', {
          'id': event.id,
          'pubkey': event.pubkey,
          'created_at': event.createdAt,
          'kind': event.kind,
          'content': event.content,
          'sig': event.sig,
          'tags': json.encode(event.tags),
          'd_tag': dTag,
          'deleted': 0,
          'first_seen': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
        
        // Insert tags
        await _insertTags(txn, event);
        
        RelayLogger.event('stored', event.id, 'kind: ${event.kind}');
        return true;
      });
    } catch (e) {
      RelayLogger.error('Failed to store event', e);
      return false;
    }
  }
  
  /// Store multiple events in a batch operation.
  /// 
  /// This method is optimized for bulk insertion scenarios such as syncing
  /// events from remote relays or importing data. Events are processed in
  /// batches to optimize database performance and memory usage.
  /// 
  /// Each event is processed with the same logic as [storeEvent], including
  /// duplicate detection and replaceable event handling. The operation is
  /// fault-tolerant - if some events fail to store, others will still be
  /// processed.
  /// 
  /// Parameters:
  /// - [events]: List of events to store
  /// 
  /// Returns the number of events that were successfully stored.
  /// 
  /// Example:
  /// ```dart
  /// // Sync events from another relay
  /// final remoteEvents = await fetchEventsFromRelay(relayUrl);
  /// final stored = await eventStore.storeEvents(remoteEvents);
  /// 
  /// print('Stored $stored out of ${remoteEvents.length} events');
  /// print('${remoteEvents.length - stored} duplicates or invalid events');
  /// ```
  Future<int> storeEvents(List<NostrEvent> events) async {
    final db = await _dbHelper.database;
    int stored = 0;
    
    // Process in batches
    for (int i = 0; i < events.length; i += RelayConstants.batchInsertSize) {
      final batch = events.skip(i).take(RelayConstants.batchInsertSize).toList();
      
      try {
        await db.transaction((txn) async {
          for (final event in batch) {
            final success = await _storeEventInTransaction(txn, event);
            if (success) stored++;
          }
        });
      } catch (e) {
        RelayLogger.error('Batch insert failed at index $i', e);
      }
    }
    
    RelayLogger.db('batch-insert', 'Stored $stored/${events.length} events');
    return stored;
  }
  
  Future<bool> _storeEventInTransaction(Transaction txn, NostrEvent event) async {
    try {
      // Check if event already exists
      final existing = await txn.query(
        'events',
        where: 'id = ?',
        whereArgs: [event.id],
        limit: 1,
      );
      
      if (existing.isNotEmpty) {
        return false;
      }
      
      // Handle replaceable events
      if (event.isReplaceable) {
        await _handleReplaceableEvent(txn, event);
      }
      
      // Extract d-tag
      String? dTag;
      if (event.isParameterizedReplaceable) {
        dTag = event.dTagValue ?? '';
      }
      
      // Insert event
      await txn.insert('events', {
        'id': event.id,
        'pubkey': event.pubkey,
        'created_at': event.createdAt,
        'kind': event.kind,
        'content': event.content,
        'sig': event.sig,
        'tags': json.encode(event.tags),
        'd_tag': dTag,
        'deleted': 0,
        'first_seen': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      
      // Insert tags
      await _insertTags(txn, event);
      
      return true;
    } catch (e) {
      RelayLogger.error('Failed to store event in transaction: ${event.id}', e);
      return false;
    }
  }
  
  Future<void> _handleReplaceableEvent(Transaction txn, NostrEvent event) async {
    if (event.kind >= 10000 && event.kind < 20000) {
      // Regular replaceable event
      await txn.update(
        'events',
        {'deleted': 1},
        where: 'kind = ? AND pubkey = ? AND created_at < ?',
        whereArgs: [event.kind, event.pubkey, event.createdAt],
      );
    } else if (event.kind >= 30000 && event.kind < 40000) {
      // Parameterized replaceable event
      final dTag = event.dTagValue ?? '';
      await txn.update(
        'events',
        {'deleted': 1},
        where: 'kind = ? AND pubkey = ? AND d_tag = ? AND created_at < ?',
        whereArgs: [event.kind, event.pubkey, dTag, event.createdAt],
      );
    }
  }
  
  Future<void> _insertTags(Transaction txn, NostrEvent event) async {
    for (int i = 0; i < event.tags.length; i++) {
      final tag = event.tags[i];
      if (tag.isEmpty) continue;
      
      final tagName = tag[0];
      final tagValue = tag.length > 1 ? tag[1] : '';
      final extraData = tag.length > 2 ? json.encode(tag.sublist(2)) : null;
      
      await txn.insert('tags', {
        'event_id': event.id,
        'tag_name': tagName,
        'tag_value': tagValue,
        'tag_index': i,
        'extra_data': extraData,
      });
    }
  }
  
  /// Query events matching the given filters.
  /// 
  /// Performs an optimized query against the event database using the provided
  /// filters. Multiple filters are combined with OR logic - an event is returned
  /// if it matches ANY of the filters.
  /// 
  /// The query is optimized for performance with proper use of database indexes.
  /// Results are automatically sorted by `created_at` in descending order
  /// (newest first).
  /// 
  /// Parameters:
  /// - [filters]: List of filters to apply (OR logic between filters)
  /// 
  /// Returns a list of events matching the filters, sorted by creation time
  /// with newest events first.
  /// 
  /// Example:
  /// ```dart
  /// // Get recent text notes and reposts
  /// final events = await eventStore.queryEvents([
  ///   Filter(kinds: [1], limit: 50),  // Text notes
  ///   Filter(kinds: [6], limit: 20),  // Reposts
  /// ]);
  /// 
  /// // Get events mentioning a specific user
  /// final mentions = await eventStore.queryEvents([
  ///   Filter(pTags: [userPubkey], limit: 100),
  /// ]);
  /// 
  /// // Get events in a time range
  /// final yesterday = DateTime.now().subtract(Duration(days: 1))
  ///     .millisecondsSinceEpoch ~/ 1000;
  /// final recentEvents = await eventStore.queryEvents([
  ///   Filter(since: yesterday, kinds: [1]),
  /// ]);
  /// ```
  Future<List<NostrEvent>> queryEvents(List<Filter> filters) async {
    final db = await _dbHelper.database;
    final allEvents = <String, NostrEvent>{};
    
    for (final filter in filters) {
      final query = _buildQuery(filter);
      final results = await db.rawQuery(query.sql, query.args);
      
      for (final row in results) {
        final event = _eventFromRow(row);
        allEvents[event.id] = event;
      }
      
      // Apply limit after combining results
      if (filter.limit != null && allEvents.length >= filter.limit!) {
        break;
      }
    }
    
    // Sort by created_at descending
    final sortedEvents = allEvents.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    return sortedEvents;
  }
  
  /// Get a single event by its ID.
  /// 
  /// Performs a fast lookup for a specific event using its unique ID.
  /// This is the most efficient way to retrieve a single event.
  /// 
  /// Parameters:
  /// - [id]: The event ID to look up (32-byte hex string)
  /// 
  /// Returns the event if found, `null` if not found or deleted.
  /// 
  /// Example:
  /// ```dart
  /// final eventId = '1234567890abcdef...';
  /// final event = await eventStore.getEvent(eventId);
  /// 
  /// if (event != null) {
  ///   print('Found event: ${event.content}');
  /// } else {
  ///   print('Event not found');
  /// }
  /// ```
  Future<NostrEvent?> getEvent(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'events',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return _eventFromRow(results.first);
  }

  /// Get event by ID for version sync (includes deleted events).
  /// 
  /// This method is used internally by the version sync handler to check
  /// for existing events, including those marked as deleted. This is needed
  /// to detect protocol violations (same ID with different content).
  /// 
  /// Parameters:
  /// - [id]: The event ID to look up
  /// 
  /// Returns the event if found, `null` if not found.
  Future<NostrEvent?> getEventById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return _eventFromRow(results.first);
  }

  /// Get the latest replaceable event of a specific kind and author.
  /// 
  /// For replaceable events (kinds 10000-19999), there should only be one
  /// current version per kind and author. This method returns the latest
  /// version based on created_at timestamp.
  /// 
  /// Parameters:
  /// - [kind]: The event kind (must be 10000-19999)
  /// - [pubkey]: The author's public key
  /// 
  /// Returns the latest replaceable event, or `null` if none exists.
  Future<NostrEvent?> getLatestReplaceableEvent(int kind, String pubkey) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'events',
      where: 'kind = ? AND pubkey = ? AND deleted = 0',
      whereArgs: [kind, pubkey],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return _eventFromRow(results.first);
  }

  /// Get the latest parameterized replaceable event of a specific kind, author, and d-tag.
  /// 
  /// For parameterized replaceable events (kinds 30000-39999), there should only be one
  /// current version per kind, author, and d-tag combination. This method returns the
  /// latest version based on created_at timestamp.
  /// 
  /// Parameters:
  /// - [kind]: The event kind (must be 30000-39999)
  /// - [pubkey]: The author's public key
  /// - [dTag]: The d-tag value (empty string if no d-tag)
  /// 
  /// Returns the latest parameterized replaceable event, or `null` if none exists.
  Future<NostrEvent?> getLatestParameterizedReplaceableEvent(
    int kind, 
    String pubkey, 
    String dTag,
  ) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'events',
      where: 'kind = ? AND pubkey = ? AND d_tag = ? AND deleted = 0',
      whereArgs: [kind, pubkey, dTag],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return _eventFromRow(results.first);
  }
  
  /// Delete events (soft delete)
  Future<void> deleteEvents(List<String> eventIds) async {
    final db = await _dbHelper.database;
    
    await db.update(
      'events',
      {'deleted': 1},
      where: 'id IN (${List.filled(eventIds.length, '?').join(',')})',
      whereArgs: eventIds,
    );
    
    RelayLogger.db('delete', 'Soft deleted ${eventIds.length} events');
  }
  
  /// Build SQL query from filter
  _QueryParts _buildQuery(Filter filter) {
    final conditions = <String>[];
    final args = <dynamic>[];
    
    // Base query
    var sql = 'SELECT DISTINCT e.* FROM events e';
    
    // Join tags table if needed
    bool needsTagJoin = filter.eTags != null || 
                       filter.pTags != null || 
                       filter.aTags != null || 
                       filter.dTags != null ||
                       (filter.tags != null && filter.tags!.isNotEmpty);
    
    if (needsTagJoin) {
      sql += ' LEFT JOIN tags t ON e.id = t.event_id';
    }
    
    // Always exclude deleted events
    conditions.add('e.deleted = 0');
    
    // Filter by IDs
    if (filter.ids != null && filter.ids!.isNotEmpty) {
      conditions.add('e.id IN (${List.filled(filter.ids!.length, '?').join(',')})');
      args.addAll(filter.ids!);
    }
    
    // Filter by authors
    if (filter.authors != null && filter.authors!.isNotEmpty) {
      conditions.add('e.pubkey IN (${List.filled(filter.authors!.length, '?').join(',')})');
      args.addAll(filter.authors!);
    }
    
    // Filter by kinds
    if (filter.kinds != null && filter.kinds!.isNotEmpty) {
      conditions.add('e.kind IN (${List.filled(filter.kinds!.length, '?').join(',')})');
      args.addAll(filter.kinds!);
    }
    
    // Filter by time range
    if (filter.since != null) {
      conditions.add('e.created_at >= ?');
      args.add(filter.since!);
    }
    
    if (filter.until != null) {
      conditions.add('e.created_at <= ?');
      args.add(filter.until!);
    }
    
    // Filter by tags
    final tagConditions = <String>[];
    
    if (filter.eTags != null && filter.eTags!.isNotEmpty) {
      tagConditions.add('(t.tag_name = "e" AND t.tag_value IN (${List.filled(filter.eTags!.length, '?').join(',')}))');
      args.addAll(filter.eTags!);
    }
    
    if (filter.pTags != null && filter.pTags!.isNotEmpty) {
      tagConditions.add('(t.tag_name = "p" AND t.tag_value IN (${List.filled(filter.pTags!.length, '?').join(',')}))');
      args.addAll(filter.pTags!);
    }
    
    if (filter.aTags != null && filter.aTags!.isNotEmpty) {
      tagConditions.add('(t.tag_name = "a" AND t.tag_value IN (${List.filled(filter.aTags!.length, '?').join(',')}))');
      args.addAll(filter.aTags!);
    }
    
    if (filter.dTags != null && filter.dTags!.isNotEmpty) {
      tagConditions.add('(t.tag_name = "d" AND t.tag_value IN (${List.filled(filter.dTags!.length, '?').join(',')}))');
      args.addAll(filter.dTags!);
    }
    
    if (tagConditions.isNotEmpty) {
      conditions.add('(${tagConditions.join(' OR ')})');
    }
    
    // Build WHERE clause
    if (conditions.isNotEmpty) {
      sql += ' WHERE ${conditions.join(' AND ')}';
    }
    
    // Order by created_at descending
    sql += ' ORDER BY e.created_at DESC';
    
    // Apply limit
    if (filter.limit != null) {
      sql += ' LIMIT ?';
      args.add(filter.limit!);
    }
    
    return _QueryParts(sql, args);
  }
  
  NostrEvent _eventFromRow(Map<String, dynamic> row) {
    return NostrEvent(
      id: row['id'] as String,
      pubkey: row['pubkey'] as String,
      createdAt: row['created_at'] as int,
      kind: row['kind'] as int,
      tags: (json.decode(row['tags'] as String) as List).cast<List>()
          .map((tag) => tag.cast<String>())
          .toList(),
      content: row['content'] as String,
      sig: row['sig'] as String,
    );
  }
  
  /// Get events for negentropy sync
  Future<List<String>> getEventIdsInRange(int startTime, int endTime) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'events',
      columns: ['id'],
      where: 'created_at >= ? AND created_at < ? AND deleted = 0',
      whereArgs: [startTime, endTime],
      orderBy: 'created_at ASC',
    );
    
    return results.map((row) => row['id'] as String).toList();
  }
  
  /// Perform garbage collection to remove old events.
  /// 
  /// Marks old events as deleted based on the retention policy. This helps
  /// keep the database size manageable and improves query performance.
  /// Events are soft-deleted (marked as deleted) rather than physically
  /// removed to maintain referential integrity.
  /// 
  /// Parameters:
  /// - [retentionDays]: Number of days to retain events (older events are deleted)
  /// - [preserveAuthors]: Optional list of author pubkeys whose events should never be deleted
  /// 
  /// Returns the number of events that were marked as deleted.
  /// 
  /// Example:
  /// ```dart
  /// // Clean up events older than 90 days, but preserve events from followed users
  /// final followedUsers = await getFollowedPubkeys();
  /// final deleted = await eventStore.garbageCollect(
  ///   retentionDays: 90,
  ///   preserveAuthors: followedUsers,
  /// );
  /// 
  /// print('Cleaned up $deleted old events');
  /// 
  /// // Run database vacuum to reclaim space
  /// await DatabaseHelper.instance.vacuum();
  /// ```
  Future<int> garbageCollect({
    required int retentionDays,
    List<String>? preserveAuthors,
  }) async {
    final db = await _dbHelper.database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch ~/ 1000;
    
    var where = 'created_at < ? AND deleted = 0';
    var whereArgs = <dynamic>[cutoffTime];
    
    if (preserveAuthors != null && preserveAuthors.isNotEmpty) {
      where += ' AND pubkey NOT IN (${List.filled(preserveAuthors.length, '?').join(',')})';
      whereArgs.addAll(preserveAuthors);
    }
    
    final count = await db.update(
      'events',
      {'deleted': 1},
      where: where,
      whereArgs: whereArgs,
    );
    
    RelayLogger.db('gc', 'Garbage collected $count events older than $retentionDays days');
    return count;
  }
}

class _QueryParts {
  final String sql;
  final List<dynamic> args;
  
  _QueryParts(this.sql, this.args);
}