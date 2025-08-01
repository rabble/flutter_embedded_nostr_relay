# Smart Relay Architecture: Local Relay as Outbox Model Proxy

## Architecture Overview

```
┌─────────────┐
│   OpenVine  │
│     App     │
└──────┬──────┘
       │ nostr_sdk (client mode)
       │ ws://localhost:7447
       ▼
┌─────────────────────────────┐
│   Embedded Local Relay      │
│  ┌─────────────────────┐    │
│  │  SQLite Storage     │    │
│  └─────────────────────┘    │
│  ┌─────────────────────┐    │
│  │  nostr_sdk          │    │
│  │  (relay mode)       │────┼──► External Relays
│  └─────────────────────┘    │    (Outbox Model)
│  ┌─────────────────────┐    │
│  │  Negentropy Sync    │    │
│  │  Engine             │◄───┼──► P2P Devices
│  └─────────────────────┘    │
└─────────────────────────────┘
```

## Key Design Principles

### 1. Single Connection Point
The app only connects to `ws://localhost:7447` and doesn't need to know about:
- Which external relays exist
- Where users publish their content
- Network connectivity status
- P2P sync protocols

### 2. Transparent Outbox Model
The embedded relay automatically:
- Reads user's relay preferences (NIP-65) from their kind:10002 events
- Fetches events from the correct relays per user
- Caches everything locally for instant access
- Handles relay failures gracefully

### 3. Unified Interface
The app uses standard Nostr protocol whether data comes from:
- Local cache
- External relays
- P2P synchronized devices
- Future sources

## Implementation Strategy

### Phase 1: Relay Within Relay Architecture

```dart
class EmbeddedNostrRelay {
  late final NostrSDK _externalClient;  // For fetching from external relays
  late final LocalStore _store;         // SQLite storage
  late final NegentropySyncEngine _p2pSync;
  
  // Relay configuration includes external relay strategy
  final OutboxConfig outboxConfig;
  
  Future<void> init() async {
    // Initialize SDK for external relay connections
    _externalClient = NostrSDK(
      // Different identity to avoid confusion
      privateKey: null,  // Read-only relay client
      relayPoolConfig: RelayPoolConfig(
        maxRelaysPerUser: 3,
        timeout: Duration(seconds: 5),
      ),
    );
    
    // Initialize local storage
    _store = await LocalStore.create(config.databasePath);
    
    // Start local WebSocket server
    await _startLocalServer();
  }
}
```

### Phase 2: Smart Request Routing

```dart
class SmartRequestRouter {
  // When app requests events via REQ
  Future<void> handleReq(String subId, List<Filter> filters) async {
    // 1. First, stream any matching local events
    await for (final event in _store.query(filters)) {
      await _sendToClient(['EVENT', subId, event.toJson()]);
    }
    
    // 2. Send EOSE for local data
    await _sendToClient(['EOSE', subId]);
    
    // 3. Determine what external data we need
    final missingRanges = await _determineMissingData(filters);
    
    // 4. Fetch from external relays using outbox model
    if (missingRanges.isNotEmpty) {
      await _fetchFromExternalRelays(subId, filters, missingRanges);
    }
    
    // 5. Keep subscription active for new events
    _activeSubscriptions[subId] = ActiveSubscription(
      filters: filters,
      includeExternal: true,
    );
  }
  
  Future<void> _fetchFromExternalRelays(
    String subId, 
    List<Filter> filters,
    List<TimeRange> missingRanges,
  ) async {
    // Analyze filters to determine whose events we need
    final authors = filters.expand((f) => f.authors ?? []).toSet();
    
    // Fetch relay preferences for each author (NIP-65)
    final relayPreferences = await _fetchRelayPreferences(authors);
    
    // Group requests by relay for efficiency  
    final requestsByRelay = _groupRequestsByRelay(
      filters, 
      relayPreferences,
      missingRanges,
    );
    
    // Fetch from each relay
    for (final entry in requestsByRelay.entries) {
      final relay = entry.key;
      final request = entry.value;
      
      try {
        await _externalClient.addRelay(relay);
        
        final events = await _externalClient.request(request);
        
        for (final event in events) {
          // Store locally
          await _store.saveEvent(event);
          
          // Forward to app if matches subscription
          if (_matchesFilters(event, filters)) {
            await _sendToClient(['EVENT', subId, event.toJson()]);
          }
        }
      } catch (e) {
        _log.warning('Failed to fetch from $relay: $e');
      }
    }
  }
}
```

