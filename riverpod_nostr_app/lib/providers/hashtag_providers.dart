// ABOUTME: Riverpod providers for hashtag-specific event queries and state management
// ABOUTME: Creates dedicated subscriptions for each hashtag to query external relays

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'relay_providers.dart';
import 'dart:async';

// StateNotifierProvider for hashtag-specific event lists
class HashtagEventListNotifier extends StateNotifier<List<NostrEvent>> {
  HashtagEventListNotifier(this.ref, this.hashtag) : super([]) {
    _initialize();
  }
  
  final Ref ref;
  final String hashtag;
  Subscription? _mainSubscription;
  final Set<String> _seenEventIds = {};
  
  bool get isLoadingMore => ref.read(_hashtagLoadingStateProvider(hashtag));
  bool get hasMoreEvents => ref.read(_hashtagHasMoreStateProvider(hashtag));
  
  Future<void> _initialize() async {
    // Wait for relay to be ready
    final relay = await ref.read(relayProvider.future);
    
    // Create subscription specifically for this hashtag
    // The embedded relay will optimize this with external relays
    _mainSubscription = relay.subscribe(
      subscriptionId: 'hashtag_${hashtag}_${DateTime.now().millisecondsSinceEpoch}',
      filters: [
        Filter(
          kinds: [32222],
          tags: {'#t': [hashtag.toLowerCase()]}, // Filter by hashtag - use #t format with lowercase
          limit: 100, // Get more initially for hashtag views
          // Get events from the last 30 days for hashtags
          since: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
        ),
      ],
      onEvent: (event) {
        _handleEvent(event);
      },
      onEose: () {
        // End of stored events - we got what was in the local database
        print('EOSE for hashtag #$hashtag - got ${state.length} events from local store');
      },
    );
    
    // Also query external relays for recent events
    // The embedded relay should handle this efficiently
    print('Initialized subscription for hashtag #$hashtag');
  }
  
  void _handleEvent(NostrEvent event) {
    // Verify the event actually has this hashtag
    bool hasHashtag = false;
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 't' && tag[1] == hashtag) {
        hasHashtag = true;
        break;
      }
    }
    
    if (!hasHashtag) return;
    
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
    _mainSubscription?.close();
    super.dispose();
  }
  
  void clear() {
    state = [];
    _seenEventIds.clear();
    ref.read(_hashtagHasMoreStateProvider(hashtag).notifier).state = true;
  }
  
  Future<void> loadMoreEvents() async {
    if (isLoadingMore || !hasMoreEvents || state.isEmpty) return;
    
    ref.read(_hashtagLoadingStateProvider(hashtag).notifier).state = true;
    
    try {
      final relay = await ref.read(relayProvider.future);
      
      // Get the oldest event timestamp
      final oldestEvent = state.reduce((a, b) => a.createdAt < b.createdAt ? a : b);
      
      // Create a separate subscription for loading more events
      final loadMoreSub = relay.subscribe(
        subscriptionId: 'hashtag_loadmore_${hashtag}_${DateTime.now().millisecondsSinceEpoch}',
        filters: [
          Filter(
            kinds: [32222],
            tags: {'#t': [hashtag.toLowerCase()]}, // Filter by hashtag - use #t format with lowercase
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
        ref.read(_hashtagHasMoreStateProvider(hashtag).notifier).state = false;
      } else if (newEventsCount < 25) {
        // Got fewer than half the requested amount
        ref.read(_hashtagHasMoreStateProvider(hashtag).notifier).state = false;
      }
    } catch (e) {
      print('Error loading more events for #$hashtag: $e');
    } finally {
      ref.read(_hashtagLoadingStateProvider(hashtag).notifier).state = false;
    }
  }
}

// Family provider for hashtag-specific event lists
final hashtagEventListProvider = StateNotifierProvider.family<HashtagEventListNotifier, List<NostrEvent>, String>((ref, hashtag) {
  return HashtagEventListNotifier(ref, hashtag);
});

// State for tracking loading state per hashtag
final _hashtagLoadingStateProvider = StateProvider.family<bool, String>((ref, hashtag) => false);

// State for tracking if more events are available per hashtag
final _hashtagHasMoreStateProvider = StateProvider.family<bool, String>((ref, hashtag) => true);

// Provider to expose loading state for a specific hashtag
final hashtagIsLoadingMoreProvider = Provider.family<bool, String>((ref, hashtag) {
  return ref.watch(_hashtagLoadingStateProvider(hashtag));
});

// Provider to expose hasMoreEvents state for a specific hashtag
final hashtagHasMoreEventsProvider = Provider.family<bool, String>((ref, hashtag) {
  return ref.watch(_hashtagHasMoreStateProvider(hashtag));
});

// Provider to get all unique hashtags from current events
final allHashtagsProvider = Provider<List<String>>((ref) {
  final eventList = ref.watch(eventListProvider);
  final hashtags = <String>{};
  
  for (final event in eventList) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 't') {
        hashtags.add(tag[1]);
      }
    }
  }
  
  return hashtags.toList()..sort();
});