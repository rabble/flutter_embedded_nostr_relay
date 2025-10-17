# External Relay Integration

Flutter Embedded Nostr Relay seamlessly integrates with external Nostr relays, acting as an intelligent proxy that provides instant local responses while managing network connections in the background.

## Overview

The external relay integration provides:
- **Smart caching** - Local responses with background updates
- **NIP-65 support** - Automatic relay list management
- **Connection pooling** - Efficient resource usage
- **Automatic failover** - Resilient relay connections
- **Optional Tor routing** - Privacy-enhanced connections

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Flutter App │ ──► │ Embedded Relay   │ ──► │  External   │
│              │     │                  │     │   Relays    │
└──────────────┘     │ ┌──────────────┐ │     └─────────────┘
                     │ │ Local Cache  │ │            │
                     │ └──────────────┘ │            │
                     │ ┌──────────────┐ │     ┌─────┴─────┐
                     │ │ Relay Client │ ├───► │ Relay 1   │
                     │ │   Manager    │ │     ├───────────┤
                     │ └──────────────┘ │     │ Relay 2   │
                     └──────────────────┘     ├───────────┤
                                             │ Relay 3   │
                                             └───────────┘
```

## Basic Usage

### Adding External Relays

```dart
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Add individual relays
await relay.addExternalRelay('wss://relay.damus.io');
await relay.addExternalRelay('wss://nos.lol');
await relay.addExternalRelay('wss://relay.nostr.band');

// Add multiple relays at once
await relay.addExternalRelays([
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
  'wss://nostr.wine',
  'wss://relay.snort.social',
]);
```

### Managing Relay Connections

```dart
// Check relay status
final status = await relay.getRelayStatus('wss://relay.damus.io');
print('Connected: ${status.isConnected}');
print('Events received: ${status.eventsReceived}');
print('Events sent: ${status.eventsSent}');

// Remove a relay
await relay.removeExternalRelay('wss://relay.damus.io');

// Disconnect all relays
await relay.disconnectAllRelays();

// Reconnect to all configured relays
await relay.reconnectAllRelays();
```

## NIP-65 Relay List Management

NIP-65 defines how clients should publish and discover relay lists. The embedded relay automatically handles this:

### Publishing Your Relay List

```dart
// Set your relay list (NIP-65)
await relay.setRelayList(
  read: [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
  ],
  write: [
    'wss://relay.damus.io',
    'wss://nos.lol',
  ],
);

// This publishes a kind:10002 event with your relay preferences
```

### Discovering User Relay Lists

```dart
// Get relay list for a user
final relayList = await relay.getUserRelayList(userPubkey);
print('Read relays: ${relayList.read}');
print('Write relays: ${relayList.write}');

// Subscribe using someone's relay preferences
await relay.subscribeToUserRelays(
  userPubkey: userPubkey,
  filters: [Filter(kinds: [1], authors: [userPubkey])],
  onEvent: (event) => print('Got event from user relays'),
);
```

## Advanced Relay Configuration

### Relay Policies

Configure how the embedded relay interacts with external relays:

```dart
await relay.setRelayPolicy(
  RelayPolicy(
    // Automatically connect to relay lists from followed users
    autoConnectNIP65: true,
    
    // Maximum number of concurrent relay connections
    maxConnections: 10,
    
    // Timeout for relay connections
    connectionTimeout: Duration(seconds: 30),
    
    // Retry failed connections
    autoReconnect: true,
    reconnectDelay: Duration(seconds: 5),
    maxReconnectAttempts: 3,
    
    // Only use relays that support NIP-42 authentication
    requireAuth: false,
  ),
);
```

### Per-Relay Configuration

Configure individual relay behavior:

```dart
await relay.configureRelay(
  url: 'wss://relay.damus.io',
  config: RelayConfig(
    // Only receive events, don't publish
    readOnly: true,
    
    // Custom timeout for this relay
    timeout: Duration(seconds: 60),
    
    // Relay-specific filters
    filters: [
      Filter(kinds: [1, 6, 7]), // Only text notes, reposts, reactions
    ],
    
    // Authentication (NIP-42)
    auth: RelayAuth(
      type: AuthType.nip42,
      credentials: {
        'pubkey': myPubkey,
        'sig': authSignature,
      },
    ),
  ),
);
```

## Intelligent Relay Selection

The embedded relay intelligently routes requests based on NIP-65 preferences:

### Publishing Events

```dart
// Publish to write relays only
final event = NostrEvent.create(
  pubkey: myPubkey,
  kind: 1,
  content: 'Hello Nostr!',
  tags: [],
).sign(privateKey);

