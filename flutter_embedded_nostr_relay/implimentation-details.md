# Critical Implementation Details for flutter_embedded_nostr_relay

## 1. Event ID Calculation (MUST BE EXACTLY RIGHT)

The event ID is **extremely specific** and must match the Nostr specification exactly:

```dart
class EventValidator {
  static String computeEventId(NostrEvent event) {
    // CRITICAL: The order and format MUST be exactly this
    final serialized = json.encode([
      0,                    // Version - always 0
      event.pubkey,         // Must be lowercase hex
      event.createdAt,      // Unix timestamp as integer
      event.kind,           // Integer
      event.tags,           // Array of arrays
      event.content,        // String
    ]);
    
    // CRITICAL: Must use SHA256, not SHA512 or others
    final bytes = utf8.encode(serialized);
    final hash = sha256.convert(bytes);
    
    // CRITICAL: Must be lowercase hex string
    return hash.toString().toLowerCase();
  }
}
```

**Common mistakes:**
- Using wrong field order
- Including the signature in the hash
- Not lowercasing the hex output
- Using wrong encoding for content

## 2. Replaceable Event Logic (Complex Edge Cases)

```dart
// CRITICAL: Different replacement rules for different kind ranges
class ReplaceableEventHandler {
  Future<void> handleEvent(NostrEvent event) async {
    if (event.kind >= 0 && event.kind < 10000) {
      // Regular events - NEVER replaceable
      await _store.insert(event);
      
    } else if (event.kind >= 10000 && event.kind < 20000) {
      // Replaceable events - one per kind per pubkey
      await _store.insertOrReplace(
        where: 'kind = ? AND pubkey = ?',
        params: [event.kind, event.pubkey],
        event: event,
      );
      
    } else if (event.kind >= 20000 && event.kind < 30000) {
      // Ephemeral events - DON'T store at all
      // Just broadcast to active subscribers
      await _broadcast(event);
      return; // Don't store!
      
    } else if (event.kind >= 30000 && event.kind < 40000) {
      // Parameterized replaceable - check 'd' tag
      final dTag = event.tags
          .firstWhere((tag) => tag[0] == 'd', orElse: () => ['d', ''])
          [1];
      
      await _store.insertOrReplace(
        where: 'kind = ? AND pubkey = ? AND d_tag = ?',
        params: [event.kind, event.pubkey, dTag],
        event: event,
      );
    }
  }
}
```

## 3. Tag Indexing (Performance Critical)

```dart
// CRITICAL: Don't index ALL tags - it explodes the database
class TagIndexer {
  // Only index specific tag types that are queried
  static const INDEXED_TAG_TYPES = ['e', 'p', 't', 'a', 'd'];
  
  Future<void> indexTags(String eventId, List<List<String>> tags) async {
    final batch = <Map<String, dynamic>>[];
    
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      if (tag.isEmpty) continue;
      
      // CRITICAL: Only index if it's a queryable tag type
      if (INDEXED_TAG_TYPES.contains(tag[0])) {
        batch.add({
          'event_id': eventId,
          'tag_name': tag[0],
          'tag_value': tag.length > 1 ? tag[1] : '',
          'tag_extra': tag.length > 2 ? json.encode(tag.sublist(2)) : null,
          'tag_order': i, // Preserve order!
        });
      }
    }
    
    // Batch insert for performance
    if (batch.isNotEmpty) {
      await _db.insertBatch('tags', batch);
    }
  }
}
```

## 4. Filter Query Optimization (Make or Break Performance)

