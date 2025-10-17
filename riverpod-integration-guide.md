# Riverpod Integration Guide for Flutter Embedded Nostr Relay

This guide explains how to integrate the Flutter Embedded Nostr Relay with Riverpod state management in production applications, based on patterns established in the example app.

## Table of Contents
1. [Core Setup](#core-setup)
2. [Provider Architecture](#provider-architecture)
3. [Event Management](#event-management)
4. [Identity Management](#identity-management)
5. [Real-time Subscriptions](#real-time-subscriptions)
6. [Hashtag Filtering](#hashtag-filtering)
7. [Testing Strategy](#testing-strategy)
8. [Best Practices](#best-practices)

## Core Setup

### Dependencies

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_riverpod: ^2.4.9
  flutter_embedded_nostr_relay:
    path: ../flutter_embedded_nostr_relay  # or published version
```

### App Initialization

Wrap your app with `ProviderScope`:

```dart
void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

## Provider Architecture

### 1. Relay Provider

The relay provider is the foundation - it initializes and provides access to the embedded relay:

```dart
// providers/relay_providers.dart
final relayProvider = FutureProvider<EmbeddedNostrRelay>((ref) async {
  final relay = EmbeddedNostrRelay();
  
  // Initialize with optional configuration
  await relay.initialize(
    enableGarbageCollection: true,
    garbageCollectionInterval: const Duration(hours: 1),
    maxEventsPerKind: 1000,
  );
  
  // Configure external relays
  await relay.addRelay('wss://relay.damus.io');
  await relay.addRelay('wss://relay.nostr.band');
  await relay.addRelay('wss://nos.lol');
  
  // Connect to all configured relays
  await relay.connectToAllRelays();
  
  // Keep relay alive for the app lifecycle
  ref.onDispose(() async {
    await relay.shutdown();
  });
  
  return relay;
});
```

### 2. Identity Provider

Manages user identity (private/public keys):

```dart
// providers/identity_providers.dart
@freezed
class Identity with _$Identity {
  const factory Identity({
    required String privateKey,
    required String publicKey,
  }) = _Identity;
}

class IdentityNotifier extends StateNotifier<Identity?> {
  IdentityNotifier() : super(null) {
    _loadIdentity();
  }
  
  static const _storageKey = 'nostr_identity';
  
  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKey = prefs.getString(_storageKey);
    
    if (privateKey != null) {
      final publicKey = NostrCrypto.getPublicKey(privateKey);
      state = Identity(privateKey: privateKey, publicKey: publicKey);
    }
  }
  
  Future<void> generateNewIdentity() async {
    final privateKey = NostrCrypto.generatePrivateKey();
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, privateKey);
    
    state = Identity(privateKey: privateKey, publicKey: publicKey);
  }
  
  Future<void> importIdentity(String privateKey) async {
    if (!NostrCrypto.isValidPrivateKey(privateKey)) {
      throw ArgumentError('Invalid private key');
    }
    
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, privateKey);
    
    state = Identity(privateKey: privateKey, publicKey: publicKey);
  }
  
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    state = null;
  }
}

final identityProvider = StateNotifierProvider<IdentityNotifier, Identity?>(
  (ref) => IdentityNotifier(),
);
```

## Event Management

### 1. Event List Provider with Real-time Updates

```dart
// providers/event_providers.dart
class EventListNotifier extends StateNotifier<List<NostrEvent>> {
  EventListNotifier(this.ref) : super([]) {
    _initialize();
  }
  
  final Ref ref;
  Subscription? _subscription;
  
  Future<void> _initialize() async {
    final relay = await ref.read(relayProvider.future);
    
    // Create subscription for events
    _subscription = relay.subscribe(
      subscriptionId: 'main_feed',
      filters: [
        Filter(
          kinds: [1, 6, 7, 32222], // Text notes, reposts, reactions, videos
          limit: 100,
          since: DateTime.now().subtract(const Duration(days: 7))
              .millisecondsSinceEpoch ~/ 1000,
        ),
      ],
      onEvent: (event) {
        // Add event maintaining chronological order
        state = _insertSorted(state, event);
      },
    );
  }
  
  List<NostrEvent> _insertSorted(List<NostrEvent> events, NostrEvent newEvent) {
    // Prevent duplicates
    if (events.any((e) => e.id == newEvent.id)) {
      return events;
    }
    
    final newList = [...events];
    final insertIndex = newList.indexWhere((e) => e.createdAt < newEvent.createdAt);
    
    if (insertIndex == -1) {
      newList.add(newEvent);
    } else {
      newList.insert(insertIndex, newEvent);
    }
    
    return newList;
  }
  
  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

final eventListProvider = StateNotifierProvider<EventListNotifier, List<NostrEvent>>(
  (ref) => EventListNotifier(ref),
);
```

### 2. StreamProvider for Real-time Events

For widgets that need to react to every event as it arrives:

```dart
final eventStreamProvider = StreamProvider<NostrEvent>((ref) async* {
  final relay = await ref.read(relayProvider.future);
  
  final controller = StreamController<NostrEvent>();
  
  final subscription = relay.subscribe(
    subscriptionId: 'stream_${DateTime.now().millisecondsSinceEpoch}',
    filters: [
      Filter(
        kinds: [1],
        limit: 0, // No limit for streaming
      ),
    ],
    onEvent: (event) {
      controller.add(event);
    },
  );
  
  ref.onDispose(() {
    subscription.close();
    controller.close();
  });
  
  yield* controller.stream;
});
```

### 3. Publishing Events

```dart
// providers/publish_providers.dart
final publishTextNoteProvider = Provider((ref) {
  return (String content, {List<List<String>>? tags}) async {
    final relay = await ref.read(relayProvider.future);
    final identity = ref.read(identityProvider);
    
    if (identity == null) {
      throw StateError('No identity available');
    }
    
    final event = NostrEvent.create(
      pubkey: identity.publicKey,
      kind: 1, // Text note
      content: content,
      tags: tags ?? [],
    );
    
    final signedEvent = event.sign(identity.privateKey);
    
    // Publish to local store and external relays
    await relay.publish(signedEvent);
    
    return signedEvent;
  };
});

// Usage in widgets:
final publishNote = ref.read(publishTextNoteProvider);
await publishNote('Hello Nostr!', tags: [['t', 'nostr']]);
```

## Hashtag Filtering

### 1. Family Providers for Per-Hashtag State

```dart
// providers/hashtag_providers.dart
class HashtagEventListNotifier extends StateNotifier<List<NostrEvent>> {
  HashtagEventListNotifier(this.ref, this.hashtag) : super([]) {
    _initialize();
  }
  
  final Ref ref;
  final String hashtag;
  Subscription? _subscription;
  final Set<String> _seenEventIds = {};
  
  Future<void> _initialize() async {
    final relay = await ref.read(relayProvider.future);
    
    _subscription = relay.subscribe(
      subscriptionId: 'hashtag_${hashtag}_${DateTime.now().millisecondsSinceEpoch}',
      filters: [
        Filter(
          kinds: [1, 32222], // Text notes and videos
          tags: {'#t': [hashtag.toLowerCase()]}, // NIP-01 compliant
          limit: 100,
        ),
      ],
      onEvent: _handleEvent,
    );
  }
  
  void _handleEvent(NostrEvent event) {
    // Verify event has the hashtag
    final hasHashtag = event.tags.any((tag) => 
      tag.length >= 2 && tag[0] == 't' && tag[1].toLowerCase() == hashtag.toLowerCase()
    );
    
    if (!hasHashtag || _seenEventIds.contains(event.id)) return;
    
    _seenEventIds.add(event.id);
    state = _insertSorted(state, event);
  }
  
  List<NostrEvent> _insertSorted(List<NostrEvent> events, NostrEvent newEvent) {
    final newList = [...events];
    final insertIndex = newList.indexWhere((e) => e.createdAt < newEvent.createdAt);
    
    if (insertIndex == -1) {
      newList.add(newEvent);
    } else {
      newList.insert(insertIndex, newEvent);
    }
    
    return newList;
  }
  
  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

// Family provider - creates separate instance for each hashtag
final hashtagEventListProvider = StateNotifierProvider.family<
  HashtagEventListNotifier, 
  List<NostrEvent>, 
  String
>((ref, hashtag) {
  return HashtagEventListNotifier(ref, hashtag);
});
```

### 2. Pagination Support

```dart
// Extended hashtag provider with pagination
class HashtagEventListNotifier extends StateNotifier<List<NostrEvent>> {
  // ... previous code ...
  
  bool _isLoadingMore = false;
  bool _hasMoreEvents = true;
  
  Future<void> loadMoreEvents() async {
    if (_isLoadingMore || !_hasMoreEvents || state.isEmpty) return;
    
    _isLoadingMore = true;
    ref.read(_hashtagLoadingStateProvider(hashtag).notifier).state = true;
    
    try {
      final relay = await ref.read(relayProvider.future);
      final oldestEvent = state.last;
      
      final loadMoreSub = relay.subscribe(
        subscriptionId: 'hashtag_loadmore_${hashtag}_${DateTime.now().millisecondsSinceEpoch}',
        filters: [
          Filter(
            kinds: [1, 32222],
            tags: {'#t': [hashtag.toLowerCase()]},
            until: oldestEvent.createdAt - 1,
            limit: 50,
          ),
        ],
        onEvent: _handleEvent,
      );
      
      final previousCount = state.length;
      await Future.delayed(const Duration(seconds: 2));
      await loadMoreSub.close();
      
      final newEventsCount = state.length - previousCount;
      if (newEventsCount < 10) {
        _hasMoreEvents = false;
        ref.read(_hashtagHasMoreStateProvider(hashtag).notifier).state = false;
      }
    } finally {
      _isLoadingMore = false;
      ref.read(_hashtagLoadingStateProvider(hashtag).notifier).state = false;
    }
  }
}

// Supporting state providers
final _hashtagLoadingStateProvider = StateProvider.family<bool, String>((ref, hashtag) => false);
final _hashtagHasMoreStateProvider = StateProvider.family<bool, String>((ref, hashtag) => true);

final hashtagIsLoadingMoreProvider = Provider.family<bool, String>((ref, hashtag) {
  return ref.watch(_hashtagLoadingStateProvider(hashtag));
});

final hashtagHasMoreEventsProvider = Provider.family<bool, String>((ref, hashtag) {
  return ref.watch(_hashtagHasMoreStateProvider(hashtag));
});
```

## Testing Strategy

### 1. Test Setup

```dart
// test/test_helpers.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';

void setupTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.enableTestMode(); // Use in-memory database
}

ProviderContainer createTestContainer({
  List<Override> overrides = const [],
}) {
  return ProviderContainer(overrides: overrides);
}

Future<void> cleanupTest(ProviderContainer container) async {
  container.dispose();
  await DatabaseHelper.reset();
}

NostrEvent createTestEvent({
  int kind = 1,
  String content = 'Test content',
  List<List<String>> tags = const [],
  int? createdAt,
  String? privateKey,
}) {
  privateKey ??= NostrCrypto.generatePrivateKey();
  final pubkey = NostrCrypto.getPublicKey(privateKey);
  
  final event = NostrEvent.create(
    pubkey: pubkey,
    kind: kind,
    tags: tags,
    content: content,
    createdAt: createdAt,
  );
  
  return event.sign(privateKey);
}
```

### 2. Provider Tests

```dart
// test/providers/event_providers_test.dart
void main() {
  setupTestEnvironment();
  
  group('EventListProvider', () {
    late ProviderContainer container;
    late EmbeddedNostrRelay relay;
    
    setUp(() async {
      relay = EmbeddedNostrRelay();
      await relay.initialize(enableGarbageCollection: false);
      
      container = createTestContainer(
        overrides: [
          relayProvider.overrideWith((ref) async => relay),
        ],
      );
    });
    
    tearDown(() async {
      await relay.shutdown();
      await cleanupTest(container);
    });
    
    test('receives events in real-time', () async {
      // Start watching the provider
      container.read(eventListProvider);
      
      // Wait for subscription to be ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Publish test event
      final event = createTestEvent(content: 'Real-time test');
      await relay.publish(event);
      
      // Wait for event to propagate
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify event was received
      final events = container.read(eventListProvider);
      expect(events.any((e) => e.id == event.id), isTrue);
    });
  });
}
```

### 3. Widget Tests

```dart
// test/widgets/timeline_test.dart
void main() {
  setupTestEnvironment();
  
  testWidgets('timeline displays events', (WidgetTester tester) async {
    final relay = EmbeddedNostrRelay();
    await relay.initialize(enableGarbageCollection: false);
    
    // Publish test events
    final event1 = createTestEvent(content: 'First event');
    final event2 = createTestEvent(content: 'Second event');
    await relay.publish(event1);
    await relay.publish(event2);
    
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relayProvider.overrideWith((ref) async => relay),
        ],
        child: const MaterialApp(
          home: TimelineScreen(),
        ),
      ),
    );
    
    // Wait for events to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    
    // Verify events are displayed
    expect(find.text('First event'), findsOneWidget);
    expect(find.text('Second event'), findsOneWidget);
    
    await relay.shutdown();
  });
}
```

## Best Practices

### 1. Provider Organization

```
lib/
  providers/
    relay_providers.dart      # Core relay setup
    identity_providers.dart   # User identity management
    event_providers.dart      # Event lists and streams
    hashtag_providers.dart    # Hashtag-specific providers
    publish_providers.dart    # Event publishing functions
    stats_providers.dart      # Relay statistics
```

### 2. Error Handling

```dart
final eventListProvider = StateNotifierProvider<EventListNotifier, AsyncValue<List<NostrEvent>>>(
  (ref) => EventListNotifier(ref),
);

class EventListNotifier extends StateNotifier<AsyncValue<List<NostrEvent>>> {
  EventListNotifier(this.ref) : super(const AsyncValue.loading()) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    try {
      final relay = await ref.read(relayProvider.future);
      
      // Set up subscription...
      
      state = AsyncValue.data(events);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }
}
```

### 3. Subscription Management

- Always close subscriptions in dispose methods
- Use unique subscription IDs
- Implement reconnection logic for dropped connections
- Handle duplicate events with Set tracking

### 4. Performance Optimization

```dart
// Limit event list size
class EventListNotifier extends StateNotifier<List<NostrEvent>> {
  static const _maxEvents = 500;
  
  void _handleEvent(NostrEvent event) {
    var newState = _insertSorted(state, event);
    
    // Trim old events
    if (newState.length > _maxEvents) {
      newState = newState.sublist(0, _maxEvents);
    }
    
    state = newState;
  }
}
```

### 5. Proper Cleanup

```dart
// In your main app widget
class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure relay is disposed when app closes
    ref.listen(relayProvider, (previous, next) {
      next.whenData((relay) {
        // Set up app lifecycle observer
        WidgetsBinding.instance.addObserver(
          _AppLifecycleObserver(relay),
        );
      });
    });
    
    return MaterialApp(
      // ... app config
    );
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final EmbeddedNostrRelay relay;
  
  _AppLifecycleObserver(this.relay);
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      relay.shutdown();
    }
  }
}
```

## Migration Guide for Existing Apps

If you have an existing app using different state management:

1. **Gradual Migration**: Start by wrapping your app with `ProviderScope` and migrate one feature at a time
2. **Relay Singleton**: Use the `relayProvider` as the single source of truth for relay access
3. **Event Deduplication**: Always check for duplicate events when merging streams
4. **Test Coverage**: Write tests for each provider before migrating UI code

## Example Usage in Production

```dart
// screens/home_screen.dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventListAsync = ref.watch(eventListProvider);
    final identity = ref.watch(identityProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nostr Client'),
        actions: [
          if (identity != null)
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => _showProfile(context, identity),
            ),
        ],
      ),
      body: eventListAsync.when(
        data: (events) => EventListView(events: events),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorView(error: error),
      ),
      floatingActionButton: identity != null
        ? FloatingActionButton(
            onPressed: () => _composeNote(context, ref),
            child: const Icon(Icons.edit),
          )
        : null,
    );
  }
}
```

This guide provides a solid foundation for integrating Flutter Embedded Nostr Relay with Riverpod in production applications. The patterns shown here have been tested and proven to work reliably with real-time Nostr event streams.