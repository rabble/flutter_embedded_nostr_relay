// ABOUTME: Provider for managing timeline events and subscriptions
// ABOUTME: Handles real-time event updates and timeline state

import 'package:flutter/foundation.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'nostr_provider.dart';

class TimelineProvider extends ChangeNotifier {
  final NostrProvider _nostrProvider;
  final List<NostrEvent> _events = [];
  Subscription? _subscription;
  
  TimelineProvider(this._nostrProvider);
  
  List<NostrEvent> get events => List.unmodifiable(_events);
  
  void startSubscription() {
    if (!_nostrProvider.isInitialized) return;
    
    _subscription?.close();
    _events.clear();
    
    _subscription = _nostrProvider.subscribeToAddressableEvents(
      onEvent: (event) {
        // Add to beginning for newest first
        _events.insert(0, event);
        notifyListeners();
      },
      onEose: () {
        // End of stored events
        notifyListeners();
      },
    );
  }
  
  void stopSubscription() {
    _subscription?.close();
    _subscription = null;
  }
  
  void clearTimeline() {
    _events.clear();
    notifyListeners();
  }
  
  @override
  void dispose() {
    stopSubscription();
    super.dispose();
  }
}