```dart
class QueryBuilder {
  // CRITICAL: Order of WHERE clauses matters for index usage
  String buildOptimalQuery(Filter filter) {
    final conditions = <String>[];
    final params = <dynamic>[];
    
    // 1. Most selective conditions first
    if (filter.ids != null && filter.ids!.isNotEmpty) {
      // IDs are most selective - SQLite will use primary key
      conditions.add('id IN (${List.filled(filter.ids!.length, '?').join(',')})');
      params.addAll(filter.ids!);
      
    } else if (filter.authors != null && filter.kinds != null) {
      // CRITICAL: This order matches our composite index
      conditions.add('kind IN (${List.filled(filter.kinds!.length, '?').join(',')})');
      params.addAll(filter.kinds!);
      
      conditions.add('pubkey IN (${List.filled(filter.authors!.length, '?').join(',')})');
      params.addAll(filter.authors!);
      
    } else if (filter.kinds != null) {
      // Single condition - use kind index
      conditions.add('kind IN (${List.filled(filter.kinds!.length, '?').join(',')})');
      params.addAll(filter.kinds!);
    }
    
    // 2. Time range (works with all indexes)
    if (filter.since != null) {
      conditions.add('created_at >= ?');
      params.add(filter.since);
    }
    if (filter.until != null) {
      conditions.add('created_at <= ?');
      params.add(filter.until);
    }
    
    // 3. Tag filters require JOIN - most expensive
    if (filter.tags != null) {
      for (final entry in filter.tags!.entries) {
        final tagName = entry.key;
        final tagValues = entry.value;
        
        // CRITICAL: Use EXISTS for better performance than JOIN
        conditions.add('''
          EXISTS (
            SELECT 1 FROM tags t 
            WHERE t.event_id = events.id 
            AND t.tag_name = ? 
            AND t.tag_value IN (${List.filled(tagValues.length, '?').join(',')})
          )
        ''');
        params.add(tagName);
        params.addAll(tagValues);
      }
    }
    
    // Build final query
    var sql = 'SELECT * FROM events';
    if (conditions.isNotEmpty) {
      sql += ' WHERE ' + conditions.join(' AND ');
    }
    
    // CRITICAL: Always order by created_at DESC for social feeds
    sql += ' ORDER BY created_at DESC';
    
    // CRITICAL: Always have a limit to prevent memory issues
    sql += ' LIMIT ?';
    params.add(filter.limit ?? 100);
    
    return sql;
  }
}
```

## 5. WebSocket Frame Size Limits

```dart
class WebSocketMessageHandler {
  // CRITICAL: WebSocket frames have size limits
  static const MAX_FRAME_SIZE = 65536; // 64KB typical limit
  
  Future<void> sendEvent(WebSocket client, NostrEvent event) async {
    final message = json.encode(['EVENT', event.toJson()]);
    
    // CRITICAL: Check size before sending
    if (message.length > MAX_FRAME_SIZE) {
      // For large events, send in chunks or reject
      await client.add(json.encode([
        'NOTICE', 
        'Event too large. Maximum size is 64KB'
      ]));
      return;
    }
    
    client.add(message);
  }
  
  // CRITICAL: Protect against malicious clients
  void handleIncomingMessage(String message) {
    if (message.length > MAX_FRAME_SIZE * 2) {
      throw Exception('Message too large');
    }
    
    // Parse with error handling
    try {
      final parsed = json.decode(message);
      // Process...
    } catch (e) {
      // Don't echo back the bad message - could be attack
      client.add(json.encode(['NOTICE', 'Invalid message format']));
    }
  }
}
```

## 6. Subscription Lifecycle Management

```dart
class SubscriptionManager {
  // CRITICAL: Prevent subscription flooding attacks
  static const MAX_SUBS_PER_CLIENT = 10;
  static const MAX_FILTERS_PER_SUB = 10;
  static const MAX_FILTER_ITEMS = 1000; // IDs, authors, etc
  
  final _subscriptions = <String, ClientSubscription>{};
  final _clientSubs = <String, Set<String>>{}; // client -> sub IDs
  
  String? addSubscription(String clientId, String subId, List<Filter> filters) {
    // CRITICAL: Enforce limits
    final clientSubs = _clientSubs[clientId] ?? {};
    if (clientSubs.length >= MAX_SUBS_PER_CLIENT) {
      return 'Too many subscriptions';
    }
    
    if (filters.length > MAX_FILTERS_PER_SUB) {
      return 'Too many filters';
    }
    
    // CRITICAL: Validate filter complexity
    for (final filter in filters) {
      if ((filter.ids?.length ?? 0) > MAX_FILTER_ITEMS ||
          (filter.authors?.length ?? 0) > MAX_FILTER_ITEMS ||
          (filter.kinds?.length ?? 0) > MAX_FILTER_ITEMS) {
        return 'Filter too complex';
      }
    }
    
    // CRITICAL: Replace existing subscription with same ID
    if (_subscriptions.containsKey(subId)) {
      removeSubscription(clientId, subId);
    }
    
    // Add new subscription
    _subscriptions[subId] = ClientSubscription(clientId, subId, filters);
    _clientSubs.putIfAbsent(clientId, () => {}).add(subId);
    
    return null; // Success
  }
  
  // CRITICAL: Clean up when client disconnects
  void handleClientDisconnect(String clientId) {
    final subs = _clientSubs[clientId];
    if (subs != null) {
      for (final subId in subs) {
        _subscriptions.remove(subId);
      }
      _clientSubs.remove(clientId);
    }
  }
}
```

