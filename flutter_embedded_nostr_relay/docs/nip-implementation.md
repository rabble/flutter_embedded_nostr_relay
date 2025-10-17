# NIP Implementation Guide

This guide covers which Nostr Implementation Possibilities (NIPs) are supported by Flutter Embedded Nostr Relay and how to use them.

## Supported NIPs

### Core Protocol

#### NIP-01: Basic Protocol Flow
**Status**: ✅ Fully Supported

The foundation of Nostr protocol:
```dart
// Event creation and signing
final event = NostrEvent.create(
  pubkey: userPubkey,
  kind: 1,
  content: 'Hello Nostr!',
  tags: [
    ['e', replyToEventId],
    ['p', mentionedPubkey],
  ],
).sign(privateKey);

// Publishing
await relay.publish(event);

// Subscribing
final subscription = relay.subscribe(
  filters: [
    Filter(
      kinds: [0, 1],
      authors: [userPubkey],
      since: timestamp,
      limit: 100,
    ),
  ],
  onEvent: (event) => handleEvent(event),
);
```

#### NIP-02: Contact List and Petnames
**Status**: ✅ Fully Supported

Manage user contacts:
```dart
// Publish contact list
final contactList = NostrEvent.create(
  pubkey: myPubkey,
  kind: 3,
  content: '',
  tags: [
    ['p', alicePubkey, 'wss://alice.relay', 'Alice'],
    ['p', bobPubkey, 'wss://bob.relay', 'Bob'],
  ],
).sign(privateKey);

await relay.publish(contactList);

// Query contacts
final contacts = await relay.queryEvents([
  Filter(kinds: [3], authors: [myPubkey], limit: 1),
]);
```

#### NIP-09: Event Deletion
**Status**: ✅ Fully Supported

Delete events:
```dart
// Create deletion event
final deletion = NostrEvent.create(
  pubkey: myPubkey,
  kind: 5,
  content: 'Deleted by author',
  tags: [
    ['e', eventIdToDelete],
  ],
).sign(privateKey);

await relay.publish(deletion);
```

### Event Types

#### NIP-16: Event Treatment
**Status**: ✅ Fully Supported

Replaceable and ephemeral events:
```dart
// Replaceable event (10000-19999)
final replaceableEvent = NostrEvent.create(
  pubkey: myPubkey,
  kind: 10002, // Relay list metadata
  content: '',
  tags: [
    ['r', 'wss://relay.example.com'],
  ],
).sign(privateKey);

// Parameterized replaceable (30000-39999)
final article = NostrEvent.create(
  pubkey: myPubkey,
  kind: 30023, // Long-form content
  content: 'Article content...',
  tags: [
    ['d', 'my-article-slug'],
    ['title', 'My Article'],
  ],
).sign(privateKey);
```

### Relay Features

#### NIP-11: Relay Information Document
**Status**: ✅ Fully Supported

Relay information endpoint:
```dart
// Configure relay information
await relay.setRelayInformation(
  RelayInformation(
    name: 'My Embedded Relay',
    description: 'A relay running inside Flutter',
    pubkey: relayPubkey,
    contact: 'admin@example.com',
    supportedNips: [1, 2, 9, 11, 16, 33, 40, 42, 65],
    software: 'flutter_embedded_nostr_relay',
    version: '0.1.0',
    limitation: RelayLimitation(
      maxMessageLength: 65536,
      maxSubscriptions: 100,
      maxFilters: 10,
      maxLimit: 5000,
      maxSubidLength: 256,
      minPowDifficulty: 0,
      authRequired: false,
      paymentRequired: false,
    ),
  ),
);
```

#### NIP-33: Parameterized Replaceable Events
**Status**: ✅ Fully Supported

Advanced replaceable events:
```dart
// Create a wiki page (replaceable by d-tag)
final wikiPage = NostrEvent.create(
  pubkey: myPubkey,
  kind: 30818, // Wiki article
  content: 'Page content...',
  tags: [
    ['d', 'bitcoin-whitepaper'], // Unique identifier
    ['title', 'Bitcoin: A Peer-to-Peer Electronic Cash System'],
    ['published_at', '${DateTime.now().millisecondsSinceEpoch ~/ 1000}'],
  ],
).sign(privateKey);

// Query by d-tag
final pages = await relay.queryEvents([
  Filter(
    kinds: [30818],
    authors: [myPubkey],
    tags: {'d': ['bitcoin-whitepaper']},
  ),
]);
```

