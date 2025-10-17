// ABOUTME: Riverpod providers for managing Nostr relay state and event streams
// ABOUTME: Provides StreamProvider integration with embedded relay for real-time updates

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'dart:convert';
import 'dart:async';

// Model for Nostr identity
class NostrIdentity {
  final String publicKey;
  final String privateKey;
  
  NostrIdentity({
    required this.publicKey,
    required this.privateKey,
  });
}

// Provider for the embedded relay instance
final relayProvider = FutureProvider<EmbeddedNostrRelay>((ref) async {
  final relay = EmbeddedNostrRelay();
  await relay.initialize();
  
  // Connect to external relays (relay3.openvine.co as primary)
  final relays = [
    'wss://relay3.openvine.co',
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
  ];
  
  for (final url in relays) {
    try {
      await relay.addExternalRelay(url);
    } catch (e) {
      print('Failed to connect to $url: $e');
    }
  }
  
  // The embedded relay should handle connection pooling and optimization
  // We just need one main subscription that we update with different filters
  
  // Don't create any subscriptions here - let the StreamProvider handle it
  // The embedded relay will optimize external subscriptions automatically
  
  // Keep relay alive for the lifetime of the provider
  ref.onDispose(() async {
    await relay.shutdown();
  });
  
  return relay;
});

// StreamProvider for kind 32222 addressable events
final addressableEventStreamProvider = StreamProvider<NostrEvent>((ref) {
  final relayAsync = ref.watch(relayProvider);
  
  return relayAsync.when(
    data: (relay) {
      // Return filtered stream of only kind 32222 events
      return relay.eventStream.where((event) => event.kind == 32222);
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

// StateNotifierProvider for accumulating events into a list
class EventListNotifier extends StateNotifier<List<NostrEvent>> {
  EventListNotifier(this.ref) : super([]) {
    _initialize();
  }
  
  final Ref ref;
  ProviderSubscription? _streamSubscription;
  Subscription? _mainSubscription;
  bool _isLoadingMore = false;
  bool _hasMoreEvents = true;
  final Set<String> _seenEventIds = {};
  
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreEvents => _hasMoreEvents;
  
  Future<void> _initialize() async {
    // Wait for relay to be ready
    final relay = await ref.read(relayProvider.future);
    
    // Create initial subscription for recent events
    _mainSubscription = relay.subscribe(
      subscriptionId: 'timeline_main',
      filters: [
        Filter(
          kinds: [32222],
          limit: 50,
          // Get events from the last 24 hours initially
          since: DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
        ),
      ],
      onEvent: (event) {
        _handleEvent(event);
      },
    );
    
    // Also subscribe to the stream for real-time updates
    _streamSubscription = ref.listen(addressableEventStreamProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        _handleEvent(next.value!);
      }
    });
  }
  
  void _handleEvent(NostrEvent event) {
    // Prevent duplicates using a Set to track seen event IDs
    if (!_seenEventIds.contains(event.id)) {
      _seenEventIds.add(event.id);
      // Insert in sorted order (newest first)
      final newState = [...state];
      final insertIndex = newState.indexWhere((e) => e.createdAt < event.createdAt);
      if (insertIndex == -1) {
        newState.add(event);
      } else {
        newState.insert(insertIndex, event);
      }
      state = newState;
    }
  }
  
  @override
  void dispose() {
    _streamSubscription?.close();
    _mainSubscription?.close();
    super.dispose();
  }
  
  void clear() {
    state = [];
    _seenEventIds.clear();
    _hasMoreEvents = true;
  }
  
  Future<void> loadMoreEvents() async {
    if (_isLoadingMore || !_hasMoreEvents || state.isEmpty) return;
    
    _isLoadingMore = true;
    
    try {
      final relay = await ref.read(relayProvider.future);
      
      // Get the oldest event timestamp
      final oldestEvent = state.reduce((a, b) => a.createdAt < b.createdAt ? a : b);
      
      // Create a separate subscription for loading more events
      // The embedded relay will manage this efficiently with external relays
      final loadMoreSub = relay.subscribe(
        subscriptionId: 'loadmore_${DateTime.now().millisecondsSinceEpoch}',
        filters: [
          Filter(
            kinds: [32222],
            until: oldestEvent.createdAt - 1,
            limit: 50,
          ),
        ],
        onEvent: (event) {
          _handleEvent(event);
        },
      );
      
      // Track how many events we had before
      final previousCount = state.length;
      
      // Wait for events to come in
      await Future.delayed(const Duration(seconds: 3));
      
      // Close the temporary subscription
      await loadMoreSub.close();
      
      // Check if we got new events
      final newEventsCount = state.length - previousCount;
      if (newEventsCount == 0) {
        _hasMoreEvents = false;
      } else if (newEventsCount < 25) {
        // Got fewer than half the requested amount
        _hasMoreEvents = false;
      }
    } catch (e) {
      print('Error loading more events: $e');
    } finally {
      _isLoadingMore = false;
    }
  }
}

final eventListProvider = StateNotifierProvider<EventListNotifier, List<NostrEvent>>((ref) {
  return EventListNotifier(ref);
});

// Provider to expose loading state
final isLoadingMoreProvider = Provider<bool>((ref) {
  // Watch the notifier to get loading state
  final notifier = ref.watch(eventListProvider.notifier);
  return notifier.isLoadingMore;
});

// Provider to expose hasMoreEvents state
final hasMoreEventsProvider = Provider<bool>((ref) {
  // Watch the notifier to get hasMore state
  final notifier = ref.watch(eventListProvider.notifier);
  return notifier.hasMoreEvents;
});

// Provider for Nostr identity management
class IdentityNotifier extends StateNotifier<NostrIdentity?> {
  IdentityNotifier() : super(null);
  
  Future<void> generateNewIdentity() async {
    final privateKey = NostrCrypto.generatePrivateKey();
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    state = NostrIdentity(
      publicKey: publicKey,
      privateKey: privateKey,
    );
  }
  
  Future<void> importIdentity(String privateKey) async {
    if (privateKey.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(privateKey)) {
      throw ArgumentError('Invalid private key format');
    }
    
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    state = NostrIdentity(
      publicKey: publicKey,
      privateKey: privateKey,
    );
  }
  
  void logout() {
    state = null;
  }
}

final identityProvider = StateNotifierProvider<IdentityNotifier, NostrIdentity?>((ref) {
  return IdentityNotifier();
});

// Provider for external relay connections
final externalRelaysProvider = FutureProvider<List<String>>((ref) async {
  final relayAsync = ref.watch(relayProvider);
  
  return relayAsync.when(
    data: (relay) => relay.connectedRelays,
    loading: () => [],
    error: (_, __) => [],
  );
});

// Provider for creating subscriptions with filters
final subscriptionProvider = Provider.family<AsyncValue<Subscription>, List<Filter>>((ref, filters) {
  final relayAsync = ref.watch(relayProvider);
  
  return relayAsync.whenData((relay) {
    final subscription = relay.subscribe(
      filters: filters,
      onEvent: (event) {
        // Events are handled by the stream provider
      },
    );
    
    ref.onDispose(() {
      subscription.close();
    });
    
    return subscription;
  });
});

// Provider for relay statistics
final relayStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final relayAsync = ref.watch(relayProvider);
  
  return relayAsync.when(
    data: (relay) async {
      final stats = await relay.getStats();
      stats['connectedRelays'] = relay.connectedRelays.length;
      return stats;
    },
    loading: () async => {},
    error: (_, __) async => {},
  );
});