## 7. Negentropy P2P Sync Implementation Details

```dart
class NegentropyImplementation {
  // CRITICAL: Fingerprint calculation must be deterministic
  
  // CORRECT: Sort event IDs before XOR
  String computeFingerprint(List<String> eventIds) {
    final sorted = eventIds.toList()..sort();  // CRITICAL: Must sort!
    
    var accumulator = BigInt.zero;
    for (final id in sorted) {
      // CRITICAL: Parse as hex, not decimal
      final idBigInt = BigInt.parse(id, radix: 16);
      accumulator ^= idBigInt;
    }
    
    // CRITICAL: Pad to consistent length
    return accumulator.toRadixString(16).padLeft(32, '0');
  }
  
  // WRONG: Unsorted XOR gives different results
  String computeFingerprintWRONG(List<String> eventIds) {
    var accumulator = BigInt.zero;
    for (final id in eventIds) {  // NOT SORTED!
      accumulator ^= BigInt.parse(id, radix: 16);
    }
    return accumulator.toRadixString(16);  // Not padded!
  }
  
  // CRITICAL: Range boundaries must be consistent
  List<Range> createRanges(int startTime, int endTime) {
    final ranges = <Range>[];
    
    // CRITICAL: Use consistent time boundaries
    // Always align to hour/day boundaries
    final alignedStart = (startTime ~/ 3600) * 3600;  // Hour boundary
    final alignedEnd = ((endTime + 3599) ~/ 3600) * 3600;  // Next hour
    
    var current = alignedStart;
    while (current < alignedEnd) {
      ranges.add(Range(
        lower: current,
        upper: min(current + 86400, alignedEnd),  // Day chunks
      ));
      current += 86400;
    }
    
    return ranges;
  }
}

// CRITICAL: Handle BLE packet fragmentation correctly
class BLENegentropyProtocol {
  static const MAX_PACKET = 512;  // BLE MTU limit
  static const HEADER_SIZE = 6;   // 4 bytes length + 2 bytes sequence
  
  Future<void> sendLargeMessage(Uint8List data) async {
    // CRITICAL: Include total length in first packet
    final totalLength = data.length;
    final numPackets = (data.length + MAX_PACKET - HEADER_SIZE - 1) ~/ 
                       (MAX_PACKET - HEADER_SIZE);
    
    for (var i = 0; i < numPackets; i++) {
      final start = i * (MAX_PACKET - HEADER_SIZE);
      final end = min(start + MAX_PACKET - HEADER_SIZE, data.length);
      
      final packet = ByteDataWriter()
        ..writeUint32(totalLength)      // Total message length
        ..writeUint16(i)                 // Packet sequence number
        ..write(data.sublist(start, end));
      
      await characteristic.write(packet.toBytes());
      
      // CRITICAL: Delay between packets to avoid BLE buffer overflow
      await Future.delayed(Duration(milliseconds: 20));
    }
  }
  
  // CRITICAL: Reassemble with timeout
  Future<Uint8List> receiveLargeMessage() async {
    final packets = <int, Uint8List>{};
    int? totalLength;
    
    final completer = Completer<Uint8List>();
    Timer? timeout;
    
    characteristic.value.listen((packet) {
      final reader = ByteDataReader(packet);
      totalLength ??= reader.readUint32();
      final sequence = reader.readUint16();
      final data = reader.readRemaining();
      
      packets[sequence] = data;
      
      // Reset timeout on each packet
      timeout?.cancel();
      timeout = Timer(Duration(seconds: 5), () {
        completer.completeError('Negentropy message timeout');
      });
      
      // Check if complete
      if (_isComplete(packets, totalLength!)) {
        timeout?.cancel();
        completer.complete(_assemble(packets));
      }
    });
    
    return completer.future;
  }
}

// CRITICAL: Efficient difference detection
class NegentropyDifferenceDetector {
  // CRITICAL: Don't send too many items at once
  static const MAX_ITEMS_PER_MESSAGE = 500;
  
  Future<void> reconcileRange(Range range, NegentropyPeer peer) async {
    final ourItems = await storage.getEventIds(range);
    
    // CRITICAL: For small sets, exchange directly
    if (ourItems.length <= MAX_ITEMS_PER_MESSAGE) {
      await peer.send(ItemsMessage(
        range: range,
        items: ourItems,
      ));
      
      final theirMessage = await peer.receive<ItemsMessage>();
      final theirItems = theirMessage.items.toSet();
      
      // CRITICAL: Compute differences efficiently
      final weNeed = theirItems.difference(ourItems.toSet());
      final theyNeed = ourItems.toSet().difference(theirItems);
      
      await _exchangeEvents(weNeed, theyNeed, peer);
      
    } else {
      // CRITICAL: Subdivide large ranges
      final subranges = _subdivideRange(range, ourItems.length);
      
      for (final subrange in subranges) {
        await reconcileRange(subrange, peer);
      }
    }
  }
  
  // CRITICAL: Smart subdivision based on data distribution
  List<Range> _subdivideRange(Range range, int itemCount) {
    final duration = range.upper - range.lower;
    
    // CRITICAL: Don't create too many subranges
    final targetRanges = min(10, max(2, itemCount ~/ MAX_ITEMS_PER_MESSAGE));
    
    final chunkSize = duration ~/ targetRanges;
    final ranges = <Range>[];
    
    for (var i = 0; i < targetRanges; i++) {
      ranges.add(Range(
        lower: range.lower + (i * chunkSize),
        upper: i == targetRanges - 1 
            ? range.upper 
            : range.lower + ((i + 1) * chunkSize),
      ));
    }
    
    return ranges;
  }
}

// CRITICAL: Handle network failures gracefully
class RobustNegentropySession {
  static const MAX_RETRIES = 3;
  static const RETRY_DELAY = Duration(seconds: 2);
  
  Future<void> syncWithRetry(NegentropyPeer peer) async {
    for (var attempt = 0; attempt < MAX_RETRIES; attempt++) {
      try {
        await _performSync(peer);
        return;  // Success
        
      } on NetworkException catch (e) {
        if (attempt == MAX_RETRIES - 1) rethrow;
        
        _log.warning('Negentropy sync failed, retry ${attempt + 1}: $e');
        await Future.delayed(RETRY_DELAY * (attempt + 1));
        
      } on CorruptedDataException {
        // CRITICAL: Don't retry on data corruption
        _log.error('Negentropy data corruption detected');
        _markPeerAsSuspicious(peer.id);
        rethrow;
      }
    }
  }
  
  // CRITICAL: Save progress for resume
  Future<void> _performSync(NegentropyPeer peer) async {
    final checkpoint = await _loadCheckpoint(peer.id);
    
    if (checkpoint != null) {
      _log.info('Resuming Negentropy sync from checkpoint');
      await _resumeFromCheckpoint(checkpoint, peer);
    } else {
      await _fullSync(peer);
    }
  }
  
  Future<void> _saveCheckpoint(String peerId, SyncProgress progress) async {
    await _store.saveJson('negentropy_checkpoint_$peerId', {
      'timestamp': DateTime.now().toIso8601String(),
      'completed_ranges': progress.completedRanges.map((r) => r.toJson()).toList(),
      'pending_ranges': progress.pendingRanges.map((r) => r.toJson()).toList(),
      'events_synced': progress.eventsSynced,
    });
  }
}
```

