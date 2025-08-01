// ABOUTME: Subscription model for managing active query subscriptions
// ABOUTME: Tracks subscription ID, filters, and callback handlers

import 'dart:async';
import 'package:equatable/equatable.dart';
import 'filter.dart';
import 'nostr_event.dart';

class Subscription extends Equatable {
  final String id;
  final List<Filter> filters;
  final Function(NostrEvent)? onEvent;
  final Function()? onEose;
  final Function(String)? onError;
  final DateTime createdAt;
  final StreamController<NostrEvent> _eventController;
  
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

  /// Check if an event matches any of the subscription filters
  bool matchesEvent(NostrEvent event) {
    final eventJson = event.toJson();
    return filters.any((filter) => filter.matches(eventJson));
  }

  /// Process an incoming event
  void processEvent(NostrEvent event) {
    if (matchesEvent(event)) {
      _eventController.add(event);
      onEvent?.call(event);
    }
  }

  /// Signal end of stored events
  void signalEose() {
    onEose?.call();
  }

  /// Handle error
  void handleError(String error) {
    _eventController.addError(error);
    onError?.call(error);
  }

  /// Close the subscription
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