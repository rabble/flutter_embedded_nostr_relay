// ABOUTME: RelayMetadata model for NIP-65 relay list management
// ABOUTME: Represents relay information with read/write permissions and priority

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'relay_metadata.g.dart';

/// Represents metadata for a relay as defined in NIP-65.
///
/// Each relay in a user's relay list has associated metadata including:
/// - The WebSocket URL of the relay
/// - Whether the relay is used for reading events
/// - Whether the relay is used for writing/publishing events  
/// - Optional priority for relay selection
///
/// According to NIP-65, if no read/write marker is specified, the relay
/// is used for both reading and writing.
///
/// Example usage:
/// ```dart
/// // Read and write relay (default)
/// final relay1 = RelayMetadata(url: 'wss://relay.example.com');
/// 
/// // Read-only relay
/// final relay2 = RelayMetadata(
///   url: 'wss://read.example.com',
///   read: true,
///   write: false,
/// );
///
/// // Write-only relay with priority
/// final relay3 = RelayMetadata(
///   url: 'wss://write.example.com',
///   read: false,
///   write: true,
///   priority: 10,
/// );
/// ```
@JsonSerializable()
class RelayMetadata extends Equatable {
  /// The WebSocket URL of the relay.
  /// 
  /// Must be a valid WebSocket URL (wss:// or ws://).
  final String url;
  
  /// Whether this relay is used for reading events.
  /// 
  /// When true, the client should query this relay when looking for events
  /// **about** the user (mentions, tags, etc).
  @JsonKey(defaultValue: true)
  final bool read;
  
  /// Whether this relay is used for writing/publishing events.
  /// 
  /// When true, the client should publish to this relay when looking for events
  /// **from** the user (authored by them).
  @JsonKey(defaultValue: true)
  final bool write;
  
  /// Optional priority for relay selection.
  /// 
  /// Higher numbers indicate higher priority. Can be used to prefer certain
  /// relays over others when multiple options are available.
  final int? priority;

  RelayMetadata({
    required this.url,
    this.read = true,
    this.write = true,
    this.priority,
  }) {
    _validateUrl(url);
  }

  /// Validates that the URL is a proper WebSocket URL.
  static void validateUrl(String url) {
    if (url.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }
    
    if (!url.startsWith('wss://') && !url.startsWith('ws://')) {
      throw ArgumentError('URL must be a WebSocket URL (wss:// or ws://)');
    }
    
    // Basic URL validation - check if it has a valid format
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        throw ArgumentError('URL must have a valid host');
      }
    } catch (e) {
      throw ArgumentError('Invalid URL format: $url');
    }
  }

  /// Internal validation method - kept for backward compatibility.
  static void _validateUrl(String url) => validateUrl(url);

  /// Create RelayMetadata from JSON representation.
  factory RelayMetadata.fromJson(Map<String, dynamic> json) {
    final metadata = _$RelayMetadataFromJson(json);
    _validateUrl(metadata.url);
    return metadata;
  }

  /// Convert RelayMetadata to JSON representation.
  Map<String, dynamic> toJson() => _$RelayMetadataToJson(this);

  /// Create a new RelayMetadata with updated fields.
  RelayMetadata copyWith({
    String? url,
    bool? read,
    bool? write,
    int? priority,
  }) {
    return RelayMetadata(
      url: url ?? this.url,
      read: read ?? this.read,
      write: write ?? this.write,
      priority: priority ?? this.priority,
    );
  }

  @override
  List<Object?> get props => [url, read, write, priority];

  @override
  String toString() {
    return 'RelayMetadata(url: $url, read: $read, write: $write, priority: $priority)';
  }
}