// ABOUTME: Core constants and configuration values for the embedded relay
// ABOUTME: Defines default ports, limits, timeouts, and protocol constants

class RelayConstants {
  RelayConstants._();
  
  // Network configuration
  static const int defaultPort = 7447;
  static const String defaultHost = 'localhost';
  static const String wsScheme = 'ws';
  static const String wssScheme = 'wss';
  
  // Protocol limits
  static const int maxMessageLength = 65536; // 64KB
  static const int maxEventSize = 65536; // 64KB
  static const int maxSubscriptions = 100;
  static const int maxFiltersPerSubscription = 10;
  static const int maxTagsPerEvent = 2000;
  static const int maxTagValueLength = 1024;
  static const int maxSubscriptionIdLength = 256;
  
  // Query limits
  static const int defaultQueryLimit = 100;
  static const int maxQueryLimit = 5000;
  static const int maxIdsPerFilter = 1000;
  static const int maxAuthorsPerFilter = 1000;
  static const int maxKindsPerFilter = 100;
  
  // Timing
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const Duration subscriptionTimeout = Duration(hours: 24);
  static const Duration eventRetentionPeriod = Duration(days: 90);
  
  // WebSocket
  static const int wsNormalClosure = 1000;
  static const int wsGoingAway = 1001;
  static const int wsProtocolError = 1002;
  static const int wsUnsupportedData = 1003;
  static const int wsInvalidFramePayloadData = 1007;
  static const int wsPolicyViolation = 1008;
  static const int wsMessageTooBig = 1009;
  static const int wsInternalError = 1011;
  
  // Database
  static const String databaseName = 'nostr_relay.db';
  static const int databaseVersion = 2; // v2: Add pending_publishes table for external relay retry queue
  static const int batchInsertSize = 1000;
  static const Duration vacuumInterval = Duration(days: 1);
  
  // P2P Sync
  static const int negentropyFrameSize = 60000; // Leave room for protocol overhead
  static const int blePacketSize = 512; // BLE MTU limit
  static const int wifiDirectPacketSize = 65536;
  static const Duration syncTimeout = Duration(minutes: 5);
  static const Duration peerDiscoveryInterval = Duration(seconds: 30);
  static const int maxSyncBatchSize = 1000;
  
  // Event kinds (NIP-01 and common NIPs)
  static const int kindMetadata = 0;
  static const int kindTextNote = 1;
  static const int kindRecommendRelay = 2;
  static const int kindContacts = 3;
  static const int kindEncryptedDirectMessage = 4;
  static const int kindDeletion = 5;
  static const int kindRepost = 6;
  static const int kindReaction = 7;
  static const int kindBadgeAward = 8;
  static const int kindChannelCreation = 40;
  static const int kindChannelMetadata = 41;
  static const int kindChannelMessage = 42;
  static const int kindChannelHideMessage = 43;
  static const int kindChannelMuteUser = 44;
  
  // Replaceable event ranges
  static const int replaceableRangeStart = 10000;
  static const int replaceableRangeEnd = 19999;
  static const int ephemeralRangeStart = 20000;
  static const int ephemeralRangeEnd = 29999;
  static const int parameterizedReplaceableRangeStart = 30000;
  static const int parameterizedReplaceableRangeEnd = 39999;
  
  // OpenVine specific
  static const int kindVideoMetadata = 32222;
  static const int videoMetadataCacheDays = 30;
  static const int maxVideosPerFeed = 1000;
  
  // Error messages
  static const String errInvalidMessage = 'error: invalid message format';
  static const String errInvalidEvent = 'error: invalid event';
  static const String errInvalidSubscriptionId = 'error: invalid subscription id';
  static const String errTooManySubscriptions = 'error: too many subscriptions';
  static const String errTooManyFilters = 'error: too many filters';
  static const String errMessageTooLong = 'error: message too long';
  static const String errSubscriptionNotFound = 'error: subscription not found';
  static const String errDuplicateEvent = 'error: duplicate event';
  static const String errBlockedEvent = 'error: event blocked by policy';
  static const String errRateLimited = 'error: rate limited';
  static const String errAuthRequired = 'error: authentication required';
}