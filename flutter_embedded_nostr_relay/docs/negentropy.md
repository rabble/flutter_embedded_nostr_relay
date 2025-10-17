# Negentropy Protocol Implementation

Flutter Embedded Nostr Relay uses the Negentropy protocol for efficient set reconciliation during P2P synchronization. This guide explains how Negentropy works and how it's implemented.

## What is Negentropy?

Negentropy is a protocol for efficient set reconciliation created by Doug Hoyte. It allows two parties to synchronize their sets of data with minimal bandwidth usage by:

1. Exchanging compact fingerprints of their data sets
2. Identifying differences through recursive partitioning
3. Transferring only the missing elements

## How It Works

### Basic Flow

```
Alice (Has: A, B, C, E)          Bob (Has: A, B, D, E)
         │                              │
         ├──── Exchange Fingerprints ───┤
         │     Range: [A-E]            │
         │     Alice: hash(A,B,C,E)    │
         │     Bob: hash(A,B,D,E)      │
         │                              │
         ├──── Fingerprints Differ ─────┤
         │     Split range in half     │
         │                              │
         ├──── Exchange [A-C] ──────────┤
         │     Alice: hash(A,B,C)      │
         │     Bob: hash(A,B)          │
         │                              │
         ├──── Difference Found ────────┤
         │     Bob missing: C          │
         │                              │
         ├──── Exchange [D-E] ──────────┤
         │     Alice: hash(E)          │
         │     Bob: hash(D,E)          │
         │                              │
         ├──── Difference Found ────────┤
         │     Alice missing: D        │
         │                              │
         ├──── Transfer Missing Items ──┤
         │     Alice sends: C          │
         │     Bob sends: D            │
         └──────────────────────────────┘
```

## Implementation Details

### 1. Fingerprint Generation

```dart
class NegentropyFingerprint {
  // Generate fingerprint for a range of events
  static Uint8List generateFingerprint(
    List<NostrEvent> events,
    int start,
    int end,
  ) {
    final hasher = SHA256();
    
    // Sort events by ID for consistent ordering
    final sortedEvents = events.sublist(start, end)
      ..sort((a, b) => a.id.compareTo(b.id));
    
    // Hash each event ID
    for (final event in sortedEvents) {
      hasher.update(hex.decode(event.id));
    }
    
    return hasher.digest();
  }
  
  // Generate hierarchical fingerprints
  static Map<String, Uint8List> generateHierarchicalFingerprints(
    List<NostrEvent> events,
  ) {
    final fingerprints = <String, Uint8List>{};
    
    // Full range fingerprint
    fingerprints['0-${events.length}'] = 
      generateFingerprint(events, 0, events.length);
    
    // Recursive subdivision
    _subdivide(events, 0, events.length, fingerprints);
    
    return fingerprints;
  }
  
  static void _subdivide(
    List<NostrEvent> events,
    int start,
    int end,
    Map<String, Uint8List> fingerprints,
  ) {
    if (end - start <= 1) return;
    
    final mid = (start + end) ~/ 2;
    
    // Left half
    fingerprints['$start-$mid'] = 
      generateFingerprint(events, start, mid);
    _subdivide(events, start, mid, fingerprints);
    
    // Right half
    fingerprints['$mid-$end'] = 
      generateFingerprint(events, mid, end);
    _subdivide(events, mid, end, fingerprints);
  }
}
```

### 2. Negentropy Message Format

