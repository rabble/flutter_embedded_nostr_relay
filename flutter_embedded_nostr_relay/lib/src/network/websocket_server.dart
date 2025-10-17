// ABOUTME: WebSocket server implementation for non-web platforms
// ABOUTME: Provides local relay endpoint on ws://localhost:7447

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';
import '../core/constants.dart';
import '../core/subscription_manager.dart';
import '../storage/event_store.dart';
import '../models/relay_message.dart';
import '../models/nostr_event.dart';

/// WebSocket server implementation providing Nostr relay protocol support.
/// 
/// This class implements a complete Nostr relay server that can be embedded
/// in Flutter applications. It handles WebSocket connections from Nostr clients
/// and processes REQ, CLOSE, and EVENT messages according to the Nostr protocol.
/// 
/// ## Server Lifecycle
/// 
/// 1. **Create**: Instantiate with required dependencies
/// 2. **Start**: Call [start] to begin listening for connections
/// 3. **Accept**: Handle incoming client connections automatically
/// 4. **Process**: Route messages between clients and relay logic
/// 5. **Stop**: Call [stop] to close all connections and stop the server
/// 
/// ## Basic Usage
/// 
/// ```dart
/// final relay = EmbeddedNostrRelay();
/// await relay.initialize();
/// 
/// final server = WebSocketServer(
///   subscriptionManager: relay._subscriptionManager,
///   eventStore: relay._eventStore,
/// );
/// 
/// // Start server on default port (7447)
/// await server.start();
/// print('Server running on ws://localhost:${server.port}');
/// 
/// // Stop when done
/// await server.stop();
/// ```
/// 
/// ## Custom Configuration
/// 
/// ```dart
/// // Custom host and port
/// await server.start(
///   host: '0.0.0.0',  // Listen on all interfaces
///   port: 8080,       // Custom port
/// );
/// ```
/// 
/// ## Message Handling
/// 
/// The server handles three main message types:
/// - **REQ**: Creates subscriptions and sends matching events
/// - **CLOSE**: Closes subscriptions
/// - **EVENT**: Accepts new events for storage and broadcasting
/// 
/// ## Client Management
/// 
/// - Automatic client connection tracking
/// - Subscription cleanup on disconnect
/// - Message broadcasting to relevant clients
/// - Statistics collection
/// 
/// ## Error Handling
/// 
/// - Invalid messages result in NOTICE responses
/// - Connection errors are logged and handled gracefully
/// - Message size limits are enforced
/// - Malformed JSON is rejected
/// 
/// ## Performance Features
/// 
/// - Broadcast messaging for efficient event distribution
/// - Connection pooling and reuse
/// - Message statistics for monitoring
/// - Configurable message size limits
class WebSocketServer {
  /// Internal HTTP server instance.
  HttpServer? _server;
  
  /// Map of client IDs to WebSocket channels.
  final Map<String, WebSocketChannel> _clients = {};
  
  /// Reverse map of WebSocket channels to client IDs.
  final Map<WebSocketChannel, String> _clientIds = {};
  
  /// Subscription manager for handling client subscriptions.
  final SubscriptionManager subscriptionManager;
  
  /// Event store for querying and storing events.
  final EventStore eventStore;
  
  /// UUID generator for client IDs.
  final Uuid _uuid = const Uuid();
  
  // Statistics tracking
  int _totalMessagesReceived = 0;
  int _totalMessagesSent = 0;

  /// Creates a new WebSocket server instance.
  /// 
  /// Parameters:
  /// - [subscriptionManager]: Handles client subscriptions and event routing
  /// - [eventStore]: Provides access to stored events and event storage
  WebSocketServer({
    required this.subscriptionManager,
    required this.eventStore,
  });
  
  /// Check if the server is currently running.
  /// 
  /// Returns `true` if the server is listening for connections, `false` otherwise.
  bool get isRunning => _server != null;
  
  /// Get the port the server is listening on.
  /// 
  /// Returns the actual port number if the server is running, 0 otherwise.
  /// This is useful when starting with port 0 to let the system choose a port.
  int get port => _server?.port ?? 0;
  
  /// Get the number of active WebSocket connections.
  /// 
  /// Returns the current count of connected clients.
  int get activeConnections => _clients.length;
  
