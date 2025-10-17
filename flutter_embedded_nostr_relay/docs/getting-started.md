# Getting Started with Flutter Embedded Nostr Relay

Welcome to Flutter Embedded Nostr Relay! This guide will help you get up and running quickly with an embedded Nostr relay in your Flutter application.

## What is Flutter Embedded Nostr Relay?

Flutter Embedded Nostr Relay is a self-contained Nostr relay that runs directly inside your Flutter app. It provides:

- **Instant local responses** - Sub-10ms query times from local SQLite cache
- **Smart proxy pattern** - Seamlessly manages external relay connections
- **P2P synchronization** - Share events between devices without internet
- **Offline-first design** - Works without connectivity, syncs when available
- **Optional Tor support** - Enhanced privacy for relay connections

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_embedded_nostr_relay: ^0.1.0
```

Then run:
```bash
flutter pub get
```

## Basic Example

Here's a minimal example to get you started:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late EmbeddedNostrRelay relay;
  
  @override
  void initState() {
    super.initState();
    _initializeRelay();
  }
  
  Future<void> _initializeRelay() async {
    relay = EmbeddedNostrRelay();
    await relay.initialize();
    
    // Subscribe to text notes
    relay.subscribe(
      filters: [Filter(kinds: [1], limit: 50)],
      onEvent: (event) {
        print('New note: ${event.content}');
      },
    );
  }
  
  @override
  void dispose() {
    relay.shutdown();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('My Nostr App')),
        body: Center(
          child: Text('Embedded relay is running!'),
        ),
      ),
    );
  }
}
```

## Next Steps

1. **[Quick Start Guide](quick-start.md)** - Build a complete Nostr app in 15 minutes
2. **[API Overview](api-overview.md)** - Detailed API documentation
3. **[Architecture](architecture.md)** - Understand how it all works
4. **[Example App](../example/)** - See a full implementation

## Platform Support

| Platform | Embedded Relay | P2P Sync | Tor Support |
|----------|----------------|----------|-------------|
| iOS      | ✅            | ✅       | ✅*         |
| Android  | ✅            | ✅       | ✅*         |
| macOS    | ✅            | ✅       | ✅*         |
| Windows  | ✅            | ❌       | ✅*         |
| Linux    | ✅            | ❌       | ✅*         |
| Web      | ✅            | ❌       | ❌          |

\* Tor support requires building with `./scripts/build_with_tor.sh`

## Common Use Cases

### Local-First Social App
Build a social app that works offline and syncs when online:
- Store all user data locally for instant access
- Sync with external relays when connected
- P2P sync between devices on same network

### Private Group Messaging
Create secure group chats:
- Run relay locally for complete privacy
- Use P2P sync for mesh networking
- Optional Tor for external connections

### Content Creation Platform
Build a decentralized publishing platform:
- Cache content locally for offline reading
- Intelligent relay routing with NIP-65
- Video optimization for kind:32222 events

## Getting Help

- **Documentation**: Browse the [docs](.) directory
- **Example App**: Check out the [example](../example/) directory
- **Issues**: [GitHub Issues](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues)
- **Discussions**: [GitHub Discussions](https://github.com/OpenVine/flutter_embedded_nostr_relay/discussions)

Ready to dive deeper? Continue with the [Quick Start Guide](quick-start.md)!