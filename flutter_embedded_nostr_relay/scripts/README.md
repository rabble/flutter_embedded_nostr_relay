# Build Scripts

This directory contains build scripts for the Flutter Embedded Nostr Relay with optional Tor support.

## Scripts

### `build_with_tor.sh`
Builds the Flutter app **with Tor support enabled**.

```bash
# Build for current platform
./scripts/build_with_tor.sh

# Build for specific platform
./scripts/build_with_tor.sh android
./scripts/build_with_tor.sh ios
./scripts/build_with_tor.sh linux
./scripts/build_with_tor.sh macos
./scripts/build_with_tor.sh windows
./scripts/build_with_tor.sh web
```

**What it does:**
- Compiles the Rust Arti FFI library
- Includes Tor native libraries in the build
- Enables runtime Tor detection and usage
- Supports .onion relay connections
- Larger binary size due to included libraries

**Requirements:**
- Rust/Cargo toolchain
- Flutter SDK
- Platform-specific build tools

### `build_without_tor.sh`
Builds the Flutter app **without Tor support**.

```bash
# Build for current platform
./scripts/build_without_tor.sh

# Build for specific platform  
./scripts/build_without_tor.sh android
./scripts/build_without_tor.sh ios
./scripts/build_without_tor.sh linux
./scripts/build_without_tor.sh macos
./scripts/build_without_tor.sh windows
./scripts/build_without_tor.sh web
```

**What it does:**
- Builds only with standard relay support
- No Tor dependencies included
- Smaller binary size
- Faster build times
- No .onion relay support

**Requirements:**
- Flutter SDK only
- Platform-specific build tools

## Usage Examples

### Development Builds
```bash
# Quick development build without Tor
./scripts/build_without_tor.sh

# Development build with Tor for testing
./scripts/build_with_tor.sh
```

### Production Builds
```bash
# Privacy-focused app with Tor support
./scripts/build_with_tor.sh android

# Lightweight app without Tor
./scripts/build_without_tor.sh android
```

### CI/CD Pipeline
```bash
# Build both variants for comparison
./scripts/build_without_tor.sh all
./scripts/build_with_tor.sh all
```

## Build Behavior

### With Tor Support
- `TorSupport.isAvailable` returns `true` if libraries loaded successfully
- `RelayClientFactory` can create `TorEnabledRelayClient` instances
- Supports connecting to `.onion` relays
- Graceful fallback to direct connections if Tor fails

### Without Tor Support  
- `TorSupport.isAvailable` always returns `false`
- `RelayClientFactory` always creates `ExternalRelayClient` instances
- `.onion` relays will fail to connect
- Smaller app bundle size

## Platform Notes

### Android
- Tor builds require additional permissions in `AndroidManifest.xml`
- Larger APK size with Tor support (~10-20MB additional)

### iOS
- Tor builds may require additional app review considerations
- Network access permissions needed

### Desktop (Linux/macOS/Windows)
- Tor support works best on desktop platforms
- Native library packaging handled automatically

### Web
- Tor support is **not available** for web builds
- Both scripts produce identical web builds (without Tor)

## Environment Variables

### `FLUTTER_TOR_ENABLED`
Set automatically by build scripts:
- `true` when building with Tor support
- `false` when building without Tor support

Can be used in Dart code for conditional compilation:
```dart
const bool torEnabled = bool.fromEnvironment('FLUTTER_TOR_ENABLED', defaultValue: false);
```

## Troubleshooting

### Rust/Cargo Not Found
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### Build Failures
1. Clean and retry:
   ```bash
   flutter clean
   flutter pub get
   ```

2. Check platform-specific requirements
3. Verify Rust toolchain for Tor builds

### Library Loading Issues
- Ensure proper platform permissions
- Check library paths in `TorSupport.libraryPath`
- Verify native libraries are included in build

## Architecture

The optional Tor support uses:
- **Conditional imports**: `tor_client_stub.dart` vs `tor_enabled_relay_client.dart`
- **Runtime detection**: `TorSupport.isAvailable` checks for library presence
- **Factory pattern**: `RelayClientFactory.create()` chooses appropriate client
- **Graceful degradation**: Falls back to direct connections when Tor unavailable

This architecture ensures:
- ✅ Clean separation between Tor and non-Tor builds
- ✅ No runtime impact when Tor is disabled
- ✅ Compile-time optimization opportunities
- ✅ Easy maintenance and testing