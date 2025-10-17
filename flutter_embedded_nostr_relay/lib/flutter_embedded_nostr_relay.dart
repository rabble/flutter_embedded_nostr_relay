// ABOUTME: Main library entry point for Flutter Embedded Nostr Relay
// ABOUTME: Exports all public APIs for embedding a Nostr relay in Flutter apps

library flutter_embedded_nostr_relay;

// Core exports
export 'src/core/embedded_nostr_relay.dart';
export 'src/core/subscription_manager.dart';
export 'src/core/constants.dart';

// Model exports
export 'src/models/nostr_event.dart';
export 'src/models/filter.dart';
export 'src/models/relay_info.dart';
export 'src/models/subscription.dart';
export 'src/models/relay_message.dart';
export 'src/models/relay_metadata.dart';
export 'src/models/relay_list.dart';
export 'src/models/relay_list_manager.dart';

// Network exports
export 'src/network/websocket_server.dart' 
    if (dart.library.html) 'src/network/websocket_server_web.dart';
export 'src/network/external_relay_client.dart';

// Sync exports
export 'src/sync/negentropy_sync.dart';
export 'src/sync/transport.dart';
export 'src/sync/ble_transport.dart' 
    if (dart.library.html) 'src/sync/transport_web.dart';
export 'src/sync/wifi_direct_transport.dart' 
    if (dart.library.html) 'src/sync/transport_web.dart';

// Storage exports
export 'src/storage/event_store.dart';
export 'src/storage/database_helper.dart';

// Utils exports
export 'src/utils/crypto.dart';
export 'src/utils/logger.dart';

// Tor exports (optional, conditional on build)
export 'src/tor/tor_config.dart';
export 'src/tor/tor_support.dart';