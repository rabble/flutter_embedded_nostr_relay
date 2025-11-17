// ABOUTME: Main entry point for the embedded Nostr relay
// ABOUTME: Coordinates storage, networking, subscriptions and P2P sync

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../models/subscription.dart';
import '../models/relay_info.dart';
import '../models/relay_message.dart';
import '../storage/event_store.dart';
import '../storage/event_write_queue.dart';
import '../storage/database_helper.dart';
import '../network/external_relay_client.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart';
import 'constants.dart';
import 'subscription_manager.dart';
import 'function_channel_relay.dart';

/// Transport protocols available for P2P synchronization.
/// 
/// These are used when [EmbeddedNostrRelay.enableP2PSync] is called to specify
/// which transport mechanisms should be enabled for peer discovery and
/// event synchronization.
enum TransportType { 
  /// Bluetooth Low Energy transport (cross-platform)
  ble, 
  /// WiFi Direct transport (Android only)
  wifiDirect 
}

/// Represents a discovered peer for P2P synchronization.
/// 
/// Contains information about a nearby device that can sync Nostr events
/// via BLE or WiFi Direct transport protocols.
class Peer {
  /// Unique identifier for the peer device
  final String id;
  
  /// Human-readable name of the peer device
  final String name;
  
  /// Transport protocol used to discover this peer
  final TransportType transport;
  
  /// When this peer was first discovered
  final DateTime discoveredAt;
  
