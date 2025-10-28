// ABOUTME: Direct function interface for embedded relay - replaces WebSocket server
// ABOUTME: Provides synchronous function calls instead of network communication

import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/nostr_event.dart';
import '../models/filter.dart';
import '../models/relay_message.dart';
import '../models/subscription.dart';
import '../storage/event_store.dart';
import '../utils/logger.dart';
import 'subscription_manager.dart';
import 'embedded_nostr_relay.dart';

/// Direct function channel for embedded relay communication.
///
/// This replaces the WebSocket server with direct function calls,
/// eliminating the need for:
/// - Local network permissions on iOS
/// - Port binding and network overhead
/// - WebSocket connection management
/// - JSON serialization/deserialization overhead
///
/// ## Benefits:
/// - **Performance**: Direct function calls are orders of magnitude faster
/// - **Reliability**: No network failures or connection drops
/// - **Compatibility**: Works on all platforms without special permissions
/// - **Simplicity**: No server management or port conflicts
class FunctionChannelRelay {
  final SubscriptionManager _subscriptionManager;
  final EventStore _eventStore;
  final EmbeddedNostrRelay _embeddedRelay;
  final Uuid _uuid = const Uuid();

  // Track active sessions and their subscriptions
  final Map<String, FunctionChannelSession> _sessions = {};

  FunctionChannelRelay({
    required SubscriptionManager subscriptionManager,
    required EventStore eventStore,
    required EmbeddedNostrRelay embeddedRelay,
  }) : _subscriptionManager = subscriptionManager,
       _eventStore = eventStore,
       _embeddedRelay = embeddedRelay;

  /// Create a new session for a client.
  ///
  /// Returns a [FunctionChannelSession] that the client can use
  /// to send messages and receive events.
  FunctionChannelSession createSession() {
    final sessionId = _uuid.v4();
    final session = FunctionChannelSession(
      sessionId: sessionId,
      relay: this,
    );
    _sessions[sessionId] = session;

    RelayLogger.info('Created function channel session: $sessionId');
    return session;
  }

  /// Close a session and clean up resources.
  Future<void> closeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await session.close();
      RelayLogger.info('Closed function channel session: $sessionId');
    }
  }

  /// Process a message from a client session.
  ///
  /// This handles REQ, CLOSE, and EVENT messages directly without
  /// going through WebSocket serialization.
  Future<void> processMessage(String sessionId, RelayMessage message) async {
    final session = _sessions[sessionId];
    if (session == null) {
      RelayLogger.warning('Message from unknown session: $sessionId');
      return;
    }

    if (message is ReqMessage) {
      await _handleReq(session, message);
    } else if (message is CloseMessage) {
      await _handleClose(session, message);
    } else if (message is ClientEventMessage) {
      await _handleEvent(session, message);
    } else {
      RelayLogger.warning('Unknown message type: ${message.runtimeType}');
    }
  }

  Future<void> _handleReq(FunctionChannelSession session, ReqMessage req) async {
    RelayLogger.debug('REQ from ${session.sessionId}: ${req.subscriptionId}');

    try {
      // Use subscription manager's handleReq method
      final subscription = await _subscriptionManager.handleReq(session.sessionId, req);

      // Note: Event delivery is handled through subscription manager's broadcastEvent

      session._activeSubscriptions.add(req.subscriptionId);

      // Query existing events
      final events = await _eventStore.queryEvents(req.filters);
      for (final event in events) {
        session._deliverEvent(req.subscriptionId, event);
      }

      // Send EOSE
      session._deliverEose(req.subscriptionId);

    } catch (e) {
      RelayLogger.error('Error handling REQ', e);
      session._deliverNotice('Error processing subscription: $e');
    }
  }

  Future<void> _handleClose(FunctionChannelSession session, CloseMessage close) async {
    RelayLogger.debug('CLOSE from ${session.sessionId}: ${close.subscriptionId}');

    await _subscriptionManager.handleClose(session.sessionId, close);
    session._activeSubscriptions.remove(close.subscriptionId);
  }

  Future<void> _handleEvent(FunctionChannelSession session, ClientEventMessage eventMsg) async {
    RelayLogger.debug('EVENT from ${session.sessionId}');

    try {
      final event = eventMsg.event;

      // TODO: Add event validation when verify() method is available
      // if (!event.verify()) {
      //   session._deliverOk(event.id, false, 'invalid: signature verification failed');
      //   return;
      // }

      // Store event
      await _eventStore.storeEvent(event);

      // Route event to subscriptions
      await _subscriptionManager.routeEvent(event);

      // Send OK
      session._deliverOk(event.id, true, '');

    } catch (e) {
      RelayLogger.error('Error handling EVENT', e);
      session._deliverNotice('Error processing event: $e');
    }
  }
}

/// A session representing a client connection via function calls.
///
/// This replaces a WebSocket connection with direct function callbacks.
class FunctionChannelSession {
  final String sessionId;
  final FunctionChannelRelay relay;
  final _activeSubscriptions = <String>{};

  // Callbacks for delivering messages to the client
  Function(String subId, NostrEvent event)? onEvent;
  Function(String subId)? onEose;
  Function(String eventId, bool success, String message)? onOk;
  Function(String message)? onNotice;

  // Stream controller for event delivery
  final _eventController = StreamController<RelayResponse>.broadcast();

  FunctionChannelSession({
    required this.sessionId,
    required this.relay,
  });

  /// Stream of relay responses (events, EOSE, OK, NOTICE).
  Stream<RelayResponse> get responseStream => _eventController.stream;

  /// Send a message to the relay for processing.
  Future<void> sendMessage(RelayMessage message) async {
    await relay.processMessage(sessionId, message);
  }

  /// Close this session and clean up subscriptions.
  Future<void> close() async {
    // Remove all subscriptions using handleClose
    for (final subId in _activeSubscriptions.toList()) {
      await relay._subscriptionManager.handleClose(
        sessionId,
        CloseMessage(subscriptionId: subId),
      );
    }
    _activeSubscriptions.clear();

    // Close stream
    await _eventController.close();
  }

  // Internal methods for delivering messages from relay
  void _deliverEvent(String subId, NostrEvent event) {
    _eventController.add(EventResponse(
      subscriptionId: subId,
      event: event,
    ));
    onEvent?.call(subId, event);
  }

  void _deliverEose(String subId) {
    _eventController.add(EoseResponse(subscriptionId: subId));
    onEose?.call(subId);
  }

  void _deliverOk(String eventId, bool success, String message) {
    _eventController.add(OkResponse(
      eventId: eventId,
      success: success,
      message: message,
    ));
    onOk?.call(eventId, success, message);
  }

  void _deliverNotice(String message) {
    _eventController.add(NoticeResponse(message: message));
    onNotice?.call(message);
  }
}

/// Base class for relay responses.
abstract class RelayResponse {}

/// Event response containing a Nostr event.
class EventResponse extends RelayResponse {
  final String subscriptionId;
  final NostrEvent event;

  EventResponse({
    required this.subscriptionId,
    required this.event,
  });
}

/// End of stored events response.
class EoseResponse extends RelayResponse {
  final String subscriptionId;

  EoseResponse({required this.subscriptionId});
}

/// OK response for event submission.
class OkResponse extends RelayResponse {
  final String eventId;
  final bool success;
  final String message;

  OkResponse({
    required this.eventId,
    required this.success,
    required this.message,
  });
}

/// Notice/error response.
class NoticeResponse extends RelayResponse {
  final String message;

  NoticeResponse({required this.message});
}