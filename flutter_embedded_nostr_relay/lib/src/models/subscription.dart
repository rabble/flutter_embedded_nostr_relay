// ABOUTME: Subscription model for managing active query subscriptions
// ABOUTME: Tracks subscription ID, filters, and callback handlers

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'filter.dart';
import 'nostr_event.dart';

/// Represents an active subscription to Nostr events.
/// 
/// A subscription manages the filtering and delivery of events to clients.
/// It can be created either through the direct API ([EmbeddedNostrRelay.subscribe])
/// or through WebSocket REQ messages ([EmbeddedNostrRelay.handleReq]).
/// 
/// ## Event Delivery
/// 
/// Events can be received through multiple mechanisms:
/// - Callback functions ([onEvent], [onEose], [onError])
/// - Stream interface ([eventStream])
/// 
/// ## Lifecycle
/// 
/// 1. **Created**: Subscription is created with filters
/// 2. **Active**: Receives matching events as they arrive
/// 3. **EOSE**: "End of stored events" - all historical events have been sent
/// 4. **Closed**: Subscription is closed and no longer receives events
/// 
/// ## Usage Example
/// 
/// ```dart
/// final subscription = relay.subscribe(
///   filters: [Filter(kinds: [1], limit: 50)],
///   onEvent: (event) {
///     print('New event: ${event.content}');
///   },
///   onEose: () {
///     print('All stored events received');
///   },
/// );
/// 
/// // Alternative: use the stream
/// subscription.eventStream.listen((event) {
///   processEvent(event);
/// });
/// 
/// // Clean up when done
/// await subscription.close();
/// ```
/// 
/// ## Filter Matching
/// 
/// Events are matched against all filters in the subscription using OR logic.
/// An event is delivered if it matches ANY of the filters.
/// 
/// ## Memory Management
/// 
/// Subscriptions should be closed when no longer needed to free resources:
/// ```dart
/// await subscription.close();
/// ```
/// 
/// The relay will automatically clean up subscriptions when clients disconnect.
class Subscription extends Equatable {
  /// Unique identifier for this subscription.
  /// 
  /// This is used to route events to the correct subscription and to
  /// identify the subscription in CLOSE messages.
  final String id;
  
  /// List of filters defining which events this subscription should receive.
  /// 
  /// Events are matched against ALL filters using OR logic - an event
  /// is delivered if it matches ANY of the filters.
  final List<Filter> filters;
  
  /// Callback function called when a matching event is received.
  /// 
  /// This is an alternative to listening to [eventStream]. Both mechanisms
  /// can be used simultaneously.
  final Function(NostrEvent)? onEvent;
  
  /// Callback function called when all stored events have been sent.
  /// 
  /// EOSE (End of Stored Events) indicates that the relay has finished
  /// sending historical events and will now only send new events as
  /// they are published.
  final Function()? onEose;
  
  /// Callback function called when an error occurs.
  /// 
  /// Errors are also added to the [eventStream] as stream errors.
  final Function(String)? onError;
  
  /// When this subscription was created.
  final DateTime createdAt;
  
  /// Internal stream controller for event delivery.
  final StreamController<NostrEvent> _eventController;
  
  /// Stream of events matching this subscription's filters.
  /// 
  /// This provides an alternative to the callback-based API. Events are
  /// delivered to both the stream and the callbacks (if provided).
  /// 
  /// Example:
  /// ```dart
  /// subscription.eventStream.listen(
  ///   (event) => processEvent(event),
  ///   onError: (error) => handleError(error),
  /// );
  /// ```
  Stream<NostrEvent> get eventStream => _eventController.stream;

  Subscription({
    required this.id,
    required this.filters,
    this.onEvent,
    this.onEose,
    this.onError,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        _eventController = StreamController<NostrEvent>.broadcast();

  /// Check if an event matches any of the subscription's filters.
  /// 
  /// Tests the event against all filters using OR logic. Returns true
  /// if the event matches ANY of the filters.
  /// 
  /// Parameters:
  /// - [event]: The event to test against the filters
  /// 
  /// Returns `true` if the event matches at least one filter, `false` otherwise.
  /// 
  /// This method is used internally by the relay to determine if an event
  /// should be delivered to this subscription.
  bool matchesEvent(NostrEvent event) {
    final eventJson = event.toJson();
    return filters.any((filter) => filter.matches(eventJson));
  }

  /// Process an incoming event for this subscription.
  /// 
  /// This method is called by the relay when a new event should be delivered
  /// to this subscription. It first checks if the event matches the filters,
  /// and if so, delivers it via both the stream and callback mechanisms.
  /// 
  /// Parameters:
  /// - [event]: The event to process and potentially deliver
  /// 
  /// The event will only be delivered if it matches at least one of the
  /// subscription's filters.
  void processEvent(NostrEvent event) {
    final matches = matchesEvent(event);
    if (!matches) {
      // Debug logging for hashtag filters
      final hasHashtagFilter = filters.any((f) => f.tags != null && f.tags!.containsKey('#t'));
      if (hasHashtagFilter) {
        final eventJson = event.toJson();
        print('[SUBSCRIPTION DEBUG] Event ${event.id.substring(0, 8)} did NOT match filter');
        print('[SUBSCRIPTION DEBUG]   Event tags: ${eventJson['tags']}');
        for (final filter in filters) {
          if (filter.tags != null && filter.tags!.containsKey('#t')) {
            print('[SUBSCRIPTION DEBUG]   Filter #t: ${filter.tags!['#t']}');
          }
        }
      }
    }
    if (matches) {
      _eventController.add(event);
      onEvent?.call(event);
    }
  }

  /// Signal end of stored events (EOSE).
  /// 
  /// This method is called by the relay after all stored events matching
  /// the subscription filters have been sent. After EOSE, only new events
  /// will be delivered as they are published.
  /// 
  /// The EOSE callback (if provided) will be invoked.
  void signalEose() {
    onEose?.call();
  }

  /// Handle error
  void handleError(String error) {
    _eventController.addError(error);
    onError?.call(error);
  }

  /// Close the subscription and free its resources.
  /// 
  /// After calling this method, the subscription will no longer receive events
  /// and cannot be reused. The event stream will be closed and all callbacks
  /// will stop being called.
  /// 
  /// This should be called when the subscription is no longer needed to
  /// prevent memory leaks.
  /// 
  /// Example:
  /// ```dart
  /// // When done with the subscription
  /// await subscription.close();
  /// ```
  Future<void> close() async {
    await _eventController.close();
  }

  /// Get the age of this subscription
  Duration get age => DateTime.now().difference(createdAt);

  /// Check if subscription is still fresh (less than 1 hour old)
  bool get isFresh => age.inHours < 1;

  /// Create REQ message for this subscription
  List<dynamic> toReqMessage() {
    return [
      'REQ',
      id,
      ...filters.map((f) => f.toJson()),
    ];
  }

  /// Create CLOSE message for this subscription
  List<dynamic> toCloseMessage() {
    return ['CLOSE', id];
  }

  @override
  List<Object?> get props => [id, filters, createdAt];

  @override
  String toString() {
    return 'Subscription(id: $id, filters: ${filters.length})';
  }
}