  /// Creates a new peer instance.
  /// 
  /// The [discoveredAt] timestamp defaults to the current time if not provided.
  Peer({
    required this.id,
    required this.name,
    required this.transport,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();
}

/// Main entry point for the Flutter Embedded Nostr Relay.
/// 
/// This class provides a complete Nostr relay implementation that can be
/// embedded directly into Flutter applications. It manages event storage,
/// subscriptions, WebSocket connections, and P2P synchronization.
/// 
/// ## Basic Usage
/// 
/// ```dart
/// final relay = EmbeddedNostrRelay();
/// 
/// // Initialize the relay
/// await relay.initialize();
/// 
/// // Subscribe to events
/// final subscription = relay.subscribe(
///   filters: [Filter(kinds: [1])], // Text notes
///   onEvent: (event) => print('New event: ${event.content}'),
/// );
/// 
/// // Publish an event
/// final event = NostrEvent.create(
///   pubkey: userPubkey,
///   kind: 1,
///   content: 'Hello Nostr!',
///   tags: [],
/// ).sign(userPrivateKey);
/// 
/// await relay.publish(event);
/// 
/// // Clean up
/// await relay.shutdown();
/// ```
/// 
/// ## WebSocket Server
/// 
/// The relay can expose a local WebSocket endpoint that external clients
/// can connect to, making your Flutter app act as a full Nostr relay:
/// 
/// ```dart
/// // This is handled by WebSocketServer separately
/// final server = WebSocketServer(
///   subscriptionManager: relay._subscriptionManager,
///   eventStore: relay._eventStore,
/// );
/// await server.start();
/// ```
/// 
/// ## P2P Synchronization
/// 
/// Enable peer-to-peer event synchronization over BLE or WiFi Direct:
/// 
/// ```dart
/// await relay.enableP2PSync(
///   transports: [TransportType.ble, TransportType.wifiDirect],
///   onPeerDiscovered: (peer) => print('Found peer: ${peer.name}'),
/// );
/// ```
/// 
/// ## Event Storage
/// 
/// Events are stored locally in SQLite with automatic garbage collection:
/// 
/// - Regular events are retained based on configurable policies
/// - Replaceable events (kinds 10000-19999, 30000-39999) automatically
///   replace older versions from the same author
/// - Ephemeral events (kinds 20000-29999) are not stored persistently
/// 
/// ## Performance Features
/// 
/// - Optimized database queries with proper indexing
/// - Batch event insertion for sync operations
/// - Automatic database maintenance and garbage collection
/// - Memory-efficient event streaming
/// 
/// ## Thread Safety
/// 
/// All public methods are async and thread-safe. The relay can handle
/// concurrent operations from multiple isolates or UI interactions.
class EmbeddedNostrRelay {
  final EventStore _eventStore = EventStore();
  final SubscriptionManager _subscriptionManager = SubscriptionManager();
  final Map<String, Subscription> _internalSubscriptions = {}; // For legacy API
  final StreamController<NostrEvent> _eventStreamController =
      StreamController<NostrEvent>.broadcast();
  final Map<String, ExternalRelayClient> _externalRelays = {};
  final Map<String, Map<String, bool>> _relaySubscriptions = {}; // relay -> subId -> active

  // Write queue for batching external events to prevent database lock contention
  late final EventWriteQueue _writeQueue;

  bool _initialized = false;
  bool _isShuttingDown = false;
  Timer? _gcTimer;
  Timer? _retryPublishTimer;

  // Function channel interface (replaces WebSocket server)
  FunctionChannelRelay? _functionChannel;
  
  /// Check if the relay is initialized
  bool get isInitialized => _initialized;
  
  /// Stream of all events processed by the relay.
  /// 
  /// This stream emits every event that is successfully published to the relay,
  /// regardless of which subscriptions might be interested in it. It's useful
  /// for implementing global event listeners or debugging.
  /// 
  /// Example:
  /// ```dart
  /// relay.eventStream.listen((event) {
  ///   print('New event published: ${event.kind} from ${event.pubkey}');
  /// });
  /// ```
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;
  
  /// Initialize the embedded relay.
  ///
  /// This must be called before using any other relay functionality. It sets up
  /// the database, logging, and optional garbage collection timer.
  ///
  /// Parameters:
  /// - [logLevel]: Controls logging verbosity (default: Level.INFO)
  /// - [enableGarbageCollection]: Whether to automatically clean up old events (default: true)
  /// - [useFunctionChannel]: Use direct function calls instead of WebSocket (default: true)
  ///
  /// Throws [StateError] if called multiple times without [shutdown] in between.
  ///
  /// Example:
  /// ```dart
  /// await relay.initialize(
  ///   logLevel: Level.WARNING, // Reduce log noise
  ///   enableGarbageCollection: false, // Keep all events
  ///   useFunctionChannel: true, // Use direct function calls
  /// );
  /// ```
  Future<void> initialize({
    Level logLevel = Level.INFO,
    bool enableGarbageCollection = true,
    bool useFunctionChannel = true,
  }) async {
    if (_initialized) return;

    // Reset shutdown flag to allow reinitialization
    _isShuttingDown = false;

    // Initialize logger
    RelayLogger.init(level: logLevel);
    RelayLogger.info('Initializing Flutter Embedded Nostr Relay');

    try {
      // Initialize database with better error handling
      RelayLogger.info('Attempting database initialization...');
      await DatabaseHelper.instance.database;
      RelayLogger.info('Database initialized successfully');

      // Initialize write queue for batching external events
      _writeQueue = EventWriteQueue(_eventStore);
      RelayLogger.info('Write queue initialized for batched event writes');

      // Start garbage collection timer
      if (enableGarbageCollection) {
        _gcTimer = Timer.periodic(
          RelayConstants.vacuumInterval,
          (_) => _runGarbageCollection(),
        );
      }

      // Start publish retry worker
      _retryPublishTimer = Timer.periodic(
        RelayConstants.publishRetryInterval,
        (_) => _retryPendingPublishes(),
      );
      RelayLogger.info('Publish retry worker started (${RelayConstants.publishRetryInterval.inSeconds}s interval)');

      // Initialize function channel if requested
      if (useFunctionChannel) {
        _functionChannel = FunctionChannelRelay(
          subscriptionManager: _subscriptionManager,
          eventStore: _eventStore,
          embeddedRelay: this,
        );
        RelayLogger.info('Function channel relay initialized (direct calls, no WebSocket)');
      }
    } catch (e, stackTrace) {
      RelayLogger.error('Database initialization failed', e);
      RelayLogger.error('Stack trace', stackTrace);

      // On iOS, this might be a permissions or sandbox issue
      if (PlatformUtils.isIOS) {
        RelayLogger.warning('iOS database initialization failed - this may be a sandbox or permissions issue');
        RelayLogger.warning('Attempting to continue with limited functionality');

        // Don't rethrow on iOS to allow the app to continue
        // The app can retry initialization later
      } else {
        // On other platforms, rethrow the error
        rethrow;
      }
    }

    _initialized = true;
    RelayLogger.info('Embedded relay initialized successfully');
  }
  
  /// Handle a REQ message from a WebSocket client.
  /// 
  /// This is primarily used by [WebSocketServer] when processing client requests.
  /// Creates a new subscription and immediately queries existing events that match
  /// the provided filters.
  /// 
  /// Parameters:
  /// - [clientId]: Unique identifier for the WebSocket client
  /// - [reqMessage]: Parsed REQ message containing subscription ID and filters
  /// 
  /// Returns the created [Subscription] that can be used to route future events.
  /// 
  /// Throws [StateError] if the relay is not initialized.
  /// 
  /// Example (typically used internally by WebSocketServer):
  /// ```dart
  /// final reqMessage = ReqMessage(
  ///   subscriptionId: 'sub1',
  ///   filters: [Filter(kinds: [1], limit: 100)],
  /// );
  /// final subscription = await relay.handleReq(clientId, reqMessage);
  /// ```
  Future<Subscription> handleReq(String clientId, ReqMessage reqMessage) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    final subscription = await _subscriptionManager.handleReq(clientId, reqMessage);
    
    // Query existing events asynchronously
    _queryAndStreamEvents(subscription);
    
    return subscription;
  }
  
  /// Handle CLOSE message from client
  Future<bool> handleClose(String clientId, CloseMessage closeMessage) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    return await _subscriptionManager.handleClose(clientId, closeMessage);
  }
  
