// ABOUTME: Event storage with optimized queries and replaceable event handling
// ABOUTME: Implements efficient storage and retrieval of Nostr events

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../core/constants.dart';
import '../utils/logger.dart';
import 'database_helper.dart';

class EventStore {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  /// Store a new event
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
  
  /// Store multiple events in a batch
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
  
  /// Query events matching the given filters
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
  
  /// Get a single event by ID
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
  
  /// Garbage collection - remove old events
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