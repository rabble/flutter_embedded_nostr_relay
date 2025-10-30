# Performance Optimization Guide

Flutter Embedded Nostr Relay is designed for high performance, with sub-10ms query times and efficient resource usage. This guide covers optimization techniques and best practices.

## Performance Metrics

Typical performance on modern devices:

| Operation | Time | Notes |
|-----------|------|-------|
| Event query (1000 events) | <10ms | From local cache |
| Event insertion | <1ms | Single event |
| Batch insertion (1000 events) | <100ms | With indexing |
| Subscription matching | <0.1ms | Per event |
| P2P sync (1000 events) | <5s | Over BLE |

## Database Optimization

### 1. Index Strategy

The relay uses optimized indexes for common query patterns:

```sql
-- Primary indexes (created automatically)
CREATE INDEX idx_events_created_at ON events(created_at DESC);
CREATE INDEX idx_events_kind_created ON events(kind, created_at DESC);
CREATE INDEX idx_events_author_created ON events(author, created_at DESC);
CREATE INDEX idx_events_kind_author_created ON events(kind, author, created_at DESC);

-- Tag indexes
CREATE INDEX idx_tags_event_id ON tags(event_id);
CREATE INDEX idx_tags_name_value ON tags(name, value);
```

### 2. Query Optimization

Use filters efficiently:

```dart
// ❌ Inefficient: Broad query then filter in memory
final allEvents = await relay.queryEvents([
  Filter(limit: 10000),
]);
final filtered = allEvents.where((e) => e.kind == 1).toList();

// ✅ Efficient: Let the database filter
final events = await relay.queryEvents([
  Filter(kinds: [1], limit: 100),
]);
```

### 3. Batch Operations

Use batch operations for bulk imports:

```dart
// ❌ Inefficient: Individual inserts
for (final event in events) {
  await relay.publish(event);
}

// ✅ Efficient: Batch insert
await relay.publishBatch(events);
```

### 4. Database Maintenance

Enable automatic maintenance:

```dart
await relay.initialize(
  config: RelayConfig(
    // Automatic garbage collection
    enableGarbageCollection: true,
    garbageCollectionInterval: Duration(hours: 24),
    
    // Database optimization
    enableVacuum: true,
    vacuumInterval: Duration(days: 7),
    
    // Index optimization
    enableAnalyze: true,
    analyzeInterval: Duration(days: 1),
  ),
);
```

## Memory Management

### 1. Subscription Limits

Limit active subscriptions and results:

```dart
// Set global limits
await relay.setResourceLimits(
  ResourceLimits(
    maxSubscriptionsPerClient: 10,
    maxFiltersPerSubscription: 10,
    maxLimitPerFilter: 1000,
    maxEventsPerResponse: 100,
  ),
);

// Use appropriate limits in filters
final subscription = relay.subscribe(
  filters: [
    Filter(
      kinds: [1],
      limit: 50, // Don't request more than needed
    ),
  ],
  onEvent: handleEvent,
);
```

### 2. Stream Processing

Process events as streams instead of lists:

```dart
// ❌ Inefficient: Load all events into memory
final events = await relay.queryEvents(filters);
for (final event in events) {
  processEvent(event);
}

// ✅ Efficient: Stream processing
final stream = relay.queryEventsAsStream(filters);
await for (final event in stream) {
  processEvent(event);
}
```

### 3. Event Pooling

Reuse event objects to reduce GC pressure:

```dart
// Enable event pooling
await relay.setEventPooling(
  enabled: true,
  poolSize: 1000,
);
```

## Network Optimization

### 1. Connection Pooling

Efficiently manage WebSocket connections:

```dart
await relay.setConnectionPoolConfig(
  ConnectionPoolConfig(
    maxConnections: 5,
    maxConnectionsPerRelay: 2,
    connectionTimeout: Duration(seconds: 30),
    idleTimeout: Duration(minutes: 5),
    keepAliveInterval: Duration(seconds: 30),
  ),
);
```

### 2. Request Batching

Batch multiple requests together:

```dart
// ❌ Inefficient: Multiple round trips
final profile = await relay.queryEvents([Filter(kinds: [0], authors: [pubkey])]);
final notes = await relay.queryEvents([Filter(kinds: [1], authors: [pubkey])]);
final reactions = await relay.queryEvents([Filter(kinds: [7], pTags: [pubkey])]);

// ✅ Efficient: Single batched query
final results = await relay.batchQuery([
  Filter(kinds: [0], authors: [pubkey]),
  Filter(kinds: [1], authors: [pubkey], limit: 50),
  Filter(kinds: [7], pTags: [pubkey], limit: 100),
]);
```

