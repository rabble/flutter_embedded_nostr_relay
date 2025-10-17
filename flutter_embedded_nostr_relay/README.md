# Flutter Embedded Nostr Relay

A self-contained Nostr relay that runs inside Flutter apps, providing instant local responses while intelligently managing external relay connections and P2P synchronization.

## Features

- 🚀 **Instant Local Responses** - Sub-10ms query times from local SQLite cache
- 🔄 **Smart Proxy Pattern** - Transparent NIP-65 Outbox Model support
- 📱 **P2P Sync with Negentropy** - Efficient bandwidth-aware synchronization over BLE/WiFi Direct
- 🎥 **Video-Optimized** - Special handling for OpenVine kind:32222 video events
- 🔒 **Privacy-Preserving** - External relays don't see your viewing patterns
- 💾 **Offline-First** - Works without internet, syncs when available
- 🌐 **Cross-Platform** - iOS, Android, macOS, Windows, Linux, and Web
- 🧅 **Optional Tor Support** - Route relay connections through Tor for enhanced privacy

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_embedded_nostr_relay: ^0.1.0
```

### Basic Usage

```dart
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

// Initialize the relay
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Connect your app to the local relay
final subscription = relay.subscribe(
  filters: [
    Filter(
      kinds: [1], // Text notes
      limit: 100,
    ),
  ],
  onEvent: (event) {
    print('Received event: ${event.content}');
  },
);

// Publish an event
final event = NostrEvent(
  kind: 1,
  content: 'Hello from embedded relay!',
  tags: [],
);
await relay.publish(event);
```

### Advanced Features

#### P2P Synchronization

```dart
// Enable P2P sync
await relay.enableP2PSync(
  transports: [TransportType.ble, TransportType.wifiDirect],
  onPeerDiscovered: (peer) {
    print('Found peer: ${peer.id}');
  },
);
```

#### External Relay Management

```dart
// Add external relays
await relay.addExternalRelay('wss://relay.damus.io');
await relay.addExternalRelay('wss://nos.lol');

// Configure NIP-65 relay lists
await relay.setRelayList(
  read: ['wss://relay.damus.io', 'wss://nos.lol'],
  write: ['wss://relay.damus.io'],
);
```

#### Tor Support (Optional)

To use Tor support, you must build your app with the Tor libraries:

```bash
# Build with Tor support enabled
./scripts/build_with_tor.sh
```

Then use the Tor configuration in your app:

```dart
// Check if Tor support is available
if (TorSupport.isAvailable) {
  // Configure Tor for relay connections
  final torConfig = TorConfig(
    enabled: true,
    forceTor: false,  // Don't require Tor for all connections
    required: false,  // Allow fallback to clearnet
    torOnlyRelays: ['wss://relay.onion'],  // Relays that require Tor
  );
  
  await relay.updateTorConfig(torConfig);
  
  // Enable Tor for relay connections
  await relay.setTorForRelays(true);
  
  // Enable Tor for video loading (optional)
  await relay.setTorForVideos(true);
}
```

## Architecture

The embedded relay acts as a smart proxy between your app and the Nostr network:

```
┌─────────────┐     WebSocket      ┌──────────────────┐
│   Flutter   │ ◄──────────────────► │ Embedded Relay  │
│     App     │   localhost:7447    │                  │
└─────────────┘                     └──────┬───────────┘
                                           │
                                    ┌──────┴───────┐
                              ┌─────┤ External WS  ├─────┐
                              │     └──────────────┘     │
                              ▼                          ▼
                        ┌──────────┐              ┌──────────┐
                        │ Relay 1  │              │ Relay 2  │
                        └──────────┘              └──────────┘
```

## Platform Support

| Platform | WebSocket Server | P2P Sync | BLE | WiFi Direct | Tor Support |
|----------|-----------------|----------|-----|-------------|-------------|
| iOS      | ✅              | ✅       | ✅  | ❌          | ✅*         |
| Android  | ✅              | ✅       | ✅  | ✅          | ✅*         |
| macOS    | ✅              | ✅       | ✅  | ❌          | ✅*         |
| Windows  | ✅              | ❌       | ❌  | ❌          | ✅*         |
| Linux    | ✅              | ❌       | ❌  | ❌          | ✅*         |
| Web      | ❌              | ❌       | ❌  | ❌          | ❌          |

\* Tor support requires building with `./scripts/build_with_tor.sh`

## Performance

- Query response time: <10ms for 100k events
- P2P sync: 1000 events in <5 seconds
- Memory usage: <100MB for 100k events
- Battery efficient with smart sync scheduling

## Documentation

- [Architecture Overview](docs/architecture.md)
- [API Overview](docs/api-overview.md)
- [P2P Sync Protocol](docs/negentropy.md)
- [Video Optimizations](docs/video.md)
- [Tor Integration](docs/tor.md)
- [Quick Start Guide](docs/quick-start.md)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Nostr protocol community
- Negentropy protocol by Doug Hoyte
- OpenVine team for video optimization requirements
