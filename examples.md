// lib/src/relay/embedded_relay.dart

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// An embedded Nostr relay that runs within your Flutter application
/// Provides local-first functionality with optional P2P synchronization
class EmbeddedNostrRelay {
  final RelayConfig config;
  late final EventStore _eventStore;
  late final WebSocketServer? _wsServer;
  late final SubscriptionManager _subscriptionManager;
  late final SyncManager? _syncManager;
  
  EmbeddedNostrRelay({required this.config});
  
  /// Initialize the embedded relay
  Future<void> init() async {
    // Initialize storage
    _eventStore = await EventStore.create(config.databasePath);
    
    // Initialize subscription manager
    _subscriptionManager = SubscriptionManager(_eventStore);
    
    // Initialize WebSocket server (not on web)
    if (!kIsWeb && config.enableLocalServer) {
      _wsServer = await WebSocketServer.start(
        port: config.localServerPort,
        onMessage: _handleClientMessage,
      );
    }
    
    // Initialize P2P sync if enabled
    if (config.enableP2PSync && !kIsWeb) {
      _syncManager = SyncManager(
        eventStore: _eventStore,
        deviceId: config.deviceId,
      );
      await _syncManager!.startDiscovery();
    }
  }
  
  /// Store an event locally
  Future<void> storeEvent(NostrEvent event) async {
    // Validate event
    if (!await EventValidator.validate(event)) {
      throw InvalidEventException('Event validation failed');
    }
    
    // Store in database
    await _eventStore.saveEvent(event);
    
    // Notify active subscriptions
    await _subscriptionManager.notifySubscribers(event);
    
    // Queue for P2P sync if enabled
    _syncManager?.queueForSync(event);
  }
  
  /// Query events with filters
  Stream<NostrEvent> queryEvents(List<Filter> filters) {
    return _eventStore.query(filters);
  }
  
  /// Subscribe to live events matching filters
  String subscribe(
    List<Filter> filters,
    void Function(NostrEvent) onEvent,
  ) {
    return _subscriptionManager.addSubscription(
      filters: filters,
      onEvent: onEvent,
    );
  }
  
  /// Handle WebSocket client messages
  Future<void> _handleClientMessage(
    String clientId,
    ClientMessage message,
  ) async {
    switch (message.type) {
      case MessageType.event:
        // Handle EVENT command
        final event = message.event!;
        try {
          await storeEvent(event);
          await _wsServer!.send(clientId, OkMessage(
            eventId: event.id,
            accepted: true,
          ));
        } catch (e) {
          await _wsServer!.send(clientId, OkMessage(
            eventId: event.id,
            accepted: false,
            message: e.toString(),
          ));
        }
        break;
        
      case MessageType.req:
        // Handle REQ command
        final subId = message.subscriptionId!;
        final filters = message.filters!;
        
        // Send existing events
        await for (final event in queryEvents(filters)) {
          await _wsServer!.send(clientId, EventMessage(
            subscriptionId: subId,
            event: event,
          ));
        }
        
        // Send EOSE
        await _wsServer!.send(clientId, EoseMessage(
          subscriptionId: subId,
        ));
        
        // Subscribe to future events
        _subscriptionManager.addClientSubscription(
          clientId: clientId,
          subscriptionId: subId,
          filters: filters,
        );
        break;
        
      case MessageType.close:
        // Handle CLOSE command
        _subscriptionManager.removeClientSubscription(
          clientId: clientId,
          subscriptionId: message.subscriptionId!,
        );
        break;
    }
  }
  
  /// Get relay information (NIP-11)
  RelayInfo getRelayInfo() {
    return RelayInfo(
      name: config.relayName,
      description: 'Embedded Nostr relay for ${config.appName}',
      pubkey: config.relayPubkey,
      contact: config.contactEmail,
      supportedNips: [1, 2, 9, 11, 18, 25, 33],
      software: 'flutter_embedded_nostr_relay',
      version: '0.1.0',
    );
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    await _wsServer?.stop();
    await _syncManager?.stop();
    await _eventStore.close();
  }
}

/// Configuration for the embedded relay
class RelayConfig {
  final String databasePath;
  final String appName;
  final String relayName;
  final String? relayPubkey;
  final String? contactEmail;
  final bool enableLocalServer;
  final int localServerPort;
  final bool enableP2PSync;
  final String deviceId;
  
  RelayConfig({
    required this.databasePath,
    required this.appName,
    this.relayName = 'Embedded Relay',
    this.relayPubkey,
    this.contactEmail,
    this.enableLocalServer = true,
    this.localServerPort = 7777,
    this.enableP2PSync = true,
    required this.deviceId,
  });
}

// Example usage in your Flutter app:
/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the embedded relay
  final relay = EmbeddedNostrRelay(
    config: RelayConfig(
      databasePath: 'nostr_events.db',
      appName: 'OpenVine',
      deviceId: await getDeviceId(),
    ),
  );
  
  await relay.init();
  
  // Use it in your app
  runApp(MyApp(relay: relay));
}

class MyApp extends StatelessWidget {
  final EmbeddedNostrRelay relay;
  
  MyApp({required this.relay});
  
  @override
  Widget build(BuildContext context) {
    // Your app can now:
    // 1. Store events locally with relay.storeEvent()
    // 2. Query events with relay.queryEvents()
    // 3. Subscribe to live updates with relay.subscribe()
    // 4. Connect Nostr clients to ws://localhost:7777
    // 5. Automatically sync with nearby devices via P2P
    
    return MaterialApp(
      home: VideoFeedScreen(relay: relay),
    );
  }
}
*/