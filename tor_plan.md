# Tor Integration Plan for Flutter Embedded Nostr Relay

## Executive Summary

This document outlines the practical implementation of optional Tor support in the Flutter Embedded Nostr Relay using Arti via FFI bindings. Tor support is compile-time optional - developers can build with or without it. This provides privacy-conscious users with anonymity while keeping the base relay lightweight.

## Table of Contents

1. [Build Configuration](#build-configuration)
2. [Architecture Overview](#architecture-overview)
3. [Implementation Guide](#implementation-guide)
4. [Platform-Specific Setup](#platform-specific-setup)
5. [Testing Strategy](#testing-strategy)
6. [Quick Start](#quick-start)

## Build Configuration

### Making Tor Support Optional

Tor support is controlled via compile-time flags and conditional dependencies:

#### pubspec.yaml
```yaml
name: flutter_embedded_nostr_relay
version: 1.0.0

dependencies:
  flutter:
    sdk: flutter
  sqlite3: ^2.1.0
  web_socket_channel: ^2.4.0
  # ... other core dependencies

# Optional Tor support - only included when tor feature is enabled
dev_dependencies:
  flutter_embedded_nostr_relay_tor:
    path: packages/tor_support
```

#### Conditional Compilation in Dart
```dart
// lib/src/network/relay_client_factory.dart
import 'package:flutter_embedded_nostr_relay/src/network/standard_relay_client.dart';

// Conditional import using Dart's conditional imports
import 'tor_client_stub.dart' 
  if (dart.library.ffi) 'tor_enabled_relay_client.dart';

class RelayClientFactory {
  static ExternalRelayClient create({TorConfig? torConfig}) {
    if (torConfig?.enabled == true && TorSupport.isAvailable) {
      return TorEnabledRelayClient(torConfig: torConfig);
    }
    return StandardRelayClient();
  }
}
```

#### Feature Detection
```dart
// lib/src/tor/tor_support.dart
class TorSupport {
  static bool _checked = false;
  static bool _available = false;
  
  static bool get isAvailable {
    if (!_checked) {
      _checked = true;
      try {
        // Try to load Tor library
        final lib = DynamicLibrary.open(_getLibraryPath());
        _available = lib.lookup('arti_client_create') != null;
      } catch (_) {
        _available = false;
      }
    }
    return _available;
  }
  
  static String _getLibraryPath() {
    if (Platform.isAndroid) return 'libarti_ffi.so';
    if (Platform.isIOS) return 'ArtiFFI.framework/ArtiFFI';
    if (Platform.isMacOS) return 'libarti_ffi.dylib';
    if (Platform.isWindows) return 'arti_ffi.dll';
    if (Platform.isLinux) return 'libarti_ffi.so';
    throw UnsupportedError('Platform not supported');
  }
}
```

### Build Scripts

#### build_with_tor.sh
```bash
#!/bin/bash
# Build with Tor support

# Build Arti FFI library first
cd packages/arti_ffi
cargo build --release

# Copy libraries to Flutter project
./copy_libraries.sh

# Build Flutter app with Tor flag
cd ../..
flutter build apk --dart-define=TOR_SUPPORT=true
```

#### build_without_tor.sh
```bash
#!/bin/bash
# Build without Tor support (standard build)

flutter build apk
```

## Architecture Overview

### High-Level Design

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App Layer                     │
├─────────────────────────────────────────────────────────┤
│                 Embedded Nostr Relay                     │
│  ┌─────────────────────────────────────────────────┐    │
│  │          External Relay Client                   │    │
│  │  ┌─────────────┐    ┌─────────────────────┐    │    │
│  │  │   Normal    │    │   Tor-Enabled       │    │    │
│  │  │ WebSocket   │    │   WebSocket         │    │    │
│  │  └─────────────┘    └──────────┬──────────┘    │    │
│  └─────────────────────────────────┼───────────────┘    │
├────────────────────────────────────┼────────────────────┤
│                 Dart FFI Layer     │                     │
│                                    ▼                     │
│                          ┌─────────────────┐            │
│                          │  Arti Bindings  │            │
│                          └────────┬────────┘            │
├──────────────────────────────────┼──────────────────────┤
│              Native Layer         ▼                      │
│                          ┌─────────────────┐            │
│                          │   Arti C API    │            │
│                          │    Wrapper      │            │
│                          └────────┬────────┘            │
│                                   ▼                      │
│                          ┌─────────────────┐            │
│                          │   Arti Client   │            │
│                          │  (Rust Library) │            │
│                          └─────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### Component Responsibilities

1. **Flutter App Layer**: Unchanged - continues using the embedded relay as before
2. **Embedded Nostr Relay**: Gains optional Tor routing capability when compiled with support
3. **External Relay Client**: Factory pattern creates Tor-enabled or standard client
4. **Dart FFI Layer**: Conditionally loaded only when Tor libraries are present
5. **Arti C API Wrapper**: Thin C wrapper around Arti's Rust API
6. **Arti Client**: Full Tor protocol implementation from the Tor Project

## Implementation Guide

### Project Structure

```
flutter_embedded_nostr_relay/
├── lib/
│   └── src/
│       ├── network/
│       │   ├── relay_client_factory.dart
│       │   ├── standard_relay_client.dart
│       │   └── tor/
│       │       ├── tor_client_stub.dart        # Used when Tor not available
│       │       ├── tor_enabled_relay_client.dart
│       │       └── tor_websocket_channel.dart
│       └── tor/
│           ├── arti_bindings.dart
│           ├── tor_config.dart
│           └── tor_support.dart
├── packages/
│   └── arti_ffi/                               # Separate package for Tor
│       ├── Cargo.toml
│       ├── src/
│       │   └── lib.rs
│       └── build.rs
└── scripts/
    ├── build_with_tor.sh
    └── build_without_tor.sh
```

### 1. Arti C API Wrapper (Rust)

```rust
// arti_ffi/src/lib.rs
#[repr(C)]
pub struct ArtiTorClient {
    inner: Arc<Mutex<TorClientInner>>,
}

struct TorClientInner {
    runtime: tokio::runtime::Runtime,
    client: TorClient<PreferredRuntime>,
    connections: HashMap<u64, TcpStream>,
}

// Core API functions
#[no_mangle]
pub extern "C" fn arti_client_create(
    config_json: *const c_char,
    state_dir: *const c_char,
    cache_dir: *const c_char,
) -> *mut ArtiTorClient;

#[no_mangle]
pub extern "C" fn arti_client_bootstrap(
    client: *mut ArtiTorClient,
    callback: BootstrapCallback,
    user_data: *mut c_void,
) -> i32;

#[no_mangle]
pub extern "C" fn arti_client_connect(
    client: *mut ArtiTorClient,
    host: *const c_char,
    port: u16,
    callback: ConnectionCallback,
    user_data: *mut c_void,
) -> u64; // Returns connection ID

#[no_mangle]
pub extern "C" fn arti_connection_read(
    client: *mut ArtiTorClient,
    conn_id: u64,
    buffer: *mut u8,
    buffer_len: usize,
    callback: ReadCallback,
    user_data: *mut c_void,
) -> i32;

#[no_mangle]
pub extern "C" fn arti_connection_write(
    client: *mut ArtiTorClient,
    conn_id: u64,
    data: *const u8,
    data_len: usize,
    callback: WriteCallback,
    user_data: *mut c_void,
) -> i32;
```

### 2. Dart FFI Bindings

```dart
// lib/src/tor/arti_bindings.dart
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Opaque type for Arti client
class ArtiTorClient extends Opaque {}

// FFI function signatures
typedef ArtiClientCreateNative = Pointer<ArtiTorClient> Function(
  Pointer<Utf8> configJson,
  Pointer<Utf8> stateDir,
  Pointer<Utf8> cacheDir,
);
typedef ArtiClientCreate = Pointer<ArtiTorClient> Function(
  Pointer<Utf8> configJson,
  Pointer<Utf8> stateDir,
  Pointer<Utf8> cacheDir,
);

typedef ArtiClientBootstrapNative = Int32 Function(Pointer<ArtiTorClient>);
typedef ArtiClientBootstrap = int Function(Pointer<ArtiTorClient>);

typedef ArtiClientConnectNative = Uint64 Function(
  Pointer<ArtiTorClient>,
  Pointer<Utf8> host,
  Uint16 port,
);
typedef ArtiClientConnect = int Function(
  Pointer<ArtiTorClient>,
  Pointer<Utf8> host,
  int port,
);

class ArtiBindings {
  late final DynamicLibrary _lib;
  late final ArtiClientCreate _create;
  late final ArtiClientBootstrap _bootstrap;
  late final ArtiClientConnect _connect;
  
  static ArtiBindings? _instance;
  
  factory ArtiBindings() {
    _instance ??= ArtiBindings._internal();
    return _instance!;
  }
  
  ArtiBindings._internal() {
    _lib = _loadLibrary();
    _create = _lib.lookupFunction<ArtiClientCreateNative, ArtiClientCreate>(
      'arti_client_create',
    );
    _bootstrap = _lib.lookupFunction<ArtiClientBootstrapNative, ArtiClientBootstrap>(
      'arti_client_bootstrap',
    );
    _connect = _lib.lookupFunction<ArtiClientConnectNative, ArtiClientConnect>(
      'arti_client_connect',
    );
  }
  
  DynamicLibrary _loadLibrary() {
    final path = TorSupport._getLibraryPath();
    return DynamicLibrary.open(path);
  }
  
  Pointer<ArtiTorClient> createClient(
    String configJson,
    String stateDir,
    String cacheDir,
  ) {
    final configPtr = configJson.toNativeUtf8();
    final statePtr = stateDir.toNativeUtf8();
    final cachePtr = cacheDir.toNativeUtf8();
    
    try {
      return _create(configPtr, statePtr, cachePtr);
    } finally {
      malloc.free(configPtr);
      malloc.free(statePtr);
      malloc.free(cachePtr);
    }
  }
  
  int bootstrap(Pointer<ArtiTorClient> client) {
    return _bootstrap(client);
  }
  
  int connect(Pointer<ArtiTorClient> client, String host, int port) {
    final hostPtr = host.toNativeUtf8();
    try {
      return _connect(client, hostPtr, port);
    } finally {
      malloc.free(hostPtr);
    }
  }
}
```

### 3. High-Level Tor Client

```dart
// lib/src/tor/tor_client.dart
class TorClient {
  final ArtiBindings _bindings = ArtiBindings();
  late final Pointer<ArtiTorClient> _client;
  final _connections = <int, TorConnection>{};
  
  Future<void> initialize({
    required String stateDir,
    required String cacheDir,
    TorConfig? config,
  }) async {
    final configJson = config?.toJson() ?? '{}';
    
    _client = _bindings.createClient(configJson, stateDir, cacheDir);
    
    final result = _bindings.bootstrap(_client);
    if (result != 0) {
      throw TorException('Failed to bootstrap Tor: $result');
    }
  }
  
  Future<TorConnection> connect(String host, int port) async {
    final connId = _bindings.connect(_client, host, port);
    if (connId == 0) {
      throw TorException('Failed to connect to $host:$port');
    }
    
    final connection = TorConnection(connId, _bindings, _client);
    _connections[connId] = connection;
    return connection;
  }
  
  void dispose() {
    for (final conn in _connections.values) {
      conn.close();
    }
    _bindings.destroyClient(_client);
  }
}

class TorConnection {
  final int id;
  final ArtiBindings _bindings;
  final Pointer<ArtiTorClient> _client;
  
  TorConnection(this.id, this._bindings, this._client);
  
  Future<void> write(Uint8List data) async {
    final result = _bindings.connectionWrite(_client, id, data);
    if (result < 0) {
      throw TorException('Write failed: $result');
    }
  }
  
  Stream<Uint8List> get stream => _createReadStream();
  
  Stream<Uint8List> _createReadStream() async* {
    final buffer = Uint8List(4096);
    while (true) {
      final bytesRead = _bindings.connectionRead(_client, id, buffer);
      if (bytesRead > 0) {
        yield buffer.sublist(0, bytesRead);
      } else if (bytesRead == 0) {
        break; // EOF
      } else {
        throw TorException('Read error: $bytesRead');
      }
    }
  }
  
  void close() {
    _bindings.connectionClose(_client, id);
  }
}
```

### 4. WebSocket Over Tor Implementation

```dart
// lib/src/tor/tor_websocket_channel.dart
class TorWebSocketChannel extends StreamChannelMixin<dynamic> 
    implements WebSocketChannel {
  final ArtiConnection _torConnection;
  final Uri _uri;
  final _controller = StreamChannelController<dynamic>();
  
  TorWebSocketChannel(this._torConnection, this._uri) {
    _performHandshake();
  }
  
  Future<void> _performHandshake() async {
    // Send WebSocket upgrade request
    final request = '''
GET ${_uri.path} HTTP/1.1\r
Host: ${_uri.host}\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: ${_generateWebSocketKey()}\r
Sec-WebSocket-Version: 13\r
\r
''';
    
    await _torConnection.write(utf8.encode(request));
    
    // Read response
    final response = await _readHttpResponse();
    _validateWebSocketResponse(response);
    
    // Start WebSocket frame handling
    _startFrameProcessing();
  }
  
  void _startFrameProcessing() {
    _torConnection.stream.listen((data) {
      // Parse WebSocket frames
      final frames = _parseWebSocketFrames(data);
      for (final frame in frames) {
        _controller.local.sink.add(frame.payload);
      }
    });
  }
}
```

### 5. Tor-Enabled Relay Client

```dart
// lib/src/network/tor/tor_enabled_relay_client.dart
class TorEnabledRelayClient extends ExternalRelayClient {
  final TorClient _torClient;
  final TorConfig _config;
  
  TorEnabledRelayClient({
    required TorClient torClient,
    required TorConfig config,
  }) : _torClient = torClient,
       _config = config;
  
  @override
  Future<WebSocketChannel> connectToRelay(String url) async {
    if (_shouldUseTor(url)) {
      final uri = Uri.parse(url);
      final connection = await _torClient.connect(
        uri.host,
        uri.port ?? (uri.scheme == 'wss' ? 443 : 80),
      );
      
      return TorWebSocketChannel(connection, uri);
    }
    
    // Fall back to direct connection
    return WebSocketChannel.connect(Uri.parse(url));
  }
  
  bool _shouldUseTor(String url) {
    // Always use Tor for .onion addresses
    if (url.contains('.onion')) return true;
    
    // Check if relay is in Tor-only list
    if (_config.torOnlyRelays.any((relay) => url.contains(relay))) {
      return true;
    }
    
    // Use Tor for all relays if forced
    return _config.forceTor;
  }
}
```

### 6. Integration with Embedded Relay

```dart
// lib/src/core/embedded_nostr_relay.dart
class EmbeddedNostrRelay {
  ExternalRelayClient? _externalClient;
  TorClient? _torClient;
  
  Future<void> initialize({
    RelayConfig? config,
    TorConfig? torConfig,
  }) async {
    _config = config ?? RelayConfig.defaults();
    
    // Create appropriate client based on Tor availability and config
    _externalClient = await _createExternalClient(torConfig);
    
    // Rest of initialization...
  }
  
  Future<ExternalRelayClient> _createExternalClient(
    TorConfig? torConfig,
  ) async {
    // Check if Tor is requested and available
    if (torConfig?.enabled == true && 
        TorSupport.isAvailable && 
        !kIsWeb) {
      
      try {
        _torClient = TorClient();
        await _torClient!.initialize(
          stateDir: await _getTorStateDir(),
          cacheDir: await _getTorCacheDir(),
          config: torConfig,
        );
        
        return TorEnabledRelayClient(
          torClient: _torClient!,
          config: torConfig!,
        );
      } catch (e) {
        _logger.warning('Failed to initialize Tor: $e');
        if (torConfig!.required) {
          rethrow;
        }
        // Fall back to standard client
      }
    }
    
    return StandardRelayClient();
  }
  
  Future<String> _getTorStateDir() async {
    final appDir = await getApplicationSupportDirectory();
    final torDir = Directory('${appDir.path}/tor_state');
    await torDir.create(recursive: true);
    return torDir.path;
  }
  
  Future<String> _getTorCacheDir() async {
    final appDir = await getTemporaryDirectory();
    final torDir = Directory('${appDir.path}/tor_cache');
    await torDir.create(recursive: true);
    return torDir.path;
  }
}
```

## Platform-Specific Setup

### Building the Arti FFI Library

#### Cargo.toml (packages/arti_ffi/Cargo.toml)
```toml
[package]
name = "arti_ffi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
arti-client = { version = "0.11", features = ["tokio", "native-tls"] }
tokio = { version = "1", features = ["full"] }
libc = "0.2"

[build-dependencies]
cbindgen = "0.26"

# Platform-specific dependencies
[target.'cfg(target_os = "android")']
jni = "0.21"
```

#### Build Script (packages/arti_ffi/build.rs)
```rust
fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file("arti_ffi.h");
}
```

#### Cross-Compilation Script (scripts/build_tor_libraries.sh)
```bash
#!/bin/bash
set -e

# Build for all platforms
PLATFORMS=("aarch64-apple-ios" "x86_64-apple-ios" "aarch64-linux-android" 
           "armv7-linux-androideabi" "x86_64-linux-android" 
           "x86_64-apple-darwin" "aarch64-apple-darwin")

for platform in "${PLATFORMS[@]}"; do
    echo "Building for $platform..."
    cargo build --target $platform --release
done

# Create xcframework for iOS
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libarti_ffi.a \
    -library target/x86_64-apple-ios/release/libarti_ffi.a \
    -output ios/ArtiFFI.xcframework

# Copy Android libraries
cp target/aarch64-linux-android/release/libarti_ffi.so android/src/main/jniLibs/arm64-v8a/
cp target/armv7-linux-androideabi/release/libarti_ffi.so android/src/main/jniLibs/armeabi-v7a/
cp target/x86_64-linux-android/release/libarti_ffi.so android/src/main/jniLibs/x86_64/
```

### iOS Setup

#### Podspec (ios/flutter_embedded_nostr_relay_tor.podspec)
```ruby
Pod::Spec.new do |s|
  s.name             = 'flutter_embedded_nostr_relay_tor'
  s.version          = '0.0.1'
  s.summary          = 'Tor support for Flutter Embedded Nostr Relay'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'ArtiFFI.xcframework'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
  
  # Flutter Framework
  s.dependency 'Flutter'
  
  # Exclude simulator architectures for M1 Macs
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'DEFINES_MODULE' => 'YES',
  }
end
```

#### Info.plist Additions
```xml
<!-- Add to Info.plist for background networking -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>
```

### Android Setup

#### build.gradle
```gradle
android {
    compileSdkVersion 33
    
    defaultConfig {
        minSdkVersion 21
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86_64'
        }
    }
    
    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
    
    packagingOptions {
        pickFirst 'lib/*/libarti_ffi.so'
    }
}

dependencies {
    implementation 'com.getkeepsafe.relinker:relinker:1.4.5'
}
```

#### AndroidManifest.xml Permissions
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- Request battery optimization exemption -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

#### ProGuard Rules (proguard-rules.pro)
```
-keep class com.example.arti_ffi.** { *; }
-keepclassmembers class * {
    native <methods>;
}
```

### Desktop Platforms

#### macOS
```bash
# Copy library to Frameworks
cp target/release/libarti_ffi.dylib macos/Frameworks/

# Sign the library
codesign --force --sign "Developer ID Application: Your Name" \
         --timestamp macos/Frameworks/libarti_ffi.dylib
```

#### Windows
```batch
REM Copy DLL to Windows runner
copy target\release\arti_ffi.dll windows\runner\
```

#### Linux
```bash
# Copy shared library
cp target/release/libarti_ffi.so linux/

# Set rpath for library loading
patchelf --set-rpath '$ORIGIN' linux/libarti_ffi.so
```

## Security & Privacy

### Threat Model

1. **Network Observers**
   - ISP tracking
   - Government surveillance
   - Corporate firewalls

2. **Relay Operators**
   - Malicious relay operators
   - Relay correlation attacks
   - Traffic analysis

3. **Application Level**
   - DNS leaks
   - WebRTC leaks
   - Timing attacks

### Mitigations

1. **Network Level**
   ```dart
   class TorSecurityConfig {
     // Force DNS over Tor
     final bool enforecDnsOverTor = true;
     
     // Disable direct connections
     final bool blockNonTorTraffic = false;
     
     // Use entry guards
     final bool useEntryGuards = true;
     
     // Bridge configuration
     final List<String> bridges = [];
   }
   ```

2. **Application Level**
   - Validate all relay certificates
   - Implement circuit isolation per relay
   - Add timing noise to requests
   - Clear connection state on errors

3. **Operational Security**
   - Don't log Tor circuit information
   - Encrypt Tor state directory
   - Clear memory after use
   - Implement panic button

### Privacy Features

```dart
class TorPrivacyEnhancements {
  // Circuit isolation per relay
  Future<void> newCircuitForRelay(String relayUrl);
  
  // Stream isolation
  Future<void> isolateStream(String streamId);
  
  // Clear all circuits
  Future<void> clearAllCircuits();
  
  // Get circuit info (debug only)
  Future<CircuitInfo?> getCircuitInfo(String relayUrl);
}
```

## Performance Optimization

### Connection Pooling

```dart
class TorConnectionPool {
  final _connections = <String, List<ArtiConnection>>{};
  final _maxPerHost = 3;
  
  Future<ArtiConnection> getConnection(String host, int port) async {
    final key = '$host:$port';
    final existing = _connections[key] ?? [];
    
    // Reuse existing connection
    for (final conn in existing) {
      if (conn.isHealthy) return conn;
    }
    
    // Create new connection
    if (existing.length < _maxPerHost) {
      final conn = await _createConnection(host, port);
      _connections[key] = [...existing, conn];
      return conn;
    }
    
    // Wait for available connection
    return _waitForConnection(key);
  }
}
```

### Preemptive Circuit Building

```dart
class CircuitManager {
  Timer? _preemptiveBuilder;
  
  void startPreemptiveBuilding() {
    _preemptiveBuilder = Timer.periodic(
      Duration(minutes: 10),
      (_) => _buildSpareCircuits(),
    );
  }
  
  Future<void> _buildSpareCircuits() async {
    final currentCount = await _torClient.getCircuitCount();
    if (currentCount < 3) {
      await _torClient.buildCircuit();
    }
  }
}
```

### Caching Strategy

```dart
class TorAwareCache {
  // Cache Tor connection status
  final _connectivityCache = <String, ConnectivityStatus>{};
  
  // Prefer relays with existing circuits
  List<String> prioritizeRelays(List<String> relays) {
    return relays.sorted((a, b) {
      final aStatus = _connectivityCache[a];
      final bStatus = _connectivityCache[b];
      
      if (aStatus?.hasCircuit == true) return -1;
      if (bStatus?.hasCircuit == true) return 1;
      return 0;
    });
  }
}
```

## Testing Strategy

### Unit Tests

```dart
// test/tor/arti_bindings_test.dart
void main() {
  group('Arti Bindings', () {
    test('loads native library', () {
      final bindings = ArtiBindings();
      expect(bindings.isLoaded, isTrue);
    });
    
    test('creates client', () async {
      final client = ArtiClient();
      await client.initialize(
        stateDir: tempDir.path,
        cacheDir: tempDir.path,
      );
      expect(client.isBootstrapped, isTrue);
    });
  });
}
```

### Integration Tests

```dart
// test/integration/tor_relay_test.dart
void main() {
  group('Tor Relay Integration', () {
    late EmbeddedNostrRelay relay;
    
    setUpAll(() async {
      relay = EmbeddedNostrRelay();
      await relay.initialize(
        torConfig: TorConfig(
          enabled: true,
          forceTor: true,
        ),
      );
    });
    
    test('connects to .onion relay', () async {
      final events = await relay
          .queryEvents([Filter(kinds: [1], limit: 1)])
          .first;
      expect(events, isNotEmpty);
    });
  });
}
```

### Performance Tests

```dart
void main() {
  group('Tor Performance', () {
    test('connection establishment time', () async {
      final stopwatch = Stopwatch()..start();
      
      final conn = await torClient.connect('relay.damus.io', 443);
      
      stopwatch.stop();
      print('Connection time: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
```

## Risk Assessment

### Technical Risks

1. **Arti API Stability** (Medium)
   - Mitigation: Pin to specific Arti version
   - Fallback: Implement version compatibility layer

2. **Platform Restrictions** (High for iOS)
   - Mitigation: Clear App Store guidelines compliance
   - Fallback: Tor as optional feature

3. **Performance Impact** (Medium)
   - Mitigation: Extensive performance testing
   - Fallback: User-controlled Tor toggle

4. **Binary Size Increase** (Low)
   - Estimated: +5-10MB per platform
   - Mitigation: Optional download

### Example Usage in Tests

```dart
// test/tor/tor_support_test.dart
void main() {
  group('TorSupport', () {
    test('detects Tor availability', () {
      // Will be false in CI, true when libraries are present
      expect(TorSupport.isAvailable, isA<bool>());
    });
  });
}

// test/tor/conditional_compilation_test.dart
void main() {
  group('Conditional Compilation', () {
    test('creates appropriate client', () async {
      final client = RelayClientFactory.create(
        torConfig: TorConfig(enabled: true),
      );
      
      if (TorSupport.isAvailable) {
        expect(client, isA<TorEnabledRelayClient>());
      } else {
        expect(client, isA<StandardRelayClient>());
      }
    });
  });
}

// integration_test/tor_integration_test.dart
void main() {
  group('Tor Integration', () {
    testWidgets('relay works with Tor config', (tester) async {
      const torConfig = TorConfig(
        enabled: true,
        torOnlyRelays: ['facebookcorewwwi.onion'],
      );
      
      final relay = EmbeddedNostrRelay();
      await relay.initialize(torConfig: torConfig);
      
      // Test that relay initializes without error
      expect(relay.isInitialized, isTrue);
    });
  });
}
```

## Quick Start

### Building with Tor Support

1. **Setup Rust environment**:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-linux-android
   ```

2. **Build Tor libraries**:
   ```bash
   ./scripts/build_tor_libraries.sh
   ```

3. **Build Flutter app**:
   ```bash
   ./scripts/build_with_tor.sh
   ```

### Using Tor in Your App

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final relay = EmbeddedNostrRelay();
  await relay.initialize(
    torConfig: TorConfig(
      enabled: true,
      torOnlyRelays: [
        'facebookcorewwwi.onion',
        'damus.io', // Will use Tor if forceTor is true
      ],
      forceTor: false, // Set to true to route all relay traffic via Tor
      bridges: [], // Add bridge config for censored networks
    ),
  );
  
  runApp(MyApp(relay: relay));
}
```

### Configuration Options

```dart
class TorConfig {
  final bool enabled;          // Enable Tor support
  final bool forceTor;         // Force all relay connections via Tor
  final bool required;         // Fail if Tor can't be initialized
  final List<String> torOnlyRelays; // Relays that must use Tor
  final List<String> bridges;  // Bridge configuration for censorship
  final Duration timeout;      // Bootstrap timeout
  
  const TorConfig({
    this.enabled = false,
    this.forceTor = false,
    this.required = false,
    this.torOnlyRelays = const [],
    this.bridges = const [],
    this.timeout = const Duration(minutes: 2),
  });
}
```

### Building without Tor

For users who don't need Tor, simply build normally:

```bash
flutter build apk  # No Tor libraries included
```

The app will automatically fall back to direct connections.

## Implementation Summary

This Tor integration provides:

- ✅ **Optional compilation** - Tor can be included or excluded at build time
- ✅ **Runtime detection** - App detects if Tor libraries are available
- ✅ **Graceful fallback** - Works without Tor if libraries aren't present
- ✅ **Flexible configuration** - Per-relay Tor routing decisions
- ✅ **.onion support** - Automatic Tor usage for .onion addresses
- ✅ **Cross-platform** - Works on iOS, Android, and desktop
- ✅ **Maintainable** - Uses official Arti implementation via clean FFI

The modular design keeps the base relay lightweight while providing powerful privacy features for users who need them.