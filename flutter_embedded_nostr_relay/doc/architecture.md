# Architecture Overview

Flutter Embedded Nostr Relay is designed as a modular, high-performance system that brings relay functionality directly into Flutter applications.

## Core Design Principles

1. **Local-First**: All operations prioritize local data for instant responses
2. **Modular Architecture**: Each component has a single responsibility
3. **Protocol Compliance**: Full adherence to Nostr protocol specifications
4. **Cross-Platform**: Unified API across all supported platforms
5. **Privacy by Default**: Optional Tor support and local data control

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter App                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Application Layer (Your App)             │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Flutter Embedded Nostr Relay API             │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │   Direct    │  │  WebSocket   │  │    P2P     │ │   │
│  │  │ Subscribe   │  │   Server     │  │   Sync     │ │   │
│  │  └─────────────┘  └──────────────┘  └────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Core Services                      │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │    Event    │  │ Subscription │  │  External  │ │   │
│  │  │    Store    │  │   Manager    │  │   Relay    │ │   │
│  │  └─────────────┘  └──────────────┘  └────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                              │                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Platform Abstraction Layer              │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │   SQLite    │  │  Transport   │  │    Tor     │ │   │
│  │  │  Database   │  │     (FFI)    │  │  Support   │ │   │
│  │  └─────────────┘  └──────────────┘  └────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. EmbeddedNostrRelay (Coordinator)

The main entry point that coordinates all subsystems:

```dart
class EmbeddedNostrRelay {
  // Manages component lifecycle
  Future<void> initialize();
  Future<void> shutdown();
  
  // Core relay operations
  Future<bool> publish(NostrEvent event);
  Subscription subscribe({filters, onEvent});
  Future<List<NostrEvent>> queryEvents(filters);
  
  // P2P and external relay management
  Future<void> enableP2PSync(config);
  Future<void> addExternalRelay(url);
}
```

**Responsibilities:**
- Component initialization and lifecycle
- API facade for Flutter applications
- Coordination between subsystems
- Configuration management

### 2. EventStore (Persistence Layer)

High-performance SQLite-based storage optimized for Nostr events:

```dart
class EventStore {
  // Storage operations
  Future<bool> storeEvent(NostrEvent event);
  Future<int> storeEvents(List<NostrEvent> events);
  
  // Query operations
  Future<List<NostrEvent>> queryEvents(List<Filter> filters);
  Future<NostrEvent?> getEventById(String id);
  
  // Maintenance
  Future<int> garbageCollect(GarbageCollectionConfig config);
}
```

**Database Schema:**
- Optimized indexes for common query patterns
- Efficient tag storage and querying
- Support for replaceable events (NIP-16)
- Automatic deduplication

### 3. SubscriptionManager (Real-time Updates)

Manages active subscriptions and event routing:

```dart
class SubscriptionManager {
  // Subscription lifecycle
  Subscription createSubscription(filters, callbacks);
  void closeSubscription(String id);
  
  // Event distribution
  void processNewEvent(NostrEvent event);
  void broadcastToSubscribers(NostrEvent event);
}
```

**Features:**
- Efficient event matching against filters
- Multiple subscription types (callback, stream)
- EOSE (End of Stored Events) handling
- Memory-efficient event routing

### 4. WebSocketServer (Protocol Server)

Local WebSocket server for protocol compliance:

```dart
class WebSocketServer {
  // Server lifecycle
  Future<void> start({host, port});
  Future<void> stop();
  
  // Client management
  void handleNewConnection(WebSocket socket);
  void processClientMessage(client, message);
}
```

**Protocol Support:**
- REQ: Subscribe to events
- EVENT: Publish new events
- CLOSE: Close subscriptions
- NOTICE: Server notifications

### 5. Transport Layer (P2P Sync)

Platform-specific P2P synchronization:

```dart
abstract class Transport {
  // Discovery
  Stream<Peer> discoverPeers();
  
  // Connection management
  Future<void> connectToPeer(Peer peer);
  Future<void> disconnectFromPeer(Peer peer);
  
  // Sync operations
  Future<void> syncWithPeer(Peer peer);
}
```

**Implementations:**
- BLE Transport (iOS, Android, macOS)
- WiFi Direct Transport (Android)
- Negentropy protocol for efficient sync