```dart
class NegentropyMessage {
  final int version;
  final String messageId;
  final NegentropyMessageType type;
  final Map<String, dynamic> payload;
  
  // Message types
  static const initiate = NegentropyMessageType.initiate;
  static const fingerprint = NegentropyMessageType.fingerprint;
  static const request = NegentropyMessageType.request;
  static const response = NegentropyMessageType.response;
  static const complete = NegentropyMessageType.complete;
  
  // Serialize to bytes
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    
    // Version (1 byte)
    buffer.addByte(version);
    
    // Message ID (16 bytes)
    buffer.add(hex.decode(messageId));
    
    // Type (1 byte)
    buffer.addByte(type.index);
    
    // Payload length (4 bytes)
    final payloadBytes = utf8.encode(jsonEncode(payload));
    buffer.add(_int32ToBytes(payloadBytes.length));
    
    // Payload
    buffer.add(payloadBytes);
    
    return buffer.toBytes();
  }
  
  // Deserialize from bytes
  static NegentropyMessage fromBytes(Uint8List bytes) {
    final reader = ByteReader(bytes);
    
    final version = reader.readByte();
    final messageId = hex.encode(reader.readBytes(16));
    final type = NegentropyMessageType.values[reader.readByte()];
    final payloadLength = reader.readInt32();
    final payload = jsonDecode(
      utf8.decode(reader.readBytes(payloadLength))
    );
    
    return NegentropyMessage(
      version: version,
      messageId: messageId,
      type: type,
      payload: payload,
    );
  }
}
```

### 3. Sync Protocol Implementation

```dart
class NegentropySyncProtocol {
  final EmbeddedNostrRelay relay;
  final Transport transport;
  
  // Initiate sync with peer
  Future<void> syncWithPeer(Peer peer) async {
    // Get our events
    final ourEvents = await relay.queryEvents([
      Filter(limit: 10000), // Adjust based on needs
    ]);
    
    // Generate fingerprints
    final fingerprints = NegentropyFingerprint
      .generateHierarchicalFingerprints(ourEvents);
    
    // Send initiate message
    await transport.send(peer, NegentropyMessage(
      version: 1,
      messageId: _generateMessageId(),
      type: NegentropyMessage.initiate,
      payload: {
        'eventCount': ourEvents.length,
        'rootFingerprint': hex.encode(fingerprints['0-${ourEvents.length}']),
        'filters': _serializeFilters(syncFilters),
      },
    ));
    
    // Handle peer response
    await _handleSyncSession(peer, ourEvents, fingerprints);
  }
  
  // Handle sync session
  Future<void> _handleSyncSession(
    Peer peer,
    List<NostrEvent> ourEvents,
    Map<String, Uint8List> ourFingerprints,
  ) async {
    final missingFromUs = <String>[];
    final missingFromPeer = <String>[];
    
    await for (final message in transport.receiveFrom(peer)) {
      switch (message.type) {
        case NegentropyMessageType.fingerprint:
          await _handleFingerprint(
            peer,
            message,
            ourEvents,
            ourFingerprints,
            missingFromUs,
            missingFromPeer,
          );
          break;
          
        case NegentropyMessageType.request:
          await _handleRequest(peer, message);
          break;
          
        case NegentropyMessageType.response:
          await _handleResponse(message, missingFromUs);
          break;
          
        case NegentropyMessageType.complete:
          await _finishSync(missingFromUs, missingFromPeer);
          return;
      }
    }
  }
  
  // Compare fingerprints and identify differences
  Future<void> _handleFingerprint(
    Peer peer,
    NegentropyMessage message,
    List<NostrEvent> ourEvents,
    Map<String, Uint8List> ourFingerprints,
    List<String> missingFromUs,
    List<String> missingFromPeer,
  ) async {
    final range = message.payload['range'] as String;
    final peerFingerprint = hex.decode(message.payload['fingerprint']);
    final ourFingerprint = ourFingerprints[range]!;
    
    // If fingerprints match, this range is synchronized
    if (_fingerprintsEqual(ourFingerprint, peerFingerprint)) {
      return;
    }
    
    // Parse range
    final parts = range.split('-');
    final start = int.parse(parts[0]);
    final end = int.parse(parts[1]);
    
    // If range is small enough, exchange event IDs
    if (end - start <= 10) {
      final ourIds = ourEvents
        .sublist(start, end)
        .map((e) => e.id)
        .toSet();
      
      final peerIds = (message.payload['eventIds'] as List)
        .cast<String>()
        .toSet();
      
      // Find differences
      missingFromUs.addAll(peerIds.difference(ourIds));
      missingFromPeer.addAll(ourIds.difference(peerIds));
    } else {
      // Subdivide range
      final mid = (start + end) ~/ 2;
      
      // Request fingerprints for subdivisions
      await transport.send(peer, NegentropyMessage(
        version: 1,
        messageId: _generateMessageId(),
        type: NegentropyMessage.fingerprint,
        payload: {
          'range': '$start-$mid',
          'fingerprint': hex.encode(ourFingerprints['$start-$mid']),
        },
      ));
      
      await transport.send(peer, NegentropyMessage(
        version: 1,
        messageId: _generateMessageId(),
        type: NegentropyMessage.fingerprint,
        payload: {
          'range': '$mid-$end',
          'fingerprint': hex.encode(ourFingerprints['$mid-$end']),
        },
      ));
    }
  }
}
```

