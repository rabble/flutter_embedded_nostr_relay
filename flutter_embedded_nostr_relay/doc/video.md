# Video Optimization Guide

Flutter Embedded Nostr Relay includes special optimizations for video events, particularly OpenVine's kind:32222 video events. This guide covers video-specific features and best practices.

## Overview

Video optimizations include:
- **Smart prefetching** - Preload video metadata and thumbnails
- **Bandwidth management** - Adaptive streaming based on connection
- **Local caching** - Store video data for offline playback
- **P2P video sharing** - Share videos directly between devices
- **CDN integration** - Efficient video delivery

## Video Event Structure

### Kind 32222 (OpenVine Video)

```dart
// Video event structure
final videoEvent = NostrEvent.create(
  pubkey: creatorPubkey,
  kind: 32222,
  content: jsonEncode({
    'title': 'My Awesome Video',
    'description': 'Check out this cool video!',
    'duration': 180, // seconds
  }),
  tags: [
    ['d', 'video-unique-id'], // Unique identifier
    ['url', 'https://cdn.example.com/video.mp4'], // Video URL
    ['m', 'video/mp4'], // MIME type
    ['dim', '1920x1080'], // Dimensions
    ['duration', '180'], // Duration in seconds
    ['size', '52428800'], // File size in bytes
    ['thumb', 'https://cdn.example.com/thumb.jpg'], // Thumbnail
    ['preview', 'https://cdn.example.com/preview.gif'], // Preview
    ['magnet', 'magnet:?xt=urn:btih:...'], // P2P magnet link
  ],
).sign(privateKey);

await relay.publish(videoEvent);
```

## Video-Specific Configuration

### 1. Enable Video Optimizations

```dart
await relay.enableVideoOptimizations(
  VideoConfig(
    // Prefetch video metadata
    prefetchMetadata: true,
    metadataCacheSize: 1000, // Number of videos
    
    // Thumbnail caching
    cacheThumbnails: true,
    thumbnailCacheSize: 100 * 1024 * 1024, // 100MB
    
    // Video caching
    cacheVideos: true,
    videoCacheSize: 1024 * 1024 * 1024, // 1GB
    maxCachedVideoSize: 100 * 1024 * 1024, // 100MB per video
    
    // Bandwidth management
    adaptiveStreaming: true,
    maxBandwidth: 5 * 1024 * 1024, // 5MB/s
    
    // P2P sharing
    enableP2PVideoSharing: true,
  ),
);
```

### 2. Video Query Optimization

```dart
// Query video events efficiently
final videos = await relay.queryVideos(
  VideoFilter(
    // Standard filters
    authors: followedCreators,
    since: lastWeek,
    
    // Video-specific filters
    minDuration: 30, // seconds
    maxDuration: 600, // 10 minutes
    mimeTypes: ['video/mp4', 'video/webm'],
    minResolution: '720p',
    hasP2P: true, // Only videos with P2P links
  ),
);
```

### 3. Tor Configuration for Videos

```dart
if (TorSupport.isAvailable) {
  // Enable/disable Tor for video loading
  await relay.setTorForVideos(false); // Usually disabled for performance
  
  // Configure video-specific Tor behavior
  await relay.setVideoTorConfig(
    VideoTorConfig(
      // Use Tor for metadata only
      useTorForMetadata: true,
      useTorForThumbnails: true,
      useTorForVideos: false, // Too slow for videos
      
      // Whitelist specific CDNs
      torWhitelist: [
        'trusted-cdn.example.com',
      ],
    ),
  );
}
```

## Prefetching and Caching

### 1. Smart Prefetching

```dart
// Configure prefetching strategy
await relay.setVideoPrefetchStrategy(
  PrefetchStrategy(
    // Prefetch upcoming videos in timeline
    prefetchAhead: 5, // Number of videos
    
    // Prefetch based on user behavior
    predictivePrefetch: true,
    
    // Network conditions
    prefetchOnWifiOnly: true,
    prefetchWhenCharging: true,
    
    // Priority rules
    priorityRules: [
      // Prefetch from followed creators first
      PrefetchRule(
        condition: (video) => followedCreators.contains(video.author),
        priority: Priority.high,
      ),
      // Prefetch short videos
      PrefetchRule(
        condition: (video) => video.duration < 60,
        priority: Priority.medium,
      ),
    ],
  ),
);
```

### 2. Cache Management

```dart
// Video cache manager
class VideoCacheManager {
  final EmbeddedNostrRelay relay;
  
  // Get cached video info
  Future<VideoCacheInfo?> getCacheInfo(String videoId) async {
    return await relay.getVideoCacheInfo(videoId);
  }
  
  // Preload video
  Future<void> preloadVideo(String videoId) async {
    await relay.preloadVideo(
      videoId,
      options: PreloadOptions(
        downloadThumbnail: true,
        downloadPreview: true,
        downloadVideo: await _shouldDownloadVideo(),
      ),
    );
  }
  
  // Clear old cache
  Future<void> clearOldCache() async {
    await relay.clearVideoCache(
      olderThan: DateTime.now().subtract(Duration(days: 30)),
      keepPinned: true,
    );
  }
  
  // Pin important videos
  Future<void> pinVideo(String videoId) async {
    await relay.pinVideo(videoId);
  }
}
```