#### NIP-40: Expiration Timestamp
**Status**: ✅ Fully Supported

Set event expiration:
```dart
// Create expiring event
final expiringEvent = NostrEvent.create(
  pubkey: myPubkey,
  kind: 1,
  content: 'This message will self-destruct',
  tags: [
    ['expiration', '${DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000}'],
  ],
).sign(privateKey);

// Relay automatically removes expired events
```

#### NIP-42: Authentication of Clients to Relays
**Status**: ✅ Fully Supported

Client authentication:
```dart
// Enable authentication
await relay.enableAuthentication(
  AuthConfig(
    requireAuth: true,
    challengeTimeout: Duration(minutes: 1),
  ),
);

// Handle authentication as client
relay.onAuthChallenge = (challenge) async {
  // Create auth event
  final authEvent = NostrEvent.create(
    pubkey: myPubkey,
    kind: 22242,
    content: '',
    tags: [
      ['relay', relay.url],
      ['challenge', challenge],
    ],
  ).sign(privateKey);
  
  return authEvent;
};
```

#### NIP-65: Relay List Metadata
**Status**: ✅ Fully Supported

Relay list management:
```dart
// Publish relay list
final relayList = NostrEvent.create(
  pubkey: myPubkey,
  kind: 10002,
  content: '',
  tags: [
    ['r', 'wss://relay.damus.io', 'read'],
    ['r', 'wss://relay.damus.io', 'write'],
    ['r', 'wss://nos.lol', 'read'],
  ],
).sign(privateKey);

await relay.publish(relayList);

// Use relay lists for routing
await relay.enableNIP65Routing(true);
```

### Content Types

#### NIP-23: Long-form Content
**Status**: ✅ Fully Supported

Articles and blog posts:
```dart
final article = NostrEvent.create(
  pubkey: myPubkey,
  kind: 30023,
  content: '# My Article\n\nArticle content in markdown...',
  tags: [
    ['d', 'my-article-2024'],
    ['title', 'My Article Title'],
    ['summary', 'A brief summary'],
    ['published_at', '${DateTime.now().millisecondsSinceEpoch ~/ 1000}'],
    ['t', 'nostr'],
    ['t', 'bitcoin'],
  ],
).sign(privateKey);
```

## Custom NIP Support

### OpenVine Video Events (Kind 32222)
**Status**: ✅ Fully Supported

Custom video event implementation:
```dart
// Video event
final videoEvent = NostrEvent.create(
  pubkey: creatorPubkey,
  kind: 32222,
  content: jsonEncode({
    'title': 'My Video',
    'description': 'Video description',
  }),
  tags: [
    ['d', 'video-id'],
    ['url', 'https://cdn.example.com/video.mp4'],
    ['m', 'video/mp4'],
    ['dim', '1920x1080'],
    ['duration', '180'],
    ['thumb', 'https://cdn.example.com/thumb.jpg'],
  ],
).sign(privateKey);
```

## Implementing Custom NIPs

### 1. Define Event Structure

```dart
// Custom NIP implementation
class CustomNIP {
  static const int KIND_CUSTOM_EVENT = 20001;
  
  static NostrEvent createCustomEvent({
    required String pubkey,
    required String privateKey,
    required Map<String, dynamic> data,
  }) {
    return NostrEvent.create(
      pubkey: pubkey,
      kind: KIND_CUSTOM_EVENT,
      content: jsonEncode(data),
      tags: [
        ['custom', 'true'],
        ['version', '1.0'],
      ],
    ).sign(privateKey);
  }
  
  static bool isCustomEvent(NostrEvent event) {
    return event.kind == KIND_CUSTOM_EVENT;
  }
  
  static Map<String, dynamic> parseCustomEvent(NostrEvent event) {
    if (!isCustomEvent(event)) {
      throw ArgumentError('Not a custom event');
    }
    return jsonDecode(event.content);
  }
}
```

### 2. Add Event Handlers