## 8. Database Transaction Boundaries

```dart
class EventStore {
  // CRITICAL: Wrong transaction boundaries kill performance
  
  // BAD - Transaction per event
  Future<void> saveEventsSlow(List<NostrEvent> events) async {
    for (final event in events) {
      await _db.transaction((txn) async {
        await txn.insert('events', event.toMap());
      });
    }
  }
  
  // GOOD - Single transaction for batch
  Future<void> saveEventsFast(List<NostrEvent> events) async {
    await _db.transaction((txn) async {
      final stmt = txn.prepare(
        'INSERT OR REPLACE INTO events VALUES (?, ?, ?, ?, ?, ?, ?)'
      );
      
      for (final event in events) {
        stmt.execute([
          event.id,
          event.pubkey,
          event.createdAt,
          event.kind,
          event.content,
          event.sig,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ]);
      }
      
      stmt.dispose();
    });
  }
  
  // CRITICAL: Don't hold transactions during I/O
  Future<void> processEvents(List<NostrEvent> events) async {
    // Validate OUTSIDE transaction
    final validEvents = <NostrEvent>[];
    for (final event in events) {
      if (await _validator.validate(event)) {
        validEvents.add(event);
      }
    }
    
    // Save in transaction
    await saveEventsFast(validEvents);
  }
}
```

