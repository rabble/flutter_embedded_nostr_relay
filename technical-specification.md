# flutter_embedded_nostr_relay Technical Specification

## 1. Project Overview

### Purpose
Create a self-contained Dart/Flutter package that provides an embedded Nostr relay running within Flutter applications, enabling local-first functionality with P2P synchronization using the Negentropy protocol.

### Core Requirements
- Must run entirely within a Flutter app (no external processes)
- Support all platforms: iOS, Android, macOS, Windows, Linux, Web
- Store events locally using SQLite
- Implement Nostr relay protocol for local clients
- Support P2P synchronization using Negentropy protocol for efficient bandwidth usage
- Handle 100,000+ events efficiently
- Maintain <10ms query response time for common operations

### Key Architecture Decisions
- **Database**: SQLite for cross-platform compatibility and performance
- **P2P Sync**: Negentropy protocol for bandwidth-efficient set reconciliation
- **Transport**: BLE and WiFi Direct for device-to-device communication
- **Relay Protocol**: Full NIP-01 compliance with extensions for replaceable events

### Package Structure
```
flutter_embedded_nostr_relay/
├── lib/
│   ├── flutter_embedded_nostr_relay.dart  # Public API exports
│   └── src/                               # Implementation (private)
├── example/                               # Example app
├── test/                                  # Unit and integration tests
├── doc/                                   # Additional documentation
└── platform/                              # Platform-specific code
```

## 2. Database Schema

### Events Table
```sql
CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,           -- Event ID (32-byte hex)
    pubkey TEXT NOT NULL,          -- Author's public key
    created_at INTEGER NOT NULL,   -- Unix timestamp
    kind INTEGER NOT NULL,         -- Event kind
    content TEXT NOT NULL,         -- Event content (JSON for some kinds)
    sig TEXT NOT NULL,             -- Schnorr signature
    deleted_at INTEGER,            -- Soft delete timestamp
    relay_url TEXT,                -- Origin relay (for sync)
    first_seen INTEGER NOT NULL    -- When we first saw this event
);

-- Indexes for common queries
CREATE INDEX idx_pubkey_created ON events(pubkey, created_at DESC);
CREATE INDEX idx_kind_created ON events(kind, created_at DESC);
CREATE INDEX idx_created_at ON events(created_at DESC);
CREATE INDEX idx_deleted ON events(deleted_at) WHERE deleted_at IS NOT NULL;
```

### Tags Table (Normalized)
```sql
CREATE TABLE IF NOT EXISTS tags (
    event_id TEXT NOT NULL,
    tag_name TEXT NOT NULL,        -- First element (e.g., 'p', 'e', 't')
    tag_value TEXT NOT NULL,       -- Second element (pubkey, event id, etc)
    tag_extra TEXT,                -- Additional elements as JSON array
    tag_order INTEGER NOT NULL,    -- Preserve tag ordering
    FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE
);

CREATE INDEX idx_tag_name_value ON tags(tag_name, tag_value);
CREATE INDEX idx_tag_event ON tags(event_id);
```

### Replaceable Events Table
```sql
CREATE TABLE IF NOT EXISTS replaceable_events (
    kind INTEGER NOT NULL,
    pubkey TEXT NOT NULL,
    d_tag TEXT NOT NULL DEFAULT '', -- Empty string for non-parameterized
    event_id TEXT NOT NULL,
    PRIMARY KEY(kind, pubkey, d_tag),
    FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE
);
```

### Sync Metadata Table
```sql
CREATE TABLE IF NOT EXISTS sync_metadata (
    peer_id TEXT PRIMARY KEY,
    last_sync INTEGER NOT NULL,
    events_sent INTEGER DEFAULT 0,
    events_received INTEGER DEFAULT 0,
    sync_filter TEXT              -- JSON filter for what to sync
);
```

## 3. Core Components

### 3.1 Event Model
```dart
class NostrEvent {
  final String id;          // 32-bytes lowercase hex
  final String pubkey;      // 32-bytes lowercase hex  
  final int createdAt;      // Unix timestamp seconds
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;         // 64-bytes hex

  // Computed properties
  String get dTag => _extractDTag();
  bool get isReplaceable => kind >= 10000 && kind < 20000;
  bool get isEphemeral => kind >= 20000 && kind < 30000;
  bool get isParameterizedReplaceable => kind >= 30000 && kind < 40000;
  
  // Serialization
  Map<String, dynamic> toJson();
  factory NostrEvent.fromJson(Map<String, dynamic> json);
  
  // Validation
  bool validateSignature() => EventValidator.verify(this);
  String computeId() => EventValidator.computeId(this);
}
```