  /// Handle client disconnect
  Future<void> handleClientDisconnect(String clientId) async {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }
    
    await _subscriptionManager.handleClientDisconnect(clientId);
  }
  
  /// Subscribe to events with filters (direct API usage).
  /// 
  /// Creates a local subscription that will receive matching events. This is
  /// the primary method for Flutter applications to subscribe to events directly
  /// without going through WebSocket protocol.
  /// 
  /// Parameters:
  /// - [filters]: List of filters defining which events to receive
  /// - [onEvent]: Callback fired when a matching event is received
  /// - [onEose]: Callback fired after all stored events have been sent
  /// - [onError]: Callback fired when an error occurs
  /// - [subscriptionId]: Optional custom subscription ID (auto-generated if null)
  /// 
  /// Returns a [Subscription] object that can be used to access the event stream
  /// or close the subscription.
  /// 
  /// Throws [StateError] if the relay is not initialized.
  /// 
  /// Example:
  /// ```dart
  /// final subscription = relay.subscribe(
  ///   filters: [
  ///     Filter(kinds: [1], authors: [userPubkey]), // My notes
  ///     Filter(kinds: [1], pTags: [userPubkey]),   // Mentions of me
  ///   ],
  ///   onEvent: (event) {
  ///     print('Received: ${event.content}');
  ///   },
  ///   onEose: () {
  ///     print('All stored events received');
  ///   },
  /// );
  /// 
  /// // Listen to the stream alternatively
  /// subscription.eventStream.listen((event) {
  ///   updateUI(event);
  /// });
  /// ```
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
    
    // Debug: Log filter details including event IDs
    RelayLogger.info('[SUBSCRIBE] Creating subscription $id with ${filters.length} filters');
    for (var i = 0; i < filters.length; i++) {
      final filter = filters[i];
      if (filter.ids != null && filter.ids!.isNotEmpty) {
        RelayLogger.info('[SUBSCRIBE] Filter $i has ${filter.ids!.length} specific event IDs');
        RelayLogger.info('[SUBSCRIBE] First ID: ${filter.ids!.first}');
      }
      if (filter.kinds != null) {
        RelayLogger.info('[SUBSCRIBE] Filter $i kinds: ${filter.kinds}');
      }
      if (filter.authors != null) {
        RelayLogger.info('[SUBSCRIBE] Filter $i authors: ${filter.authors?.take(2).toList()}');
      }
    }
    
    // Create subscription for internal use (legacy API)
    final subscription = Subscription(
      id: id,
      filters: filters,
      onEvent: onEvent,
      onEose: onEose,
      onError: onError,
    );
    
    _internalSubscriptions[id] = subscription;
    RelayLogger.subscription('created', id, 'filters: ${filters.length}');

    // Query existing events asynchronously
    _queryAndStreamEvents(subscription);

    // Subscribe to external relays
    _subscribeToExternalRelays(id, filters);

    return subscription;
  }
  
  /// Unsubscribe from a subscription (legacy method)
  Future<void> unsubscribe(String subscriptionId) async {
    final subscription = _internalSubscriptions.remove(subscriptionId);
    if (subscription != null) {
      await subscription.close();
      
      // Unsubscribe from external relays
      await _unsubscribeFromExternalRelays(subscriptionId);
      
      RelayLogger.subscription('closed', subscriptionId);
    }
  }
  
  /// Publish an event to the relay.
  /// 
  /// Validates the event signature, stores it in the database, and routes it
  /// to all matching subscriptions. The event will also be emitted on the
  /// global [eventStream].
  /// 
  /// For replaceable events (kinds 10000-19999, 30000-39999), this will
  /// automatically replace any older events from the same author with the
  /// same kind (and d-tag for parameterized replaceable events).
  /// 
  /// Parameters:
  /// - [event]: The signed event to publish
  /// 
  /// Returns `true` if the event was successfully stored, `false` if it was
  /// rejected (invalid signature, duplicate, etc.).
  /// 
  /// Throws [StateError] if the relay is not initialized.
  /// 
  /// Example:
  /// ```dart
  /// // Create and sign an event
  /// final event = NostrEvent.create(
  ///   pubkey: myPubkey,
  ///   kind: 1,
  ///   content: 'Hello, Nostr!',
  ///   tags: [['t', 'hello']],
  /// ).sign(myPrivateKey);
  /// 
  /// // Publish it
  /// final success = await relay.publish(event);
  /// if (success) {
  ///   print('Event published successfully!');
  /// } else {
  ///   print('Event was rejected');
  /// }
  /// ```
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
      // Check if relay is shutting down
      if (_isShuttingDown) {
        RelayLogger.info('Relay is shutting down, skipping event routing for ${event.id}');
        return false;
      }

      // Notify legacy internal subscriptions
      _notifyInternalSubscriptions(event);

      // Route event through subscription manager
      await _subscriptionManager.routeEvent(event);

      // Emit to global stream (only if not shutting down and stream not closed)
      if (!_eventStreamController.isClosed) {
        _eventStreamController.add(event);
      }

      // Publish to external relays
      await _publishToExternalRelays(event);

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
  
  /// Get subscription manager statistics
  Map<String, dynamic> getSubscriptionStats() {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }

    final managerStats = _subscriptionManager.getStatistics();
    managerStats['internalSubscriptions'] = _internalSubscriptions.length;
    return managerStats;
  }

  /// Create a function channel session for direct API access.
  ///
  /// This replaces WebSocket connections with direct function calls,
  /// eliminating network overhead and local network permissions.
  ///
  /// Returns a [FunctionChannelSession] that can be used to:
  /// - Send REQ, CLOSE, and EVENT messages
  /// - Receive events via stream or callbacks
  ///
  /// Example:
  /// ```dart
  /// final session = relay.createFunctionSession();
  ///
  /// // Listen for events
  /// session.responseStream.listen((response) {
  ///   if (response is EventResponse) {
  ///     print('Received event: ${response.event.content}');
  ///   }
  /// });
  ///
  /// // Send a subscription request
  /// await session.sendMessage(ReqMessage(
  ///   subscriptionId: 'sub1',
  ///   filters: [Filter(kinds: [1])],
  /// ));
  /// ```
  FunctionChannelSession createFunctionSession() {
    if (!_initialized) {
      throw StateError('Relay not initialized. Call initialize() first.');
    }

    if (_functionChannel == null) {
      throw StateError('Function channel not initialized. Call initialize(useFunctionChannel: true) first.');
    }

    return _functionChannel!.createSession();
  }

  /// Get the function channel relay instance (if initialized).
  ///
  /// Returns null if the relay was initialized without function channel support.
  FunctionChannelRelay? get functionChannel => _functionChannel;
  
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
      if (PlatformUtils.isAndroid) {
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
    
    RelayLogger.info('[ADD-RELAY] Attempting to add external relay: $url');
    
    if (_externalRelays.containsKey(url)) {
      RelayLogger.info('[ADD-RELAY] External relay already added: $url');
      return;
    }
    
    final client = ExternalRelayClient(url: url);
    
    // Set up event handlers
    client.onEvent = (event) {
      RelayLogger.info('[ADD-RELAY] Event handler triggered for event from $url');
      _handleExternalEvent(url, event);
    };
    
    client.onEose = (subscriptionId) {
      RelayLogger.info('[ADD-RELAY] EOSE from $url for subscription $subscriptionId');
    };
    
    client.onOk = (eventId, status, message) {
      RelayLogger.debug('[ADD-RELAY] OK from $url: $eventId - $status - $message');
    };
    
    client.onNotice = (notice) {
      RelayLogger.info('[ADD-RELAY] NOTICE from $url: $notice');
    };
    
    try {
      await client.connect();
      
      // Only add to our list if connection succeeded
      if (client.isConnected) {
        _externalRelays[url] = client;
        _relaySubscriptions[url] = {};
        
        RelayLogger.info('[ADD-RELAY] Successfully connected to external relay: $url');
        RelayLogger.info('[ADD-RELAY] Total external relays connected: ${_externalRelays.length}');
        
        // Sync existing subscriptions to the new relay
        await _syncSubscriptionsToRelay(url);
        
        RelayLogger.info('[ADD-RELAY] Completed setup for external relay: $url');
      } else {
        RelayLogger.warning('[ADD-RELAY] Failed to establish connection to external relay: $url');
      }
    } catch (e) {
      RelayLogger.error('[ADD-RELAY] Failed to connect to external relay $url: $e');
      // Don't throw - just log and continue without this relay
    }
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
  
  /// Remove an external relay
  Future<void> removeExternalRelay(String url) async {
    final client = _externalRelays[url];
    if (client != null) {
      await client.disconnect();
      _externalRelays.remove(url);
      _relaySubscriptions.remove(url);
      RelayLogger.info('Removed external relay: $url');
    }
  }
  
  /// Get list of connected external relays
  List<String> get connectedRelays => _externalRelays.entries
      .where((entry) => entry.value.isConnected)
      .map((entry) => entry.key)
      .toList();
  
  void _handleExternalEvent(String relayUrl, NostrEvent event) {
    RelayLogger.info('[EXTERNAL-EVENT] Received event ${event.id} from $relayUrl - kind: ${event.kind}');
    RelayLogger.info('[EXTERNAL-EVENT] Event content preview: ${event.content.substring(0, event.content.length.clamp(0, 100))}...');
    
    // Check which subscriptions this event matches
    for (final entry in _internalSubscriptions.entries) {
      final subId = entry.key;
      final subscription = entry.value;
      if (subscription.matchesEvent(event)) {
        RelayLogger.info('[EXTERNAL-EVENT] Event ${event.id} matches subscription $subId');
      }
    }
    
    // Store event locally via write queue (batching prevents database lock contention)
    _writeQueue.enqueue(event).then((stored) {
      if (stored) {
        RelayLogger.info('[EXTERNAL-EVENT] Successfully stored event ${event.id} in local database');

        // Check if relay is shutting down before routing events
        if (_isShuttingDown) {
          RelayLogger.info('[EXTERNAL-EVENT] Relay is shutting down, skipping event routing for ${event.id}');
          return;
        }

        // Route to local subscriptions (including legacy internal subscriptions)
        _notifyInternalSubscriptions(event);
        _subscriptionManager.routeEvent(event);

        // Emit on event stream (only if not shutting down)
        if (!_eventStreamController.isClosed) {
          _eventStreamController.add(event);
        }

        RelayLogger.info('[EXTERNAL-EVENT] Routed event ${event.id} to subscriptions');
      } else {
        RelayLogger.info('[EXTERNAL-EVENT] Event ${event.id} already exists in database or was rejected');
      }
    }).catchError((e) {
      RelayLogger.error('[EXTERNAL-EVENT] Failed to store event ${event.id}: $e');
    });
  }
  
  Future<void> _syncSubscriptionsToRelay(String relayUrl) async {
    final client = _externalRelays[relayUrl];
    if (client == null) return;
    
    // Get all active subscriptions
    final activeSubscriptions = _subscriptionManager.getAllSubscriptions();
    
    for (final entry in activeSubscriptions.entries) {
      final subId = entry.key;
      final filters = entry.value;
      
      try {
        await client.sendRequest(subId, filters);
        _relaySubscriptions[relayUrl]![subId] = true;
        RelayLogger.debug('Synced subscription $subId to relay $relayUrl');
      } catch (e) {
        RelayLogger.error('Failed to sync subscription $subId to $relayUrl: $e');
      }
    }
  }
  
  Future<void> _publishToExternalRelays(NostrEvent event) async {
    final db = await DatabaseHelper.instance.database;
    final eventJson = jsonEncode(event.toJson());
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entry in _externalRelays.entries) {
      final relayUrl = entry.key;
      final client = entry.value;

      // Check connection status and reconnect if needed - do this RIGHT before publishing
      // to minimize race conditions
      if (!client.isConnected) {
        RelayLogger.info('🔌 Relay $relayUrl disconnected, attempting reconnection...');
        try {
          await client.connect();
          // Wait for connection to establish
          await Future.delayed(Duration(milliseconds: 1000));

          if (client.isConnected) {
            RelayLogger.info('✅ Successfully reconnected to $relayUrl');
          } else {
            RelayLogger.warning('⚠️ Reconnection failed - relay still disconnected: $relayUrl');
          }
        } catch (e) {
          RelayLogger.error('❌ Reconnection attempt failed for $relayUrl: $e');
        }
      }

      // Now attempt to publish - check connection one final time
      final isConnectedNow = client.isConnected;
      RelayLogger.debug('📊 Relay $relayUrl connection status before publish: $isConnectedNow');

      if (isConnectedNow) {
        try {
          await client.sendEvent(event);
          RelayLogger.info('📤 Successfully published event ${event.id} to external relay $relayUrl');

          // Remove from pending queue if it was queued before
          try {
            await db.delete(
              'pending_publishes',
              where: 'event_id = ? AND relay_url = ?',
              whereArgs: [event.id, relayUrl],
            );
          } catch (e) {
            RelayLogger.debug('Failed to remove from pending queue: $e');
          }
        } catch (e) {
          RelayLogger.error('❌ Failed to publish event ${event.id} to $relayUrl: $e');

          // Add to retry queue
          try {
            await db.insert(
              'pending_publishes',
              {
                'event_id': event.id,
                'relay_url': relayUrl,
                'event_json': eventJson,
                'retry_count': 0,
                'last_attempt': now,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            RelayLogger.info('📝 Queued event ${event.id} for retry to $relayUrl (publish error)');
          } catch (dbError) {
            RelayLogger.error('Failed to queue event for retry: $dbError');
          }
        }
      } else {
        // Relay not connected even after reconnection attempt - queue for retry
        RelayLogger.warning('⚠️  Relay $relayUrl not connected after reconnect attempt, queuing event ${event.id} for retry');
        try {
          final insertId = await db.insert(
            'pending_publishes',
            {
              'event_id': event.id,
              'relay_url': relayUrl,
              'event_json': eventJson,
              'retry_count': 0,
              'last_attempt': now,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          RelayLogger.info('📝 Event queued in database (row $insertId): ${event.id} -> $relayUrl');
        } catch (dbError) {
          RelayLogger.error('Failed to queue event for retry: $dbError');
        }
      }
    }
  }
  
  Future<void> _subscribeToExternalRelays(String subscriptionId, List<Filter> filters) async {
    RelayLogger.info('[EXTERNAL-SUB] Subscribing to ${_externalRelays.length} external relays - sub: $subscriptionId, filters: ${filters.length}');

    // Log filter details for external relay subscription
    for (var i = 0; i < filters.length; i++) {
      final filter = filters[i];
      if (filter.ids != null && filter.ids!.isNotEmpty) {
        RelayLogger.info('[EXTERNAL-SUB] Filter $i requests ${filter.ids!.length} specific event IDs from external relays');
        for (final id in filter.ids!) {
          RelayLogger.info('[EXTERNAL-SUB] Requesting event ID: $id');
        }
      }
    }

    if (_externalRelays.isEmpty) {
      RelayLogger.warning('[EXTERNAL-SUB] No external relays connected!');
      return;
    }

    for (final entry in _externalRelays.entries) {
      final relayUrl = entry.key;
      final client = entry.value;

      if (client.isConnected) {
        try {
          RelayLogger.info('[EXTERNAL-SUB] Sending REQ to $relayUrl with subscription ID: $subscriptionId');
          final success = await client.sendRequest(subscriptionId, filters);
          if (success) {
            _relaySubscriptions[relayUrl]![subscriptionId] = true;
            RelayLogger.info('[EXTERNAL-SUB] Successfully created subscription $subscriptionId on external relay $relayUrl');
          } else {
            RelayLogger.warning('[EXTERNAL-SUB] Failed to send REQ to $relayUrl');
          }
        } catch (e) {
          RelayLogger.error('[EXTERNAL-SUB] Failed to subscribe to $relayUrl: $e');
        }
      } else {
        RelayLogger.warning('[EXTERNAL-SUB] Relay $relayUrl is not connected, skipping subscription');
      }
    }
  }
  
  Future<void> _unsubscribeFromExternalRelays(String subscriptionId) async {
    for (final entry in _externalRelays.entries) {
      final relayUrl = entry.key;
      final client = entry.value;
      
      if (client.isConnected && _relaySubscriptions[relayUrl]?[subscriptionId] == true) {
        try {
          await client.closeSubscription(subscriptionId);
          _relaySubscriptions[relayUrl]!.remove(subscriptionId);
          RelayLogger.debug('Closed subscription $subscriptionId on external relay $relayUrl');
        } catch (e) {
          RelayLogger.error('Failed to unsubscribe from $relayUrl: $e');
        }
      }
    }
  }
  
  /// Get metrics about pending publishes
  Future<Map<String, dynamic>> getPendingPublishMetrics() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Get total count
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as total FROM pending_publishes',
      );
      final total = countResult.first['total'] as int;

      // Get count by relay
      final relayResult = await db.rawQuery(
        'SELECT relay_url, COUNT(*) as count FROM pending_publishes GROUP BY relay_url',
      );
      final byRelay = Map<String, int>.fromEntries(
        relayResult.map((row) => MapEntry(
          row['relay_url'] as String,
          row['count'] as int,
        )),
      );

      // Get events near max retries
      final nearMaxResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM pending_publishes WHERE retry_count >= ?',
        [RelayConstants.maxPublishRetries - 5],
      );
      final nearMax = nearMaxResult.first['count'] as int;

      return {
        'total_pending': total,
        'by_relay': byRelay,
        'near_max_retries': nearMax,
      };
    } catch (e) {
      RelayLogger.error('Failed to get pending publish metrics: $e');
      return {
        'total_pending': 0,
        'by_relay': <String, int>{},
        'near_max_retries': 0,
        'error': e.toString(),
      };
    }
  }

  /// Retry publishing pending events to external relays
  Future<void> _retryPendingPublishes() async {
    if (_isShuttingDown) {
      RelayLogger.debug('🔄 Retry worker: Skipping retry (shutting down)');
      return;
    }

    try {
      RelayLogger.debug('🔄 Retry worker: Checking for pending publishes...');
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Get pending publishes that need retry
      final pendingRows = await db.query(
        'pending_publishes',
        where: 'retry_count < ?',
        whereArgs: [RelayConstants.maxPublishRetries],
        orderBy: 'created_at ASC',
        limit: 100,
      );

      RelayLogger.info('🔄 Retry worker: Found ${pendingRows.length} pending publishes');

      if (pendingRows.isEmpty) return;

      RelayLogger.info('🔄 Retrying ${pendingRows.length} pending publishes');

      for (final row in pendingRows) {
        final eventId = row['event_id'] as String;
        final relayUrl = row['relay_url'] as String;
        final eventJson = row['event_json'] as String;
        final retryCount = row['retry_count'] as int;
        final id = row['id'] as int;

        // Check if relay is connected
        final client = _externalRelays[relayUrl];
        if (client == null || !client.isConnected) {
          RelayLogger.debug('Relay $relayUrl not connected, skipping retry for event $eventId');
          continue;
        }

        try {
          // Parse event from JSON
          final eventMap = jsonDecode(eventJson) as Map<String, dynamic>;
          final event = NostrEvent.fromJson(eventMap);

          // Attempt to publish
          await client.sendEvent(event);
          RelayLogger.info('✅ Retry SUCCESS: Published event $eventId to $relayUrl (retry #$retryCount)');

          // Remove from queue on success
          await db.delete(
            'pending_publishes',
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (e) {
          RelayLogger.warning('❌ Retry FAILED: Event $eventId to $relayUrl (retry #$retryCount): $e');

          // Increment retry count
          final newRetryCount = retryCount + 1;
          if (newRetryCount >= RelayConstants.maxPublishRetries) {
            RelayLogger.error('⚠️  Max retries reached for event $eventId to $relayUrl, removing from queue');
            await db.delete(
              'pending_publishes',
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            await db.update(
              'pending_publishes',
              {
                'retry_count': newRetryCount,
                'last_attempt': now,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      }
    } catch (e) {
      RelayLogger.error('Error in retry worker: $e');
    }
  }

  /// Shutdown the relay
  Future<void> shutdown() async {
    RelayLogger.info('Shutting down embedded relay');

    // Set shutdown flag FIRST to prevent new events from being added to streams
    _isShuttingDown = true;

    // Cancel timers
    _gcTimer?.cancel();
    _retryPublishTimer?.cancel();

    // Disconnect from external relays (stops new events from arriving)
    for (final relay in _externalRelays.values) {
      await relay.disconnect();
    }
    _externalRelays.clear();
    _relaySubscriptions.clear();

    // CRITICAL: Drain write queue before closing database
    // This ensures all pending events are written and prevents "Cannot add events after close" errors
    RelayLogger.info('Draining write queue before shutdown...');
    await _writeQueue.drain();
    RelayLogger.info('Write queue drained successfully');

    // Close subscription manager
    await _subscriptionManager.close();

    // Close internal subscriptions
    for (final subscription in _internalSubscriptions.values) {
      await subscription.close();
    }
    _internalSubscriptions.clear();

    // Close streams
    await _eventStreamController.close();

    // Close database (safe now that write queue is drained)
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
      RelayLogger.info('[QUERY-LOCAL] Querying local database for subscription ${subscription.id}');

      // Check if we're looking for specific event IDs
      bool hasSpecificIds = false;
      for (final filter in subscription.filters) {
        if (filter.ids != null && filter.ids!.isNotEmpty) {
          hasSpecificIds = true;
          RelayLogger.info('[QUERY-LOCAL] Filter requests ${filter.ids!.length} specific event IDs');
        }
      }

      // Query existing events
      final events = await _eventStore.queryEvents(subscription.filters);

      RelayLogger.info('[QUERY-LOCAL] Found ${events.length} events in local database');

      // Send events to subscription
      for (final event in events) {
        subscription.processEvent(event);
      }

      // Signal end of stored events
      subscription.signalEose();

      // Log if we couldn't find requested events locally
      if (hasSpecificIds && events.isEmpty) {
        RelayLogger.warning('[QUERY-LOCAL] No events found locally for specific IDs - should be fetched from external relays');
      }

    } catch (e, stackTrace) {
      RelayLogger.error('[QUERY-LOCAL] Error querying events for subscription ${subscription.id}', e);
      subscription.handleError(e.toString());
    }
  }
  
  void _notifyInternalSubscriptions(NostrEvent event) {
    for (final subscription in _internalSubscriptions.values) {
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