// ABOUTME: State management for timeline and feed functionality
// ABOUTME: Handles event subscriptions, timeline updates, and post interactions

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'user_provider.dart';

enum TimelineType {
  global,
  following,
  mentions,
}

class TimelineEvent {
  final NostrEvent event;
  final UserProfile? authorProfile;
  final List<NostrEvent> reactions;
  final List<NostrEvent> replies;
  final bool isLiked;
  final bool isReposted;

  TimelineEvent({
    required this.event,
    this.authorProfile,
    this.reactions = const [],
    this.replies = const [],
    this.isLiked = false,
    this.isReposted = false,
  });

  TimelineEvent copyWith({
    NostrEvent? event,
    UserProfile? authorProfile,
    List<NostrEvent>? reactions,
    List<NostrEvent>? replies,
    bool? isLiked,
    bool? isReposted,
  }) {
    return TimelineEvent(
      event: event ?? this.event,
      authorProfile: authorProfile ?? this.authorProfile,
      reactions: reactions ?? this.reactions,
      replies: replies ?? this.replies,
      isLiked: isLiked ?? this.isLiked,
      isReposted: isReposted ?? this.isReposted,
    );
  }

  int get likeCount => reactions.where((r) => r.content == '+' || r.content == '❤️').length;
  int get replyCount => replies.length;
  
  bool get hasMedia {
    // Check for image URLs in content
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    final urlPattern = RegExp(r'https?://[^\s]+');
    final urls = urlPattern.allMatches(event.content);
    
    for (final match in urls) {
      final url = match.group(0)?.toLowerCase() ?? '';
      if (imageExtensions.any((ext) => url.contains(ext))) {
        return true;
      }
    }
    return false;
  }
  
  List<String> get mediaUrls {
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    final urlPattern = RegExp(r'https?://[^\s]+');
    final urls = urlPattern.allMatches(event.content);
    final mediaUrls = <String>[];
    
    for (final match in urls) {
      final url = match.group(0) ?? '';
      if (imageExtensions.any((ext) => url.toLowerCase().contains(ext))) {
        mediaUrls.add(url);
      }
    }
    return mediaUrls;
  }
}

class TimelineProvider extends ChangeNotifier {
  static final _logger = Logger('TimelineProvider');
  
  UserProvider? _userProvider;
  EmbeddedNostrRelay? _relay;
  
  // Timeline state
  final Map<TimelineType, List<TimelineEvent>> _timelines = {
    TimelineType.global: [],
    TimelineType.following: [],
    TimelineType.mentions: [],
  };
  
  TimelineType _currentTimeline = TimelineType.global;
  bool _isLoading = false;
  String? _error;
  
  // Subscriptions
  final Map<TimelineType, Subscription> _subscriptions = {};
  StreamSubscription<NostrEvent>? _eventStreamSubscription;
  
  // Cache
  final Map<String, NostrEvent> _eventCache = {};
  final Map<String, List<NostrEvent>> _reactionCache = {};
  final Map<String, List<NostrEvent>> _replyCache = {};
  
  // Getters
  List<TimelineEvent> get currentTimelineEvents => _timelines[_currentTimeline] ?? [];
  TimelineType get currentTimeline => _currentTimeline;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<TimelineEvent> getTimelineEvents(TimelineType type) => _timelines[type] ?? [];

  void setUserProvider(UserProvider userProvider) {
    _userProvider = userProvider;
  }

  void setRelay(EmbeddedNostrRelay relay) {
    _relay = relay;
    _startEventStreamSubscription();
  }

  /// Switch timeline type
  void switchTimeline(TimelineType type) {
    if (_currentTimeline == type) return;
    
    _currentTimeline = type;
    notifyListeners();
    
    // Load timeline if empty
    if (_timelines[type]?.isEmpty ?? true) {
      loadTimeline(type);
    }
  }

