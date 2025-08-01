# AI Implementation Guide for flutter_embedded_nostr_relay

## Development Workflow

### Phase 1: Core Infrastructure (Week 1)
1. **Create package structure**
   ```bash
   flutter create --template=package flutter_embedded_nostr_relay
   cd flutter_embedded_nostr_relay
   ```

2. **Set up dependencies** in `pubspec.yaml` (see spec section 14)

3. **Create basic models**
   - Start with `NostrEvent` class
   - Implement JSON serialization
   - Add validation methods (skip signature verification initially)

4. **Implement SQLite storage**
   - Create `DatabaseFactory` for platform abstraction
   - Implement schema creation
   - Test basic CRUD operations

### Phase 2: Event Storage (Week 2)
1. **Implement EventStore**
   - Start with `saveEvent` and `getEvent`
   - Add batch operations
   - Implement query system with filters

2. **Add indexes and optimize queries**
   - Create all indexes from spec
   - Test query performance with 10k events

3. **Handle replaceable events**
   - Implement special logic for kinds 10000-39999
   - Test replacement scenarios

### Phase 3: Protocol Implementation (Week 3)
1. **Create message classes**
   - Client messages: EVENT, REQ, CLOSE
   - Relay messages: EVENT, OK, EOSE, NOTICE

2. **Build subscription manager**
   - Track active subscriptions
   - Implement filter matching
   - Handle subscription lifecycle

3. **Add WebSocket server** (skip for initial web version)
   - Use shelf + shelf_web_socket
   - Implement message routing
   - Add connection management

### Phase 4: P2P Sync with Negentropy (Week 4)
1. **Abstract transport layer**
   - Define `NegentropyTransport` interface
   - Implement `MockNegentropyTransport` for testing

2. **Add BLE transport with Negentropy**
   - Use flutter_blue_plus
   - Handle connection/disconnection
   - Implement Negentropy message fragmentation for BLE's 512-byte limit

3. **Implement Negentropy sync protocol**
   - Port from https://github.com/hoytech/negentropy
   - Start with basic range fingerprinting
   - Add recursive subdivision for large datasets
   - Test with simulated network delays

```dart
// Example Negentropy implementation structure
class NegentropyEngine {
  // Core Negentropy algorithm
  Future<void> sync(NegentropyPeer peer) async {
    // 1. Initialize with full range fingerprint
    final fullRange = await _getFullEventRange();
    final fingerprint = await _computeFingerprint(fullRange);
    
    // 2. Exchange initial fingerprints
    await peer.send(NegentropyInit(
      ranges: [RangeFingerprint(
        lower: fullRange.start,
        upper: fullRange.end,
        fingerprint: fingerprint,
      )],
    ));
    
    // 3. Recursively reconcile differences
    await _reconcileLoop(peer);
  }
  
  String _computeFingerprint(List<String> eventIds) {
    // XOR all event IDs for efficient fingerprinting
    var accumulator = BigInt.zero;
    for (final id in eventIds.sorted()) {
      accumulator ^= BigInt.parse(id, radix: 16);
    }
    return accumulator.toRadixString(16).padLeft(32, '0');
  }
}

## Code Organization Patterns

### Repository Pattern for Storage
```dart
// Abstract repository
abstract class EventRepository {
  Future<void> save(NostrEvent event);
  Future<NostrEvent?> findById(String id);
  Stream<NostrEvent> findByFilter(Filter filter);
}

// SQLite implementation
class SQLiteEventRepository implements EventRepository {
  final Database _db;
  
  @override
  Future<void> save(NostrEvent event) async {
    // Implementation
  }
}

// In-memory implementation for testing
class InMemoryEventRepository implements EventRepository {
  final _events = <String, NostrEvent>{};
  
  @override
  Future<void> save(NostrEvent event) async {
    _events[event.id] = event;
  }
}
```

### Service Layer Pattern
```dart
// Separate business logic from storage
class EventService {
  final EventRepository _repository;
  final EventValidator _validator;
  
