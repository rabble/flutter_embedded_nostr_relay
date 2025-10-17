# Flutter Embedded Nostr Relay - Quick Start Guide

Get up and running with Flutter Embedded Nostr Relay in 15 minutes! This guide will walk you through setting up a local Nostr relay that runs directly inside your Flutter app.

## What You'll Build

By the end of this guide, you'll have:
- ✅ A working embedded Nostr relay in your Flutter app
- ✅ Ability to publish events locally
- ✅ Real-time event subscriptions
- ✅ Cross-platform support (iOS, Android, Web)
- ✅ P2P synchronization capabilities

## Prerequisites

- Flutter SDK 3.0.0+
- Dart SDK 3.8.1+
- Basic knowledge of Flutter and Dart
- 15 minutes of your time

## Step 1: Add the Dependency

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_embedded_nostr_relay: ^0.1.0
```

Run:
```bash
flutter pub get
```

## Step 2: Basic Setup

### Import the Package

```dart
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
```

### Initialize the Relay

Create your relay instance and initialize it:

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late EmbeddedNostrRelay relay;
  bool isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeRelay();
  }

  Future<void> _initializeRelay() async {
    relay = EmbeddedNostrRelay();
    
    try {
      await relay.initialize(
        logLevel: Level.INFO,
        enableGarbageCollection: true,
      );
      
      setState(() {
        isInitialized = true;
      });
      
      print('🚀 Relay initialized successfully!');
    } catch (e) {
      print('❌ Failed to initialize relay: $e');
    }
  }

  @override
  void dispose() {
    relay.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: isInitialized 
        ? NostrHomePage(relay: relay)
        : Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          ),
    );
  }
}
```

## Step 3: Create Your First Event

Let's create and publish a simple text note:

```dart
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'dart:math';

class NostrHomePage extends StatefulWidget {
  final EmbeddedNostrRelay relay;
  
  const NostrHomePage({Key? key, required this.relay}) : super(key: key);

  @override
  _NostrHomePageState createState() => _NostrHomePageState();
}

class _NostrHomePageState extends State<NostrHomePage> {
  final TextEditingController _messageController = TextEditingController();
  final List<NostrEvent> _events = [];

  // Generate a test keypair (in production, use proper key management)
  final String _privateKey = _generatePrivateKey();
  late String _publicKey;

  @override
  void initState() {
    super.initState();
    _publicKey = NostrCrypto.getPublicKey(_privateKey);
    _subscribeToEvents();
  }

  static String _generatePrivateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _publishNote() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      // Create unsigned event
      final event = NostrEvent.create(
        pubkey: _publicKey,
        kind: 1, // Text note
        tags: [],
        content: content,
      );

      // Sign the event
      final signedEvent = event.sign(_privateKey);

      // Publish to relay
      final success = await widget.relay.publish(signedEvent);
      
      if (success) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📝 Note published!')),
        );
      } else {
        throw Exception('Failed to publish event');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Nostr App'),
        subtitle: Text('Events: ${_events.length}'),
      ),
      body: Column(
        children: [
          // Input area
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'What\'s happening?',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _publishNote,
                  child: Text('Post'),
                ),
              ],
            ),
          ),
          Divider(),
          // Events list
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[_events.length - 1 - index];
                return _buildEventCard(event);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(NostrEvent event) {
    final isMyEvent = event.pubkey == _publicKey;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      event.createdAt * 1000,
    );

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isMyEvent ? Colors.blue[50] : null,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMyEvent ? Icons.person : Icons.person_outline,
                  size: 16,
                ),
                SizedBox(width: 4),
                Text(
                  isMyEvent ? 'You' : event.pubkey.substring(0, 8),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                Text(
                  _formatTime(timestamp),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(event.content),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
```

## Step 4: Subscribe to Events

Add real-time event subscriptions to see events as they arrive:

```dart
void _subscribeToEvents() {
  // Method 1: Using the legacy subscribe API
  final subscription = widget.relay.subscribe(
    filters: [
      Filter(
        kinds: [1], // Text notes
        limit: 50,
      ),
    ],
    onEvent: (event) {
      setState(() {
        _events.add(event);
      });
    },
    onEose: () {
      print('📥 End of stored events');
    },
    onError: (error) {
      print('❌ Subscription error: $error');
    },
  );

  // Method 2: Using the event stream
  widget.relay.eventStream.listen((event) {
    if (event.kind == 1) { // Only text notes
      print('📨 New event: ${event.content}');
    }
  });
}
```

## Step 5: Platform-Specific Setup