### 3. Compression

Enable compression for network traffic:

```dart
await relay.setNetworkConfig(
  NetworkConfig(
    enableCompression: true,
    compressionLevel: 6, // 1-9, higher = better compression
    minCompressionSize: 1024, // Only compress >1KB
  ),
);
```

## P2P Sync Optimization

### 1. Negentropy Efficiency

Configure Negentropy for optimal performance:

```dart
await relay.setNegentropyConfig(
  NegentropyConfig(
    // Fingerprint size affects sync efficiency
    fingerprintSize: 16, // bytes
    
    // Frame size for sync messages
    frameSize: 4096, // bytes
    
    // Maximum events per sync round
    maxEventsPerRound: 100,
  ),
);
```

### 2. Selective Sync

Only sync what's needed:

```dart
await relay.enableP2PSync(
  syncConfig: SyncConfig(
    // Time-based filtering
    syncWindow: Duration(days: 30),
    
    // Kind-based filtering
    syncKinds: [0, 1, 3, 6, 7], // Only common kinds
    
    // Size limits
    maxEventSize: 64 * 1024, // Skip large events
    
    // Bandwidth limits
    bandwidthLimit: 100 * 1024, // 100KB/s
  ),
);
```

### 3. Sync Scheduling

Optimize sync timing:

```dart
await relay.setSyncSchedule(
  SyncSchedule(
    // Initial sync on connection
    syncOnConnect: true,
    
    // Periodic sync
    syncInterval: Duration(minutes: 15),
    
    // Battery-aware sync
    syncOnlyWhenCharging: true,
    
    // Network-aware sync
    syncOnlyOnWifi: true,
  ),
);
```

## Query Performance

### 1. Filter Optimization

Write efficient filters:

```dart
// ❌ Inefficient: Multiple overlapping filters
final subscription = relay.subscribe(
  filters: [
    Filter(kinds: [1], authors: [alice]),
    Filter(kinds: [1], authors: [bob]),
    Filter(kinds: [1], authors: [charlie]),
  ],
  onEvent: handleEvent,
);

// ✅ Efficient: Combined filter
final subscription = relay.subscribe(
  filters: [
    Filter(kinds: [1], authors: [alice, bob, charlie]),
  ],
  onEvent: handleEvent,
);
```

### 2. Time-Based Queries

Use time ranges effectively:

```dart
// ❌ Inefficient: No time bounds
final events = await relay.queryEvents([
  Filter(kinds: [1], authors: followedUsers),
]);

// ✅ Efficient: Time-bounded query
final events = await relay.queryEvents([
  Filter(
    kinds: [1],
    authors: followedUsers,
    since: DateTime.now().subtract(Duration(days: 7))
        .millisecondsSinceEpoch ~/ 1000,
  ),
]);
```

### 3. Pagination

Use cursor-based pagination for large result sets:

```dart
// Implement pagination
String? cursor;
const pageSize = 50;

do {
  final page = await relay.queryEventsPaginated(
    filters: [Filter(kinds: [1])],
    limit: pageSize,
    cursor: cursor,
  );
  
  for (final event in page.events) {
    processEvent(event);
  }
  
  cursor = page.nextCursor;
} while (cursor != null);
```

## Garbage Collection

### 1. Automatic Cleanup

Configure automatic garbage collection:

```dart
await relay.setGarbageCollectionPolicy(
  GarbageCollectionPolicy(
    // Keep events for 90 days
    retentionPeriod: Duration(days: 90),
    
    // Keep events from followed users longer
    followedUsersRetention: Duration(days: 365),
    
    // Maximum database size
    maxDatabaseSize: 1024 * 1024 * 1024, // 1GB
    
    // Run garbage collection daily
    runInterval: Duration(days: 1),
    
    // Run during low activity
    runOnlyWhenIdle: true,
  ),
);
```

### 2. Manual Cleanup

Trigger manual cleanup when needed:

```dart
// Run garbage collection
final deleted = await relay.runGarbageCollection();
print('Deleted $deleted events');

// Vacuum database to reclaim space
await relay.vacuumDatabase();

// Analyze and optimize indexes
await relay.analyzeDatabase();
```

## Platform-Specific Optimizations

### iOS/macOS

```dart
if (Platform.isIOS || Platform.isMacOS) {
  await relay.setPlatformOptimizations(
    IOSOptimizations(
      // Use native SQLite
      useNativeSQLite: true,
      
      // Enable file protection
      enableFileProtection: true,
      
      // Background processing
      enableBackgroundProcessing: true,
    ),
  );
}
```