  Future<void> publishEvent(NostrEvent event) async {
    // Validate
    if (!await _validator.validate(event)) {
      throw ValidationException();
    }
    
    // Check replaceable logic
    if (event.isReplaceable) {
      await _handleReplaceable(event);
    }
    
    // Store
    await _repository.save(event);
    
    // Notify subscribers
    await _notifySubscribers(event);
  }
}
```

### Factory Pattern for Platform Differences
```dart
abstract class RelayFactory {
  static EmbeddedRelay create() {
    if (kIsWeb) {
      return WebEmbeddedRelay();
    } else if (Platform.isAndroid || Platform.isIOS) {
      return MobileEmbeddedRelay();
    } else {
      return DesktopEmbeddedRelay();
    }
  }
}
```

## Testing Strategy

### Unit Test Structure
```dart
// test/models/event_test.dart
void main() {
  group('NostrEvent', () {
    test('should serialize to JSON correctly', () {
      final event = NostrEvent(
        id: '...',
        pubkey: '...',
        createdAt: 1234567890,
        kind: 1,
        tags: [['p', 'abc123']],
        content: 'Hello',
        sig: '...',
      );
      
      final json = event.toJson();
      expect(json['id'], equals(event.id));
      expect(json['tags'], equals([['p', 'abc123']]));
    });
    
    test('should compute correct event ID', () {
      // Test ID calculation
    });
  });
}
```

### Integration Test Pattern
```dart
// test/integration/relay_test.dart
void main() {
  late EmbeddedNostrRelay relay;
  
  setUp(() async {
    relay = EmbeddedNostrRelay(
      config: RelayConfig(
        databasePath: ':memory:',
        enableWebSocketServer: false,
        enableP2PSync: false,
      ),
    );
    await relay.initialize();
  });
  
  tearDown(() async {
    await relay.dispose();
  });
  
  test('should store and retrieve events', () async {
    final event = TestEvents.textNote();
    await relay.publishEvent(event);
    
    final retrieved = await relay.getEvent(event.id);
    expect(retrieved, equals(event));
  });
}
```

### Performance Test Template
```dart
// test/performance/query_performance_test.dart
void main() {
  test('should query 20 events in under 10ms', () async {
    // Setup: Insert 100k events
    final relay = await setupRelayWithEvents(100000);
    
    // Measure query time
    final stopwatch = Stopwatch()..start();
    final events = await relay.subscribe([
      Filter(kinds: [1], limit: 20)
    ]).take(20).toList();
    stopwatch.stop();
    
    expect(stopwatch.elapsedMilliseconds, lessThan(10));
    expect(events.length, equals(20));
  });
}
```

## Common Implementation Pitfalls

### 1. WebSocket Message Ordering
**Problem**: Messages arrive out of order
**Solution**: Queue messages per subscription
```dart
class SubscriptionQueue {
  final _queues = <String, Queue<NostrEvent>>{};
  
  void addEvent(String subId, NostrEvent event) {
    _queues.putIfAbsent(subId, () => Queue()).add(event);
    _processQueue(subId);
  }
}
```

### 2. Memory Leaks in Subscriptions
**Problem**: Subscriptions not cleaned up
**Solution**: Use automatic cleanup
```dart
class AutoCleanupSubscription {
  Timer? _timeoutTimer;
  
  void start() {
    _timeoutTimer = Timer(Duration(minutes: 10), () {
      _cleanup();
    });
  }
  
  void activity() {
    _timeoutTimer?.cancel();
    start(); // Reset timer
  }
}
```

### 3. SQLite Lock Contention
**Problem**: "database is locked" errors
**Solution**: Use connection pool
```dart
class DatabasePool {
  final _available = Queue<Database>();
  final _inUse = Set<Database>();
  