### 3.2 Filter Model (for queries)
```dart
class Filter {
  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final int? since;
  final int? until;
  final int? limit;
  final Map<String, List<String>>? tags; // e.g., {'e': [...], 'p': [...]}
  
  // Convert to SQL WHERE clause
  String toSqlWhere();
  Map<String, dynamic> toSqlParams();
}
```

### 3.3 Storage Layer Interface
```dart
abstract class EventStore {
  Future<void> saveEvent(NostrEvent event);
  Future<void> saveEvents(List<NostrEvent> events);
  Future<NostrEvent?> getEvent(String id);
  Stream<NostrEvent> query(List<Filter> filters);
  Future<int> count(Filter filter);
  Future<void> deleteEvent(String id); // Soft delete
  Future<void> vacuum(); // Cleanup old events
}
```

### 3.4 WebSocket Protocol Messages

#### Client to Relay
```dart
// EVENT - publish an event
class EventMessage {
  final String type = 'EVENT';
  final NostrEvent event;
}

// REQ - request events and subscribe
class ReqMessage {
  final String type = 'REQ';
  final String subscriptionId;
  final List<Filter> filters;
}

// CLOSE - close a subscription
class CloseMessage {
  final String type = 'CLOSE';
  final String subscriptionId;
}
```

#### Relay to Client
```dart
// EVENT - send event to client
class RelayEventMessage {
  final String type = 'EVENT';
  final String subscriptionId;
  final NostrEvent event;
}

// OK - acknowledge event
class OkMessage {
  final String type = 'OK';
  final String eventId;
  final bool accepted;
  final String? message;
}

// EOSE - end of stored events
class EoseMessage {
  final String type = 'EOSE';
  final String subscriptionId;
}

// NOTICE - relay message
class NoticeMessage {
  final String type = 'NOTICE';
  final String message;
}
```

## 4. Platform-Specific Implementations

### 4.1 Database Initialization
```dart
// Mobile/Desktop (using sqlite3)
class NativeDatabaseFactory {
  static Future<Database> create(String path) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqlite3.ensureInitialized();
    }
    return sqlite3.open(path);
  }
}

// Web (using sql.js WASM)
class WebDatabaseFactory {
  static Future<Database> create(String name) async {
    final sqlite = await SqlJsFlutterFactory().createDatabase();
    // Store in IndexedDB for persistence
    await _persistToIndexedDB(name, sqlite);
    return sqlite;
  }
}
```

### 4.2 WebSocket Server
```dart
// Mobile/Desktop only
class EmbeddedWebSocketServer {
  Future<void> start(int port) async {
    final server = await HttpServer.bind('localhost', port);
    server.transform(WebSocketTransformer()).listen((webSocket) {
      final client = ClientConnection(webSocket);
      _handleClient(client);
    });
  }
}

// Web fallback - no server, only local API
class WebRelayInterface {
  // Provides same API but no WebSocket server
  // Other parts of app call methods directly
}
```

### 4.3 P2P Sync Transports with Negentropy

