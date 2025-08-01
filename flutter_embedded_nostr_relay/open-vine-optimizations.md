# OpenVine-Specific Relay Optimizations

## Video-Centric Architecture Benefits

### 1. Metadata-First Loading Strategy

```dart
class VideoOptimizedRelay {
  // OpenVine's kind:32222 events contain video metadata, not video data
  // This enables smart loading strategies
  
  Future<void> handleVideoFeedRequest(Filter filter) async {
    // 1. Immediately return cached metadata
    final cachedVideos = await _store.query(
      filter.copyWith(kinds: [32222])
    );
    
    // 2. Analyze video freshness
    for (final video in cachedVideos) {
      final videoId = video.dTag;
      final lastUpdate = video.createdAt;
      
      // Check if we might have missed updates
      if (_shouldRefreshVideo(video)) {
        _queueVideoRefresh(video);
      }
    }
    
    // 3. Pre-fetch metadata for videos likely to be viewed
    await _prefetchUpcomingVideos(filter);
    
    // 4. DON'T fetch video files - let app handle via CDN
    // We only manage Nostr metadata
  }
  
  bool _shouldRefreshVideo(NostrEvent video) {
    // Addressable events can be updated - check periodically
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - video.createdAt;
    
    // Refresh if:
    // - Newer than 1 hour: every 5 minutes (might be editing)
    // - Newer than 1 day: every hour
    // - Newer than 1 week: every 6 hours  
    // - Older: every 24 hours
    
    if (age < 3600) return _lastRefresh(video) > Duration(minutes: 5);
    if (age < 86400) return _lastRefresh(video) > Duration(hours: 1);
    if (age < 604800) return _lastRefresh(video) > Duration(hours: 6);
    return _lastRefresh(video) > Duration(hours: 24);
  }
}
```

### 2. Social Graph Optimization for Video Discovery

```dart
class VideoSocialGraphOptimizer {
  // Video apps need different social features than text
  
  Future<void> optimizeForVideoDiscovery(String userPubkey) async {
    // 1. Pre-fetch videos from followed creators
    final following = await _getFollowList(userPubkey);
    
    // Fetch recent videos from each
    for (final creator in following) {
      await _backgroundFetch(Filter(
        kinds: [32222],
        authors: [creator],
        limit: 10, // Last 10 videos per creator
      ));
    }
    
    // 2. Pre-fetch reaction counts for videos
    // This helps with popularity sorting
    await _fetchVideoEngagement(following);
    
    // 3. Build creator profiles for rich previews
    await _fetchCreatorProfiles(following);
  }
  
  Future<void> _fetchVideoEngagement(List<String> creators) async {
    // Fetch reactions (kind:7) for recent videos
    final recentVideos = await _store.query([
      Filter(
        kinds: [32222],
        authors: creators,
        since: _daysAgo(7),
      )
    ]).toList();
    
    // Batch fetch reactions
    for (final batch in recentVideos.slices(20)) {
      final videoIds = batch.map((v) => v.id).toList();
      
      await _backgroundFetch(Filter(
        kinds: [7], // Reactions
        tags: {'e': videoIds},
      ));
    }
  }
}
```

### 3. Bandwidth-Aware Sync for Mobile

```dart
class MobileVideoSyncStrategy {
  // Videos = large files, mobile = limited bandwidth
  
  Future<void> syncWithPeer(Peer peer, ConnectionType connection) async {
    switch (connection) {
      case ConnectionType.wifi:
        // Full sync - metadata + recent engagement
        await _fullSync(peer);
        break;
        
      case ConnectionType.bluetooth:
        // Metadata only - no thumbnails
        await _metadataOnlySync(peer);
        break;
        
      case ConnectionType.cellular:
        // Only sync if user explicitly requested
        if (_userRequestedSync) {
          await _minimalSync(peer);
        }
        break;
    }
  }
  
  Future<void> _metadataOnlySync(Peer peer) async {
    // Only sync text metadata, not image URLs
    final filter = NegentropySyncFilter(
      kinds: [
        0,     // Profiles (text only)
        3,     // Follow lists
        32222, // Video metadata
      ],
      // Skip events with large content
      maxContentSize: 5000,
      
      // Skip old videos
      since: _daysAgo(30),
    );
    
    await _negentropy.sync(peer, filter);
  }
}
```

### 4. Intelligent Pre-caching for Video Feeds

```dart
class VideoFeedPreloader {
  // Pre-load metadata for smooth scrolling
  
  Future<void> preloadForScroll(
    int currentIndex,
    ScrollDirection direction,
  ) async {
    if (direction == ScrollDirection.down) {
      // User scrolling down - preload next videos
      await _preloadRange(currentIndex + 1, currentIndex + 10);
      
      // Also preload comments for next 3 videos
      await _preloadComments(currentIndex + 1, currentIndex + 3);
      
    } else {
      // User scrolling up - they might be reviewing
      // Preload engagement data for previous videos
      await _preloadEngagement(currentIndex - 5, currentIndex);
    }
  }
  
  Future<void> _preloadComments(int startIndex, int endIndex) async {
    final videos = await _getVideosInRange(startIndex, endIndex);
    
    for (final video in videos) {
      // Only fetch if not cached
      if (!await _hasRecentComments(video.id)) {
        _backgroundQueue.add(
          Filter(
            kinds: [1], // Comments
            tags: {'e': [video.id]},
            limit: 20, // Top comments
          ),
        );
      }
    }
  }
}
```