### 4. Bandwidth Optimization

```dart
class NegentropyOptimizer {
  // Adaptive frame sizing
  static int calculateOptimalFrameSize(
    int eventCount,
    int bandwidth,
    double latency,
  ) {
    // Base frame size
    int frameSize = 4096;
    
    // Adjust for event count
    if (eventCount > 10000) {
      frameSize = 8192;
    } else if (eventCount < 1000) {
      frameSize = 2048;
    }
    
    // Adjust for bandwidth
    if (bandwidth < 100000) { // < 100KB/s
      frameSize = frameSize ~/ 2;
    } else if (bandwidth > 1000000) { // > 1MB/s
      frameSize = frameSize * 2;
    }
    
    // Adjust for latency
    if (latency > 100) { // > 100ms
      frameSize = frameSize * 2; // Larger frames
    }
    
    return frameSize.clamp(1024, 16384);
  }
  
  // Compression for fingerprints
  static Uint8List compressFingerprints(
    Map<String, Uint8List> fingerprints,
  ) {
    // Use delta encoding for similar fingerprints
    final compressed = BytesBuilder();
    
    Uint8List? previous;
    for (final entry in fingerprints.entries) {
      if (previous == null) {
        // First fingerprint - store full
        compressed.add(entry.value);
      } else {
        // Store delta from previous
        final delta = _calculateDelta(previous, entry.value);
        compressed.addByte(delta.length);
        compressed.add(delta);
      }
      previous = entry.value;
    }
    
    // Compress with zlib
    return ZLibEncoder().convert(compressed.toBytes());
  }
}
```

## Configuration Options

### 1. Basic Configuration

```dart
await relay.setNegentropyConfig(
  NegentropyConfig(
    // Fingerprint parameters
    fingerprintSize: 16, // bytes (128-bit)
    hashAlgorithm: HashAlgorithm.sha256,
    
    // Protocol parameters
    maxFrameSize: 8192, // bytes
    subdivisionThreshold: 10, // events
    
    // Optimization
    enableCompression: true,
    adaptiveFraming: true,
    
    // Timeouts
    syncTimeout: Duration(minutes: 5),
    messageTimeout: Duration(seconds: 30),
  ),
);
```

### 2. Advanced Configuration

```dart
await relay.setAdvancedNegentropyConfig(
  AdvancedNegentropyConfig(
    // Hierarchical fingerprinting
    hierarchyLevels: 5,
    branchingFactor: 4,
    
    // Bloom filters for large sets
    useBloomFilters: true,
    bloomFilterSize: 10000,
    bloomFilterHashes: 7,
    
    // Parallel sync
    enableParallelSync: true,
    maxParallelSessions: 3,
    
    // Recovery
    enableCheckpoints: true,
    checkpointInterval: 1000, // events
  ),
);
```

## Performance Characteristics

### Bandwidth Usage

