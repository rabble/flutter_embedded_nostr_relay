# Flutter Embedded Nostr Relay Documentation

Welcome to the comprehensive documentation for Flutter Embedded Nostr Relay. This documentation covers everything you need to know to integrate and use the embedded relay in your Flutter applications.

## Documentation Structure

### Getting Started
- **[Getting Started](getting-started.md)** - Introduction and basic setup
- **[Quick Start Guide](quick-start.md)** - Build a Nostr app in 15 minutes
- **[API Overview](api-overview.md)** - Complete API reference

### Core Concepts
- **[Architecture](architecture.md)** - System design and components
- **[NIP Implementation](nip-implementation.md)** - Supported Nostr Implementation Possibilities

### Features
- **[P2P Synchronization](p2p-sync.md)** - Peer-to-peer sync between devices
- **[External Relays](external-relays.md)** - Integration with external Nostr relays
- **[Video Optimization](video.md)** - Special handling for video events
- **[Tor Integration](tor.md)** - Optional Tor support for privacy

### Advanced Topics
- **[Negentropy Protocol](negentropy.md)** - Efficient set reconciliation
- **[Performance](performance.md)** - Optimization techniques and best practices
- **[Security](security.md)** - Security features and best practices
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions

## Quick Links

### For New Users
1. Start with [Getting Started](getting-started.md)
2. Follow the [Quick Start Guide](quick-start.md)
3. Explore the [Example App](../example/)

### For Developers
1. Review the [API Overview](api-overview.md)
2. Understand the [Architecture](architecture.md)
3. Learn about [Performance](performance.md) optimization

### For Advanced Users
1. Implement [P2P Synchronization](p2p-sync.md)
2. Enable [Tor Integration](tor.md)
3. Study the [Negentropy Protocol](negentropy.md)

## Key Features

### 🚀 Instant Local Responses
- Sub-10ms query times from local SQLite cache
- Optimized indexes for common query patterns
- Efficient event storage and retrieval

### 🔄 Smart Proxy Pattern
- Transparent caching of external relay data
- Intelligent request routing
- NIP-65 Outbox Model support

### 📱 P2P Synchronization
- BLE and WiFi Direct support
- Negentropy protocol for efficient sync
- Works offline between devices

### 🎥 Video Optimization
- Special handling for OpenVine kind:32222 events
- Smart prefetching and caching
- CDN integration support

### 🔒 Privacy Features
- Optional Tor support for relay connections
- Local-first architecture
- No telemetry or tracking

### 💾 Offline-First Design
- Full functionality without internet
- Automatic sync when connected
- Persistent local storage

## Platform Support

| Platform | Relay | P2P | Tor |
|----------|-------|-----|-----|
| iOS      | ✅    | ✅  | ✅* |
| Android  | ✅    | ✅  | ✅* |
| macOS    | ✅    | ✅  | ✅* |
| Windows  | ✅    | ❌  | ✅* |
| Linux    | ✅    | ❌  | ✅* |
| Web      | ✅    | ❌  | ❌  |

\* Requires building with Tor libraries

## Example Code

### Basic Usage
```dart
// Initialize relay
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Subscribe to events
relay.subscribe(
  filters: [Filter(kinds: [1], limit: 50)],
  onEvent: (event) => print('New event: ${event.content}'),
);

// Publish event
final event = NostrEvent.create(
  pubkey: myPubkey,
  kind: 1,
  content: 'Hello Nostr!',
  tags: [],
).sign(privateKey);

await relay.publish(event);
```

### Advanced Features
```dart
// Enable P2P sync
await relay.enableP2PSync(
  transports: [TransportType.ble],
  onPeerDiscovered: (peer) => print('Found: ${peer.name}'),
);

// Configure external relays
await relay.addExternalRelays([
  'wss://relay.damus.io',
  'wss://nos.lol',
]);

// Enable Tor (if available)
if (TorSupport.isAvailable) {
  await relay.setTorForRelays(true);
}
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](../CONTRIBUTING.md) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues)
- **Discussions**: [GitHub Discussions](https://github.com/OpenVine/flutter_embedded_nostr_relay/discussions)
- **Example**: [Example App](../example/)

## License

This project is licensed under the MIT License. See the [LICENSE](../LICENSE) file for details.