## P2P Video Sharing

### 1. Enable P2P for Videos

```dart
await relay.enableP2PVideoSharing(
  P2PVideoConfig(
    // Share cached videos with peers
    shareOwnVideos: true,
    shareCachedVideos: true,
    
    // Bandwidth limits
    uploadBandwidthLimit: 1024 * 1024, // 1MB/s
    maxSimultaneousUploads: 3,
    
    // Storage limits
    maxSharedStorage: 5 * 1024 * 1024 * 1024, // 5GB
    
    // Peer preferences
    preferLocalPeers: true,
    requireEncryption: true,
  ),
);
```

### 2. P2P Video Discovery

```dart
// Find peers with specific video
final peers = await relay.findPeersWithVideo(videoId);
print('Found ${peers.length} peers with video');

// Download from fastest peer
final fastestPeer = peers.reduce((a, b) => 
  a.bandwidth > b.bandwidth ? a : b);

await relay.downloadVideoFromPeer(
  videoId: videoId,
  peer: fastestPeer,
  onProgress: (progress) {
    print('Download progress: ${progress.percent}%');
  },
);
```

## Video Player Integration

### 1. Video Player Widget

```dart
class NostrVideoPlayer extends StatefulWidget {
  final NostrEvent videoEvent;
  final EmbeddedNostrRelay relay;
  
  const NostrVideoPlayer({
    required this.videoEvent,
    required this.relay,
  });
  
  @override
  _NostrVideoPlayerState createState() => _NostrVideoPlayerState();
}

class _NostrVideoPlayerState extends State<NostrVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadVideo();
  }
  
  Future<void> _loadVideo() async {
    // Get video URL (cached or remote)
    final videoUrl = await widget.relay.getVideoUrl(
      widget.videoEvent.id,
      preferCached: true,
    );
    
    // Initialize player
    _controller = VideoPlayerController.network(videoUrl)
      ..initialize().then((_) {
        setState(() => _isLoading = false);
      });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }
    
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
  
  Widget _buildLoadingState() {
    // Show thumbnail while loading
    final thumbUrl = widget.videoEvent.tags
        .firstWhere((t) => t[0] == 'thumb', orElse: () => ['', ''])[1];
    
    return Stack(
      children: [
        if (thumbUrl.isNotEmpty)
          Image.network(thumbUrl, fit: BoxFit.cover),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
```

### 2. Video Timeline

```dart
class VideoTimeline extends StatefulWidget {
  final EmbeddedNostrRelay relay;
  
  @override
  _VideoTimelineState createState() => _VideoTimelineState();
}

class _VideoTimelineState extends State<VideoTimeline> {
  final List<NostrEvent> _videos = [];
  late Subscription _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscribeToVideos();
  }
  
  void _subscribeToVideos() {
    _subscription = widget.relay.subscribe(
      filters: [
        Filter(
          kinds: [32222], // Video events
          limit: 50,
        ),
      ],
      onEvent: (event) {
        setState(() => _videos.add(event));
        
        // Prefetch upcoming videos
        widget.relay.prefetchVideo(event.id);
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        return VideoCard(
          video: video,
          relay: widget.relay,
          onTap: () => _playVideo(video),
        );
      },
    );
  }
}
```

## CDN Integration

### 1. CDN Configuration

```dart
await relay.configureCDN(
  CDNConfig(
    // Primary CDN
    primaryCDN: 'https://cdn1.example.com',
    
    // Fallback CDNs
    fallbackCDNs: [
      'https://cdn2.example.com',
      'https://cdn3.example.com',
    ],
    
    // CDN selection strategy
    selectionStrategy: CDNStrategy.lowestLatency,
    
    // Health checking
    healthCheckInterval: Duration(minutes: 5),
    healthCheckTimeout: Duration(seconds: 10),
    
    // Signed URLs
    signedUrlHandler: (url) async {
      // Generate signed URL for private content
      return await generateSignedUrl(url);
    },
  ),
);
```

### 2. Adaptive Streaming

```dart
// Configure adaptive bitrate streaming
await relay.setAdaptiveStreaming(
  AdaptiveStreamingConfig(
    // Enable HLS/DASH support
    enableHLS: true,
    enableDASH: true,
    
    // Quality levels
    qualityLevels: [
      QualityLevel(name: '360p', bitrate: 800000),
      QualityLevel(name: '720p', bitrate: 2500000),
      QualityLevel(name: '1080p', bitrate: 5000000),
    ],
    
    // Adaptation rules
    adaptationRules: AdaptationRules(
      // Start with medium quality
      initialQuality: '720p',
      
      // Adjust based on bandwidth
      minBufferTime: Duration(seconds: 10),
      maxBufferTime: Duration(seconds: 30),
      
      // Switch quality thresholds
      upgradeThreshold: 1.5, // 150% bandwidth available
      downgradeThreshold: 0.8, // 80% bandwidth available
    ),
  ),
);
```

