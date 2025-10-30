# Security Best Practices

Security is paramount when building Nostr applications. This guide covers security considerations and best practices for Flutter Embedded Nostr Relay.

## Overview

Key security features:
- **Event signature validation** - All events are cryptographically verified
- **Input sanitization** - Protection against injection attacks
- **Secure storage** - Encrypted database options
- **Network security** - TLS/SSL and optional Tor support
- **Access control** - Client authentication and rate limiting

## Event Security

### 1. Signature Validation

All events are automatically validated:

```dart
// Automatic validation on publish
final event = NostrEvent.create(
  pubkey: userPubkey,
  kind: 1,
  content: 'Hello Nostr!',
  tags: [],
).sign(privateKey);

// The relay validates the signature
final success = await relay.publish(event);
if (!success) {
  print('Invalid event signature or duplicate');
}

// Manual validation
if (event.isValid) {
  print('Event signature is valid');
}
```

### 2. Event Sanitization

Protect against malicious content:

```dart
await relay.setSanitizationPolicy(
  SanitizationPolicy(
    // Remove dangerous HTML/scripts
    sanitizeHtml: true,
    
    // Validate URLs
    validateUrls: true,
    
    // Check event size limits
    maxEventSize: 64 * 1024, // 64KB
    
    // Validate timestamps
    maxTimeDrift: Duration(minutes: 10),
    
    // Block events too far in future
    rejectFutureEvents: true,
    maxFutureTime: Duration(hours: 1),
  ),
);
```

### 3. Content Filtering

Implement content filtering:

```dart
// Set up content filters
await relay.setContentFilters([
  // Block spam patterns
  ContentFilter(
    type: FilterType.regex,
    pattern: r'(viagra|casino|lottery)',
    action: FilterAction.reject,
  ),
  
  // Rate limit similar content
  ContentFilter(
    type: FilterType.similarity,
    threshold: 0.95,
    window: Duration(minutes: 1),
    action: FilterAction.rateLimit,
  ),
]);

// Custom content validator
relay.setContentValidator((event) {
  // Your custom validation logic
  if (isSpam(event)) {
    return ValidationResult.reject('Spam detected');
  }
  return ValidationResult.accept();
});
```

## Key Management

### 1. Secure Key Storage

Never store private keys in plain text:

```dart
// ❌ Never do this
final privateKey = "nsec1..."; // Stored in code

// ✅ Use secure storage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyManager {
  final _storage = FlutterSecureStorage();
  
  Future<void> savePrivateKey(String key) async {
    await _storage.write(
      key: 'nostr_private_key',
      value: key,
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: IOSAccessibility.first_unlock_this_device,
      ),
    );
  }
  
  Future<String?> getPrivateKey() async {
    return await _storage.read(key: 'nostr_private_key');
  }
  
  Future<void> deletePrivateKey() async {
    await _storage.delete(key: 'nostr_private_key');
  }
}
```

### 2. Key Derivation

Use proper key derivation:

```dart
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;

class NostrKeyDerivation {
  // Generate mnemonic
  static String generateMnemonic() {
    return bip39.generateMnemonic(strength: 256);
  }
  
  // Derive Nostr key from mnemonic
  static String derivePrivateKey(String mnemonic, {int index = 0}) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    
    // Nostr derivation path: m/44'/1237'/0'/0/0
    final node = root.derivePath("m/44'/1237'/0'/0/$index");
    
    return node.privateKey!.map((b) => 
      b.toRadixString(16).padLeft(2, '0')).join();
  }
}
```

### 3. Key Rotation

Implement key rotation policies:

```dart
class KeyRotationManager {
  Future<void> rotateKeys() async {
    // Generate new keypair
    final newPrivateKey = NostrCrypto.generatePrivateKey();
    final newPublicKey = NostrCrypto.getPublicKey(newPrivateKey);
    
    // Publish key rotation event (custom kind)
    final rotationEvent = NostrEvent.create(
      pubkey: oldPublicKey,
      kind: 13, // Key rotation event
      content: jsonEncode({
        'new_pubkey': newPublicKey,
        'rotation_timestamp': DateTime.now().toIso8601String(),
      }),
      tags: [['p', newPublicKey]],
    ).sign(oldPrivateKey);
    
    await relay.publish(rotationEvent);
    
    // Update stored keys
    await secureStorage.savePrivateKey(newPrivateKey);
  }
}
```

## Database Security

### 1. Encryption at Rest

Enable database encryption:

```dart
await relay.initialize(
  databaseConfig: DatabaseConfig(
    // Enable encryption
    enableEncryption: true,
    
    // Encryption key (derive from user password)
    encryptionKey: await deriveKey(userPassword),
    
    // Use SQLCipher on supported platforms
    useSQLCipher: true,
  ),
);

// Key derivation from password
Future<String> deriveKey(String password) async {
  final salt = await SecureStorage.read(key: 'db_salt') ?? 
    await generateAndStoreSalt();
  
  return pbkdf2(password, salt, iterations: 100000);
}
```