  /// Start the WebSocket server.
  /// 
  /// Begins listening for WebSocket connections on the specified host and port.
  /// If the server is already running, this method does nothing.
  /// 
  /// Parameters:
  /// - [host]: IP address to bind to (default: 'localhost')
  /// - [port]: Port to listen on (default: 7447, use 0 for system-assigned)
  /// 
  /// Example:
  /// ```dart
  /// // Start on default settings (localhost:7447)
  /// await server.start();
  /// 
  /// // Start on all interfaces with custom port
  /// await server.start(host: '0.0.0.0', port: 8080);
  /// 
  /// // Let system choose port
  /// await server.start(port: 0);
  /// print('Server started on port ${server.port}');
  /// ```
  Future<void> start({
    String host = RelayConstants.defaultHost,
    int? port,
  }) async {
    if (_server != null) {
      RelayLogger.warning('WebSocket server already running');
      return;
    }
    
    final serverPort = port ?? RelayConstants.defaultPort;
    
    final handler = webSocketHandler((WebSocketChannel webSocket) {
      _handleConnection(webSocket);
    });
    
    _server = await shelf_io.serve(
      handler,
      host,
      serverPort,
    );
    
    RelayLogger.info('WebSocket server listening on ws://$host:${_server!.port}');
  }
  
  /// Stop the WebSocket server.
  /// 
  /// Closes all active client connections and stops listening for new connections.
  /// This method is safe to call multiple times and will do nothing if the
  /// server is not running.
  /// 
  /// All client connections will be gracefully closed and their subscriptions
  /// will be cleaned up automatically.
  /// 
  /// Example:
  /// ```dart
  /// // Stop the server when shutting down
  /// await server.stop();
  /// ```
  Future<void> stop() async {
    if (_server == null) return;
    
    // Close all client connections
    final closePromises = <Future>[];
    final clientsToClose = List.from(_clients.values);
    for (final client in clientsToClose) {
      closePromises.add(client.sink.close());
    }
    
    // Wait for all connections to close
    await Future.wait(closePromises);
    _clients.clear();
    _clientIds.clear();
    
    // Stop server
    await _server!.close();
    _server = null;
    
    RelayLogger.info('WebSocket server stopped');
  }
  
  void _handleConnection(WebSocketChannel webSocket) {
    final clientId = _uuid.v4();
    _clients[clientId] = webSocket;
    _clientIds[webSocket] = clientId;
    
    RelayLogger.ws('client-connected', 'Client $clientId connected. Total clients: ${_clients.length}');
    
    // Listen for messages
    webSocket.stream.listen(
      (message) {
        _handleMessage(webSocket, message);
      },
      onError: (error) {
        RelayLogger.error('WebSocket error for client $clientId', error);
        _handleClientDisconnect(webSocket);
      },
      onDone: () {
        _handleClientDisconnect(webSocket);
      },
    );
  }
  
  void _handleClientDisconnect(WebSocketChannel webSocket) {
    final clientId = _clientIds.remove(webSocket);
    if (clientId != null) {
      _clients.remove(clientId);
      
      // Clean up subscriptions
      subscriptionManager.handleClientDisconnect(clientId);
      
      RelayLogger.ws('client-disconnected', 'Client $clientId disconnected. Total clients: ${_clients.length}');
    }
  }
  
  Future<void> _handleMessage(WebSocketChannel client, dynamic message) async {
    final clientId = _clientIds[client];
    if (clientId == null) return;
    
    _totalMessagesReceived++;
    
    try {
      // Check message size
      if (message.toString().length > RelayConstants.maxMessageLength) {
        _sendNotice(client, RelayConstants.errMessageTooLong);
        return;
      }
      
      // Parse JSON message
      final List<dynamic> messageList;
      try {
        messageList = json.decode(message.toString()) as List<dynamic>;
      } catch (e) {
        _sendNotice(client, RelayConstants.errInvalidMessage);
        return;
      }
      
      if (messageList.isEmpty) {
        _sendNotice(client, RelayConstants.errInvalidMessage);
        return;
      }
      
      // Parse message type
      final messageType = messageList[0] as String;
      RelayLogger.ws('message-received', '$messageType from client $clientId');
      
      switch (messageType.toUpperCase()) {
        case 'REQ':
          await _handleReqMessage(client, clientId, ReqMessage.fromJsonArray(messageList));
          break;
        case 'CLOSE':
          await _handleCloseMessage(client, clientId, CloseMessage.fromJsonArray(messageList));
          break;
        case 'EVENT':
          final eventMessage = RelayMessage.fromJson(messageList);
          if (eventMessage is ClientEventMessage) {
            await _handleClientEventMessage(client, clientId, eventMessage);
          } else if (eventMessage is EventMessage) {
            await _handleEventMessage(client, clientId, eventMessage);
          } else {
            _sendNotice(client, 'Invalid EVENT message format');
          }
          break;
        default:
          _sendNotice(client, 'Unknown message type: $messageType');
      }
    } catch (e) {
      RelayLogger.error('Failed to handle WebSocket message from client $clientId', e);
      _sendNotice(client, RelayConstants.errInvalidMessage);
    }
  }
  