#### Bluetooth Low Energy (BLE) with Negentropy
```dart
class BLENegentropyTransport {
  static const SERVICE_UUID = "12345678-1234-1234-1234-123456789012";
  static const NEGENTROPY_CHAR_UUID = "87654321-4321-4321-4321-210987654321";
  static const MAX_BLE_PACKET = 512; // BLE MTU limit
  
  Future<void> performNegentropySync(BLEPeer peer) async {
    // Establish BLE connection
    final device = await FlutterBluePlus.connect(peer.device);
    final service = await device.discoverServices()
        .firstWhere((s) => s.uuid == SERVICE_UUID);
    final characteristic = service.characteristics
        .firstWhere((c) => c.uuid == NEGENTROPY_CHAR_UUID);
    
    // Create Negentropy session over BLE
    final session = NegentropySession(
      storage: _storage,
      peer: BLENegentropyPeer(characteristic),
      isInitiator: true,
    );
    
    await session.performSync();
  }
}

class BLENegentropyPeer implements NegentropyPeer {
  final BluetoothCharacteristic characteristic;
  final _receiveBuffer = ByteBuffer();
  
  @override
  Future<void> send(NegentropyMessage message) async {
    final bytes = message.toBytes();
    
    // Fragment large messages for BLE
    final header = ByteDataWriter()
      ..writeUint32(bytes.length)
      ..writeUint16(0xNEG0); // Magic number
    
    await characteristic.write(header.toBytes());
    
    // Send in chunks
    for (var i = 0; i < bytes.length; i += MAX_BLE_PACKET) {
      final chunk = bytes.sublist(i, min(i + MAX_BLE_PACKET, bytes.length));
      await characteristic.write(chunk);
      
      // Small delay to prevent overwhelming BLE stack
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
  
  @override
  Future<NegentropyMessage> receive() async {
    // Read header first
    await characteristic.setNotifyValue(true);
    
    final completer = Completer<NegentropyMessage>();
    int? expectedLength;
    
    characteristic.value.listen((data) {
      _receiveBuffer.add(data);
      
      // Check if we have the header
      if (expectedLength == null && _receiveBuffer.length >= 6) {
        final reader = ByteDataReader(_receiveBuffer.toBytes());
        expectedLength = reader.readUint32();
        final magic = reader.readUint16();
        
        if (magic != 0xNEG0) {
          completer.completeError('Invalid Negentropy message');
          return;
        }
        
        _receiveBuffer.clear();
      }
      
      // Check if we have the full message
      if (expectedLength != null && _receiveBuffer.length >= expectedLength!) {
        final messageBytes = _receiveBuffer.toBytes().sublist(0, expectedLength!);
        final message = NegentropyMessage.fromBytes(messageBytes);
        completer.complete(message);
      }
    });
    
    return completer.future;
  }
}
```

#### WiFi Direct with Negentropy
```dart
class WiFiDirectNegentropyTransport {
  static const NEGENTROPY_PORT = 7448;
  
  Future<void> performNegentropySync(WiFiDirectPeer peer) async {
    // Android only - use flutter_p2p_connection
    if (!Platform.isAndroid) {
      throw UnsupportedError('WiFi Direct only supported on Android');
    }
    
    // Establish TCP connection over WiFi Direct
    final socket = await Socket.connect(peer.address, NEGENTROPY_PORT);
    
    // Create Negentropy session over TCP
    final session = NegentropySession(
      storage: _storage,
      peer: TCPNegentropyPeer(socket),
      isInitiator: peer.isGroupOwner,
    );
    
    await session.performSync();
  }
}

class TCPNegentropyPeer implements NegentropyPeer {
  final Socket socket;
  final _messageQueue = Queue<NegentropyMessage>();
  
  TCPNegentropyPeer(this.socket) {
    _listenForMessages();
  }
  
  @override
  Future<void> send(NegentropyMessage message) async {
    final bytes = message.toBytes();
    
    // Length-prefixed protocol
    final lengthBytes = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    
    socket.add(lengthBytes.buffer.asUint8List());
    socket.add(bytes);
    await socket.flush();
  }
  
  @override
  Future<NegentropyMessage> receive() async {
    while (_messageQueue.isEmpty) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    return _messageQueue.removeFirst();
  }
  
  void _listenForMessages() {
    final buffer = ByteBuffer();
    int? expectedLength;
    
    socket.listen((data) {
      buffer.add(data);
      
      while (true) {
        // Read length header
        if (expectedLength == null && buffer.length >= 4) {
          final lengthBytes = buffer.toBytes().sublist(0, 4);
          expectedLength = ByteData.view(Uint8List.fromList(lengthBytes).buffer)
              .getUint32(0, Endian.big);
          buffer.removeFirst(4);
        }
        
        // Read message body
        if (expectedLength != null && buffer.length >= expectedLength!) {
          final messageBytes = buffer.toBytes().sublist(0, expectedLength!);
          final message = NegentropyMessage.fromBytes(messageBytes);
          _messageQueue.add(message);
          
          buffer.removeFirst(expectedLength!);
          expectedLength = null;
        } else {
          break; // Wait for more data
        }
      }
    });
  }
}
```

## 5. Negentropy Sync Protocol

### 5.1 Negentropy Protocol Overview
Negentropy is an efficient set reconciliation protocol that minimizes bandwidth usage when synchronizing large datasets. It's perfect for P2P Nostr relay synchronization.

