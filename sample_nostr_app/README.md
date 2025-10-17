# Sample Nostr App

A sample Flutter application demonstrating the Flutter Embedded Nostr Relay library.

## Overview

This sample app showcases how to build a Nostr client using the embedded relay library. The key feature is that **the relay runs embedded within your app** - no external relay connection needed!

## How It Works

The app uses the `flutter_embedded_nostr_relay` package which provides:
- **Embedded Relay**: A full Nostr relay running inside your Flutter app
- **Local Database**: Events are stored locally using SQLite
- **External Relay Support**: Connects to popular Nostr relays for global reach
- **WebSocket Server**: On non-web platforms, exposes a local WebSocket server on port 7447

### Current Implementation

The embedded relay now acts as a local cache and proxy:
1. **All events are stored locally** in the app's database for offline access
2. **Events are synced with external relays** (relay.damus.io, nos.lol, etc.)
3. **Works both online and offline** - view cached events without internet
4. **Automatic relay connection** when generating or importing identity

Default external relays connected:
- wss://relay.damus.io
- wss://nos.lol
- wss://relay.nostr.band
- wss://relay.snort.social

## Features

### Identity Management
- Generate new Nostr identity with secure key generation
- Import existing private key
- Secure key storage using flutter_secure_storage

### Social Features
- Post text notes that sync to the global Nostr network
- View timeline of events from all connected relays
- Update profile metadata (name, about, picture)
- Real-time event updates from external relays

### Relay Integration
- Embedded relay runs within the app
- Automatic connection to popular external relays
- View relay statistics (event count, subscriptions, connected relays)
- Local WebSocket server for debugging (port 7447)
- Offline support with local event caching

## Project Structure

```
lib/
├── main.dart                # App entry point
├── providers/              # State management
│   ├── nostr_provider.dart # Nostr service state
│   └── timeline_provider.dart # Timeline state
├── screens/                # UI screens
│   └── home_screen.dart    # Main app screen
└── services/               # Business logic
    └── nostr_service.dart  # Nostr relay interaction
```

## Getting Started

1. Install dependencies:
```bash
flutter pub get
```

2. Run the app:
```bash
flutter run
```

3. The embedded relay starts automatically when the app launches

4. To see relay debug info, you can connect to the local WebSocket:
```bash
# On non-web platforms only
websocat ws://localhost:7447
```

## Testing

The app includes comprehensive tests following TDD methodology:

```bash
# Run all tests
flutter test

# Run unit tests
flutter test test/unit/

# Run widget tests
flutter test test/widget/

# Run integration tests
flutter test test/integration/
```

## Architecture

The app follows a clean architecture pattern:

- **Services**: Handle business logic and relay interaction
- **Providers**: Manage application state with ChangeNotifier
- **Screens**: Present UI and handle user interaction
- **Models**: Data structures for Nostr entities

## Key Components

### NostrService
Manages Nostr identity and relay operations:
- Key generation and management
- Event publishing
- Subscription handling

### NostrProvider
State management for the Nostr service:
- Exposes service state to UI
- Handles state updates
- Manages lifecycle

### HomeScreen
Main application screen with:
- Onboarding flow for new users
- Timeline view for events
- Bottom navigation
- Post creation dialog

## Current Limitations

1. **Basic Crypto**: Using temporary implementations for key generation (production apps should use proper crypto)
2. **Fixed Relay List**: Currently connects to hardcoded list of relays (should be configurable)
3. **No Relay Management UI**: Can't add/remove relays from the app yet

## Future Enhancements

- [x] External relay connections (ExternalRelayClient) ✅
- [x] Sync with public Nostr relays ✅
- [ ] Configurable relay management
- [ ] Media attachments
- [ ] Direct messages
- [ ] Contact list management
- [ ] Advanced filtering options
- [ ] Proper cryptographic implementations
- [ ] P2P sync via BLE/WiFi Direct

## Dependencies

- `flutter_embedded_nostr_relay`: The embedded Nostr relay
- `provider`: State management
- `flutter_secure_storage`: Secure key storage
- `intl`: Date formatting
- `share_plus`: Sharing functionality
- `qr_flutter`: QR code generation

## Development Notes

This sample app was built using Test-Driven Development (TDD):
1. Tests were written first for each feature
2. Implementation followed to make tests pass
3. Refactoring maintained test coverage

The embedded relay automatically initializes when the app starts and provides a local Nostr relay for development and testing.