### 2. Access Control

Implement database access control:

```dart
// Per-user database isolation
final userRelay = EmbeddedNostrRelay();
await userRelay.initialize(
  databaseConfig: DatabaseConfig(
    // Unique database per user
    databaseName: 'nostr_${userPublicKey.substring(0, 8)}.db',
    
    // Restrict file permissions
    filePermissions: 0x600, // rw-------
  ),
);
```

### 3. Secure Deletion

Properly delete sensitive data:

```dart
// Secure event deletion
await relay.secureDelete(
  eventIds: sensitiveEventIds,
  options: SecureDeleteOptions(
    // Overwrite data before deletion
    overwritePasses: 3,
    
    // Vacuum database after deletion
    vacuumAfterDelete: true,
  ),
);

// Complete database wipe
await relay.secureWipeDatabase(
  confirmation: 'DELETE_EVERYTHING',
  options: WipeOptions(
    overwritePasses: 7,
    deleteBackups: true,
  ),
);
```

## Network Security

### 1. Transport Security

Ensure secure connections:

```dart
await relay.setNetworkSecurity(
  NetworkSecurityConfig(
    // Require TLS for all connections
    requireTLS: true,
    minTLSVersion: '1.2',
    
    // Certificate pinning
    certificatePins: {
      'relay.example.com': [
        'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      ],
    },
    
    // Validate certificates
    validateCertificates: true,
    allowSelfSignedCerts: false,
  ),
);
```

### 2. Tor Integration

Use Tor for enhanced privacy:

```dart
if (TorSupport.isAvailable) {
  await relay.updateTorConfig(
    TorConfig(
      enabled: true,
      forceTor: true, // Require Tor for all connections
      
      // Use bridges in censored regions
      bridges: [
        'Bridge obfs4 ...',
      ],
      
      // Isolate circuits per relay
      isolateCircuits: true,
    ),
  );
}
```

### 3. Rate Limiting

Protect against abuse:

```dart
await relay.setRateLimiting(
  RateLimitConfig(
    // Global limits
    maxEventsPerMinute: 60,
    maxSubscriptionsPerClient: 10,
    maxFiltersPerSubscription: 10,
    
    // Per-client limits
    perClientLimits: {
      'maxEventsPerMinute': 30,
      'maxDataPerMinute': 1024 * 1024, // 1MB
    },
    
    // Burst allowance
    burstMultiplier: 2.0,
    
    // Ban duration for violations
    banDuration: Duration(minutes: 15),
  ),
);
```

## Client Authentication

### 1. NIP-42 Authentication

Implement relay authentication:

```dart
await relay.enableAuthentication(
  AuthConfig(
    // Require authentication
    requireAuth: true,
    
    // Challenge-response timeout
    challengeTimeout: Duration(minutes: 1),
    
    // Allowed public keys
    whitelist: trustedPubkeys,
    
    // Custom auth validator
    validator: (pubkey, signature, challenge) async {
      // Verify signature
      if (!verifyAuthSignature(pubkey, signature, challenge)) {
        return AuthResult.reject('Invalid signature');
      }
      
      // Check additional criteria
      if (await isUserBanned(pubkey)) {
        return AuthResult.reject('User banned');
      }
      
      return AuthResult.accept();
    },
  ),
);
```

### 2. Access Control Lists

Implement fine-grained permissions:

```dart
await relay.setAccessControl(
  AccessControlConfig(
    // Default permissions
    defaultPermissions: Permissions(
      canRead: true,
      canWrite: false,
      canDelete: false,
    ),
    
    // User-specific permissions
    userPermissions: {
      adminPubkey: Permissions.all(),
      moderatorPubkey: Permissions(
        canRead: true,
        canWrite: true,
        canDelete: true,
        canBan: true,
      ),
    },
    
    // Event-based permissions
    eventPermissions: (event) {
      // Only author can delete their events
      if (event.pubkey == currentUser) {
        return Permissions(canDelete: true);
      }
      return Permissions.readOnly();
    },
  ),
);
```

## Privacy Protection

### 1. Metadata Protection

Minimize metadata leakage:

```dart
await relay.setPrivacyConfig(
  PrivacyConfig(
    // Don't leak viewer information
    hideViewerMetadata: true,
    
    // Randomize request timing
    randomizeRequestTiming: true,
    timingJitter: Duration(milliseconds: 500),
    
    // Batch requests to hide patterns
    batchRequests: true,
    batchWindow: Duration(seconds: 5),
    
    // Fake traffic to obscure real requests
    generateCoverTraffic: true,
  ),
);
```