**Key Concepts:**
- **Range-based fingerprints**: Divide the dataset into ranges and compute fingerprints
- **Recursive subdivision**: Efficiently identify differences by subdividing ranges
- **Minimal bandwidth**: Only exchange the actual differences, not entire datasets

### 5.2 Negentropy Implementation for Nostr
```dart
class NegentropySyncEngine {
  // Based on: https://github.com/hoytech/negentropy
  static const int FINGERPRINT_SIZE = 16; // 128-bit fingerprints
  static const int MAX_ITEMS_PER_MESSAGE = 500;
  
  Future<void> syncWithPeer(Peer peer) async {
    final session = NegentropySession(
      storage: _storage,
      peer: peer,
      isInitiator: true,
    );
    
    try {
      await session.performSync();
    } finally {
      await session.close();
    }
  }
}

class NegentropySession {
  final NegentropyStorage storage;
  final Peer peer;
  final bool isInitiator;
  
  // Message types
  static const MSG_INIT = 0x00;
  static const MSG_FINGERPRINT = 0x01;
  static const MSG_ITEMS = 0x02;
  static const MSG_ITEMS_NEEDED = 0x03;
  static const MSG_DONE = 0x04;
  
  Future<void> performSync() async {
    if (isInitiator) {
      await _initiateSync();
    } else {
      await _respondToSync();
    }
  }
  
  Future<void> _initiateSync() async {
    // Step 1: Send initial message with our full range fingerprint
    final fullRange = await storage.getFullRange();
    final fingerprint = await storage.computeFingerprint(fullRange);
    
    await peer.send(NegentropyMessage(
      type: MSG_INIT,
      ranges: [RangeFingerprint(
        lower: fullRange.lower,
        upper: fullRange.upper,
        fingerprint: fingerprint,
        itemCount: await storage.count(fullRange),
      )],
    ));
    
    // Step 2: Process response and reconcile
    await _reconcileRanges();
  }
  
  Future<void> _reconcileRanges() async {
    final queue = Queue<Range>();
    
    while (true) {
      final msg = await peer.receive<NegentropyMessage>();
      
      switch (msg.type) {
        case MSG_FINGERPRINT:
          // Compare fingerprints and subdivide if different
          for (final remoteRange in msg.ranges) {
            final localFingerprint = await storage.computeFingerprint(
              Range(remoteRange.lower, remoteRange.upper)
            );
            
            if (localFingerprint != remoteRange.fingerprint) {
              // Fingerprints differ - need to subdivide
              if (remoteRange.itemCount <= MAX_ITEMS_PER_MESSAGE) {
                // Small enough - request items directly
                await _requestItems(remoteRange);
              } else {
                // Too large - subdivide the range
                await _subdivideRange(remoteRange);
              }
            }
          }
          break;
          
        case MSG_ITEMS:
          // Received items - determine what we need
          final theirItems = msg.items;
          final ourItems = await storage.getItems(
            Range(msg.rangeLower, msg.rangeUpper)
          );
          
          final weNeed = theirItems.difference(ourItems);
          final theyNeed = ourItems.difference(theirItems);
          
          if (weNeed.isNotEmpty) {
            await peer.send(NegentropyMessage(
              type: MSG_ITEMS_NEEDED,
              items: weNeed.toList(),
            ));
          }
          
          if (theyNeed.isNotEmpty) {
            await _sendEvents(theyNeed);
          }
          break;
          
        case MSG_ITEMS_NEEDED:
          // They need these items
          await _sendEvents(msg.items.toSet());
          break;
          
        case MSG_DONE:
          // Sync complete
          return;
      }
    }
  }
}

class NegentropyStorage {
  final EventStore eventStore;
  
  // Compute fingerprint for a range of events
  Future<String> computeFingerprint(Range range) async {
    // Get all event IDs in range (sorted)
    final eventIds = await eventStore.getEventIdsInRange(
      range.lower,
      range.upper,
      sorted: true,
    );
    
    if (eventIds.isEmpty) {
      return '0' * 32; // Zero fingerprint
    }
    
    // XOR all event IDs together
    var accumulator = BigInt.zero;
    for (final id in eventIds) {
      final idBigInt = BigInt.parse(id, radix: 16);
      accumulator ^= idBigInt;
    }
    
    // Take lower 128 bits as fingerprint
    final fingerprintHex = (accumulator & ((BigInt.one << 128) - BigInt.one))
        .toRadixString(16)
        .padLeft(32, '0');
    
    return fingerprintHex;
  }
  
  // Smart range subdivision for Nostr events
  List<Range> subdivideRange(Range range) {
    final duration = range.upper - range.lower;
    
    if (duration <= 3600) {
      // Less than 1 hour - split into 10-minute chunks
      return _splitByTime(range, 600);
    } else if (duration <= 86400) {
      // Less than 1 day - split into hourly chunks
      return _splitByTime(range, 3600);
    } else if (duration <= 604800) {
      // Less than 1 week - split into daily chunks
      return _splitByTime(range, 86400);
    } else {
      // More than 1 week - split into weekly chunks
      return _splitByTime(range, 604800);
    }
  }
}
```

