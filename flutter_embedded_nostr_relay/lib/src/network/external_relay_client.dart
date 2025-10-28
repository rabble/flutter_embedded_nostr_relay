// ABOUTME: Client for connecting to external Nostr relays
// ABOUTME: Manages WebSocket connections and message routing to external relays

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'websocket_channel_factory.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../models/relay_message.dart';
import '../utils/logger.dart';

class ExternalRelayClient {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;
  final _reconnectTimer = Timer.periodic(Duration(seconds: 5), (_) {});
  bool _shouldReconnect = true;
  
  // Callbacks for different message types
  Function(NostrEvent)? onEvent;
  Function(String)? onEose;
  Function(String, bool, String?)? onOk;
  Function(String)? onNotice;
  
  ExternalRelayClient({required this.url}) {
    _reconnectTimer.cancel(); // Cancel the dummy timer
  }
  
  Future<void> connect() async {
    if (_connected) return;
    
    await runZonedGuarded(() async {
      try {
        RelayLogger.info('Connecting to external relay: $url');
        
        // Create WebSocket connection
        final uri = Uri.parse(url);
        if (uri.scheme != 'ws' && uri.scheme != 'wss') {
          throw Exception('Invalid WebSocket URL scheme: ${uri.scheme}');
        }
        
        // Use platform-appropriate WebSocket implementation
        _channel = WebSocketChannelFactory.connect(uri);
        
        // Listen for messages with error handling
        _subscription = _channel!.stream
            .handleError((error) {
              RelayLogger.error('WebSocket stream error: $error');
              _handleDisconnect();
              return;
            })
            .listen(
          (message) {
            try {
              _handleMessage(message);
            } catch (e) {
              RelayLogger.error('Error handling message: $e');
            }
          },
          onError: (error) {
            RelayLogger.error('WebSocket error: $error');
            _handleDisconnect();
          },
          onDone: () {
            RelayLogger.info('WebSocket connection closed by remote');
            _handleDisconnect();
          },
          cancelOnError: false, // Keep listening even after errors
        );
        
        _connected = true;
        RelayLogger.info('Connected to external relay: $url');
      } catch (e) {
        RelayLogger.error('Failed to connect to relay: $e');
        _connected = false;
        // Don't throw - just log the error and continue
        _handleDisconnect();
      }
    }, (error, stack) {
      // Catch any unhandled async errors
      RelayLogger.error('Unhandled WebSocket error: $error');
      _handleDisconnect();
    });
  }
  
  Future<void> disconnect() async {
    _shouldReconnect = false;
    await _closeConnection();
  }
  
  Future<void> _closeConnection() async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }
    
    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
    }
    
    _connected = false;
    RelayLogger.info('Disconnected from external relay: $url');
  }
  
  void _handleDisconnect() {
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_shouldReconnect) {
      // TODO: Implement reconnection logic
      RelayLogger.info('Will attempt to reconnect to $url');
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final decoded = json.decode(message as String) as List<dynamic>;
      final messageType = decoded[0] as String;
      
      RelayLogger.debug('[RELAY-CLIENT<-$url] Received message type: $messageType');
      
      switch (messageType) {
        case 'EVENT':
          _handleEventMessage(decoded);
          break;
        case 'EOSE':
          _handleEoseMessage(decoded);
          break;
        case 'OK':
          _handleOkMessage(decoded);
          break;
        case 'NOTICE':
          _handleNoticeMessage(decoded);
          break;
        default:
          RelayLogger.warning('[RELAY-CLIENT<-$url] Unknown message type: $messageType');
      }
    } catch (e) {
      RelayLogger.error('[RELAY-CLIENT<-$url] Error handling message: $e');
    }
  }
  
  void _handleEventMessage(List<dynamic> message) {
    if (message.length >= 3) {
      final subscriptionId = message[1] as String;
      final eventData = message[2] as Map<String, dynamic>;
      final event = NostrEvent.fromJson(eventData);
      
      RelayLogger.info('[RELAY-CLIENT<-$url] EVENT for subscription $subscriptionId');
      RelayLogger.info('[RELAY-CLIENT<-$url] Event ID: ${event.id}, Kind: ${event.kind}');
      
      if (onEvent != null) {
        RelayLogger.info('[RELAY-CLIENT<-$url] Calling onEvent callback for event ${event.id}');
        onEvent!(event);
      } else {
        RelayLogger.warning('[RELAY-CLIENT<-$url] No onEvent callback registered!');
      }
    }
  }
  
  void _handleEoseMessage(List<dynamic> message) {
    if (message.length >= 2) {
      final subscriptionId = message[1] as String;
      if (onEose != null) {
        onEose!(subscriptionId);
      }
    }
  }
  
  void _handleOkMessage(List<dynamic> message) {
    if (message.length >= 3) {
      final eventId = message[1] as String;
      final status = message[2] as bool;
      final reason = message.length > 3 ? message[3] as String? : null;
      
      if (onOk != null) {
        onOk!(eventId, status, reason);
      }
    }
  }
  
  void _handleNoticeMessage(List<dynamic> message) {
    if (message.length >= 2) {
      final notice = message[1] as String;
      if (onNotice != null) {
        onNotice!(notice);
      }
    }
  }
  
  // For testing purposes
  Future<void> handleMessage(String message) async {
    _handleMessage(message);
  }
  
  Future<bool> sendRequest(String subscriptionId, List<Filter> filters) async {
    if (!_connected || _channel == null) {
      RelayLogger.warning('[RELAY-CLIENT] Cannot send REQ - not connected to $url');
      return false;
    }
    
    try {
      final filterMaps = filters.map((f) => f.toJson()).toList();
      final message = json.encode(['REQ', subscriptionId, ...filterMaps]);
      
      // Log the REQ message being sent
      RelayLogger.info('[RELAY-CLIENT->$url] Sending REQ: subscription=$subscriptionId');
      for (var i = 0; i < filterMaps.length; i++) {
        final filter = filterMaps[i];
        if (filter['ids'] != null) {
          final ids = filter['ids'] as List;
          RelayLogger.info('[RELAY-CLIENT->$url] Filter $i has ${ids.length} event IDs');
          if (ids.isNotEmpty) {
            RelayLogger.info('[RELAY-CLIENT->$url] Requesting event: ${ids.first}');
          }
        }
      }
      RelayLogger.debug('[RELAY-CLIENT->$url] Full REQ message: $message');
      
      _channel!.sink.add(message);
      return true;
    } catch (e) {
      RelayLogger.error('[RELAY-CLIENT->$url] Error sending REQ: $e');
      return false;
    }
  }
  
  Future<bool> sendEvent(NostrEvent event) async {
    if (!_connected || _channel == null) return false;
    
    try {
      final message = json.encode(['EVENT', event.toJson()]);
      _channel!.sink.add(message);
      return true;
    } catch (e) {
      RelayLogger.error('Error sending EVENT: $e');
      return false;
    }
  }
  
  Future<bool> closeSubscription(String subscriptionId) async {
    if (!_connected || _channel == null) return false;
    
    try {
      final message = json.encode(['CLOSE', subscriptionId]);
      _channel!.sink.add(message);
      return true;
    } catch (e) {
      RelayLogger.error('Error sending CLOSE: $e');
      return false;
    }
  }
  
  bool get isConnected => _connected;
}