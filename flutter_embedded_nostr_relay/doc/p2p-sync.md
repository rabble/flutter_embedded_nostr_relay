# P2P Synchronization Guide

Flutter Embedded Nostr Relay includes powerful peer-to-peer synchronization capabilities, allowing devices to share events directly without internet connectivity.

## Overview

P2P sync enables:
- **Offline mesh networks** - Share events without internet
- **Efficient synchronization** - Only transfer missing events
- **Multi-transport support** - BLE, WiFi Direct, and more
- **Automatic peer discovery** - Find nearby devices automatically
- **Privacy-preserving** - Direct device-to-device communication

## How It Works

P2P sync uses the [Negentropy protocol](negentropy.md) for efficient set reconciliation:

```
Device A                          Device B
   │                                 │
   ├──── Discover Peer ──────────────┤
   │                                 │
   ├──── Exchange Fingerprints ───────┤
   │        (Negentropy)             │
   │                                 │
   ├──── Identify Differences ───────┤
   │                                 │
   ├──── Transfer Missing Events ────┤
   │                                 │
   └──── Sync Complete ──────────────┘
```

## Basic Usage

### Enable P2P Sync

```dart
final relay = EmbeddedNostrRelay();
await relay.initialize();

// Enable P2P with default settings
await relay.enableP2PSync(
  transports: [TransportType.ble], // BLE works on all platforms
  onPeerDiscovered: (peer) {
    print('Found peer: ${peer.name}');
  },
  onPeerLost: (peer) {
    print('Lost peer: ${peer.name}');
  },
  onSyncProgress: (peer, progress) {
    print('Sync with ${peer.name}: ${progress.percent}%');
  },
);
```

### Transport Options

#### Bluetooth Low Energy (BLE)
Supported on: iOS, Android, macOS

```dart
await relay.enableP2PSync(
  transports: [TransportType.ble],
  config: BLEConfig(
    serviceUUID: 'your-custom-uuid', // Optional custom UUID
    scanDuration: Duration(seconds: 10),
    advertisingName: 'MyNostrApp',
  ),
);
```

#### WiFi Direct
Supported on: Android only

```dart
await relay.enableP2PSync(
  transports: [TransportType.wifiDirect],
  config: WiFiDirectConfig(
    groupName: 'NostrMesh',
    password: 'optional-password',
  ),
);
```

#### Multiple Transports
Use multiple transports simultaneously:

```dart
await relay.enableP2PSync(
  transports: [
    TransportType.ble,
    TransportType.wifiDirect,
  ],
);
```

## Advanced Configuration

### Sync Filters

Control which events are synchronized:

```dart
await relay.enableP2PSync(
  transports: [TransportType.ble],
  syncConfig: SyncConfig(
    filters: [
      Filter(kinds: [1, 6, 7]), // Only sync specific event types
      Filter(
        since: DateTime.now().subtract(Duration(days: 7))
            .millisecondsSinceEpoch ~/ 1000,
      ), // Only sync recent events
    ],
    maxEventsPerSync: 1000, // Limit events per sync session
    bandwidthLimit: 100 * 1024, // 100KB/s limit
  ),
);
```

### Manual Peer Management

```dart
// Get list of discovered peers
final peers = await relay.getDiscoveredPeers();

// Manually initiate sync with specific peer
await relay.syncWithPeer(peers.first);

// Block/unblock peers
await relay.blockPeer(peer.id);
await relay.unblockPeer(peer.id);

// Set peer preferences
await relay.setPeerTrust(peer.id, TrustLevel.high);
```

### Sync Strategies

#### 1. Mutual Sync (Default)
Both devices exchange missing events:

```dart
syncConfig: SyncConfig(
  strategy: SyncStrategy.mutual,
)
```

#### 2. Pull Only
Only receive events from peer:

```dart
syncConfig: SyncConfig(
  strategy: SyncStrategy.pullOnly,
)
```

#### 3. Push Only
Only send events to peer:

```dart
syncConfig: SyncConfig(
  strategy: SyncStrategy.pushOnly,
)
```

## Platform-Specific Setup

### iOS Setup

Add to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to sync with nearby devices</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to sync with nearby devices</string>
```

### Android Setup

Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- For WiFi Direct -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
```

Request runtime permissions:

```dart
// Using permission_handler package
final statuses = await [
  Permission.bluetooth,
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
  Permission.location,
].request();
```

### macOS Setup

Add to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to sync with nearby devices</string>
```

Enable Bluetooth in `Runner.entitlements`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

## UI Integration

### Peer Discovery UI

```dart
class PeerListScreen extends StatefulWidget {
  @override
  _PeerListScreenState createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> {
  final List<Peer> _peers = [];
  
  @override
  void initState() {
    super.initState();
    _enableP2P();
  }
  
  Future<void> _enableP2P() async {
    await relay.enableP2PSync(
      transports: [TransportType.ble],
      onPeerDiscovered: (peer) {
        setState(() {
          _peers.add(peer);
        });
      },
      onPeerLost: (peer) {
        setState(() {
          _peers.removeWhere((p) => p.id == peer.id);
        });
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _peers.length,
      itemBuilder: (context, index) {
        final peer = _peers[index];
        return ListTile(
          leading: Icon(Icons.devices),
          title: Text(peer.name),
          subtitle: Text('Signal: ${peer.signalStrength}'),
          trailing: IconButton(
            icon: Icon(Icons.sync),
            onPressed: () => _syncWithPeer(peer),
          ),
        );
      },
    );
  }
  
  Future<void> _syncWithPeer(Peer peer) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SyncProgressDialog(peer: peer),
    );
    
    await relay.syncWithPeer(peer);
    
    Navigator.pop(context);
  }
}
```

### Sync Progress Dialog

```dart
class SyncProgressDialog extends StatefulWidget {
  final Peer peer;
  
