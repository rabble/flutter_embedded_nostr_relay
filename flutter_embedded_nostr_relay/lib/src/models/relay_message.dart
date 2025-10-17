// ABOUTME: WebSocket message types for Nostr relay protocol
// ABOUTME: Implements REQ, EVENT, CLOSE, EOSE, OK, NOTICE message formats

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'nostr_event.dart';
import 'filter.dart';

abstract class RelayMessage extends Equatable {
  String get type;
  
  /// Base constructor for RelayMessage subclasses
  const RelayMessage();
  
  /// Serialize message to JSON array format
  List<dynamic> toJsonArray();
  
  /// Serialize to JSON string for WebSocket transmission
  String toJsonString() => json.encode(toJsonArray());
  
  /// Parse a message from JSON
  factory RelayMessage.fromJson(List<dynamic> json) {
    if (json.isEmpty) {
      throw FormatException('Empty message');
    }
    
    final messageType = json[0] as String;
    
    switch (messageType.toUpperCase()) {
      case 'EVENT':
        // Handle both client-to-relay and relay-to-client EVENT formats
        if (json.length == 2) {
          // Client-to-relay format: ["EVENT", event]
          return ClientEventMessage.fromJsonArray(json);
        } else if (json.length >= 3) {
          // Relay-to-client format: ["EVENT", subscription_id, event]
          return EventMessage.fromJsonArray(json);
        } else {
          throw FormatException('EVENT message has invalid format');
        }
      case 'REQ':
        return ReqMessage.fromJsonArray(json);
      case 'CLOSE':
        return CloseMessage.fromJsonArray(json);
      case 'EOSE':
        return EoseMessage.fromJsonArray(json);
      case 'OK':
        return OkMessage.fromJsonArray(json);
      case 'NOTICE':
        return NoticeMessage.fromJsonArray(json);
      case 'AUTH':
        return AuthMessage.fromJsonArray(json);
      case 'COUNT':
        return CountMessage.fromJsonArray(json);
      default:
        throw FormatException('Unknown message type: $messageType');
    }
  }
}

/// EVENT message - Sent by relays to clients (with subscription ID)
class EventMessage extends RelayMessage {
  final String subscriptionId;
  final NostrEvent event;
  
  const EventMessage({
    required this.subscriptionId,
    required this.event,
  }) : super();
  
  factory EventMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 3) {
      throw FormatException('EVENT message must have at least 3 elements');
    }
    
    return EventMessage(
      subscriptionId: json[1] as String,
      event: NostrEvent.fromJson(json[2] as Map<String, dynamic>),
    );
  }
  
  @override
  String get type => 'EVENT';
  
  @override
  List<dynamic> toJsonArray() => ['EVENT', subscriptionId, event.toJson()];
  
  @override
  List<Object?> get props => [subscriptionId, event];
}

/// CLIENT_EVENT message - Sent by clients to relays (without subscription ID)
class ClientEventMessage extends RelayMessage {
  final NostrEvent event;
  
  const ClientEventMessage({
    required this.event,
  }) : super();
  
  factory ClientEventMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 2) {
      throw FormatException('CLIENT_EVENT message must have at least 2 elements');
    }
    
    return ClientEventMessage(
      event: NostrEvent.fromJson(json[1] as Map<String, dynamic>),
    );
  }
  
  @override
  String get type => 'CLIENT_EVENT';
  
  @override
  List<dynamic> toJsonArray() => ['EVENT', event.toJson()];
  
  @override
  List<Object?> get props => [event];
}

/// REQ message - Sent by clients to request events
class ReqMessage extends RelayMessage {
  final String subscriptionId;
  final List<Filter> filters;
  
  const ReqMessage({
    required this.subscriptionId,
    required this.filters,
  }) : super();
  