### Phase 3: NIP-65 Outbox Model Implementation

```dart
class OutboxModelManager {
  // Cache of user relay preferences
  final _relayLists = <String, RelayList>{};
  
  Future<RelayList> getRelayList(String pubkey) async {
    // Check cache first
    if (_relayLists.containsKey(pubkey)) {
      return _relayLists[pubkey]!;
    }
    
    // Check local storage
    final stored = await _store.getEvent(
      Filter(
        authors: [pubkey],
        kinds: [10002], // NIP-65 relay list
        limit: 1,
      ),
    );
    
    if (stored != null) {
      return _parseRelayList(stored);
    }
    
    // Fetch from known relays
    final event = await _fetchRelayList(pubkey);
    if (event != null) {
      await _store.saveEvent(event);
      return _parseRelayList(event);
    }
    
    // Fallback to default relays
    return RelayList.defaultRelays();
  }
  
  RelayList _parseRelayList(NostrEvent event) {
    final relays = RelayList();
    
    for (final tag in event.tags) {
      if (tag[0] == 'r') {
        final url = tag[1];
        final mode = tag.length > 2 ? tag[2] : 'read';
        
        if (mode == 'read' || mode == null) {
          relays.read.add(url);
        }
        if (mode == 'write' || mode == null) {
          relays.write.add(url);
        }
      }
    }
    
    return relays;
  }
}
```

## Negentropy Protocol Implementation

### Understanding Negentropy
Negentropy is an efficient set reconciliation protocol that allows two parties to synchronize their sets with minimal bandwidth usage.

```dart
class NegentropySyncEngine {
  // Based on: https://github.com/hoytech/negentropy
  
  Future<void> syncWithPeer(Peer peer) async {
    final conn = await _connectToPeer(peer);
    
    // Phase 1: Exchange fingerprints of our data ranges
    final ourRanges = await _computeRangeFingerprints();
    await conn.send(NegentropySyncInit(ranges: ourRanges));
    
    final theirRanges = await conn.receive<NegentropySyncInit>();
    
    // Phase 2: Identify differences efficiently
    final differences = _findRangeDifferences(ourRanges, theirRanges);
    
    // Phase 3: For each different range, drill down
    for (final range in differences) {
      await _reconcileRange(conn, range);
    }
  }
  
  Future<List<RangeFingerprint>> _computeRangeFingerprints() async {
    // Split our events into time-based ranges
    final ranges = <RangeFingerprint>[];
    
    // Example: Daily ranges for the last month
    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      final startTime = _startOfDay(date).millisecondsSinceEpoch ~/ 1000;
      final endTime = _endOfDay(date).millisecondsSinceEpoch ~/ 1000;
      
      // Get all event IDs in this range
      final eventIds = await _store.getEventIdsInTimeRange(startTime, endTime);
      
      if (eventIds.isNotEmpty) {
        // Compute fingerprint using XOR of all IDs
        final fingerprint = _computeXorFingerprint(eventIds);
        
        ranges.add(RangeFingerprint(
          startTime: startTime,
          endTime: endTime,
          fingerprint: fingerprint,
          count: eventIds.length,
        ));
      }
    }
    
    return ranges;
  }
  
  Future<void> _reconcileRange(Connection conn, TimeRange range) async {
    // Get our event IDs in this range
    final ourIds = await _store.getEventIdsInTimeRange(
      range.startTime, 
      range.endTime,
    );
    
    // Use binary search to efficiently find differences
    if (ourIds.length < 100) {
      // Small set - just exchange IDs directly
      await conn.send(EventIdList(ids: ourIds));
      final theirIds = await conn.receive<EventIdList>();
      
      await _exchangeEvents(conn, ourIds.toSet(), theirIds.ids.toSet());
    } else {
      // Large set - recursively subdivide
      final midTime = (range.startTime + range.endTime) ~/ 2;
      
      await _reconcileRange(conn, TimeRange(range.startTime, midTime));
      await _reconcileRange(conn, TimeRange(midTime, range.endTime));
    }
  }
}
```