### Android Setup

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth for P2P Nostr synchronization</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth for P2P Nostr synchronization</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses location for Bluetooth discovery</string>
```

### Web Support

The relay automatically handles web platform differences. No additional setup required!

## Step 6: Enable P2P Sync (Optional)

Add peer-to-peer synchronization for offline-first functionality:

```dart
Future<void> _enableP2PSync() async {
  await widget.relay.enableP2PSync(
    transports: [TransportType.ble], // BLE works on all platforms
    onPeerDiscovered: (peer) {
      print('🔗 Found peer: ${peer.name}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found peer: ${peer.name}')),
      );
    },
    onPeerLost: (peer) {
      print('📡 Lost peer: ${peer.name}');
    },
  );
}

// Call this after relay initialization
@override
void initState() {
  super.initState();
  _publicKey = NostrCrypto.getPublicKey(_privateKey);
  _subscribeToEvents();
  _enableP2PSync(); // Add this line
}
```

## Step 7: Advanced Features

### Query Events Directly

```dart
Future<void> _loadOlderEvents() async {
  final events = await widget.relay.queryEvents([
    Filter(
      kinds: [1],
      authors: [_publicKey],
      limit: 10,
    ),
  ]);
  
  setState(() {
    _events.addAll(events);
  });
}
```

### Connect to External Relays

```dart
Future<void> _addExternalRelay() async {
  await widget.relay.addExternalRelay('wss://relay.damus.io');
  print('🌐 Connected to external relay');
}
```

### Enable Tor Support (Optional)

First, build your app with Tor support:

```bash
./scripts/build_with_tor.sh
```

Then configure Tor in your app:

```dart
Future<void> _configureTor() async {
  if (TorSupport.isAvailable) {
    // Enable Tor for relay connections
    await widget.relay.setTorForRelays(true);
    
    // Enable Tor for video loading
    await widget.relay.setTorForVideos(true);
    
    // Add an onion relay
    await widget.relay.addExternalRelay('wss://relay.onion');
    
    print('🧅 Tor support enabled');
  } else {
    print('❌ Tor support not available - build with ./scripts/build_with_tor.sh');
  }
}
```

### Monitor Statistics

```dart
Future<void> _showStats() async {
  final stats = await widget.relay.getStats();
  final subStats = widget.relay.getSubscriptionStats();
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Relay Statistics'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Events stored: ${stats['events'] ?? 0}'),
          Text('Authors: ${stats['authors'] ?? 0}'),
          Text('Active subscriptions: ${subStats['totalSubscriptions'] ?? 0}'),
          Text('Connected clients: ${subStats['totalClients'] ?? 0}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    ),
  );
}
```

## Common Issues & Troubleshooting

### Issue: "Relay not initialized" Error

**Solution:** Always call `await relay.initialize()` before using any relay methods.

```dart
// ❌ Wrong
final relay = EmbeddedNostrRelay();
await relay.publish(event); // Error!

// ✅ Correct
final relay = EmbeddedNostrRelay();
await relay.initialize();
await relay.publish(event); // Works!
```

### Issue: Events Not Appearing

**Solution:** Check your filters and make sure you're subscribed to the right event kinds.

```dart
// Subscribe to multiple event types
final subscription = relay.subscribe(
  filters: [
    Filter(kinds: [0, 1, 3, 7]), // Metadata, notes, contacts, reactions
    Filter(authors: [myPubkey]), // My events
  ],
  onEvent: (event) => print('Got event: ${event.kind}'),
);
```

### Issue: Invalid Event Signature

**Solution:** Make sure you're signing events with the correct private key.

```dart
// Generate a proper keypair
final privateKey = NostrCrypto.generatePrivateKey();
final publicKey = NostrCrypto.getPublicKey(privateKey);