| Event Count | Bandwidth Used | Sync Time |
|-------------|----------------|-----------|
| 100         | ~2 KB          | <1s       |
| 1,000       | ~10 KB         | ~2s       |
| 10,000      | ~50 KB         | ~5s       |
| 100,000     | ~200 KB        | ~30s      |

### Comparison with Other Methods

| Method | 10K Events | 100K Events | 1M Events |
|--------|------------|-------------|-----------|
| Full Transfer | 10 MB | 100 MB | 1 GB |
| Timestamp-based | 5 MB | 50 MB | 500 MB |
| Negentropy | 50 KB | 200 KB | 2 MB |

## Debugging Negentropy

### 1. Enable Debug Logging

```dart
Logger('Negentropy').level = Level.ALL;
Logger('Negentropy').onRecord.listen((record) {
  print('[Negentropy] ${record.message}');
  
  if (record.object != null) {
    print('  Data: ${record.object}');
  }
});
```

### 2. Sync Visualization

```dart
class NegentropySyncVisualizer extends StatefulWidget {
  final Stream<NegentropySyncEvent> syncEvents;
  
  @override
  _NegentropySyncVisualizerState createState() => 
    _NegentropySyncVisualizerState();
}

class _NegentropySyncVisualizerState 
    extends State<NegentropySyncVisualizer> {
  final List<SyncNode> _nodes = [];
  
  @override
  void initState() {
    super.initState();
    widget.syncEvents.listen((event) {
      setState(() {
        _nodes.add(SyncNode.fromEvent(event));
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NegentropySyncPainter(nodes: _nodes),
      size: Size.infinite,
    );
  }
}
```

### 3. Performance Monitoring

```dart
// Monitor Negentropy performance
relay.onNegentropySyncMetrics = (metrics) {
  print('Sync efficiency: ${metrics.efficiency}%');
  print('Bandwidth saved: ${metrics.bandwidthSaved} bytes');
  print('Round trips: ${metrics.roundTrips}');
  print('Events synced: ${metrics.eventsSynced}');
};
```

## Troubleshooting

### Common Issues

1. **Slow sync performance**
   - Increase frame size for better throughput
   - Enable compression for large sets
   - Use bloom filters for very large sets

2. **High bandwidth usage**
   - Reduce fingerprint size (trade-off: more collisions)
   - Increase subdivision threshold
   - Enable adaptive framing

3. **Sync failures**
   - Check timeout settings
   - Verify both peers use compatible versions
   - Check for network interruptions

### Optimization Tips

1. **Pre-sort events** - Sort by ID before sync for better performance
2. **Use filters** - Only sync relevant events
3. **Batch small syncs** - Combine multiple small syncs
4. **Monitor metrics** - Track efficiency and adjust parameters

## Example: Custom Negentropy Implementation

```dart
class CustomNegentropySyncer {
  final EmbeddedNostrRelay relay;
  
  // Custom sync with filtering
  Future<SyncResult> customSync(
    Peer peer,
    List<Filter> filters,
  ) async {
    // Get filtered events
    final events = await relay.queryEvents(filters);
    
    // Generate optimized fingerprints
    final optimizer = NegentropyOptimizer();
    final frameSize = optimizer.calculateOptimalFrameSize(
      events.length,
      peer.bandwidth,
      peer.latency,
    );
    
    // Configure for this sync
    final config = NegentropyConfig(
      maxFrameSize: frameSize,
      enableCompression: peer.bandwidth < 100000,
      adaptiveFraming: true,
    );
    
    // Perform sync
    final protocol = NegentropySyncProtocol(relay, transport);
    final result = await protocol.syncWithPeer(
      peer,
      config: config,
      events: events,
    );
    
    return result;
  }
}
```

## Next Steps

- Learn about [P2P Synchronization](p2p-sync.md)
- Explore [Performance Optimization](performance.md)
- Review [External Relay Integration](external-relays.md)