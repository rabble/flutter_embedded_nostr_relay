# Tor Integration

Flutter Embedded Nostr Relay supports optional Tor integration for enhanced privacy when connecting to external relays.

## Overview

The Tor support is built using [Arti](https://gitlab.torproject.org/tpo/core/arti), the Tor Project's official Rust implementation. This provides:

- 🧅 **Anonymous relay connections** - Hide your IP from external relays
- 🔒 **Onion service support** - Connect to .onion relay addresses
- 🌐 **Selective routing** - Choose which connections use Tor
- ⚡ **Graceful degradation** - Works without Tor when libraries unavailable

## Building with Tor Support

Tor support is optional and requires building with the Arti FFI libraries:

```bash
# From the project root
./scripts/build_with_tor.sh

# This will:
# 1. Build the Arti FFI library for your platform
# 2. Link it into your Flutter app
# 3. Enable TorSupport.isAvailable at runtime
```

### Platform Requirements

- **Rust toolchain** - Required to build Arti
- **Platform SDKs** - iOS/Android/macOS SDK for respective platforms
- **CMake** - For native builds

## Using Tor in Your App

### Basic Usage

```dart
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

// Check if Tor support is available
if (TorSupport.isAvailable) {
  final relay = EmbeddedNostrRelay();
  
  // Enable Tor for relay connections
  await relay.setTorForRelays(true);
  
  // Enable Tor for video loading (optional)
  await relay.setTorForVideos(true);
  
  // Add an onion relay
  await relay.addExternalRelay('wss://relay.onion');
}
```

### Advanced Configuration

```dart
// Create a custom Tor configuration
final torConfig = TorConfig(
  enabled: true,
  forceTor: false,        // Allow fallback to clearnet
  required: false,        // Don't fail if Tor unavailable
  timeout: Duration(minutes: 2),
  torOnlyRelays: [        // Relays that MUST use Tor
    'wss://private.onion',
    'wss://secure.onion',
  ],
  bridges: [              // Optional bridge configuration
    'Bridge obfs4 ...',
    'Bridge obfs4 ...',
  ],
);

await relay.updateTorConfig(torConfig);
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | false | Enable Tor for connections |
| `forceTor` | bool | false | Require Tor for ALL connections |
| `required` | bool | false | Fail if Tor cannot be established |
| `timeout` | Duration | 2 min | Connection timeout |
| `torOnlyRelays` | List<String> | [] | Relays requiring Tor |
| `bridges` | List<String> | [] | Bridge configuration |

## Architecture

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────┐
│   Flutter   │ ───► │ RelayClientFactory│ ───► │ Tor Client  │
│     App     │      │                  │      │   (Arti)    │
└─────────────┘      └──────────────────┘      └──────┬──────┘
                              │                         │
                              ▼                         ▼
                     ┌─────────────────┐       ┌──────────────┐
                     │ Regular Client  │       │ SOCKS5 Proxy │
                     │  (clearnet)     │       │ 127.0.0.1:9050│
                     └─────────────────┘       └──────────────┘
```

### Components

1. **TorSupport** - Runtime detection of Tor library availability
2. **TorConfig** - Configuration model with serialization
3. **RelayClientFactory** - Creates appropriate client based on Tor availability
4. **Arti FFI** - Native Rust library providing Tor functionality

## UI Integration

The library provides UI helpers for Tor settings:

```dart
// In your settings screen
if (TorSupport.isAvailable) {
  SwitchListTile(
    title: Text('Use Tor for relay connections'),
    subtitle: Text('Route through Tor for privacy'),
    value: provider.torForRelays,
    onChanged: (enabled) => provider.setTorForRelays(enabled),
  );
  
  SwitchListTile(
    title: Text('Use Tor for video loading'),
    subtitle: Text('May be slower but more private'),
    value: provider.torForVideos,
    onChanged: (enabled) => provider.setTorForVideos(enabled),
  );
}
```

## Performance Considerations

- **Initial connection**: First Tor connection takes 10-30 seconds to establish circuit
- **Latency**: Add 100-500ms per request due to onion routing
- **Bandwidth**: Typically 50-80% of clearnet speed
- **Battery**: Moderate impact due to encryption overhead

### Optimization Tips

1. **Selective usage** - Only enable Tor for sensitive operations
2. **Connection pooling** - Reuse established circuits
3. **Timeout tuning** - Adjust timeouts based on network conditions
4. **Bridge usage** - Use bridges in restrictive networks

## Testing

### Unit Tests

```dart
test('should detect Tor availability', () {
  expect(TorSupport.isAvailable, isTrue);
});

test('should handle onion URLs correctly', () {
  expect(TorConfig.isOnionRelay('wss://relay.onion'), isTrue);
  expect(TorConfig.isOnionRelay('wss://relay.com'), isFalse);
});
```

### Integration Tests

```dart
testWidgets('Tor settings persist across app restarts', (tester) async {
  // Enable Tor
  await provider.setTorForRelays(true);
  
  // Restart app
  await tester.pumpWidget(MyApp());
  
  // Verify settings persisted
  expect(provider.torForRelays, isTrue);
});
```

## Troubleshooting

### Common Issues

1. **"Tor support not available"**
   - Ensure you built with `./scripts/build_with_tor.sh`
   - Check that `libarti_ffi.dylib/so/dll` is in your app bundle

2. **Connection timeouts**
   - Increase timeout in TorConfig
   - Check network connectivity
   - Try using bridges

3. **Architecture mismatch warnings**
   - Ensure Arti library matches your target architecture
   - Rebuild for correct platform

### Debug Logging

```dart
// Enable debug logging
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) {
  print('${record.level.name}: ${record.message}');
});
```

## Security Considerations

1. **Traffic analysis** - Tor prevents IP tracking but not traffic pattern analysis
2. **Exit nodes** - Traffic exits Tor network in cleartext to relay
3. **Onion services** - .onion relays provide end-to-end encryption
4. **Metadata** - Event timestamps and patterns may still leak information

## Future Enhancements

- [ ] Built-in bridge configuration UI
- [ ] Tor circuit visualization
- [ ] Pluggable transport support
- [ ] Onion service hosting for P2P
- [ ] Automatic .onion discovery via NIP-65

## References

- [Arti Project](https://gitlab.torproject.org/tpo/core/arti)
- [Tor Project](https://www.torproject.org/)
- [NIP-65 Relay List Metadata](https://github.com/nostr-protocol/nips/blob/master/65.md)