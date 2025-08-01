// ABOUTME: Main entry point for the embedded Nostr relay
// ABOUTME: Coordinates storage, networking, subscriptions and P2P sync

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../models/subscription.dart';
import '../models/relay_info.dart';
import '../storage/event_store.dart';
import '../storage/database_helper.dart';
import '../utils/logger.dart';
import 'constants.dart';

enum TransportType { ble, wifiDirect }

class Peer {
  final String id;
  final String name;
  final TransportType transport;
  final DateTime discoveredAt;
  
  Peer({
    required this.id,
    required this.name,
    required this.transport,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();
}

class EmbeddedNostrRelay {
  final EventStore _eventStore = EventStore();
  final Map<String, Subscription> _subscriptions = {};
  final StreamController<NostrEvent> _eventStreamController = 
      StreamController<NostrEvent>.broadcast();
  
  bool _initialized = false;
  Timer? _gcTimer;
  
  // Public streams
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;
  
  /// Initialize the embedded relay
  Future<void> initialize({
    Level logLevel = Level.INFO,
    bool enableGarbageCollection = true,
  }) async {
    if (_initialized) return;
    
    // Initialize logger
    RelayLogger.init(level: logLevel);
    RelayLogger.info('Initializing Flutter Embedded Nostr Relay');
    
    // Initialize database
    final db = await DatabaseHelper.instance.database;
    RelayLogger.info('Database initialized');
    
    // Start garbage collection timer
    if (enableGarbageCollection) {
      _gcTimer = Timer.periodic(
        RelayConstants.vacuumInterval,
        (_) => _runGarbageCollection(),
      );
    }
    
    _initialized = true;
    RelayLogger.info('Embedded relay initialized successfully');
  }
  
  /// Subscribe to events with filters
  Subscription subscribe({
    required List<Filter> filters,
    Function(NostrEvent)? onEvent,
    Function()? onEose,
    Function(String)? onError,
    String? subscriptionId,
  }) {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    final id = subscriptionId ?? _generateSubscriptionId();
    
    // Create subscription
    final subscription = Subscription(
      id: id,
      filters: filters,
      onEvent: onEvent,
      onEose: onEose,
      onError: onError,
    );
    
    _subscriptions[id] = subscription;
    RelayLogger.subscription('created', id, 'filters: ${filters.length}');
    
    // Query existing events asynchronously
    _queryAndStreamEvents(subscription);
    
    return subscription;
  }
  
  /// Unsubscribe from a subscription
  Future<void> unsubscribe(String subscriptionId) async {
    final subscription = _subscriptions.remove(subscriptionId);
    if (subscription != null) {
      await subscription.close();
      RelayLogger.subscription('closed', subscriptionId);
    }
  }
  
  /// Publish an event
  Future<bool> publish(NostrEvent event) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    // Validate event
    if (!event.isValid) {
      RelayLogger.warning('Rejecting invalid event: ${event.id}');
      return false;
    }
    
    // Store event
    final stored = await _eventStore.storeEvent(event);
    
    if (stored) {
      // Notify local subscriptions
      _notifySubscriptions(event);
      
      // Emit to global stream
      _eventStreamController.add(event);
      
      RelayLogger.event('published', event.id);
    }
    
    return stored;
  }
  
  /// Query events directly without subscription
  Future<List<NostrEvent>> queryEvents(List<Filter> filters) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    final stopwatch = Stopwatch()..start();
    final events = await _eventStore.queryEvents(filters);
    stopwatch.stop();
    
    RelayLogger.perf('query', stopwatch.elapsed, 'returned ${events.length} events');
    
    return events;
  }
  
  /// Get a single event by ID
  Future<NostrEvent?> getEvent(String id) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    return await _eventStore.getEvent(id);
  }
  
  /// Delete events (implements NIP-09)
  Future<void> deleteEvents(List<String> eventIds) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    await _eventStore.deleteEvents(eventIds);
    RelayLogger.info('Deleted ${eventIds.length} events');
  }
  
  /// Get relay information (NIP-11)
  RelayInfo getRelayInfo() {
    return RelayInfo.embedded();
  }
  
  /// Get database statistics
  Future<Map<String, int>> getStats() async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    return await DatabaseHelper.instance.getStats();
  }
  
  /// Enable P2P synchronization
  Future<void> enableP2PSync({
    required List<TransportType> transports,
    Function(Peer)? onPeerDiscovered,
    Function(Peer)? onPeerLost,
  }) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    // Platform check
    if (kIsWeb) {
      RelayLogger.warning('P2P sync not supported on web platform');
      return;
    }
    
    if (transports.contains(TransportType.ble)) {
      // TODO: Initialize BLE transport
      RelayLogger.info('BLE transport enabled');
    }
    
    if (transports.contains(TransportType.wifiDirect)) {
      if (Platform.isAndroid) {
        // TODO: Initialize WiFi Direct transport
        RelayLogger.info('WiFi Direct transport enabled');
      } else {
        RelayLogger.warning('WiFi Direct only supported on Android');
      }
    }
  }
  
  /// Add an external relay for proxying
  Future<void> addExternalRelay(String url) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    // TODO: Implement external relay connection
    RelayLogger.info('Added external relay: $url');
  }
  
  /// Configure NIP-65 relay lists
  Future<void> setRelayList({
    required List<String> read,
    required List<String> write,
  }) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    // TODO: Implement NIP-65 relay list management
    RelayLogger.info('Updated relay list - read: ${read.length}, write: ${write.length}');
  }
  
  /// Shutdown the relay
  Future<void> shutdown() async {
    RelayLogger.info('Shutting down embedded relay');
    
    // Cancel timers
    _gcTimer?.cancel();
    
    // Close subscriptions
    for (final subscription in _subscriptions.values) {
      await subscription.close();
    }
    _subscriptions.clear();
    
    // Close streams
    await _eventStreamController.close();
    
    // Close database
    await DatabaseHelper.instance.close();
    
    _initialized = false;
    RelayLogger.info('Embedded relay shut down');
  }
  
  // Private methods
  
  String _generateSubscriptionId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  
  Future<void> _queryAndStreamEvents(Subscription subscription) async {
    try {
      // Query existing events
      final events = await _eventStore.queryEvents(subscription.filters);
      
      // Send events to subscription
      for (final event in events) {
        subscription.processEvent(event);
      }
      
      // Signal end of stored events
      subscription.signalEose();
      
    } catch (e) {
      RelayLogger.error('Error querying events for subscription ${subscription.id}', e);
      subscription.handleError(e.toString());
    }
  }
  
  void _notifySubscriptions(NostrEvent event) {
    for (final subscription in _subscriptions.values) {
      if (subscription.matchesEvent(event)) {
        subscription.processEvent(event);
      }
    }
  }
  
  Future<void> _runGarbageCollection() async {
    try {
      RelayLogger.info('Running garbage collection');
      
      // Get followed users (would come from kind:3 contact lists)
      final followedUsers = <String>[]; // TODO: Get from contact lists
      
      // Run GC
      final deleted = await _eventStore.garbageCollect(
        retentionDays: 90,
        preserveAuthors: followedUsers,
      );
      
      if (deleted > 0) {
        // Run vacuum if significant deletions
        await DatabaseHelper.instance.vacuum();
      }
      
    } catch (e) {
      RelayLogger.error('Garbage collection failed', e);
    }
  }
}