### 5.3 Negentropy Message Format
```dart
class NegentropyMessage {
  final int type;
  final List<RangeFingerprint>? ranges;
  final List<String>? items;
  final int? rangeLower;
  final int? rangeUpper;
  
  // Serialize to bytes for transport
  Uint8List toBytes() {
    final buffer = ByteDataWriter();
    buffer.writeUint8(type);
    
    switch (type) {
      case MSG_INIT:
      case MSG_FINGERPRINT:
        buffer.writeUint16(ranges!.length);
        for (final range in ranges!) {
          buffer.writeUint32(range.lower);
          buffer.writeUint32(range.upper);
          buffer.write(hex.decode(range.fingerprint));
          buffer.writeUint32(range.itemCount);
        }
        break;
        
      case MSG_ITEMS:
        buffer.writeUint32(rangeLower!);
        buffer.writeUint32(rangeUpper!);
        buffer.writeUint16(items!.length);
        for (final item in items!) {
          buffer.write(hex.decode(item));
        }
        break;
        
      case MSG_ITEMS_NEEDED:
        buffer.writeUint16(items!.length);
        for (final item in items!) {
          buffer.write(hex.decode(item));
        }
        break;
    }
    
    return buffer.toBytes();
  }
  
  factory NegentropyMessage.fromBytes(Uint8List bytes) {
    final reader = ByteDataReader(bytes);
    final type = reader.readUint8();
    
    // Parse based on type...
    return NegentropyMessage(type: type);
  }
}

class RangeFingerprint {
  final int lower;  // Unix timestamp (inclusive)
  final int upper;  // Unix timestamp (exclusive)  
  final String fingerprint; // 128-bit hex string
  final int itemCount;
}
```

### 5.4 Conflict Resolution for Replaceable Events
```dart
class ConflictResolver {
  NostrEvent? resolveWithNegentropy(NostrEvent local, NostrEvent remote) {
    // For regular events - no conflict, keep both
    if (!local.isReplaceable) return null;
    
    // For replaceable events - latest wins
    if (local.kind >= 10000 && local.kind < 40000) {
      return local.createdAt > remote.createdAt ? local : remote;
    }
    
    // For parameterized replaceable - check d tag
    if (local.dTag == remote.dTag) {
      return local.createdAt > remote.createdAt ? local : remote;
    }
    
    // Different d tags - keep both
    return null;
  }
  
  // Batch conflict resolution after Negentropy sync
  Future<void> resolveAfterSync(List<NostrEvent> newEvents) async {
    final replaceable = newEvents.where((e) => e.isReplaceable);
    
    for (final event in replaceable) {
      final existing = await _store.getExistingReplaceable(
        kind: event.kind,
        pubkey: event.pubkey,
        dTag: event.dTag,
      );
      
      if (existing != null) {
        final winner = resolveWithNegentropy(existing, event);
        if (winner?.id != existing.id) {
          await _store.replaceEvent(existing, winner!);
        }
      } else {
        await _store.saveEvent(event);
      }
    }
  }
}
```

## 6. Performance Optimizations

