# Troubleshooting Guide

This guide helps you diagnose and fix common issues with Flutter Embedded Nostr Relay.

## Common Issues

### Installation Issues

#### Package Resolution Errors

**Problem**: `flutter pub get` fails with version conflicts

```
Because flutter_embedded_nostr_relay depends on sqlite3 ^2.0.0...
```

**Solution**:
```yaml
# Add dependency overrides in pubspec.yaml
dependency_overrides:
  sqlite3: ^2.0.0
  sqlite3_flutter_libs: ^0.5.0
```

#### Platform-Specific Build Errors

**Problem**: Build fails on specific platforms

**Solutions**:

iOS:
```bash
cd ios
pod install --repo-update
```

Android:
```gradle
// In android/app/build.gradle
android {
    compileSdkVersion 33
    
    defaultConfig {
        minSdkVersion 21 // Minimum for SQLite
    }
}
```

### Initialization Errors

#### "Relay not initialized" Error

**Problem**: Methods fail with initialization error

```dart
// ❌ Wrong
final relay = EmbeddedNostrRelay();
await relay.publish(event); // Error!

// ✅ Correct
final relay = EmbeddedNostrRelay();
await relay.initialize();
await relay.publish(event);
```

#### Database Initialization Failures

**Problem**: Database fails to initialize

**Solution**:
```dart
try {
  await relay.initialize();
} catch (e) {
  if (e.toString().contains('database')) {
    // Clear corrupted database
    await relay.resetDatabase();
    await relay.initialize();
  }
}
```

### Event Issues

#### Invalid Event Signatures

**Problem**: Events rejected with "invalid signature"

**Debugging**:
```dart
// Verify event manually
final event = NostrEvent.create(
  pubkey: pubkey,
  kind: 1,
  content: 'Test',
  tags: [],
).sign(privateKey);

print('Event ID: ${event.id}');
print('Is valid: ${event.isValid}');

// Check key pair
final derivedPubkey = NostrCrypto.getPublicKey(privateKey);
print('Pubkey matches: ${derivedPubkey == pubkey}');
```

#### Events Not Appearing

**Problem**: Published events don't show in subscriptions

**Checklist**:
```dart
// 1. Check filters match
final filter = Filter(kinds: [1], authors: [pubkey]);
print('Filter would match: ${filter.matches(event)}');

// 2. Check subscription is active
print('Active subscriptions: ${relay.activeSubscriptionCount}');

// 3. Check for EOSE
subscription.onEose = () {
  print('End of stored events reached');
};

// 4. Enable debug logging
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) {
  print('${record.level}: ${record.message}');
});
```

### Subscription Issues

#### No Events Received

**Problem**: Subscriptions don't receive any events

**Debug Steps**:
```dart
// Test with broad filter first
final testSub = relay.subscribe(
  filters: [Filter(limit: 10)], // Get any 10 events
  onEvent: (event) {
    print('Received: ${event.id}');
  },
  onEose: () {
    print('EOSE - no stored events match');
  },
  onError: (error) {
    print('Subscription error: $error');
  },
);

// Check event count
final stats = await relay.getStats();
print('Total events in database: ${stats['events']}');
```

#### Subscription Limits

**Problem**: "Too many subscriptions" error

**Solution**:
```dart
// Close unused subscriptions
final oldSubscription = subscriptions[userId];
await oldSubscription?.close();

// Or increase limits
await relay.setResourceLimits(
  ResourceLimits(
    maxSubscriptionsPerClient: 20,
  ),
);
```

### P2P Sync Issues

#### Peers Not Discovering

**Problem**: No peers found during P2P discovery

**Checklist**:
1. **Permissions granted**:
```dart
// Check permissions (using permission_handler)
final bluetoothStatus = await Permission.bluetooth.status;
final locationStatus = await Permission.location.status;

if (!bluetoothStatus.isGranted || !locationStatus.isGranted) {
  await [Permission.bluetooth, Permission.location].request();
}
```

2. **Bluetooth/WiFi enabled**:
```dart
// Check if Bluetooth is on
final isBluetoothOn = await FlutterBluePlus.isOn;
if (!isBluetoothOn) {
  print('Please enable Bluetooth');
}
```

3. **Same network** (for WiFi Direct):
```dart
// Ensure devices are on same network
print('Local IP: ${await getLocalIP()}');
```