  factory ReqMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 3) {
      throw FormatException('REQ message must have at least 3 elements');
    }
    
    final subscriptionId = json[1] as String;
    final filters = <Filter>[];
    
    for (int i = 2; i < json.length; i++) {
      filters.add(Filter.fromJson(json[i] as Map<String, dynamic>));
    }
    
    return ReqMessage(
      subscriptionId: subscriptionId,
      filters: filters,
    );
  }
  
  @override
  String get type => 'REQ';
  
  @override
  List<dynamic> toJsonArray() => [
        'REQ',
        subscriptionId,
        ...filters.map((f) => f.toJson()),
      ];
  
  @override
  List<Object?> get props => [subscriptionId, filters];
}

/// CLOSE message - Sent by clients to close a subscription
class CloseMessage extends RelayMessage {
  final String subscriptionId;
  
  const CloseMessage({required this.subscriptionId}) : super();
  
  factory CloseMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 2) {
      throw FormatException('CLOSE message must have at least 2 elements');
    }
    
    return CloseMessage(subscriptionId: json[1] as String);
  }
  
  @override
  String get type => 'CLOSE';
  
  @override
  List<dynamic> toJsonArray() => ['CLOSE', subscriptionId];
  
  @override
  List<Object?> get props => [subscriptionId];
}

/// EOSE message - End of Stored Events
class EoseMessage extends RelayMessage {
  final String subscriptionId;
  
  const EoseMessage({required this.subscriptionId}) : super();
  
  factory EoseMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 2) {
      throw FormatException('EOSE message must have at least 2 elements');
    }
    
    return EoseMessage(subscriptionId: json[1] as String);
  }
  
  @override
  String get type => 'EOSE';
  
  @override
  List<dynamic> toJsonArray() => ['EOSE', subscriptionId];
  
  @override
  List<Object?> get props => [subscriptionId];
}

/// OK message - Sent by relays to indicate acceptance or rejection of an EVENT
class OkMessage extends RelayMessage {
  final String eventId;
  final bool accepted;
  final String message;
  
  const OkMessage({
    required this.eventId,
    required this.accepted,
    required this.message,
  }) : super();
  
  factory OkMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 4) {
      throw FormatException('OK message must have at least 4 elements');
    }
    
    return OkMessage(
      eventId: json[1] as String,
      accepted: json[2] as bool,
      message: json[3] as String,
    );
  }
  
  @override
  String get type => 'OK';
  
  @override
  List<dynamic> toJsonArray() => ['OK', eventId, accepted, message];
  
  @override
  List<Object?> get props => [eventId, accepted, message];
}

/// NOTICE message - Sent by relays to clients
class NoticeMessage extends RelayMessage {
  final String message;
  
  const NoticeMessage({required this.message}) : super();
  
  factory NoticeMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 2) {
      throw FormatException('NOTICE message must have at least 2 elements');
    }
    
    return NoticeMessage(message: json[1] as String);
  }
  
  @override
  String get type => 'NOTICE';
  
  @override
  List<dynamic> toJsonArray() => ['NOTICE', message];
  
  @override
  List<Object?> get props => [message];
}

/// AUTH message - Used for NIP-42 authentication
class AuthMessage extends RelayMessage {
  final String challenge;
  
  const AuthMessage({required this.challenge}) : super();
  
  factory AuthMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 2) {
      throw FormatException('AUTH message must have at least 2 elements');
    }
    
    return AuthMessage(challenge: json[1] as String);
  }
  
  @override
  String get type => 'AUTH';
  
  @override
  List<dynamic> toJsonArray() => ['AUTH', challenge];
  
  @override
  List<Object?> get props => [challenge];
}

/// COUNT message - Response to COUNT requests (NIP-45)
class CountMessage extends RelayMessage {
  final String subscriptionId;
  final int count;
  
  const CountMessage({
    required this.subscriptionId,
    required this.count,
  }) : super();
  
  factory CountMessage.fromJsonArray(List<dynamic> json) {
    if (json.length < 3) {
      throw FormatException('COUNT message must have at least 3 elements');
    }
    
    return CountMessage(
      subscriptionId: json[1] as String,
      count: (json[2] as Map<String, dynamic>)['count'] as int,
    );
  }
  
  @override
  String get type => 'COUNT';
  
  @override
  List<dynamic> toJsonArray() => ['COUNT', subscriptionId, {'count': count}];
  
  @override
  List<Object?> get props => [subscriptionId, count];
}