// Helper provider for publishing events
final eventPublisherProvider = Provider((ref) {
  return EventPublisher(ref);
});

class EventPublisher {
  final Ref ref;
  
  EventPublisher(this.ref);
  
  Future<NostrEvent?> publishAddressableEvent({
    required String dTag,
    required Map<String, dynamic> content,
  }) async {
    final identity = ref.read(identityProvider);
    if (identity == null) {
      throw StateError('No identity set');
    }
    
    final relayAsync = ref.read(relayProvider);
    
    return relayAsync.when(
      data: (relay) async {
        final event = NostrEvent.create(
          pubkey: identity.publicKey,
          kind: 32222,
          tags: [
            ['d', dTag],
          ],
          content: json.encode(content),
        );
        
        final signedEvent = event.sign(identity.privateKey);
        await relay.publish(signedEvent);
        
        return signedEvent;
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }
  
  Future<NostrEvent?> publishTextNote(String content) async {
    final identity = ref.read(identityProvider);
    if (identity == null) {
      throw StateError('No identity set');
    }
    
    final relayAsync = ref.read(relayProvider);
    
    return relayAsync.when(
      data: (relay) async {
        final event = NostrEvent.create(
          pubkey: identity.publicKey,
          kind: 1,
          tags: [],
          content: content,
        );
        
        final signedEvent = event.sign(identity.privateKey);
        await relay.publish(signedEvent);
        
        return signedEvent;
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }
}