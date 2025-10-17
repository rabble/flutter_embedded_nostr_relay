// ABOUTME: Manages client subscriptions and routes events to matching subscriptions
// ABOUTME: Handles REQ/CLOSE messages and provides efficient event routing with <10ms performance
import 'dart:async';
import 'package:logging/logging.dart';
import '../models/subscription.dart';
import '../models/nostr_event.dart';
import '../models/relay_message.dart';
import '../models/filter.dart';
import '../utils/logger.dart';

class SubscriptionManager {
  /// Map of client ID to their subscriptions
  final Map<String, Map<String, Subscription>> _clientSubscriptions = {};
  
  /// Statistics tracking
  int _totalEventsRouted = 0;
  int _totalMatchingSubscriptions = 0;
  
  /// Handle REQ message from a client
  Future<Subscription> handleReq(String clientId, ReqMessage reqMessage) async {
    if (clientId.isEmpty) {
      throw ArgumentError('Client ID cannot be empty');
    }
    
    if (reqMessage.subscriptionId.isEmpty) {
      throw ArgumentError('Subscription ID cannot be empty');
    }
    
    if (reqMessage.filters.isEmpty) {
      throw ArgumentError('Filters list cannot be empty');
    }
    
    // Initialize client subscriptions map if not exists
    _clientSubscriptions[clientId] ??= <String, Subscription>{};
    
    // Close existing subscription with same ID if exists
    final existingSubscription = _clientSubscriptions[clientId]![reqMessage.subscriptionId];
    if (existingSubscription != null) {
      await existingSubscription.close();
    }
    
    // Create new subscription
    final subscription = Subscription(
      id: reqMessage.subscriptionId,
      filters: reqMessage.filters,
    );
    
    _clientSubscriptions[clientId]![reqMessage.subscriptionId] = subscription;
    
    RelayLogger.subscription('created', reqMessage.subscriptionId, 
        'client: $clientId, filters: ${reqMessage.filters.length}');
    
    return subscription;
  }
  
  /// Handle CLOSE message from a client
  Future<bool> handleClose(String clientId, CloseMessage closeMessage) async {
    final clientSubs = _clientSubscriptions[clientId];
    if (clientSubs == null) {
      return false;
    }
    
    final subscription = clientSubs.remove(closeMessage.subscriptionId);
    if (subscription == null) {
      return false;
    }
    
    await subscription.close();
    
    // Clean up empty client map
    if (clientSubs.isEmpty) {
      _clientSubscriptions.remove(clientId);
    }
    
    RelayLogger.subscription('closed', closeMessage.subscriptionId, 'client: $clientId');
    
    return true;
  }
  
  /// Route an event to all matching subscriptions
  Future<int> routeEvent(NostrEvent event) async {
    int matchingSubscriptions = 0;
    
    for (final clientSubs in _clientSubscriptions.values) {
      for (final subscription in clientSubs.values) {
        if (subscription.matchesEvent(event)) {
          subscription.processEvent(event);
          matchingSubscriptions++;
        }
      }
    }
    
    _totalEventsRouted++;
    _totalMatchingSubscriptions += matchingSubscriptions;
    
    return matchingSubscriptions;
  }
  
  /// Handle client disconnect - removes all subscriptions for the client
  Future<void> handleClientDisconnect(String clientId) async {
    final clientSubs = _clientSubscriptions.remove(clientId);
    if (clientSubs == null) {
      return;
    }
    
    // Close all subscriptions for this client
    for (final subscription in clientSubs.values) {
      await subscription.close();
    }
    
    RelayLogger.info('Client disconnected: $clientId (${clientSubs.length} subscriptions closed)');
  }
  
  /// Get all subscriptions for a specific client
  List<Subscription> getSubscriptionsForClient(String clientId) {
    final clientSubs = _clientSubscriptions[clientId];
    if (clientSubs == null) {
      return [];
    }
    return clientSubs.values.toList();
  }
  
  /// Get the number of active clients
  int getActiveClientsCount() {
    return _clientSubscriptions.length;
  }
  
  /// Get all active subscriptions with their filters
  Map<String, List<Filter>> getAllSubscriptions() {
    final allSubscriptions = <String, List<Filter>>{};
    
    for (final clientSubs in _clientSubscriptions.values) {
      for (final entry in clientSubs.entries) {
        final subId = entry.key;
        final subscription = entry.value;
        allSubscriptions[subId] = subscription.filters;
      }
    }
    
    return allSubscriptions;
  }
  
  /// Get comprehensive statistics
  Map<String, dynamic> getStatistics() {
    final subscriptionsPerClient = <String, int>{};
    int totalSubscriptions = 0;
    
    for (final entry in _clientSubscriptions.entries) {
      final clientId = entry.key;
      final subCount = entry.value.length;
      subscriptionsPerClient[clientId] = subCount;
      totalSubscriptions += subCount;
    }
    
    return {
      'totalSubscriptions': totalSubscriptions,
      'activeClients': _clientSubscriptions.length,
      'subscriptionsPerClient': subscriptionsPerClient,
      'totalEventsRouted': _totalEventsRouted,
      'totalMatchingSubscriptions': _totalMatchingSubscriptions,
    };
  }
  
  /// Close the subscription manager and clean up all resources
  Future<void> close() async {
    RelayLogger.info('Closing SubscriptionManager');
    
    // Close all subscriptions
    for (final clientSubs in _clientSubscriptions.values) {
      for (final subscription in clientSubs.values) {
        await subscription.close();
      }
    }
    
    _clientSubscriptions.clear();
    _totalEventsRouted = 0;
    _totalMatchingSubscriptions = 0;
    
    RelayLogger.info('SubscriptionManager closed');
  }
}