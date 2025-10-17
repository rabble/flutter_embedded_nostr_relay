// ABOUTME: Provider for managing Nostr service and identity state
// ABOUTME: Handles initialization, key management, and event publishing

import 'package:flutter/foundation.dart';
import '../services/nostr_service.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

class NostrProvider extends ChangeNotifier {
  final NostrService _service = NostrService();
  
  NostrIdentity? get currentIdentity => _service.currentIdentity;
  bool get isInitialized => _service.isInitialized;
  NostrService get service => _service;
  
  Future<void> generateNewIdentity() async {
    await _service.generateNewIdentity();
    notifyListeners();
  }
  
  Future<void> importIdentity(String privateKey) async {
    await _service.importIdentity(privateKey);
    notifyListeners();
  }
  
  Future<NostrEvent> publishTextNote(String content) async {
    final event = await _service.publishTextNote(content);
    return event;
  }
  
  Future<NostrEvent> updateProfile(UserProfile profile) async {
    final event = await _service.updateProfile(profile);
    notifyListeners();
    return event;
  }
  
  Subscription subscribeToTimeline({
    required Function(NostrEvent) onEvent,
    Function()? onEose,
  }) {
    return _service.subscribeToTimeline(
      onEvent: onEvent,
      onEose: onEose,
    );
  }
  
  Subscription subscribeToAddressableEvents({
    required Function(NostrEvent) onEvent,
    Function()? onEose,
  }) {
    return _service.subscribeToAddressableEvents(
      onEvent: onEvent,
      onEose: onEose,
    );
  }
  
  Future<Map<String, int>> getRelayStats() async {
    return await _service.getRelayStats();
  }
  
  @override
  Future<void> dispose() async {
    await _service.dispose();
    super.dispose();
  }
}