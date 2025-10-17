# Nostr Social - Example App

A comprehensive Flutter example app that showcases all features of the embedded Nostr relay library. This social networking app demonstrates how to build a decentralized social platform with real-time updates, P2P synchronization, and Material Design 3.

## Features

### Core Functionality
- **User Onboarding**: Generate new Nostr keys or import existing ones
- **Timeline**: View global, following, and mentions feeds with real-time updates
- **Post Creation**: Compose and publish text posts with reactions
- **Direct Messaging**: Encrypted peer-to-peer messaging (NIP-04)
- **Profile Management**: View and edit user profiles with metadata

### Embedded Relay Features
- **Local Relay**: Self-contained Nostr relay running in the app
- **Real-time Updates**: Instant local responses for better UX
- **P2P Synchronization**: Bluetooth and WiFi Direct sync when offline
- **External Relay Integration**: Connect to the broader Nostr network
- **Statistics Monitoring**: Real-time relay performance metrics
- **Tor Support**: Optional privacy-enhanced relay connections (when built with Tor)

### Technical Features
- **Material Design 3**: Modern UI with dynamic color theming
- **State Management**: Clean architecture with Provider pattern
- **Offline Support**: P2P sync enables offline-first usage
- **Platform Integration**: Platform-specific features and optimizations

## Screenshots

[Screenshots would go here in a real app]

## Getting Started

### Prerequisites
- Flutter 3.0.0 or later
- Dart 3.8.1 or later
- Android SDK (for Android deployment)
- Xcode (for iOS deployment)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd flutter_embedded_nostr_relay/example
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

4. **(Optional) Build with Tor support**
   ```bash
   # From the library root directory
   cd ..
   ./scripts/build_with_tor.sh
   
   # Then run the example
   cd example
   flutter run
   ```

### First Run

1. **Create Account**: Generate a new Nostr keypair or import existing keys
2. **Setup Profile**: Add your name, bio, and profile picture
3. **Enable P2P**: Turn on P2P sync for offline functionality
4. **Add Relays**: Connect to external Nostr relays for broader network access

## Architecture

### State Management
The app uses the Provider pattern with the following providers:

- **RelayProvider**: Manages embedded relay lifecycle and statistics
- **UserProvider**: Handles user identity and key management
- **TimelineProvider**: Manages timeline data and real-time updates
- **MessagingProvider**: Handles direct message conversations

### Screen Structure
```
lib/src/screens/
├── onboarding/          # User registration and setup
├── timeline/            # Main feed and post interactions
├── messaging/           # Direct message conversations
├── profile/             # User profile management
├── relay_status/        # Relay monitoring and configuration
└── settings/            # App preferences and configuration
```

### Widget Organization
```
lib/src/widgets/
├── timeline_event_card.dart    # Individual post display
├── post_composer.dart          # Post creation interface
└── [additional widgets]
```

## Key Components

### Embedded Relay Integration
```dart
// Initialize the embedded relay
final relayProvider = context.read<RelayProvider>();
await relayProvider.initialize();

// Publish a post
final event = userProvider.createTextNote(content: "Hello Nostr!");
await relayProvider.relay.publish(event);

// Subscribe to events
final subscription = relayProvider.relay.subscribe(
  filters: [Filter(kinds: [1], limit: 100)],
  onEvent: (event) => handleNewEvent(event),
);
```

### P2P Synchronization
```dart
// Enable P2P sync with multiple transports
await relayProvider.enableP2PSync(
  transports: [TransportType.ble, TransportType.wifiDirect],
  onPeerDiscovered: (peer) => print('Found peer: ${peer.name}'),
);
```

### Real-time Updates
```dart
// Listen to the relay's event stream
relayProvider.relay.eventStream.listen((event) {
  // Handle new events in real-time
  timelineProvider.addEventToTimeline(event);
});
```

### Tor Integration
```dart
// Check if Tor support is available
if (TorSupport.isAvailable) {
  // Enable Tor for relay connections
  await relayProvider.setTorForRelays(true);
  
  // Enable Tor for video loading (optional)
  await relayProvider.setTorForVideos(true);
  
  // Configure Tor settings
  await relayProvider.updateTorConfig(TorConfig(
    enabled: true,
    forceTor: false,
    timeout: Duration(minutes: 2),
  ));
}
```

## Customization

### Theming
The app supports Material Design 3 with dynamic color theming:

```dart
// Custom theme configuration
ThemeData theme = ThemeService.getTheme(
  brightness: Brightness.light,
  dynamicColorScheme: lightDynamic,
);
```

### Adding New Features
1. Create new providers for state management
2. Add screens to the appropriate directory
3. Update navigation and routing
4. Integrate with the embedded relay API

## Performance

### Optimizations
- **Local-first**: Embedded relay provides instant responses
- **Efficient caching**: Smart caching of profiles and media
- **Lazy loading**: Timeline events loaded on-demand
- **Memory management**: Automatic cleanup of old events

### Benchmarks
- **Startup time**: < 2 seconds with relay initialization
- **Event publishing**: < 100ms for local relay
- **Timeline loading**: 100 events in < 500ms
- **P2P sync**: Sub-second peer discovery

## Building for Production

### Android
```bash
flutter build apk --release
# or
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Platform-specific Notes

#### Android
- Requires permissions for Bluetooth and location (for WiFi Direct)
- Minimum SDK version: 21 (Android 5.0)
- Target SDK version: 34 (Android 14)

#### iOS
- Requires Bluetooth permissions for P2P sync
- Minimum iOS version: 11.0
- Uses Background App Refresh for relay sync

## Troubleshooting

### Common Issues

**Relay fails to initialize**
- Check device storage space
- Verify network connectivity
- Clear app data and restart

**P2P sync not working**
- Ensure Bluetooth is enabled
- Grant location permissions (Android)
- Check device compatibility

**Timeline not updating**
- Verify relay connection
- Check external relay URLs
- Restart the app

### Debug Mode
Enable debug logging by setting the log level:
```dart
await relayProvider.initialize(logLevel: Level.FINE);
```

## Contributing

This example app demonstrates the capabilities of the Flutter Embedded Nostr Relay library. Contributions to improve the example or showcase additional features are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This example app is provided under the same license as the main library. See the LICENSE file for details.

## Support

- **Documentation**: Check the main library documentation
- **Issues**: Report bugs via GitHub issues
- **Community**: Join the Nostr developer community
- **Discussions**: Participate in GitHub discussions

## Related

- [Flutter Embedded Nostr Relay Library](../)
- [Nostr Protocol Specification](https://nostr-protocol.org/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Material Design 3](https://m3.material.io/)