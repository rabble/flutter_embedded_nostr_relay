// ABOUTME: WebSocket message types for Nostr relay protocol
// ABOUTME: Implements REQ, EVENT, CLOSE, EOSE, OK, NOTICE message formats

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'nostr_event.dart';
import 'filter.dart';

abstract class RelayMessage extends Equatable {
  String get type;
  
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
        return EventMessage.fromJsonArray(json);
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

/// EVENT message - Sent by relays to clients
class EventMessage extends RelayMessage {
  final String subscriptionId;
  final NostrEvent event;
  
  EventMessage({
    required this.subscriptionId,
    required this.event,
  });
  
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

/// REQ message - Sent by clients to request events
class ReqMessage extends RelayMessage {
  final String subscriptionId;
  final List<Filter> filters;
  
  ReqMessage({
    required this.subscriptionId,
    required this.filters,
  });
  
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
  
  CloseMessage({required this.subscriptionId});
  
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
  
  EoseMessage({required this.subscriptionId});
  
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
  
  OkMessage({
    required this.eventId,
    required this.accepted,
    required this.message,
  });
  
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
  
  NoticeMessage({required this.message});
  
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
  
  AuthMessage({required this.challenge});
  
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
  
  CountMessage({
    required this.subscriptionId,
    required this.count,
  });
  
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