### 5. Creator-Centric Relay Lists

```dart
class CreatorRelayManager {
  // Video creators often use specific relays for content
  
  Future<List<String>> getRelaysForCreator(String creatorPubkey) async {
    // 1. Check creator's NIP-65 relay list
    final creatorRelays = await _getRelayList(creatorPubkey);
    
    // 2. Check where their recent videos were published
    final recentVideos = await _store.query([
      Filter(
        kinds: [32222],
        authors: [creatorPubkey],
        limit: 10,
      )
    ]).toList();
    
    // Track which relays had their content
    final activeRelays = <String, int>{};
    for (final video in recentVideos) {
      final sourceRelay = video.sourceRelay;
      if (sourceRelay != null) {
        activeRelays[sourceRelay] = (activeRelays[sourceRelay] ?? 0) + 1;
      }
    }
    
    // 3. Prefer relays where creator actually posts
    final sorted = activeRelays.entries
      .sorted((a, b) => b.value.compareTo(a.value))
      .map((e) => e.key)
      .toList();
    
    return sorted.take(3).toList();
  }
}
```

### 6. Video-Specific Event Priorities

```dart
class VideoEventPrioritizer {
  // Not all events are equal for a video app
  
  int getPriority(NostrEvent event) {
    switch (event.kind) {
      case 32222: // Video metadata
        return 100; // Highest priority
        
      case 0: // Profiles
        if (_isVideoCreator(event.pubkey)) {
          return 90; // Creator profiles are important
        }
        return 50; // Other profiles less so
        
      case 7: // Reactions
        if (_isVideoReaction(event)) {
          return 80; // Video likes matter for sorting
        }
        return 30;
        
      case 1: // Comments
        if (_isVideoComment(event)) {
          return 70; // Comments drive engagement
        }
        return 20;
        
      case 6: // Reposts
        if (_isVideoRepost(event)) {
          return 85; // Reposts = discovery
        }
        return 25;
        
      case 3: // Follow lists
        return 60; // Needed for social features
        
      default:
        return 10; // Everything else is low priority
    }
  }
}
```

### 7. OpenVine-Specific Configuration

```dart
class OpenVineRelayConfig {
  static final config = EmbeddedRelayConfig(
    // Video-optimized settings
    maxEventsPerKind: {
      32222: 50000,  // Keep lots of video metadata
      0: 10000,      // Creator profiles
      7: 100000,     // Reactions (they're small)
      1: 50000,      // Comments
      6: 20000,      // Reposts
      3: 5000,       // Follow lists
    },
    
    // Aggressive caching for video metadata
    cacheStrategy: CacheStrategy(
      // Always cache video metadata
      alwaysCacheKinds: [32222, 0],
      
      // Cache videos from followed creators longer
      creatorContentRetention: Duration(days: 90),
      
      // Pre-fetch upcoming videos in feed
      prefetchStrategy: PrefetchStrategy.aggressive,
    ),
    
    // Outbox model tuned for video creators
    outboxConfig: OutboxConfig(
      // Video creators often use fewer, more reliable relays
      maxRelaysPerUser: 5,
      
      // Check video-specific relays first
      priorityRelays: [
        'wss://video.nostr.build',
        'wss://nostr.wine',
        'wss://relay.damus.io',
      ],
    ),
    
    // P2P sync optimized for video apps
    syncConfig: SyncConfig(
      // Only sync recent content by default
      defaultSyncWindow: Duration(days: 7),
      
      // But sync all content from favorite creators
      favoriteCreatorSyncWindow: Duration(days: 90),
      
      // Bandwidth-aware sync
      wifiSyncStrategy: SyncStrategy.full,
      cellularSyncStrategy: SyncStrategy.metadataOnly,
      bluetoothSyncStrategy: SyncStrategy.metadataOnly,
    ),
  );
}
```

## The Result: Lightning-Fast Video Experience

With this architecture, OpenVine gets:

1. **Instant video feed loading** - Metadata loads from local cache immediately
2. **Smart background updates** - Fresh content appears seamlessly
3. **Efficient P2P sharing** - Watch parties and local sharing work great
4. **Creator-optimized** - Finds content wherever creators publish
5. **Bandwidth-aware** - Respects mobile data limits
6. **Privacy-preserving** - External relays don't know viewing habits

The embedded relay becomes a video-optimized content delivery system that makes the decentralized Nostr network feel as fast as centralized platforms.