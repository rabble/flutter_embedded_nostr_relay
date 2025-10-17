// ABOUTME: Stub implementation for Tor client when FFI/Tor libraries are not available
// ABOUTME: Provides fallback that always returns standard relay client

import 'external_relay_client.dart';
import '../tor/tor_config.dart';

/// Stub function that creates standard relay client when Tor not available
ExternalRelayClient createTorEnabledClient({
  required String url,
  required TorConfig torConfig,
}) {
  // When Tor libraries are not available, always return standard client
  return ExternalRelayClient(url: url);
}