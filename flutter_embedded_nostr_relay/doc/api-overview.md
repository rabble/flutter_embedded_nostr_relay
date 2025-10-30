# Flutter Embedded Nostr Relay - API Overview

## Introduction

The Flutter Embedded Nostr Relay is a complete Nostr relay implementation designed to be embedded directly into Flutter applications. It provides local event storage, subscription management, WebSocket server capabilities, and peer-to-peer synchronization features.

## Core Architecture

The library is built around several key components:

- **EmbeddedNostrRelay**: Main coordination class
- **EventStore**: High-performance event storage
- **SubscriptionManager**: Client subscription handling  
- **WebSocketServer**: Local relay server
- **Transport Layer**: P2P synchronization (BLE, WiFi Direct)

## Key Classes

### EmbeddedNostrRelay

The main entry point for the embedded relay functionality. Coordinates all other components and provides the primary API for Flutter applications.

**Key Features:**
- Event publishing and querying
- Direct subscription API (no WebSocket required)
- P2P sync coordination
- Garbage collection management
- Statistics and monitoring
- Optional Tor support for external relays

**Basic Usage:**
```dart
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Direct subscription
final subscription = relay.subscribe(
  filters: [Filter(kinds: [1], limit: 50)],
  onEvent: (event) => print('New event: ${event.content}'),
);

// Publish events
final event = NostrEvent.create(
  pubkey: userPubkey,
  kind: 1,
  content: 'Hello, Nostr!',
  tags: [],
).sign(privateKey);

await relay.publish(event);

// Optional: Enable Tor
if (TorSupport.isAvailable) {
  await relay.setTorForRelays(true);
  await relay.setTorForVideos(true);
}
```

### NostrEvent

Represents a Nostr event according to NIP-01. Handles creation, validation, signing, and provides utility methods for working with event data.

**Key Features:**
- Event creation and signing
- Signature validation
- Replaceable event detection
- Tag parsing and utilities
- JSON serialization

**Example:**
```dart
// Create and sign an event
final event = NostrEvent.create(
  pubkey: myPubkey,
  kind: 1,
  content: 'Hello world!',
  tags: [
    ['t', 'hello'],          // Topic tag
    ['p', friendPubkey],     // Mention friend
  ],
).sign(myPrivateKey);

// Verify event
if (event.isValid) {
  print('Event is valid and ready to publish');
}

// Check event properties
print('Mentions: ${event.mentionedPubkeys}');
print('Is replaceable: ${event.isReplaceable}');
```

### Filter

Defines criteria for querying and subscribing to events. Supports all standard Nostr filter types with optimized query performance.

**Key Features:**
- All standard NIP-01 filter fields
- Tag filtering with dedicated helpers
- Event matching logic
- JSON serialization for protocol compliance

**Example:**
```dart
// Complex filter example
final filter = Filter(
  kinds: [1, 6],                    // Text notes and reposts
  authors: [alice, bob],            // From specific users
  pTags: [myPubkey],               // Mentioning me
  since: yesterdayTimestamp,        // From last 24 hours
  limit: 100,                       // Max 100 events
);

// Use in subscription
final subscription = relay.subscribe(
  filters: [filter],
  onEvent: handleEvent,
);
```

### Subscription

Manages active event subscriptions with support for both callback and stream-based event delivery.

**Key Features:**
- Filter-based event matching
- Multiple delivery mechanisms (callbacks + streams)
- Lifecycle management
- EOSE (End of Stored Events) signaling

**Example:**
```dart
final subscription = relay.subscribe(
  filters: [Filter(kinds: [1])],
  onEvent: (event) => print('Callback: ${event.content}'),
  onEose: () => print('All stored events received'),
);

// Alternative: stream-based approach
subscription.eventStream.listen(
  (event) => updateUI(event),
  onError: (error) => handleError(error),
);

// Clean up
await subscription.close();
```

### WebSocketServer

Provides a local WebSocket endpoint that external Nostr clients can connect to, making your Flutter app act as a full Nostr relay.

**Key Features:**
- Full Nostr protocol compliance (REQ, CLOSE, EVENT messages)
- Client connection management
- Message broadcasting
- Statistics and monitoring
- Configurable host/port

