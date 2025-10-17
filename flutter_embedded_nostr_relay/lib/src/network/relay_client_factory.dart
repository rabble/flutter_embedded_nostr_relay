// ABOUTME: Factory for creating appropriate relay clients based on Tor availability and config
// ABOUTME: Uses conditional imports to create Tor-enabled or standard relay clients

import 'external_relay_client.dart';
import '../tor/tor_config.dart';
import '../tor/tor_support.dart';

// Conditional import - will use stub if Tor not compiled in
import 'tor_client_stub.dart'
  if (dart.library.ffi) '../tor/tor_enabled_relay_client.dart';

/// Factory for creating relay clients with optional Tor support
class RelayClientFactory {
  /// Create a relay client, using Tor if available and configured
  static ExternalRelayClient create({
    required String url,
    TorConfig? torConfig,
  }) {
    // If no Tor config or Tor disabled, use standard client
    if (torConfig?.enabled != true) {
      return ExternalRelayClient(url: url);
    }
    
    // Check if Tor libraries are available at runtime
    if (!TorSupport.isAvailable) {
      // Graceful fallback to standard client
      return ExternalRelayClient(url: url);
    }
    
    // Check if this relay should use Tor
    if (!torConfig!.shouldUseTor(url)) {
      return ExternalRelayClient(url: url);
    }
    
    // Try to create Tor-enabled client
    try {
      return createTorEnabledClient(url: url, torConfig: torConfig);
    } catch (e) {
      // If Tor client creation fails, fallback to standard client
      // This can happen if Tor fails to initialize
      return ExternalRelayClient(url: url);
    }
  }
}