  /// Load timeline events
  Future<void> loadTimeline(TimelineType type, {bool refresh = false}) async {
    if (_relay == null) {
      _logger.warning('Relay not available');
      return;
    }

    if (refresh) {
      _timelines[type] = [];
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final filters = _createFiltersForTimeline(type);
      final events = await _relay!.queryEvents(filters);
      
      // Sort events by creation time (newest first)
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      // Cache events
      for (final event in events) {
        _eventCache[event.id] = event;
      }
      
      // Convert to timeline events
      final timelineEvents = <TimelineEvent>[];
      for (final event in events) {
        if (event.kind == 1) { // Text notes only for main timeline
          final timelineEvent = await _createTimelineEvent(event);
          timelineEvents.add(timelineEvent);
        }
      }
      
      _timelines[type] = timelineEvents;
      
      // Subscribe for real-time updates
      await _subscribeToTimeline(type);
      
    } catch (e) {
      _error = 'Failed to load timeline: $e';
      _logger.severe('Failed to load timeline', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Publish a new post
  Future<void> publishPost({
    required String content,
    List<String>? replyTo,
    List<String>? mentionPubkeys,
  }) async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      throw StateError('User not signed in');
    }
    
    if (_relay == null) {
      throw StateError('Relay not available');
    }

    try {
      final event = _userProvider!.createTextNote(
        content: content,
        replyTo: replyTo,
        mentionPubkeys: mentionPubkeys,
      );
      
      final published = await _relay!.publish(event);
      
      if (published) {
        _logger.info('Post published: ${event.id}');
        
        // Add to timeline immediately for better UX
        final timelineEvent = await _createTimelineEvent(event);
        _timelines[TimelineType.global]?.insert(0, timelineEvent);
        
        if (_currentTimeline == TimelineType.global) {
          notifyListeners();
        }
      } else {
        throw Exception('Failed to publish post');
      }
    } catch (e) {
      _logger.severe('Failed to publish post', e);
      rethrow;
    }
  }

  /// React to an event
  Future<void> reactToEvent({
    required String eventId,
    required String eventAuthor,
    required String reaction,
  }) async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      throw StateError('User not signed in');
    }
    
    if (_relay == null) {
      throw StateError('Relay not available');
    }

