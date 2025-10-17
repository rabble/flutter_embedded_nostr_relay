// ABOUTME: Configuration model for Tor support with validation and serialization
// ABOUTME: Defines how the relay should use Tor for different relays and scenarios

import 'package:equatable/equatable.dart';

/// Configuration for Tor support in the embedded relay
class TorConfig extends Equatable {
  /// Whether Tor support is enabled
  final bool enabled;
  
  /// Force all relay connections through Tor (even non-.onion relays)
  final bool forceTor;
  
  /// Fail initialization if Tor can't be started (vs fallback to direct)
  final bool required;
  
  /// List of relay URLs that must use Tor (in addition to .onion relays)
  final List<String> torOnlyRelays;
  
  /// Bridge configuration for censored networks
  final List<String> bridges;
  
  /// Timeout for Tor bootstrap process
  final Duration timeout;
  
  const TorConfig({
    this.enabled = false,
    this.forceTor = false,
    this.required = false,
    this.torOnlyRelays = const [],
    this.bridges = const [],
    this.timeout = const Duration(minutes: 2),
  });
  
  /// Create TorConfig from JSON
  factory TorConfig.fromJson(Map<String, dynamic> json) {
    return TorConfig(
      enabled: json['enabled'] as bool? ?? false,
      forceTor: json['forceTor'] as bool? ?? false,
      required: json['required'] as bool? ?? false,
      torOnlyRelays: (json['torOnlyRelays'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? const [],
      bridges: (json['bridges'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? const [],
      timeout: Duration(minutes: json['timeoutMinutes'] as int? ?? 2),
    );
  }
  
  /// Convert TorConfig to JSON
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'forceTor': forceTor,
      'required': required,
      'torOnlyRelays': torOnlyRelays,
      'bridges': bridges,
      'timeoutMinutes': timeout.inMinutes,
    };
  }
  
  /// Check if a URL is an onion relay
  static bool isOnionRelay(String url) {
    // Remove protocol if present
    final cleanUrl = url.replaceFirst(RegExp(r'^wss?://'), '');
    // Split by '/' to get just the host part
    final host = cleanUrl.split('/').first;
    // Check if host ends with .onion (not just contains)
    return host.endsWith('.onion');
  }
  
  /// Determine if a specific relay URL should use Tor
  bool shouldUseTor(String relayUrl) {
    // If Tor is disabled, never use it
    if (!enabled) return false;
    
    // Always use Tor for .onion addresses
    if (isOnionRelay(relayUrl)) return true;
    
    // Check if relay is in the torOnlyRelays list
    final cleanUrl = relayUrl.replaceFirst(RegExp(r'^wss?://'), '');
    if (torOnlyRelays.any((relay) => cleanUrl.contains(relay))) {
      return true;
    }
    
    // If forceTor is enabled, use Tor for all relays
    return forceTor;
  }
  
  /// Create a copy with modified values
  TorConfig copyWith({
    bool? enabled,
    bool? forceTor,
    bool? required,
    List<String>? torOnlyRelays,
    List<String>? bridges,
    Duration? timeout,
  }) {
    return TorConfig(
      enabled: enabled ?? this.enabled,
      forceTor: forceTor ?? this.forceTor,
      required: required ?? this.required,
      torOnlyRelays: torOnlyRelays ?? this.torOnlyRelays,
      bridges: bridges ?? this.bridges,
      timeout: timeout ?? this.timeout,
    );
  }
  
  @override
  List<Object?> get props => [
    enabled,
    forceTor,
    required,
    torOnlyRelays,
    bridges,
    timeout,
  ];
}