#### Sync Failures

**Problem**: P2P sync starts but fails

**Debug**:
```dart
// Enable detailed P2P logging
Logger('P2PTransport').level = Level.ALL;
Logger('Negentropy').level = Level.ALL;

// Monitor sync progress
relay.enableP2PSync(
  onSyncProgress: (peer, progress) {
    print('Sync ${progress.percent}%: ${progress.status}');
  },
  onSyncError: (peer, error) {
    print('Sync error with ${peer.name}: $error');
  },
);
```

### Network Issues

#### WebSocket Connection Failures

**Problem**: Can't connect to external relays

**Debug**:
```dart
// Test connectivity
relay.onRelayConnecting = (url) {
  print('Connecting to $url...');
};

relay.onRelayConnected = (url) {
  print('Connected to $url');
};

relay.onRelayError = (error) {
  print('Relay error: ${error.url} - ${error.message}');
  
  // Common issues:
  if (error.message.contains('certificate')) {
    print('SSL certificate issue');
  } else if (error.message.contains('timeout')) {
    print('Connection timeout - check network');
  }
};
```

#### Tor Connection Issues

**Problem**: Tor doesn't work

**Checklist**:
```dart
// 1. Check Tor support
print('Tor available: ${TorSupport.isAvailable}');

// 2. Check library loading
try {
  TorSupport.loadLibrary();
  print('Tor library loaded successfully');
} catch (e) {
  print('Tor library error: $e');
}

// 3. Enable Tor debug logging
Logger('TorSupport').level = Level.ALL;

// 4. Test Tor connection
if (TorSupport.isAvailable) {
  await relay.setTorForRelays(true);
  await relay.addExternalRelay('wss://relay.onion');
}
```

### Performance Issues

#### Slow Queries

**Problem**: Event queries take too long

**Solutions**:
```dart
// 1. Add appropriate limits
final events = await relay.queryEvents([
  Filter(
    kinds: [1],
    authors: followedUsers,
    limit: 50, // Don't query everything
    since: recentTimestamp, // Time bounds
  ),
]);

// 2. Check indexes
await relay.analyzeDatabase();

// 3. Enable query profiling
relay.onSlowQuery = (query, duration) {
  print('Slow query (${duration.inMs}ms): $query');
};
```

#### High Memory Usage

**Problem**: App uses too much memory

**Solutions**:
```dart
// 1. Limit cached data
await relay.setMemoryLimits(
  MemoryLimits(
    maxCachedEvents: 1000,
    maxSubscriptionBuffer: 100,
  ),
);

// 2. Enable garbage collection
await relay.setGarbageCollectionPolicy(
  GarbageCollectionPolicy(
    retentionPeriod: Duration(days: 30),
    runInterval: Duration(hours: 12),
  ),
);

// 3. Use stream processing
relay.queryEventsAsStream(filters).listen(
  processEvent,
  onDone: () => print('Processing complete'),
);
```

### Platform-Specific Issues

#### iOS Background Execution

**Problem**: Relay stops working in background

**Solution**:
```swift
// In AppDelegate.swift
func application(_ application: UIApplication,
                performFetchWithCompletionHandler completionHandler:
                @escaping (UIBackgroundFetchResult) -> Void) {
    // Trigger relay background sync
    FlutterEmbeddedNostrRelay.performBackgroundSync { result in
        completionHandler(result)
    }
}
```

#### Android Battery Optimization

**Problem**: Android kills the app

**Solution**:
```xml
<!-- In AndroidManifest.xml -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
```

```dart
// Request exemption
if (Platform.isAndroid) {
  await requestBatteryOptimizationExemption();
}
```

#### Web Database Limits

**Problem**: Web storage quota exceeded

**Solution**:
```dart
// Monitor storage usage
if (kIsWeb) {
  final usage = await relay.getStorageUsage();
  if (usage.percent > 80) {
    // Clean up old data
    await relay.runGarbageCollection();
  }
}
```

## Debugging Tools

### Enable Comprehensive Logging

```dart
void setupDebugLogging() {
  // Set root logger level
  Logger.root.level = Level.ALL;
  
  // Configure output
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String();
    final level = record.level.name;
    final logger = record.loggerName;
    final message = record.message;
    
    debugPrint('$time [$level] $logger: $message');
    
    if (record.error != null) {
      debugPrint('  Error: ${record.error}');
      debugPrint('  Stack: ${record.stackTrace}');
    }
  });
  
  // Enable specific loggers
  Logger('EventStore').level = Level.ALL;
  Logger('SubscriptionManager').level = Level.ALL;
  Logger('RelayClient').level = Level.ALL;
  Logger('P2PTransport').level = Level.ALL;
}
```