### 6. RelayClient (External Connections)

Manages connections to external Nostr relays:

```dart
class RelayClient {
  // Connection management
  Future<void> connect(String url);
  Future<void> disconnect();
  
  // Protocol operations
  Future<void> subscribe(filters);
  Future<void> publish(NostrEvent event);
  
  // Tor support
  Future<void> enableTor(TorConfig config);
}
```

**Features:**
- Automatic reconnection
- Request/response correlation
- Optional Tor routing
- Connection pooling

## Data Flow

### Publishing Events

```
User Action
    │
    ▼
Flutter App
    │
    ├─► Local Store (immediate)
    │       │
    │       ├─► SQLite Database
    │       └─► Notify Subscribers
    │
    ├─► P2P Broadcast (if enabled)
    │       │
    │       └─► Connected Peers
    │
    └─► External Relays (async)
            │
            └─► Configured Relays
```

### Subscribing to Events

```
Subscription Request
    │
    ├─► Query Local Store
    │       │
    │       └─► Return Cached Events
    │
    ├─► Monitor New Events
    │       │
    │       ├─► Local Publications
    │       ├─► P2P Sync
    │       └─► External Relays
    │
    └─► Event Delivery
            │
            └─► Callback/Stream
```

## Platform Abstractions

### Database Layer

- **iOS/Android/Desktop**: Native SQLite
- **Web**: sql.js (WASM SQLite)

### P2P Transport

- **iOS**: Core Bluetooth
- **Android**: Bluetooth + WiFi Direct
- **macOS**: Core Bluetooth
- **Others**: Not supported

### Tor Integration

- **Mobile/Desktop**: Arti FFI bindings
- **Web**: Not supported

## Performance Optimizations

### 1. Query Performance

- Composite indexes on (kind, author, created_at)
- Separate tag indexes for efficient filtering
- Query plan optimization
- Result pagination

### 2. Memory Management

- Event streaming instead of bulk loading
- Subscription lifecycle management
- Automatic garbage collection
- Connection pooling

### 3. Network Efficiency

- Negentropy protocol for minimal sync overhead
- Request batching for external relays
- Intelligent relay selection (NIP-65)
- Optional compression

## Security Architecture

### 1. Local Security

- Event signature validation
- Input sanitization
- SQL injection prevention
- Resource limits

### 2. Network Security

- WebSocket TLS/SSL
- Optional Tor routing
- Connection authentication
- Rate limiting

### 3. Privacy Features

- Local-first architecture
- No telemetry or tracking
- Optional Tor support
- Minimal external requests

## Extension Points

### 1. Custom Filters

Extend filter matching for specialized use cases:

```dart
class CustomFilter extends Filter {
  @override
  bool matches(NostrEvent event) {
    // Custom matching logic
  }
}
```

### 2. Storage Providers

Implement custom storage backends:

```dart
abstract class StorageProvider {
  Future<bool> store(NostrEvent event);
  Future<List<NostrEvent>> query(Filter filter);
}
```

### 3. Transport Plugins

Add new P2P transport mechanisms:

```dart
class CustomTransport extends Transport {
  // Implementation
}
```

## Best Practices

### 1. Initialization

Always initialize before use:
```dart
final relay = EmbeddedNostrRelay();
await relay.initialize();
```

### 2. Resource Management

Clean up resources properly:
```dart
@override
void dispose() {
  subscription.close();
  relay.shutdown();
  super.dispose();
}
```

### 3. Error Handling

Handle errors gracefully:
```dart
try {
  await relay.publish(event);
} catch (e) {
  // Handle error
}
```

### 4. Performance

- Use appropriate filter limits
- Enable garbage collection
- Close unused subscriptions
- Batch operations when possible

## Future Architecture Plans

1. **Plugin System**: Allow third-party extensions
2. **Clustering**: Multi-device relay clusters
3. **Advanced Routing**: Intelligent relay selection
4. **Analytics**: Optional usage analytics
5. **GraphQL API**: Alternative query interface

## Conclusion

The architecture of Flutter Embedded Nostr Relay prioritizes performance, reliability, and developer experience while maintaining full protocol compliance. The modular design allows for easy extension and platform-specific optimizations while providing a consistent API across all platforms.