**Example:**
```dart
final server = WebSocketServer(
  subscriptionManager: relay._subscriptionManager,
  eventStore: relay._eventStore,
);

// Start server
await server.start(host: 'localhost', port: 7447);
print('Relay server running on ws://localhost:${server.port}');

// Monitor connections
print('Active connections: ${server.activeConnections}');

// Stop when done
await server.stop();
```

### TorSupport

Provides optional Tor integration for enhanced privacy when connecting to external relays. Requires building with Tor libraries.

**Key Features:**
- Runtime detection of Tor library availability
- Automatic .onion relay detection
- Configurable routing policies
- Graceful fallback to clearnet

**Example:**
```dart
// Check Tor availability
if (TorSupport.isAvailable) {
  print('Tor support is available');
  
  // Enable Tor for relay connections
  await relay.setTorForRelays(true);
  
  // Enable Tor for video loading
  await relay.setTorForVideos(true);
  
  // Configure advanced Tor settings
  final torConfig = TorConfig(
    enabled: true,
    forceTor: false,
    required: false,
    timeout: Duration(minutes: 2),
    torOnlyRelays: ['wss://relay.onion'],
  );
  
  await relay.updateTorConfig(torConfig);
}
```

### EventStore

High-performance SQLite-based storage system optimized for Nostr events with support for all event types and efficient querying.

**Key Features:**
- Optimized database schema with proper indexing
- Replaceable event handling
- Batch operations for sync scenarios
- Tag indexing for fast queries
- Garbage collection

**Example:**
```dart
final store = EventStore();

// Store single event
final success = await store.storeEvent(signedEvent);

// Batch storage (efficient for sync)
final events = await fetchFromRemoteRelay();
final stored = await store.storeEvents(events);
print('Stored $stored/${events.length} events');

// Query with filters
final recentEvents = await store.queryEvents([
  Filter(kinds: [1], limit: 50),
]);

// Garbage collection
final deleted = await store.garbageCollect(
  retentionDays: 90,
  preserveAuthors: followedUsers,
);
```

## Common Usage Patterns

### 1. Simple Event Publishing

```dart
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Create and publish a text note
final note = NostrEvent.create(
  pubkey: userPubkey,
  kind: 1,
  content: 'My first note!',
  tags: [],
).sign(privateKey);

final success = await relay.publish(note);
print('Published: $success');
```

### 2. Timeline Subscription

```dart
// Subscribe to timeline events
final subscription = relay.subscribe(
  filters: [
    Filter(kinds: [1], authors: followedUsers, limit: 100),  // Notes from followed users
    Filter(kinds: [1], pTags: [userPubkey], limit: 50),     // Mentions of me
  ],
  onEvent: (event) {
    // Update UI with new event
    timelineController.addEvent(event);
  },
  onEose: () {
    // All stored events loaded
    setState(() => loading = false);
  },
);
```

### 3. Local Relay Server

```dart
// Set up embedded relay
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Start WebSocket server
final server = WebSocketServer(
  subscriptionManager: relay._subscriptionManager,
  eventStore: relay._eventStore,
);
await server.start();

// Now external clients can connect to ws://localhost:7447
print('Local relay running on port ${server.port}');
```

### 4. P2P Synchronization

```dart
// Enable peer-to-peer sync
await relay.enableP2PSync(
  transports: [TransportType.ble, TransportType.wifiDirect],
  onPeerDiscovered: (peer) {
    print('Found peer: ${peer.name} via ${peer.transport}');
  },
  onPeerLost: (peer) {
    print('Lost peer: ${peer.name}');
  },
);
```

### 5. Advanced Querying

```dart
// Complex multi-filter query
final events = await relay.queryEvents([
  // Recent notes from friends
  Filter(
    kinds: [1],
    authors: friendPubkeys,
    since: DateTime.now().subtract(Duration(hours: 24))
        .millisecondsSinceEpoch ~/ 1000,
    limit: 50,
  ),
  // Reactions to my notes
  Filter(
    kinds: [7],
    eTags: myNoteIds,
    limit: 100,
  ),
  // Reposts of my content
  Filter(
    kinds: [6],
    eTags: myNoteIds,
    limit: 25,
  ),
]);

// Process results
for (final event in events) {
  switch (event.kind) {
    case 1: handleTextNote(event); break;
    case 6: handleRepost(event); break;
    case 7: handleReaction(event); break;
  }
}
```

### 6. Tor Configuration