await relay.publish(event); // Automatically sent to write relays
```

### Querying Events

```dart
// Query from read relays
final events = await relay.queryEvents([
  Filter(
    authors: [userPubkey],
    kinds: [1],
    limit: 50,
  ),
]);
// Automatically queries the user's read relays
```

## Connection Management

### Connection Pooling

The relay client maintains a connection pool for efficiency:

```dart
// Configure connection pool
await relay.setConnectionPoolConfig(
  ConnectionPoolConfig(
    maxConnectionsPerRelay: 2,
    maxIdleTime: Duration(minutes: 5),
    keepAliveInterval: Duration(seconds: 30),
  ),
);
```

### Health Monitoring

Monitor relay health and performance:

```dart
// Get relay statistics
final stats = await relay.getRelayStatistics();
for (final relay in stats.relays) {
  print('Relay: ${relay.url}');
  print('  Uptime: ${relay.uptime}');
  print('  Latency: ${relay.averageLatency}ms');
  print('  Success rate: ${relay.successRate}%');
}

// Subscribe to relay health updates
relay.relayHealthStream.listen((health) {
  if (health.status == RelayStatus.unhealthy) {
    print('Relay ${health.url} is unhealthy: ${health.reason}');
  }
});
```

## Tor Integration

Route relay connections through Tor for enhanced privacy:

```dart
// Enable Tor for all relay connections
if (TorSupport.isAvailable) {
  await relay.setTorForRelays(true);
  
  // Configure Tor behavior
  await relay.updateTorConfig(TorConfig(
    enabled: true,
    forceTor: false, // Allow fallback to clearnet
    torOnlyRelays: [
      'wss://relay.onion',
      'wss://private.onion',
    ],
  ));
  
  // Add onion relays
  await relay.addExternalRelay('wss://relay.onion');
}
```

## Sync Strategies

### 1. Lazy Sync (Default)

Only fetch from external relays when local cache misses:

```dart
await relay.setSyncStrategy(SyncStrategy.lazy);
```

### 2. Eager Sync

Proactively sync with external relays:

```dart
await relay.setSyncStrategy(SyncStrategy.eager);

// Configure eager sync behavior
await relay.setEagerSyncConfig(
  EagerSyncConfig(
    syncInterval: Duration(minutes: 5),
    syncOnStartup: true,
    syncInBackground: true,
  ),
);
```

### 3. Selective Sync

Sync only specific types of events:

```dart
await relay.setSyncStrategy(
  SyncStrategy.selective,
  config: SelectiveSyncConfig(
    filters: [
      Filter(kinds: [0, 3]), // Profiles and contact lists
      Filter(
        kinds: [1],
        authors: followedUsers, // Notes from followed users
      ),
    ],
  ),
);
```

## Error Handling

Handle relay errors gracefully:

```dart
// Global error handler
relay.onRelayError = (error) {
  print('Relay error: ${error.relay} - ${error.message}');
  
  if (error.type == RelayErrorType.authRequired) {
    // Handle authentication
    _authenticateToRelay(error.relay);
  }
};

// Per-relay error handling
try {
  await relay.addExternalRelay('wss://relay.example.com');
} on RelayConnectionException catch (e) {
  print('Failed to connect: ${e.message}');
} on RelayAuthException catch (e) {
  print('Authentication failed: ${e.message}');
}
```

## UI Integration

### Relay Management Screen

```dart
class RelayManagementScreen extends StatefulWidget {
  @override
  _RelayManagementScreenState createState() => _RelayManagementScreenState();
}