### 6.1 Query Optimization
```dart
class QueryOptimizer {
  // Convert Nostr filters to optimal SQL
  String buildQuery(List<Filter> filters) {
    // Merge filters with same kind/author combinations
    final merged = _mergeFilters(filters);
    
    // Use UNION for OR conditions instead of complex WHERE
    if (merged.length > 1) {
      return merged.map(_buildSingleQuery).join(' UNION ');
    }
    
    return _buildSingleQuery(merged.first);
  }
  
  String _buildSingleQuery(Filter filter) {
    final conditions = <String>[];
    
    // Use covering indexes
    if (filter.kinds != null && filter.authors != null) {
      // idx_kind_author_created will be used
      conditions.add('kind IN (${filter.kinds.join(',')})');
      conditions.add('pubkey IN (${filter.authors.map((a) => "'$a'").join(',')})');
    }
    
    // Time range with index
    if (filter.since != null) {
      conditions.add('created_at >= ${filter.since}');
    }
    
    return '''
      SELECT * FROM events 
      WHERE ${conditions.join(' AND ')}
      ORDER BY created_at DESC
      LIMIT ${filter.limit ?? 100}
    ''';
  }
}
```

### 6.2 Batch Operations
```dart
class BatchProcessor {
  static const BATCH_SIZE = 1000;
  
  Future<void> saveEventsBatch(List<NostrEvent> events) async {
    // Process in batches to avoid memory issues
    for (var i = 0; i < events.length; i += BATCH_SIZE) {
      final batch = events.skip(i).take(BATCH_SIZE).toList();
      
      await db.transaction((txn) async {
        // Bulk insert with prepared statement
        final stmt = txn.prepare('''
          INSERT OR REPLACE INTO events 
          (id, pubkey, created_at, kind, content, sig, first_seen)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ''');
        
        for (final event in batch) {
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
  }
}
```

### 6.3 Memory Management
```dart
class MemoryManager {
  final _eventCache = LRUMap<String, NostrEvent>(1000);
  final _queryCache = LRUMap<String, List<String>>(100);
  
  // Isolate for heavy operations
  static Future<void> validateEventsInIsolate(List<NostrEvent> events) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_validateEvents, receivePort.sendPort);
    
    final sendPort = await receivePort.first as SendPort;
    final responsePort = ReceivePort();
    sendPort.send([events, responsePort.sendPort]);
    
    final results = await responsePort.first as List<bool>;
    return results;
  }
}
```

## 7. API Surface

### 7.1 Main Class
```dart
class EmbeddedNostrRelay {
  // Lifecycle
  Future<void> initialize();
  Future<void> dispose();
  
  // Event operations
  Future<void> publishEvent(NostrEvent event);
  Future<NostrEvent?> getEvent(String id);
  Stream<NostrEvent> subscribe(List<Filter> filters);
  Future<void> unsubscribe(String subscriptionId);
  
  // Relay information
  RelayInfo get info;
  RelayStats get stats;
  
  // P2P sync
  Future<void> enableP2PSync();
  Future<void> disableP2PSync();
  Stream<SyncProgress> get syncProgress;
  
  // Maintenance
  Future<void> vacuum(Duration olderThan);
  Future<void> exportEvents(String path);
  Future<void> importEvents(String path);
}
```

### 7.2 Configuration
```dart
class RelayConfig {
  // Storage
  final String databasePath;
  final int maxEvents;
  final Duration eventRetention;
  
  // Server (mobile/desktop only)
  final bool enableWebSocketServer;
  final int webSocketPort;
  final int maxClients;
  final int maxSubscriptionsPerClient;
  
  // P2P Sync with Negentropy
  final bool enableP2PSync;
  final List<TransportType> enabledTransports;
  final NegentropyConfig negentropyConfig;
  
  // Performance
  final int queryTimeout;
  final int maxFilterComplexity;
  final bool enableQueryCache;
  
  // NIPs
  final List<int> supportedNips;
  final Map<int, NipHandler> customNipHandlers;
}

class NegentropyConfig {
  // Sync window - how far back to sync
  final Duration defaultSyncWindow;
  final Duration maxSyncWindow;
  
  // Performance tuning
  final int maxItemsPerMessage;
  final int minItemsForFingerprint;
  final int maxRecursionDepth;
  
  // Transport-specific settings
  final int bleMtu;
  final Duration blePacketDelay;
  final int tcpBufferSize;
  
  // Sync strategy
  final SyncStrategy syncStrategy;
  final bool autoSyncOnDiscovery;
  final Duration syncInterval;
  
  const NegentropyConfig({
    this.defaultSyncWindow = const Duration(days: 7),
    this.maxSyncWindow = const Duration(days: 30),
    this.maxItemsPerMessage = 500,
    this.minItemsForFingerprint = 10,
    this.maxRecursionDepth = 10,
    this.bleMtu = 512,
    this.blePacketDelay = const Duration(milliseconds: 20),
    this.tcpBufferSize = 65536,
    this.syncStrategy = SyncStrategy.adaptive,
    this.autoSyncOnDiscovery = true,
    this.syncInterval = const Duration(minutes: 30),
  });
}
```