// Create and sign event
final event = NostrEvent.create(
  pubkey: publicKey, // Must match the signing key
  kind: 1,
  tags: [],
  content: 'Hello Nostr!',
).sign(privateKey); // Sign with matching private key
```

### Issue: P2P Not Working

**Solution:** Check platform permissions and make sure Bluetooth is enabled.

```dart
// Check if P2P is supported
if (kIsWeb) {
  print('P2P not supported on web');
} else {
  // Enable on mobile platforms
  await relay.enableP2PSync(transports: [TransportType.ble]);
}
```

### Issue: Database Errors on Web

**Solution:** The package automatically handles web database differences using SQLite compatibility layer.

### Performance Tips

1. **Use appropriate limits:** Don't query too many events at once
```dart
Filter(limit: 50) // Good for most use cases
```

2. **Clean up subscriptions:** Always close subscriptions when done
```dart
@override
void dispose() {
  subscription.close();
  super.dispose();
}
```

3. **Enable garbage collection:** Let the relay clean up old events
```dart
await relay.initialize(enableGarbageCollection: true);
```

## Next Steps

Congratulations! You now have a working Nostr app with an embedded relay. Here's what you can explore next:

1. **[NIP Implementation Guide](./nip-implementation.md)** - Add support for more Nostr features
2. **[P2P Synchronization](./p2p-sync.md)** - Build mesh networks with other devices  
3. **[External Relay Integration](./external-relays.md)** - Connect to the broader Nostr network
4. **[Performance Optimization](./performance.md)** - Scale your app for production
5. **[Security Best Practices](./security.md)** - Protect your users and their data

## Complete Example App

Here's the complete working example you can copy and run:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'dart:math';
import 'package:logging/logging.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late EmbeddedNostrRelay relay;
  bool isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeRelay();
  }

  Future<void> _initializeRelay() async {
    relay = EmbeddedNostrRelay();
    
    try {
      await relay.initialize(
        logLevel: Level.INFO,
        enableGarbageCollection: true,
      );
      
      setState(() {
        isInitialized = true;
      });
      
      print('🚀 Relay initialized successfully!');
    } catch (e) {
      print('❌ Failed to initialize relay: $e');
    }
  }

  @override
  void dispose() {
    relay.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Nostr App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: isInitialized 
        ? NostrHomePage(relay: relay)
        : Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing Nostr Relay...'),
                ],
              ),
            ),
          ),
    );
  }
}

class NostrHomePage extends StatefulWidget {
  final EmbeddedNostrRelay relay;
  
  const NostrHomePage({Key? key, required this.relay}) : super(key: key);

  @override
  _NostrHomePageState createState() => _NostrHomePageState();
}

class _NostrHomePageState extends State<NostrHomePage> {
  final TextEditingController _messageController = TextEditingController();
  final List<NostrEvent> _events = [];
  
  // Generate test keypair (use proper key management in production)
  final String _privateKey = _generatePrivateKey();
  late String _publicKey;
  
  static String _generatePrivateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void initState() {
    super.initState();
    _publicKey = NostrCrypto.getPublicKey(_privateKey);
    _subscribeToEvents();
  }

  void _subscribeToEvents() {
    widget.relay.subscribe(
      filters: [
        Filter(kinds: [1], limit: 50),
      ],
      onEvent: (event) {
        setState(() {
          _events.add(event);
        });
      },
      onEose: () => print('📥 End of stored events'),
      onError: (error) => print('❌ Subscription error: $error'),
    );
  }

  Future<void> _publishNote() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      final event = NostrEvent.create(
        pubkey: _publicKey,
        kind: 1,
        tags: [],
        content: content,
      ).sign(_privateKey);

      final success = await widget.relay.publish(event);
      
      if (success) {
        _messageController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📝 Note published!')),
        );
      } else {
        throw Exception('Failed to publish event');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Nostr App'),
        subtitle: Text('Events: ${_events.length}'),
        actions: [
          IconButton(
            icon: Icon(Icons.info),
            onPressed: _showStats,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'What\'s happening?',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _publishNote,
                  child: Text('Post'),
                ),
              ],
            ),
          ),
          Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[_events.length - 1 - index];
                return _buildEventCard(event);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(NostrEvent event) {
    final isMyEvent = event.pubkey == _publicKey;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isMyEvent ? Colors.blue[50] : null,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isMyEvent ? Icons.person : Icons.person_outline, size: 16),
                SizedBox(width: 4),
                Text(
                  isMyEvent ? 'You' : event.pubkey.substring(0, 8),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                Text(
                  _formatTime(timestamp),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(event.content),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _showStats() async {
    final stats = await widget.relay.getStats();
    final subStats = widget.relay.getSubscriptionStats();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Relay Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Events stored: ${stats['events'] ?? 0}'),
            Text('Authors: ${stats['authors'] ?? 0}'),
            Text('Active subscriptions: ${subStats['totalSubscriptions'] ?? 0}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}
```

Save this as your `main.dart` and run:

```bash
flutter run
```

You'll have a fully functional Nostr app with local relay capabilities!

## Example App

For a more complete example with UI, P2P sync, and external relay management, check out the example app in the repository. The example app demonstrates:

- Complete UI with Material Design
- User profile management
- Timeline with real-time updates
- Messaging functionality
- Relay status monitoring
- P2P synchronization
- External relay connections
- Tor support (when built with Tor libraries)

To run the example app:

```bash
cd example
flutter run
```

## Community & Support

- **Documentation:** [Full API Overview](./api-overview.md)
- **Tor Integration:** [Tor Setup Guide](./tor.md)
- **Issues:** [GitHub Issues](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues)
- **Discussions:** [GitHub Discussions](https://github.com/OpenVine/flutter_embedded_nostr_relay/discussions)

Happy building! 🚀