  Future<T> use<T>(Future<T> Function(Database) action) async {
    final db = _acquire();
    try {
      return await action(db);
    } finally {
      _release(db);
    }
  }
}
```

## Debugging Helpers

### Event Flow Tracker
```dart
class EventFlowTracker {
  static void trackEvent(NostrEvent event, String stage) {
    if (kDebugMode) {
      print('[${DateTime.now()}] Event ${event.id.substring(0, 8)} - $stage');
    }
  }
}

// Usage throughout code:
EventFlowTracker.trackEvent(event, 'received');
EventFlowTracker.trackEvent(event, 'validated');
EventFlowTracker.trackEvent(event, 'stored');
EventFlowTracker.trackEvent(event, 'broadcast');
```

### Performance Profiler
```dart
class QueryProfiler {
  static final _metrics = <String, List<int>>{};
  
  static Future<T> profile<T>(String operation, Future<T> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      return await action();
    } finally {
      sw.stop();
      _metrics.putIfAbsent(operation, () => []).add(sw.elapsedMicroseconds);
      
      if (_metrics[operation]!.length % 100 == 0) {
        _printStats(operation);
      }
    }
  }
  
  static void _printStats(String operation) {
    final times = _metrics[operation]!;
    final avg = times.reduce((a, b) => a + b) / times.length;
    print('$operation: avg ${avg}μs over ${times.length} calls');
  }
}
```

## Platform-Specific Implementation Notes

### Web Limitations
1. **No WebSocket Server**: Skip `shelf` implementation
2. **Storage**: Use IndexedDB for persistence
3. **Worker Threads**: Use web workers for crypto operations
```dart
// web/crypto_worker.dart
import 'dart:html' as html;

class WebCryptoWorker {
  late html.Worker _worker;
  
  void init() {
    _worker = html.Worker('crypto_worker.js');
    _worker.onMessage.listen((event) {
      // Handle validation results
    });
  }
}
```

### iOS Specific
1. **Background Modes**: Add to Info.plist
```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
</array>
```

2. **BLE State Restoration**
```dart
class IOSBleManager {
  static const RESTORATION_ID = 'nostr_relay_ble';
  
  void enableStateRestoration() {
    // iOS-specific BLE state restoration
  }
}
```

### Android Specific
1. **Foreground Service**: For P2P sync
```dart
class AndroidSyncService {
  static const CHANNEL_ID = 'nostr_sync';
  
  static void startForegroundSync() {
    // Platform channel to start foreground service
  }
}
```

## Release Checklist

### Before Release
- [ ] All tests passing
- [ ] Performance benchmarks meet requirements
- [ ] Documentation complete
- [ ] Example app working on all platforms
- [ ] CHANGELOG.md updated
- [ ] Version bumped in pubspec.yaml
- [ ] License headers on all source files

### Security Audit
- [ ] Input validation on all public methods
- [ ] SQL injection prevention verified
- [ ] Resource limits enforced
- [ ] Error messages don't leak sensitive info
- [ ] Crypto operations use secure random
- [ ] P2P connections authenticated

### Platform Testing Matrix
- [ ] iOS Simulator
- [ ] iOS Device
- [ ] Android Emulator  
- [ ] Android Device
- [ ] Chrome
- [ ] Safari
- [ ] macOS
- [ ] Windows
- [ ] Linux

## Incremental Implementation Order

1. **Minimal Working Version** (2-3 days)
   - Basic event model
   - Simple SQLite storage
   - Query by ID only
   - No validation

2. **Add Filtering** (2 days)
   - Implement Filter model
   - Add query optimization
   - Test with 1k events

3. **Add Protocol** (3 days)
   - Message parsing
   - Subscription management
   - Basic WebSocket server

4. **Add Validation** (2 days)
   - Event ID verification
   - Signature validation
   - Content limits

5. **Add P2P** (1 week)
   - Transport abstraction
   - BLE implementation
   - Simple sync protocol

6. **Optimize** (3 days)
   - Query performance
   - Memory usage
   - Battery efficiency

7. **Polish** (2 days)
   - Error handling
   - Logging
   - Documentation

This guide provides the practical details needed to systematically build the package, avoiding common pitfalls and ensuring good architecture from the start.