  Future<void> _handleReqMessage(WebSocketChannel client, String clientId, ReqMessage reqMessage) async {
    try {
      // Create subscription
      final subscription = await subscriptionManager.handleReq(clientId, reqMessage);
      
      // Query stored events
      final events = await eventStore.queryEvents(reqMessage.filters);
      
      // Send matching events to client
      for (final event in events) {
        final eventMessage = EventMessage(
          subscriptionId: reqMessage.subscriptionId,
          event: event,
        );
        _sendMessage(client, eventMessage.toJsonString());
      }
      
      // Send EOSE
      final eoseMessage = EoseMessage(subscriptionId: reqMessage.subscriptionId);
      _sendMessage(client, eoseMessage.toJsonString());
      
      RelayLogger.subscription('processed-req', reqMessage.subscriptionId, 
          'client: $clientId, sent ${events.length} events');
    } catch (e) {
      RelayLogger.error('Failed to handle REQ message', e);
      _sendNotice(client, 'Error processing subscription: ${e.toString()}');
    }
  }
  
  Future<void> _handleCloseMessage(WebSocketChannel client, String clientId, CloseMessage closeMessage) async {
    try {
      final success = await subscriptionManager.handleClose(clientId, closeMessage);
      
      if (!success) {
        RelayLogger.subscription('close-not-found', closeMessage.subscriptionId, 'client: $clientId');
      }
    } catch (e) {
      RelayLogger.error('Failed to handle CLOSE message', e);
    }
  }
  
  Future<void> _handleClientEventMessage(WebSocketChannel client, String clientId, ClientEventMessage eventMessage) async {
    try {
      final event = eventMessage.event;
      
      // Validate event
      if (!event.isValid) {
        _sendOkMessage(client, event.id, false, 'invalid: event signature verification failed');
        return;
      }
      
      // Store event
      final stored = await eventStore.storeEvent(event);
      
      if (stored) {
        // Route to matching subscriptions
        final matchingSubscriptions = await subscriptionManager.routeEvent(event);
        
        // Send event to all clients with matching subscriptions
        await _broadcastEventToSubscribers(event);
        
        _sendOkMessage(client, event.id, true, '');
        
        RelayLogger.event('accepted', event.id, 
            'kind: ${event.kind}, routed to $matchingSubscriptions subscriptions');
      } else {
        _sendOkMessage(client, event.id, false, 'duplicate: event already exists');
      }
    } catch (e) {
      RelayLogger.error('Failed to handle CLIENT_EVENT message', e);
      _sendOkMessage(client, eventMessage.event.id, false, 'error: ${e.toString()}');
    }
  }

  Future<void> _handleEventMessage(WebSocketChannel client, String clientId, EventMessage eventMessage) async {
    // This method handles relay-to-client EVENT messages (usually not received by relays)
    RelayLogger.warning('Received relay-to-client EVENT message from client $clientId');
    _sendNotice(client, 'Unexpected EVENT message format');
  }
  
  Future<void> _broadcastEventToSubscribers(NostrEvent event) async {
    for (final entry in _clients.entries) {
      final clientId = entry.key;
      final client = entry.value;
      
      final subscriptions = subscriptionManager.getSubscriptionsForClient(clientId);
      
      for (final subscription in subscriptions) {
        if (subscription.matchesEvent(event)) {
          final eventMessage = EventMessage(
            subscriptionId: subscription.id,
            event: event,
          );
          _sendMessage(client, eventMessage.toJsonString());
        }
      }
    }
  }
  
  void _sendMessage(WebSocketChannel client, String message) {
    try {
      client.sink.add(message);
      _totalMessagesSent++;
    } catch (e) {
      RelayLogger.error('Failed to send message to client', e);
    }
  }
  
  void _sendNotice(WebSocketChannel client, String message) {
    final noticeMessage = NoticeMessage(message: message);
    _sendMessage(client, noticeMessage.toJsonString());
  }
  
  void _sendOkMessage(WebSocketChannel client, String eventId, bool accepted, String message) {
    final okMessage = OkMessage(
      eventId: eventId,
      accepted: accepted,
      message: message,
    );
    _sendMessage(client, okMessage.toJsonString());
  }
  
  /// Get server statistics.
  /// 
  /// Returns a map containing server performance and connection metrics:
  /// - `activeConnections`: Number of currently connected clients
  /// - `totalMessagesReceived`: Total messages received from clients
  /// - `totalMessagesSent`: Total messages sent to clients
  /// - `isRunning`: Whether the server is currently running
  /// - `port`: Port the server is listening on (0 if not running)
  /// 
  /// This is useful for monitoring, debugging, and health checks.
  /// 
  /// Example:
  /// ```dart
  /// final stats = server.getStatistics();
  /// print('Active connections: ${stats['activeConnections']}');
  /// print('Messages received: ${stats['totalMessagesReceived']}');
  /// ```
  Map<String, dynamic> getStatistics() {
    return {
      'activeConnections': _clients.length,
      'totalMessagesReceived': _totalMessagesReceived,
      'totalMessagesSent': _totalMessagesSent,
      'isRunning': isRunning,
      'port': port,
    };
  }
}