### 2. Query Privacy

Protect query patterns:

```dart
// Use private information retrieval
final events = await relay.privateQuery(
  filters: sensitiveFilters,
  options: PrivateQueryOptions(
    // Use multiple relays to obscure queries
    distributeQueries: true,
    minRelays: 3,
    
    // Add noise queries
    noiseQueries: 5,
    
    // Delay correlation
    randomDelay: Duration(seconds: 2),
  ),
);
```

## Security Monitoring

### 1. Audit Logging

Log security events:

```dart
await relay.enableAuditLogging(
  AuditConfig(
    // What to log
    logEvents: [
      AuditEventType.authentication,
      AuditEventType.authorization,
      AuditEventType.dataAccess,
      AuditEventType.configChange,
    ],
    
    // Log retention
    retentionPeriod: Duration(days: 90),
    
    // Secure log storage
    encryptLogs: true,
    
    // Real-time alerts
    alertHandler: (event) {
      if (event.severity == Severity.critical) {
        sendSecurityAlert(event);
      }
    },
  ),
);
```

### 2. Intrusion Detection

Detect suspicious activity:

```dart
await relay.enableIntrusionDetection(
  IntrusionDetectionConfig(
    // Detection rules
    rules: [
      // Rapid authentication failures
      DetectionRule(
        type: RuleType.authFailures,
        threshold: 5,
        window: Duration(minutes: 5),
        action: RuleAction.blockIP,
      ),
      
      // Unusual query patterns
      DetectionRule(
        type: RuleType.queryAnomaly,
        sensitivity: 0.8,
        action: RuleAction.alert,
      ),
    ],
    
    // Response actions
    responseHandler: (detection) async {
      switch (detection.severity) {
        case Severity.critical:
          await blockClient(detection.clientId);
          await notifyAdmin(detection);
          break;
        case Severity.warning:
          await logSecurityEvent(detection);
          break;
      }
    },
  ),
);
```

## Security Checklist

### Configuration
- [ ] Enable event signature validation
- [ ] Set appropriate content filters
- [ ] Configure rate limiting
- [ ] Enable audit logging

### Key Management
- [ ] Use secure key storage
- [ ] Implement key derivation
- [ ] Plan for key rotation
- [ ] Never log private keys

### Database
- [ ] Enable encryption at rest
- [ ] Set proper file permissions
- [ ] Implement secure deletion
- [ ] Regular backups with encryption

### Network
- [ ] Require TLS connections
- [ ] Consider Tor integration
- [ ] Implement certificate pinning
- [ ] Monitor for anomalies

### Privacy
- [ ] Minimize metadata leakage
- [ ] Protect query patterns
- [ ] Consider cover traffic
- [ ] Respect user privacy settings

## Example: Secure Relay Setup

```dart
class SecureNostrApp extends StatefulWidget {
  @override
  _SecureNostrAppState createState() => _SecureNostrAppState();
}

class _SecureNostrAppState extends State<SecureNostrApp> {
  final relay = EmbeddedNostrRelay();
  final keyManager = SecureKeyManager();
  
  @override
  void initState() {
    super.initState();
    _initializeSecureRelay();
  }
  
  Future<void> _initializeSecureRelay() async {
    // Initialize with security features
    await relay.initialize(
      config: RelayConfig(
        // Enable all security features
        enableSignatureValidation: true,
        enableContentFiltering: true,
        enableRateLimiting: true,
        enableAuditLogging: true,
        
        // Database encryption
        databaseConfig: DatabaseConfig(
          enableEncryption: true,
          encryptionKey: await _getDatabaseKey(),
        ),
      ),
    );
    
    // Configure security policies
    await relay.setSanitizationPolicy(
      SanitizationPolicy(
        sanitizeHtml: true,
        validateUrls: true,
        maxEventSize: 64 * 1024,
      ),
    );
    
    await relay.setRateLimiting(
      RateLimitConfig(
        maxEventsPerMinute: 60,
        maxSubscriptionsPerClient: 10,
      ),
    );
    
    // Enable Tor if available
    if (TorSupport.isAvailable) {
      await relay.setTorForRelays(true);
    }
    
    // Start security monitoring
    await relay.enableIntrusionDetection(
      IntrusionDetectionConfig(
        rules: defaultSecurityRules,
        responseHandler: handleSecurityEvent,
      ),
    );
  }
  
  Future<String> _getDatabaseKey() async {
    // Derive key from user authentication
    final userAuth = await authenticateUser();
    return deriveKey(userAuth.password);
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SecureNostrHome(relay: relay),
    );
  }
}
```

## Next Steps

- Review [Performance Optimization](performance.md)
- Learn about [Troubleshooting](troubleshooting.md)
- Understand [NIP Implementation](nip-implementation.md)