## 8. Testing Requirements

### 8.1 Unit Tests
- Event validation and signature verification
- Database operations (CRUD)
- Query optimization
- Filter to SQL conversion
- Conflict resolution
- Message parsing/serialization

### 8.2 Integration Tests
- Multi-platform database initialization
- WebSocket server communication
- P2P discovery and sync
- Large dataset handling (100k+ events)
- Concurrent client connections
- Memory usage under load

### 8.3 Performance Benchmarks
- Insert 10,000 events < 1 second
- Query latest 20 events < 10ms
- Full-text search < 50ms
- P2P sync 1000 events < 5 seconds
- Memory usage < 100MB for 100k events

## 9. Error Handling

### 9.1 Event Validation Errors
```dart
class EventValidationException implements Exception {
  final String reason;
  final NostrEvent? event;
  
  // Specific validation failures
  static const INVALID_ID = 'Event ID does not match computed ID';
  static const INVALID_SIGNATURE = 'Signature verification failed';
  static const INVALID_TIMESTAMP = 'Timestamp too far in future';
  static const INVALID_CONTENT = 'Content exceeds size limit';
}
```

### 9.2 Storage Errors
```dart
class StorageException implements Exception {
  final String operation;
  final String? details;
  
  // Handle disk full, corruption, etc.
  static const DISK_FULL = 'Insufficient storage space';
  static const DATABASE_CORRUPT = 'Database integrity check failed';
  static const TRANSACTION_FAILED = 'Transaction rolled back';
}
```

## 10. Security Considerations

### 10.1 Input Validation
- Validate all event fields before storage
- Sanitize content to prevent injection
- Verify signatures using secp256k1
- Rate limit client connections
- Limit subscription complexity

### 10.2 P2P Security
- Verify peer identity before sync
- Use encrypted transport when available
- Validate all received events
- Implement sync rate limiting
- Detect and ban malicious peers

## 11. Example Implementation

### Complete Video Feed Example
```dart
// See artifact: openvine-relay-usage
// This shows real-world usage for a video social app
```

## 12. Migration and Upgrades

### 12.1 Schema Migrations
```dart
class MigrationManager {
  static const CURRENT_VERSION = 3;
  
  static final migrations = [
    Migration(
      version: 1,
      up: '''
        CREATE TABLE events (...);
        CREATE TABLE tags (...);
      ''',
    ),
    Migration(
      version: 2,
      up: '''
        CREATE TABLE replaceable_events (...);
        CREATE INDEX idx_replaceable ON events(...);
      ''',
    ),
    Migration(
      version: 3,
      up: '''
        CREATE TABLE sync_metadata (...);
        ALTER TABLE events ADD COLUMN relay_url TEXT;
      ''',
    ),
  ];
}
```

## 13. Platform Feature Matrix

| Feature | iOS | Android | Web | macOS | Windows | Linux |
|---------|-----|---------|-----|--------|---------|--------|
| SQLite Storage | ✓ | ✓ | ✓* | ✓ | ✓ | ✓ |
| WebSocket Server | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ |
| BLE Sync | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| WiFi Direct | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Background Sync | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ |

\* Web uses sql.js WASM with IndexedDB persistence

## 14. Dependencies and Versions

```yaml
dependencies:
  flutter: ">=3.10.0"
  sqlite3: ^2.1.0          # Native SQLite
  sqlite_async: ^0.8.1     # Async wrapper
  sql_js_flutter: ^2.0.0   # Web SQLite
  web_socket_channel: ^2.4.0
  cryptography: ^2.5.0     # For secp256k1
  flutter_blue_plus: ^1.32.0
  flutter_p2p_connection: ^2.0.0
```

## 15. Build Instructions

### Development Setup
1. Clone repository
2. Run `flutter pub get`
3. Run `dart run build_runner build`
4. Run tests: `flutter test`

### Platform-specific Setup
- iOS: Add Bluetooth permissions to Info.plist
- Android: Add WiFi/Bluetooth permissions to manifest
- Web: Ensure CORS headers for WebSocket connections

This specification provides everything needed to build a production-ready embedded Nostr relay for Flutter.