### Android

```dart
if (Platform.isAndroid) {
  await relay.setPlatformOptimizations(
    AndroidOptimizations(
      // Use native SQLite
      useNativeSQLite: true,
      
      // Enable write-ahead logging
      enableWAL: true,
      
      // Memory mapping for large databases
      enableMemoryMapping: true,
    ),
  );
}
```

### Web

```dart
if (kIsWeb) {
  await relay.setPlatformOptimizations(
    WebOptimizations(
      // Use IndexedDB for persistence
      useIndexedDB: true,
      
      // Cache size for sql.js
      memoryCacheSize: 50 * 1024 * 1024, // 50MB
      
      // Enable web workers
      useWebWorkers: true,
    ),
  );
}
```

## Monitoring and Profiling

### 1. Performance Metrics

Enable performance monitoring:

```dart
// Enable metrics collection
await relay.enableMetrics(
  MetricsConfig(
    collectQueryMetrics: true,
    collectNetworkMetrics: true,
    collectStorageMetrics: true,
    metricsInterval: Duration(minutes: 1),
  ),
);

// Get current metrics
final metrics = await relay.getMetrics();
print('Average query time: ${metrics.averageQueryTime}ms');
print('Cache hit rate: ${metrics.cacheHitRate}%');
print('Active subscriptions: ${metrics.activeSubscriptions}');
```

### 2. Query Analysis

Analyze slow queries:

```dart
// Enable query logging
relay.onSlowQuery = (query, duration) {
  if (duration > Duration(milliseconds: 100)) {
    print('Slow query (${duration.inMilliseconds}ms): $query');
  }
};

// Get query statistics
final stats = await relay.getQueryStatistics();
for (final stat in stats.slowestQueries) {
  print('Query: ${stat.filter}');
  print('Average time: ${stat.averageTime}ms');
  print('Execution count: ${stat.count}');
}
```

## Best Practices Checklist

### Database
- [ ] Use appropriate filter limits
- [ ] Enable garbage collection
- [ ] Run periodic maintenance
- [ ] Use batch operations for bulk data

### Memory
- [ ] Limit active subscriptions
- [ ] Use stream processing for large datasets
- [ ] Close unused subscriptions
- [ ] Monitor memory usage

### Network
- [ ] Enable compression
- [ ] Use connection pooling
- [ ] Implement request batching
- [ ] Set appropriate timeouts

### P2P Sync
- [ ] Configure selective sync
- [ ] Set bandwidth limits
- [ ] Use battery-aware scheduling
- [ ] Monitor sync performance

### General
- [ ] Profile your specific use case
- [ ] Monitor performance metrics
- [ ] Test on target devices
- [ ] Optimize for your data patterns

## Example: Optimized Configuration

```dart
class OptimizedNostrApp extends StatefulWidget {
  @override
  _OptimizedNostrAppState createState() => _OptimizedNostrAppState();
}

class _OptimizedNostrAppState extends State<OptimizedNostrApp> {
  final relay = EmbeddedNostrRelay();
  
  @override
  void initState() {
    super.initState();
    _initializeOptimizedRelay();
  }
  
  Future<void> _initializeOptimizedRelay() async {
    await relay.initialize(
      config: RelayConfig(
        // Database optimization
        enableGarbageCollection: true,
        garbageCollectionInterval: Duration(hours: 24),
        enableVacuum: true,
        vacuumInterval: Duration(days: 7),
        
        // Memory optimization
        maxSubscriptionsPerClient: 10,
        maxEventsPerResponse: 100,
        enableEventPooling: true,
        
        // Network optimization
        enableCompression: true,
        compressionLevel: 6,
        connectionPoolSize: 5,
        
        // Query optimization
        defaultQueryLimit: 50,
        maxQueryLimit: 500,
      ),
    );
    
    // Platform-specific optimizations
    if (Platform.isIOS || Platform.isAndroid) {
      await relay.setPlatformOptimizations(
        MobileOptimizations(
          enableBackgroundSync: true,
          syncOnlyOnWifi: true,
          syncOnlyWhenCharging: false,
          reducedMemoryMode: false,
        ),
      );
    }
    
    // Monitor performance
    relay.enableMetrics(MetricsConfig(
      collectQueryMetrics: true,
      collectNetworkMetrics: true,
    ));
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: NostrHomeScreen(relay: relay),
    );
  }
}
```

## Next Steps

- Review [Security Best Practices](security.md)
- Learn about [Troubleshooting](troubleshooting.md)
- Explore the [Example App](../example/)