## Analytics and Monitoring

### 1. Video Analytics

```dart
// Track video metrics
await relay.enableVideoAnalytics(
  VideoAnalyticsConfig(
    // Track events
    trackEvents: [
      VideoEvent.play,
      VideoEvent.pause,
      VideoEvent.complete,
      VideoEvent.error,
    ],
    
    // Quality metrics
    trackQualityMetrics: true,
    qualityReportInterval: Duration(seconds: 10),
    
    // Engagement metrics
    trackEngagement: true,
    engagementEvents: [
      'like', 'share', 'comment', 'zap',
    ],
  ),
);

// Get video statistics
final stats = await relay.getVideoStatistics(videoId);
print('Views: ${stats.views}');
print('Average watch time: ${stats.averageWatchTime}');
print('Completion rate: ${stats.completionRate}%');
```

### 2. Performance Monitoring

```dart
// Monitor video performance
relay.onVideoPerformanceUpdate = (metrics) {
  if (metrics.bufferingRatio > 0.05) {
    print('High buffering detected: ${metrics.bufferingRatio}');
  }
  
  if (metrics.droppedFrames > 100) {
    print('Dropped frames: ${metrics.droppedFrames}');
  }
};
```

## Best Practices

### 1. Bandwidth Optimization

```dart
// Implement bandwidth-aware loading
class BandwidthAwareVideoLoader {
  final EmbeddedNostrRelay relay;
  
  Future<void> loadVideo(String videoId) async {
    final bandwidth = await relay.estimateBandwidth();
    
    if (bandwidth < 1000000) { // < 1 Mbps
      // Load thumbnail only
      await relay.loadVideoThumbnail(videoId);
    } else if (bandwidth < 5000000) { // < 5 Mbps
      // Load low quality
      await relay.loadVideo(videoId, quality: '360p');
    } else {
      // Load high quality
      await relay.loadVideo(videoId, quality: '720p');
    }
  }
}
```

### 2. Offline Support

```dart
// Download videos for offline viewing
class OfflineVideoManager {
  final EmbeddedNostrRelay relay;
  
  Future<void> downloadForOffline(String videoId) async {
    await relay.downloadVideo(
      videoId,
      options: DownloadOptions(
        quality: '720p',
        includeSubtitles: true,
        includeThumbnail: true,
        priority: DownloadPriority.high,
      ),
      onProgress: (progress) {
        print('Download: ${progress.percent}%');
      },
    );
  }
  
  Future<List<String>> getOfflineVideos() async {
    return await relay.getOfflineVideoIds();
  }
}
```

### 3. Privacy Considerations

```dart
// Privacy-aware video loading
await relay.setVideoPrivacyConfig(
  VideoPrivacyConfig(
    // Don't auto-play videos
    autoPlay: false,
    
    // Require user interaction
    requireUserInteraction: true,
    
    // Use Tor for metadata
    useTorForMetadata: true,
    
    // Don't report detailed analytics
    minimalAnalytics: true,
    
    // Proxy thumbnails
    proxyThumbnails: true,
  ),
);
```

## Example: Complete Video App

```dart
class NostrVideoApp extends StatefulWidget {
  @override
  _NostrVideoAppState createState() => _NostrVideoAppState();
}

class _NostrVideoAppState extends State<NostrVideoApp> {
  final relay = EmbeddedNostrRelay();
  
  @override
  void initState() {
    super.initState();
    _initializeVideoRelay();
  }
  
  Future<void> _initializeVideoRelay() async {
    await relay.initialize();
    
    // Enable video optimizations
    await relay.enableVideoOptimizations(
      VideoConfig(
        prefetchMetadata: true,
        cacheThumbnails: true,
        cacheVideos: true,
        adaptiveStreaming: true,
        enableP2PVideoSharing: true,
      ),
    );
    
    // Configure CDN
    await relay.configureCDN(
      CDNConfig(
        primaryCDN: 'https://video-cdn.example.com',
        selectionStrategy: CDNStrategy.lowestLatency,
      ),
    );
    
    // Set up prefetching
    await relay.setVideoPrefetchStrategy(
      PrefetchStrategy(
        prefetchAhead: 3,
        predictivePrefetch: true,
        prefetchOnWifiOnly: true,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Nostr Videos')),
        body: VideoTimeline(relay: relay),
      ),
    );
  }
}
```

## Next Steps

- Learn about [P2P Synchronization](p2p-sync.md)
- Explore [Performance Optimization](performance.md)
- Review [Security Best Practices](security.md)