## 9. Memory Pressure on Mobile

```dart
class MobileMemoryManager {
  // CRITICAL: Mobile devices have limited memory
  static const MAX_CACHED_EVENTS = 1000;
  static const MAX_QUERY_RESULTS = 100;
  
  // CRITICAL: Stream results instead of loading all into memory
  Stream<NostrEvent> queryEventsStreaming(Filter filter) async* {
    final query = _buildQuery(filter);
    
    // CRITICAL: Use SQLite's step() for streaming
    final stmt = _db.prepare(query);
    
    try {
      while (stmt.step()) {
        final row = stmt.current;
        yield NostrEvent.fromRow(row);
      }
    } finally {
      stmt.dispose();
    }
  }
  
  // CRITICAL: Implement aggressive cleanup
  Timer? _cleanupTimer;
  
  void startMemoryMonitoring() {
    _cleanupTimer = Timer.periodic(Duration(minutes: 5), (_) async {
      // Clear old cached data
      await _clearCache();
      
      // Run SQLite VACUUM monthly
      if (DateTime.now().day == 1) {
        await _db.execute('VACUUM');
      }
    });
  }
}
```

## 11. Negentropy Algorithm Core Implementation

```dart
// CRITICAL: The core Negentropy algorithm must be implemented exactly
class NegentropyCore {
  // CRITICAL: Use consistent hash function across all peers
  static Uint8List hash(Uint8List data) {
    return sha256.convert(data).bytes as Uint8List;
  }
  
  // CRITICAL: Accumulator for XOR operations
  class Accumulator {
    BigInt _value = BigInt.zero;
    
    void add(String eventId) {
      // CRITICAL: Must be lowercase hex
      final normalized = eventId.toLowerCase();
      if (normalized.length != 64) {
        throw ArgumentError('Event ID must be 64 hex chars');
      }
      
      final idBigInt = BigInt.parse(normalized, radix: 16);
      _value ^= idBigInt;
    }
    
    String getFingerprint() {
      // CRITICAL: Always pad to 32 hex chars (128 bits)
      final hex = _value.toRadixString(16).padLeft(32, '0');
      return hex.substring(hex.length - 32);  // Take last 128 bits
    }
  }
  
  // CRITICAL: Range splitting must be deterministic
  class RangeSplitter {
    static List<Range> split(Range range, int targetCount) {
      if (targetCount <= 1) return [range];
      
      final items = range.upper - range.lower;
      if (items <= targetCount) {
        // One item per range
        return List.generate(items, (i) => 
          Range(range.lower + i, range.lower + i + 1)
        );
      }
      
      // CRITICAL: Use power-of-2 splitting for consistency
      final splits = _nextPowerOfTwo(min(targetCount, 16));
      final chunkSize = items ~/ splits;
      
      return List.generate(splits, (i) {
        final start = range.lower + (i * chunkSize);
        final end = (i == splits - 1) 
            ? range.upper 
            : range.lower + ((i + 1) * chunkSize);
        return Range(start, end);
      });
    }
    
    static int _nextPowerOfTwo(int n) {
      n--;
      n |= n >> 1;
      n |= n >> 2;
      n |= n >> 4;
      n |= n >> 8;
      n |= n >> 16;
      return n + 1;
    }
  }
  
  // CRITICAL: Message ordering for protocol flow
  class ProtocolStateMachine {
    State _state = State.initial;
    final _pendingRanges = Queue<Range>();
    final _completedRanges = <Range>{};
    
    NegentropyMessage? getNextMessage() {
      switch (_state) {
        case State.initial:
          _state = State.waitingForResponse;
          return _createInitMessage();
          
        case State.processing:
          if (_pendingRanges.isEmpty) {
            _state = State.complete;
            return NegentropyMessage(type: MSG_DONE);
          }
          
          final range = _pendingRanges.removeFirst();
          return _processRange(range);
          
        case State.waitingForResponse:
          return null;  // Wait for peer
          
        case State.complete:
          return null;
      }
    }
    
    void handleMessage(NegentropyMessage msg) {
      // CRITICAL: Validate state transitions
      switch (msg.type) {
        case MSG_FINGERPRINT:
          if (_state != State.waitingForResponse) {
            throw StateError('Unexpected fingerprint message');
          }
          _handleFingerprints(msg.ranges!);
          _state = State.processing;
          break;
          
        case MSG_ITEMS:
          _handleItems(msg);
          break;
          
        case MSG_DONE:
          _state = State.complete;
          break;
      }
    }
  }
}

// CRITICAL: Optimal parameters for Nostr
class NegentropyOptimalParams {
  // Based on typical Nostr event patterns
  
  // Don't create ranges smaller than this
  static const MIN_RANGE_SECONDS = 300;  // 5 minutes
  
  // Don't send more than this many items
  static const MAX_ITEMS_PER_MESSAGE = 500;
  
  // Stop subdividing at this depth
  static const MAX_RECURSION_DEPTH = 10;
  
  // Minimum items to bother with fingerprinting
  static const MIN_ITEMS_FOR_FINGERPRINT = 10;
  
  static bool shouldSubdivide(Range range, int itemCount) {
    // Too few items - just send them
    if (itemCount < MIN_ITEMS_FOR_FINGERPRINT) return false;
    
    // Too many items - must subdivide
    if (itemCount > MAX_ITEMS_PER_MESSAGE) return true;
    
    // Range too small - don't subdivide
    final duration = range.upper - range.lower;
    if (duration < MIN_RANGE_SECONDS) return false;
    
    // Use heuristic: subdivide if density is high
    final density = itemCount / duration.toDouble();
    return density > 0.1;  // More than 1 event per 10 seconds
  }
}

// CRITICAL: BLE-specific Negentropy optimizations
class BLENegentropyOptimizations {
  // BLE has limited bandwidth - optimize protocol
  
  static const BLE_MTU = 512;
  static const USABLE_BYTES = BLE_MTU - 20;  // BLE overhead
  
  // CRITICAL: Compress event IDs for BLE transport
  static Uint8List compressEventIds(List<String> eventIds) {
    // Sort for better compression
    final sorted = eventIds.toList()..sort();
    
    // Pack hex strings efficiently
    final buffer = ByteDataWriter();
    
    for (final id in sorted) {
      // Convert hex to bytes (2:1 compression)
      final bytes = hex.decode(id);
      buffer.write(bytes);
    }
    
    return buffer.toBytes();
  }
  
  static List<String> decompressEventIds(Uint8List compressed) {
    final ids = <String>[];
    
    // Each ID is 32 bytes
    for (var i = 0; i < compressed.length; i += 32) {
      final bytes = compressed.sublist(i, i + 32);
      ids.add(hex.encode(bytes));
    }
    
    return ids;
  }
  
  // CRITICAL: Adaptive message sizing for BLE
  static int getOptimalBatchSize(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 100;  // Can handle larger batches
        
      case ConnectionQuality.good:
        return 50;
        
      case ConnectionQuality.poor:
        return 20;  // Small batches for reliability
    }
  }
}