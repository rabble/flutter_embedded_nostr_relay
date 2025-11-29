// ABOUTME: Client for connecting to external Nostr relays
// ABOUTME: Manages WebSocket connections and message routing to external relays

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'websocket_channel_factory.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../utils/logger.dart';

class ExternalRelayClient {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(minutes: 5);

  // Pending OK responses for verified sends
  final Map<String, Completer<bool>> _pendingOkResponses = {};
  static const Duration _okTimeout = Duration(seconds: 30);

  // Callbacks for different message types
  Function(NostrEvent)? onEvent;
  Function(String)? onEose;
  Function(String, bool, String?)? onOk;
  Function(String)? onNotice;
  Function()? onConnected;
  Function()? onDisconnected;

  ExternalRelayClient({required this.url});
  
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
        _reconnectAttempts = 0; // Reset on successful connection
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        RelayLogger.info('Connected to external relay: $url');
        onConnected?.call();
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    final wasConnected = _connected;
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    // Fail any pending OK responses
    for (final completer in _pendingOkResponses.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingOkResponses.clear();

    // Notify listener of disconnection
    if (wasConnected) {
      onDisconnected?.call();
    }

    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      RelayLogger.warning('Max reconnect attempts reached for $url');
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return; // Already scheduled

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s... capped at 5 min
    final delay = Duration(
      milliseconds: (_baseReconnectDelay.inMilliseconds *
              (1 << _reconnectAttempts.clamp(0, 8)))
          .clamp(0, _maxReconnectDelay.inMilliseconds),
    );

    _reconnectAttempts++;
    RelayLogger.info(
        'Scheduling reconnect to $url in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_shouldReconnect && !_connected) {
        RelayLogger.info('Attempting reconnect to $url...');
        await connect();
      }
    });
  }

  /// Force an immediate reconnection attempt, resetting the backoff
  Future<void> reconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _shouldReconnect = true;
    await _closeConnection();
    await connect();
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
      final accepted = message[2] as bool;
      final reason = message.length > 3 ? message[3] as String? : null;

      RelayLogger.info(
          '[RELAY-CLIENT<-$url] OK for event $eventId: accepted=$accepted${reason != null ? ' reason=$reason' : ''}');

      // Complete any pending verified send
      final completer = _pendingOkResponses.remove(eventId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(accepted);
      }

      if (onOk != null) {
        onOk!(eventId, accepted, reason);
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
        // Log hashtag filters
        if (filter['#t'] != null) {
          RelayLogger.info('[RELAY-CLIENT->$url] Filter $i has hashtag filter: ${filter['#t']}');
        }
        // Log divine extensions (sort, int#, cursor)
        if (filter['sort'] != null) {
          RelayLogger.info('[RELAY-CLIENT->$url] ✨ Filter $i has DIVINE SORT: ${filter['sort']}');
        }
        filter.forEach((key, value) {
          if (key.startsWith('int#')) {
            RelayLogger.info('[RELAY-CLIENT->$url] ✨ Filter $i has DIVINE INT FILTER $key: $value');
          }
        });
        if (filter['cursor'] != null) {
          RelayLogger.info('[RELAY-CLIENT->$url] ✨ Filter $i has DIVINE CURSOR: ${filter['cursor']}');
        }
        // Log all tag filters
        filter.forEach((key, value) {
          if (key.startsWith('#') && !key.startsWith('int#')) {
            RelayLogger.info('[RELAY-CLIENT->$url] Filter $i has tag filter $key: $value');
          }
        });
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

  /// Send event and wait for OK response from relay
  /// Returns true if relay accepted the event, false otherwise
  Future<bool> sendEventWithVerification(NostrEvent event) async {
    if (!_connected || _channel == null) {
      RelayLogger.warning(
          '[RELAY-CLIENT->$url] Cannot send verified EVENT - not connected');
      return false;
    }

    try {
      // Create completer for this event's OK response
      final completer = Completer<bool>();
      _pendingOkResponses[event.id] = completer;

      final message = json.encode(['EVENT', event.toJson()]);
      RelayLogger.info(
          '[RELAY-CLIENT->$url] Sending EVENT ${event.id} (waiting for OK)');
      _channel!.sink.add(message);

      // Wait for OK with timeout
      final result = await completer.future.timeout(
        _okTimeout,
        onTimeout: () {
          RelayLogger.warning(
              '[RELAY-CLIENT->$url] Timeout waiting for OK for event ${event.id}');
          _pendingOkResponses.remove(event.id);
          return false;
        },
      );

      if (result) {
        RelayLogger.info(
            '[RELAY-CLIENT->$url] Event ${event.id} verified as received');
      } else {
        RelayLogger.warning(
            '[RELAY-CLIENT->$url] Event ${event.id} was rejected by relay');
      }

      return result;
    } catch (e) {
      RelayLogger.error('[RELAY-CLIENT->$url] Error sending verified EVENT: $e');
      _pendingOkResponses.remove(event.id);
      return false;
    }
  }

  /// Verify an event exists on this relay by requesting it back
  /// Returns true if the event is found, false otherwise
  Future<bool> verifyEventExists(String eventId,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (!_connected || _channel == null) {
      RelayLogger.warning(
          '[RELAY-CLIENT->$url] Cannot verify event - not connected');
      return false;
    }

    final subscriptionId = 'verify_${eventId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<bool>();
    bool eventFound = false;

    // Temporarily listen for event response
    final originalOnEvent = onEvent;
    final originalOnEose = onEose;

    onEvent = (event) {
      if (event.id == eventId) {
        eventFound = true;
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
      // Also call original handler
      originalOnEvent?.call(event);
    };

    onEose = (subId) {
      if (subId == subscriptionId && !completer.isCompleted) {
        completer.complete(eventFound);
      }
      originalOnEose?.call(subId);
    };

    try {
      // Request the specific event
      final filter = Filter(ids: [eventId]);
      await sendRequest(subscriptionId, [filter]);

      // Wait for response with timeout
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          RelayLogger.warning(
              '[RELAY-CLIENT->$url] Timeout verifying event $eventId');
          return false;
        },
      );

      // Close the subscription
      await closeSubscription(subscriptionId);

      // Restore original handlers
      onEvent = originalOnEvent;
      onEose = originalOnEose;

      if (result) {
        RelayLogger.info(
            '[RELAY-CLIENT->$url] ✅ Event $eventId verified on relay');
      } else {
        RelayLogger.warning(
            '[RELAY-CLIENT->$url] ❌ Event $eventId NOT found on relay');
      }

      return result;
    } catch (e) {
      RelayLogger.error('[RELAY-CLIENT->$url] Error verifying event: $e');
      onEvent = originalOnEvent;
      onEose = originalOnEose;
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

  /// Number of pending OK responses waiting
  int get pendingOkCount => _pendingOkResponses.length;

  /// Current reconnection attempt number
  int get reconnectAttempts => _reconnectAttempts;
}