```dart
// Check if Tor support is available
if (TorSupport.isAvailable) {
  // Basic Tor enablement
  await relay.setTorForRelays(true);
  await relay.setTorForVideos(true);
  
  // Advanced configuration
  final torConfig = TorConfig(
    enabled: true,
    forceTor: false,  // Allow clearnet fallback
    required: false,  // Don't fail if Tor unavailable
    timeout: Duration(minutes: 3),
    torOnlyRelays: [
      'wss://relay.onion',
      'wss://private.onion',
    ],
    bridges: [
      'Bridge obfs4 ...',  // For censored networks
    ],
  );
  
  await relay.updateTorConfig(torConfig);
  
  // Add onion relay
  await relay.addExternalRelay('wss://relay.onion');
}
```

## Event Types and Handling

### Regular Events
Most events (kinds 0-9999) are stored normally with no special handling.

### Replaceable Events (10000-19999)
Newer events automatically replace older ones from the same author with the same kind.

```dart
// Profile update - replaces previous profile
final profile = NostrEvent.create(
  pubkey: userPubkey,
  kind: 0,
  content: jsonEncode({
    'name': 'Alice',
    'about': 'Nostr enthusiast',
    'picture': 'https://example.com/avatar.jpg',
  }),
  tags: [],
).sign(privateKey);

await relay.publish(profile); // Replaces old profile automatically
```

### Ephemeral Events (20000-29999)
These events are not stored persistently but are still processed and forwarded to active subscriptions.

### Parameterized Replaceable Events (30000-39999)
Replacement is based on the combination of kind, author, and d-tag value.

```dart
// Long-form article with identifier
final article = NostrEvent.create(
  pubkey: userPubkey,
  kind: 30023,
  content: 'Article content...',
  tags: [
    ['d', 'my-article-slug'],      // Identifier
    ['title', 'My Article'],
    ['published_at', '$timestamp'],
  ],
).sign(privateKey);

await relay.publish(article); // Replaces article with same d-tag
```

## Performance Considerations

### Database Optimization
- Use appropriate limits in filters to avoid large result sets
- Prefer indexed fields (kinds, authors, created_at) for filtering
- Use batch operations for bulk imports
- Run garbage collection periodically

### Memory Management
- Close subscriptions when no longer needed
- Use streams instead of storing large event lists in memory
- Configure appropriate garbage collection policies

### Network Efficiency
- Implement reasonable rate limiting for WebSocket clients
- Use appropriate message size limits
- Consider using compression for large payloads

## Error Handling

The library uses a combination of return values, exceptions, and logging for error handling:

```dart
try {
  await relay.initialize();
  
  final success = await relay.publish(event);
  if (!success) {
    print('Event rejected (invalid or duplicate)');
  }
  
} catch (e) {
  print('Relay initialization failed: $e');
}

// Subscription error handling
final subscription = relay.subscribe(
  filters: [filter],
  onEvent: handleEvent,
  onError: (error) {
    print('Subscription error: $error');
  },
);
```

## Testing and Development

### Unit Testing
Test individual components in isolation:

```dart
test('event validation', () {
  final event = NostrEvent.create(
    pubkey: testPubkey,
    kind: 1,
    content: 'test',
    tags: [],
  ).sign(testPrivateKey);
  
  expect(event.isValid, isTrue);
});
```

### Integration Testing
Test complete workflows:

```dart
testWidgets('relay publish and subscribe', (tester) async {
  final relay = EmbeddedNostrRelay();
  await relay.initialize();
  
  final receivedEvents = <NostrEvent>[];
  final subscription = relay.subscribe(
    filters: [Filter(kinds: [1])],
    onEvent: receivedEvents.add,
  );
  
  final event = createTestEvent();
  await relay.publish(event);
  
  await tester.pump();
  expect(receivedEvents, contains(event));
});
```

## Migration and Versioning

The library handles database migrations automatically. When upgrading versions:

1. The database schema will be updated automatically on first run
2. Existing events are preserved during migrations
3. Check the changelog for any breaking API changes
4. Test thoroughly before deploying updates

## Conclusion

The Flutter Embedded Nostr Relay provides a comprehensive solution for integrating Nostr functionality into Flutter applications. Whether you need simple event publishing, local storage, or a full relay server, the library's modular architecture allows you to use only the components you need while maintaining high performance and Nostr protocol compliance.

For detailed API documentation, see the generated DartDoc documentation. For examples and tutorials, check the `/example` directory in the repository.