```dart
// Register custom event handler
relay.registerEventHandler(
  kind: CustomNIP.KIND_CUSTOM_EVENT,
  handler: (event) async {
    // Validate custom event
    if (!CustomNIP.isCustomEvent(event)) {
      return EventHandlerResult.reject('Invalid custom event');
    }
    
    try {
      final data = CustomNIP.parseCustomEvent(event);
      
      // Process custom event
      await processCustomEvent(data);
      
      return EventHandlerResult.accept();
    } catch (e) {
      return EventHandlerResult.reject('Processing failed: $e');
    }
  },
);
```

### 3. Custom Filters

```dart
// Extend filter functionality
class CustomFilter extends Filter {
  final String? customField;
  
  CustomFilter({
    this.customField,
    super.kinds,
    super.authors,
    super.since,
    super.until,
    super.limit,
  });
  
  @override
  bool matches(NostrEvent event) {
    if (!super.matches(event)) return false;
    
    if (customField != null) {
      final hasCustomTag = event.tags.any((tag) => 
        tag.length >= 2 && tag[0] == 'custom' && tag[1] == customField
      );
      if (!hasCustomTag) return false;
    }
    
    return true;
  }
}
```

## NIP Compatibility Matrix

| NIP | Name | Status | Notes |
|-----|------|--------|-------|
| 01 | Basic protocol | ✅ Full | Core functionality |
| 02 | Contact List | ✅ Full | Petname support |
| 04 | Encrypted DM | 🚧 Planned | Under development |
| 09 | Event Deletion | ✅ Full | Soft delete |
| 11 | Relay Info | ✅ Full | REST endpoint |
| 16 | Event Treatment | ✅ Full | Replaceable events |
| 23 | Long-form | ✅ Full | Articles |
| 33 | Parameterized | ✅ Full | d-tag support |
| 40 | Expiration | ✅ Full | Auto cleanup |
| 42 | Authentication | ✅ Full | Challenge-response |
| 65 | Relay Lists | ✅ Full | Outbox model |

## Best Practices

### 1. Event Validation

Always validate events according to their NIP:
```dart
class NIPValidator {
  static bool validateEvent(NostrEvent event) {
    // Basic validation
    if (!event.isValid) return false;
    
    // NIP-specific validation
    switch (event.kind) {
      case 0: // Metadata
        return _validateMetadata(event);
      case 3: // Contact list
        return _validateContactList(event);
      case 10002: // Relay list
        return _validateRelayList(event);
      default:
        return true;
    }
  }
  
  static bool _validateMetadata(NostrEvent event) {
    try {
      jsonDecode(event.content);
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

### 2. Backward Compatibility

Maintain compatibility with older clients:
```dart
// Support multiple event formats
class CompatibilityLayer {
  static NostrEvent normalizeEvent(NostrEvent event) {
    // Handle old format
    if (event.kind == 3 && event.tags.isEmpty && event.content.isNotEmpty) {
      // Old contact list format
      return _convertOldContactList(event);
    }
    
    return event;
  }
}
```

### 3. Feature Detection

Check relay capabilities:
```dart
// Check NIP support
final relayInfo = await relay.getRelayInformation();
final supportsNIP65 = relayInfo.supportedNips.contains(65);

if (supportsNIP65) {
  // Use advanced relay routing
  await relay.enableNIP65Routing(true);
} else {
  // Fall back to basic routing
  await relay.useBasicRouting();
}
```

## Testing NIP Implementations

```dart
// Test NIP compliance
class NIPComplianceTest {
  static Future<void> testNIP01Compliance(EmbeddedNostrRelay relay) async {
    // Test event creation
    final event = NostrEvent.create(
      pubkey: testPubkey,
      kind: 1,
      content: 'Test',
      tags: [],
    ).sign(testPrivateKey);
    
    assert(event.isValid);
    
    // Test publishing
    final published = await relay.publish(event);
    assert(published);
    
    // Test querying
    final events = await relay.queryEvents([
      Filter(ids: [event.id]),
    ]);
    assert(events.length == 1);
    assert(events.first.id == event.id);
  }
}
```

## Next Steps

- Review [API Overview](api-overview.md)
- Learn about [Security Best Practices](security.md)
- Explore [Performance Optimization](performance.md)