class _RelayManagementScreenState extends State<RelayManagementScreen> {
  List<RelayInfo> _relays = [];
  
  @override
  void initState() {
    super.initState();
    _loadRelays();
  }
  
  Future<void> _loadRelays() async {
    final relays = await relay.getConfiguredRelays();
    setState(() => _relays = relays);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Relay Management'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _addRelay,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _relays.length,
        itemBuilder: (context, index) {
          final relay = _relays[index];
          return ListTile(
            leading: Icon(
              relay.isConnected ? Icons.check_circle : Icons.error,
              color: relay.isConnected ? Colors.green : Colors.red,
            ),
            title: Text(relay.url),
            subtitle: Text(
              'Events: ${relay.eventsReceived} received, ${relay.eventsSent} sent',
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: Text('Configure'),
                  value: 'configure',
                ),
                PopupMenuItem(
                  child: Text('Remove'),
                  value: 'remove',
                ),
              ],
              onSelected: (value) {
                if (value == 'configure') {
                  _configureRelay(relay);
                } else if (value == 'remove') {
                  _removeRelay(relay);
                }
              },
            ),
          );
        },
      ),
    );
  }
  
  Future<void> _addRelay() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Relay'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'wss://relay.example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('Add'),
          ),
        ],
      ),
    );
    
    if (url != null && url.isNotEmpty) {
      await relay.addExternalRelay(url);
      _loadRelays();
    }
  }
}
```

## Performance Optimization

### 1. Request Deduplication

Prevent duplicate requests to external relays:

```dart
// Enabled by default, but can be configured
await relay.setRequestDeduplication(
  enabled: true,
  window: Duration(seconds: 5),
);
```

### 2. Response Caching

Cache relay responses to reduce network usage:

```dart
await relay.setCachePolicy(
  CachePolicy(
    cacheResponses: true,
    cacheDuration: Duration(minutes: 10),
    maxCacheSize: 100 * 1024 * 1024, // 100MB
  ),
);
```

### 3. Bandwidth Management

Limit bandwidth usage per relay:

```dart
await relay.setBandwidthLimits(
  perRelayLimit: 100 * 1024, // 100KB/s per relay
  totalLimit: 500 * 1024, // 500KB/s total
);
```

## Best Practices

1. **Start with popular relays**: Use well-known relays for better connectivity
2. **Respect relay policies**: Some relays have specific rules or rate limits
3. **Use NIP-65**: Publish and respect relay lists for better routing
4. **Monitor relay health**: Remove or replace unhealthy relays
5. **Configure timeouts**: Set appropriate timeouts for your use case
6. **Handle errors gracefully**: Network issues are common

## Example: Complete Relay Setup

```dart
class NostrApp extends StatefulWidget {
  @override
  _NostrAppState createState() => _NostrAppState();
}

class _NostrAppState extends State<NostrApp> {
  final relay = EmbeddedNostrRelay();
  
  @override
  void initState() {
    super.initState();
    _setupRelay();
  }
  
  Future<void> _setupRelay() async {
    // Initialize embedded relay
    await relay.initialize();
    
    // Configure relay behavior
    await relay.setRelayPolicy(
      RelayPolicy(
        autoConnectNIP65: true,
        maxConnections: 8,
        autoReconnect: true,
      ),
    );
    
    // Add default relays
    await relay.addExternalRelays([
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.nostr.band',
      'wss://nostr.wine',
    ]);
    
    // Publish our relay list
    await relay.setRelayList(
      read: ['wss://relay.damus.io', 'wss://nos.lol'],
      write: ['wss://relay.damus.io'],
    );
    
    // Enable Tor if available
    if (TorSupport.isAvailable) {
      await relay.setTorForRelays(true);
    }
    
    // Start syncing
    await relay.setSyncStrategy(SyncStrategy.eager);
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

- Learn about [P2P Synchronization](p2p-sync.md)
- Explore [Performance Optimization](performance.md)
- Understand [Security Best Practices](security.md)