## Smart Caching Strategy

```dart
class SmartCache {
  // Intelligent decisions about what to cache
  
  Future<void> handleExternalEvent(NostrEvent event) async {
    // Always cache events from followed users
    if (await _isFollowedUser(event.pubkey)) {
      await _store.saveEvent(event);
      return;
    }
    
    // Cache recent events (last 7 days)
    final sevenDaysAgo = DateTime.now().subtract(Duration(days: 7));
    if (event.createdAt > sevenDaysAgo.millisecondsSinceEpoch ~/ 1000) {
      await _store.saveEvent(event);
      return;
    }
    
    // For older events, only cache if directly requested
    if (_wasDirectlyRequested(event)) {
      await _store.saveEvent(event);
    }
  }
  
  // Garbage collection strategy
  Future<void> performGarbageCollection() async {
    // Keep all events from followed users
    final following = await _getFollowingList();
    
    // Delete old events from non-followed users
    await _store.deleteWhere('''
      created_at < ? AND 
      pubkey NOT IN (${following.map((_) => '?').join(',')}) AND
      kind NOT IN (0, 3, 10002)  -- Keep profiles and relay lists
    ''', [
      _thirtyDaysAgo(),
      ...following,
    ]);
  }
}
```

## Configuration for OpenVine

```dart
class OpenVineRelayConfig extends RelayConfig {
  OpenVineRelayConfig() : super(
    // Local relay settings
    databasePath: 'openvine_relay.db',
    localPort: 7447,
    
    // Outbox model settings
    outboxConfig: OutboxConfig(
      // Fetch relay lists from these bootstrap relays
      bootstrapRelays: [
        'wss://relay.damus.io',
        'wss://relay.snort.social',
        'wss://nos.lol',
      ],
      
      // Maximum relays to query per user
      maxRelaysPerUser: 3,
      
      // Cache relay lists for 24 hours
      relayListCacheDuration: Duration(hours: 24),
    ),
    
    // P2P sync settings
    negentropySyncConfig: NegentropySyncConfig(
      // Sync when discovering peers
      autoSync: true,
      
      // Only sync recent content by default
      defaultSyncWindow: Duration(days: 7),
      
      // For followed users, sync more history
      followedUserSyncWindow: Duration(days: 30),
    ),
    
    // Smart caching
    cacheConfig: CacheConfig(
      maxEvents: 100000,
      
      // Keep events from followed users longer
      followedUserRetention: Duration(days: 90),
      generalRetention: Duration(days: 30),
      
      // Run GC daily at 3 AM
      garbageCollectionSchedule: '0 3 * * *',
    ),
  );
}
```

## Benefits of This Architecture

1. **Simplified App Logic**: The app just connects to one relay and uses standard Nostr protocol

2. **Intelligent Caching**: The relay decides what to cache based on follow relationships and usage patterns

3. **Transparent Relay Selection**: Implements the outbox model without the app knowing

4. **Offline First**: Always returns cached data immediately, then fetches updates

5. **P2P Syncing**: Negentropy protocol ensures efficient sync with nearby devices

6. **Bandwidth Efficiency**: Only fetches what's missing, uses fingerprints to detect differences

This architecture makes the embedded relay a smart proxy that handles all the complexity of the decentralized Nostr network while presenting a simple, fast interface to the app.