  const SyncProgressDialog({required this.peer});
  
  @override
  _SyncProgressDialogState createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  double _progress = 0.0;
  String _status = 'Connecting...';
  
  @override
  void initState() {
    super.initState();
    relay.setSyncProgressCallback(widget.peer.id, (progress) {
      setState(() {
        _progress = progress.percent / 100;
        _status = progress.status;
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Syncing with ${widget.peer.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          SizedBox(height: 16),
          Text(_status),
        ],
      ),
    );
  }
}
```

## Performance Optimization

### 1. Bandwidth Management

Limit bandwidth usage for battery and data efficiency:

```dart
syncConfig: SyncConfig(
  bandwidthLimit: 50 * 1024, // 50KB/s
  compressEvents: true, // Enable compression
)
```

### 2. Selective Sync

Only sync relevant events:

```dart
syncConfig: SyncConfig(
  filters: [
    // Only sync events from followed users
    Filter(authors: followedUsers),
    // Only sync recent events
    Filter(since: recentTimestamp),
  ],
)
```

### 3. Background Sync

Enable background synchronization (platform-specific):

```dart
// iOS: Enable background modes in Info.plist
// Android: Use WorkManager or similar

await relay.enableBackgroundSync(
  interval: Duration(minutes: 15),
  requiresCharging: false,
  requiresWifi: false,
);
```

## Security Considerations

### 1. Peer Authentication

Implement peer verification:

```dart
await relay.enableP2PSync(
  transports: [TransportType.ble],
  security: P2PSecurityConfig(
    requireAuthentication: true,
    trustedPeers: ['pubkey1', 'pubkey2'],
    verificationMethod: VerificationMethod.challenge,
  ),
);
```

### 2. Encrypted Transport

All P2P communications are encrypted by default using:
- BLE: AES-128 with ephemeral keys
- WiFi Direct: WPA2 encryption

### 3. Event Validation

All received events are validated:
- Signature verification
- Timestamp validation
- Content sanitization

## Troubleshooting

### Common Issues

1. **Peers not discovering**
   - Check Bluetooth/WiFi is enabled
   - Verify permissions are granted
   - Ensure devices are in range (10-30m for BLE)

2. **Sync failures**
   - Check bandwidth limits aren't too restrictive
   - Verify event filters aren't excluding everything
   - Look for signature validation errors

3. **Poor performance**
   - Reduce number of events being synced
   - Enable compression
   - Use WiFi Direct for large transfers

### Debug Logging

Enable detailed P2P logs:

```dart
Logger.root.level = Level.ALL;
Logger('P2PTransport').onRecord.listen((record) {
  print('P2P: ${record.message}');
});
```

## Best Practices

1. **Battery Life**: Disable P2P when not needed
2. **Privacy**: Only sync with trusted peers
3. **Data Usage**: Set appropriate bandwidth limits
4. **UX**: Show clear sync status to users
5. **Reliability**: Handle connection drops gracefully

## Example: Offline Event App

Here's a complete example of an app that works offline:

```dart
class OfflineEventApp extends StatefulWidget {
  @override
  _OfflineEventAppState createState() => _OfflineEventAppState();
}

class _OfflineEventAppState extends State<OfflineEventApp> {
  final relay = EmbeddedNostrRelay();
  final _peers = <Peer>[];
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    await relay.initialize();
    
    // Enable P2P for offline sync
    await relay.enableP2PSync(
      transports: [TransportType.ble],
      onPeerDiscovered: (peer) {
        setState(() => _peers.add(peer));
        
        // Auto-sync with new peers
        relay.syncWithPeer(peer);
      },
      syncConfig: SyncConfig(
        filters: [
          Filter(kinds: [1, 6, 7], limit: 100),
        ],
        strategy: SyncStrategy.mutual,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Offline Nostr'),
          actions: [
            IconButton(
              icon: Icon(Icons.people),
              onPressed: () => _showPeers(),
            ),
          ],
        ),
        body: NostrTimeline(relay: relay),
      ),
    );
  }
  
  void _showPeers() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nearby Devices (${_peers.length})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _peers.map((peer) => ListTile(
            title: Text(peer.name),
            subtitle: Text('Last sync: ${peer.lastSync}'),
          )).toList(),
        ),
      ),
    );
  }
}
```

## Next Steps

- Learn about the [Negentropy Protocol](negentropy.md)
- Explore [External Relay Integration](external-relays.md)
- Check out [Performance Optimization](performance.md)