### Database Inspector

```dart
class DatabaseInspector {
  final EmbeddedNostrRelay relay;
  
  Future<void> inspectDatabase() async {
    // Get table info
    final tables = await relay.getDatabaseTables();
    for (final table in tables) {
      print('Table: $table');
      final count = await relay.getTableRowCount(table);
      print('  Rows: $count');
    }
    
    // Check indexes
    final indexes = await relay.getDatabaseIndexes();
    for (final index in indexes) {
      print('Index: ${index.name} on ${index.table}');
    }
    
    // Analyze query performance
    final stats = await relay.getQueryStatistics();
    print('Slowest queries:');
    for (final query in stats.slowestQueries) {
      print('  ${query.sql} - ${query.averageMs}ms');
    }
  }
}
```

### Network Monitor

```dart
class NetworkMonitor {
  void monitorRelayConnections(EmbeddedNostrRelay relay) {
    // Connection events
    relay.onRelayConnecting = (url) {
      print('[CONNECTING] $url');
    };
    
    relay.onRelayConnected = (url) {
      print('[CONNECTED] $url');
    };
    
    relay.onRelayDisconnected = (url, reason) {
      print('[DISCONNECTED] $url: $reason');
    };
    
    // Message events
    relay.onRelayMessageSent = (url, message) {
      print('[SENT->$url] $message');
    };
    
    relay.onRelayMessageReceived = (url, message) {
      print('[RECV<-$url] $message');
    };
    
    // Error events
    relay.onRelayError = (error) {
      print('[ERROR] ${error.url}: ${error.message}');
    };
  }
}
```

## Error Recovery

### Automatic Recovery

```dart
class RelayRecovery {
  final EmbeddedNostrRelay relay;
  
  void setupAutoRecovery() {
    // Database corruption recovery
    relay.onDatabaseError = (error) async {
      if (error.isCorruption) {
        print('Database corrupted, attempting recovery...');
        await relay.recoverDatabase();
      }
    };
    
    // Network recovery
    relay.onNetworkError = (error) async {
      if (error.isTimeout) {
        print('Network timeout, retrying...');
        await Future.delayed(Duration(seconds: 5));
        await relay.reconnectAllRelays();
      }
    };
    
    // P2P recovery
    relay.onP2PError = (error) async {
      if (error.isConnectionLost) {
        print('P2P connection lost, restarting...');
        await relay.restartP2PSync();
      }
    };
  }
}
```

## Getting Help

### Collect Diagnostic Information

```dart
Future<String> collectDiagnostics(EmbeddedNostrRelay relay) async {
  final buffer = StringBuffer();
  
  buffer.writeln('=== Flutter Embedded Nostr Relay Diagnostics ===');
  buffer.writeln('Version: ${relay.version}');
  buffer.writeln('Platform: ${Platform.operatingSystem}');
  buffer.writeln('Dart: ${Platform.version}');
  
  final stats = await relay.getStats();
  buffer.writeln('\nDatabase Stats:');
  buffer.writeln('  Events: ${stats['events']}');
  buffer.writeln('  Size: ${stats['databaseSize']}');
  
  final relays = await relay.getConfiguredRelays();
  buffer.writeln('\nRelays: ${relays.length}');
  for (final relay in relays) {
    buffer.writeln('  ${relay.url}: ${relay.status}');
  }
  
  return buffer.toString();
}
```

### Report Issues

When reporting issues:

1. **Check existing issues**: [GitHub Issues](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues)
2. **Provide diagnostics**: Run diagnostic collection
3. **Include reproduction**: Minimal code to reproduce
4. **Specify versions**: Flutter, Dart, package versions

### Community Support

- **Discussions**: [GitHub Discussions](https://github.com/OpenVine/flutter_embedded_nostr_relay/discussions)
- **Nostr**: Follow development on Nostr
- **Example App**: Check the example for working implementations

## Next Steps

- Review [Security Best Practices](security.md)
- Learn about [Performance Optimization](performance.md)
- Explore the [Example App](../example/)