    try {
      final reactionEvent = _userProvider!.createReaction(
        eventId: eventId,
        eventAuthor: eventAuthor,
        reaction: reaction,
      );
      
      final published = await _relay!.publish(reactionEvent);
      
      if (published) {
        _logger.info('Reaction published: ${reactionEvent.id}');
        
        // Update local cache
        _reactionCache[eventId] = (_reactionCache[eventId] ?? [])..add(reactionEvent);
        
        // Update timeline event
        _updateTimelineEventReactions(eventId);
      }
    } catch (e) {
      _logger.severe('Failed to react to event', e);
      rethrow;
    }
  }

  /// Toggle like on an event
  Future<void> toggleLike(String eventId, String eventAuthor) async {
    final currentReactions = _reactionCache[eventId] ?? [];
    final userPubkey = _userProvider?.publicKey;
    
    if (userPubkey == null) return;
    
    final existingLike = currentReactions.firstWhere(
      (r) => r.pubkey == userPubkey && (r.content == '+' || r.content == '❤️'),
      orElse: () => NostrEvent(
        id: '',
        pubkey: '',
        createdAt: 0,
        kind: 0,
        tags: [],
        content: '',
        sig: '',
      ),
    );
    
    if (existingLike.id.isEmpty) {
      // Like the event
      await reactToEvent(
        eventId: eventId,
        eventAuthor: eventAuthor,
        reaction: '❤️',
      );
    } else {
      // Unlike - create deletion event (NIP-09)
      // TODO: Implement deletion when supported
      _logger.info('Unlike functionality not yet implemented');
    }
  }

  /// Refresh current timeline
  Future<void> refreshCurrentTimeline() async {
    await loadTimeline(_currentTimeline, refresh: true);
  }

  // Private methods

  List<Filter> _createFiltersForTimeline(TimelineType type) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final oneDayAgo = now - (24 * 60 * 60);
    
    switch (type) {
      case TimelineType.global:
        return [
          Filter(
            kinds: [1], // Text notes
            since: oneDayAgo,
            limit: 100,
          ),
        ];
      
      case TimelineType.following:
        final following = _userProvider?.profile?.relays ?? [];
        if (following.isEmpty) {
          return []; // No follows, return empty
        }
        return [
          Filter(
            kinds: [1],
            authors: following,
            since: oneDayAgo,
            limit: 100,
          ),
        ];
      
      case TimelineType.mentions:
        final userPubkey = _userProvider?.publicKey;
        if (userPubkey == null) {
          return [];
        }
        return [
          Filter(
            kinds: [1],
            pTags: [userPubkey], // Events mentioning the user
            since: oneDayAgo,
            limit: 50,
          ),
        ];
    }
  }

  Future<TimelineEvent> _createTimelineEvent(NostrEvent event) async {
    // Get author profile
    UserProfile? authorProfile;
    if (_userProvider != null) {
      authorProfile = await _userProvider!.getProfile(event.pubkey);
    }
    
    // Get reactions and replies
    final reactions = _reactionCache[event.id] ?? [];
    final replies = _replyCache[event.id] ?? [];
    
    // Check if user has liked/reposted
    final userPubkey = _userProvider?.publicKey ?? '';
    final isLiked = reactions.any((r) => 
      r.pubkey == userPubkey && (r.content == '+' || r.content == '❤️'));
    final isReposted = false; // TODO: Implement repost detection
    
    return TimelineEvent(
      event: event,
      authorProfile: authorProfile,
      reactions: reactions,
      replies: replies,
      isLiked: isLiked,
      isReposted: isReposted,
    );
  }

  Future<void> _subscribeToTimeline(TimelineType type) async {
    if (_relay == null) return;
    
    // Close existing subscription
    final existingSubscription = _subscriptions[type];
    if (existingSubscription != null) {
      await existingSubscription.close();
    }
    
    final filters = _createFiltersForTimeline(type);
    if (filters.isEmpty) return;
    
    final subscription = _relay!.subscribe(
      filters: filters,
      onEvent: (event) => _handleNewEvent(event, type),
      onError: (error) => _logger.warning('Timeline subscription error: $error'),
    );
    
    _subscriptions[type] = subscription;
  }

  void _handleNewEvent(NostrEvent event, TimelineType type) {
    // Cache the event
    _eventCache[event.id] = event;
    
    if (event.kind == 1) {
      // Text note - add to timeline
      _createTimelineEvent(event).then((timelineEvent) {
        final timeline = _timelines[type];
        if (timeline != null) {
          // Insert at the beginning (newest first)
          timeline.insert(0, timelineEvent);
          
          // Limit timeline size
          if (timeline.length > 200) {
            timeline.removeRange(200, timeline.length);
          }
          
          if (_currentTimeline == type) {
            notifyListeners();
          }
        }
      });
    } else if (event.kind == 7) {
      // Reaction - update cached reactions
      final referencedEvents = event.referencedEventIds;
      for (final eventId in referencedEvents) {
        _reactionCache[eventId] = (_reactionCache[eventId] ?? [])..add(event);
        _updateTimelineEventReactions(eventId);
      }
    }
  }

  void _updateTimelineEventReactions(String eventId) {
    // Update all timelines that contain this event
    for (final timeline in _timelines.values) {
      for (int i = 0; i < timeline.length; i++) {
        if (timeline[i].event.id == eventId) {
          _createTimelineEvent(timeline[i].event).then((updatedEvent) {
            timeline[i] = updatedEvent;
            notifyListeners();
          });
          break;
        }
      }
    }
  }

  void _startEventStreamSubscription() {
    _eventStreamSubscription?.cancel();
    
    if (_relay == null) return;
    
    _eventStreamSubscription = _relay!.eventStream.listen(
      (event) {
        // Handle all new events from the relay
        _handleNewEvent(event, _currentTimeline);
      },
      onError: (error) {
        _logger.warning('Event stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _eventStreamSubscription?.cancel();
    
    // Close all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.close();
    }
    _subscriptions.clear();
    
    super.dispose();
  }
}