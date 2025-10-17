// ABOUTME: State management for embedded Nostr relay functionality
// ABOUTME: Handles relay initialization, stats, P2P sync, and external relay management

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelayProvider extends ChangeNotifier {
  static final _logger = Logger('RelayProvider');
  
  final EmbeddedNostrRelay _relay = EmbeddedNostrRelay();
  bool _isInitialized = false;
  bool _isInitializing = false;
  
  // Relay statistics
  Map<String, int> _stats = {};
  Map<String, dynamic> _subscriptionStats = {};
  
  // P2P sync
  bool _p2pEnabled = false;
  List<Peer> _discoveredPeers = [];
  
  // External relays
  final List<String> _externalRelays = [];
  final Map<String, bool> _relayConnections = {};
  
  // Connectivity
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  
  // Tor configuration
  TorConfig _torConfig = const TorConfig();
  bool _torForRelays = false;
  bool _torForVideos = false;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  Map<String, int> get stats => _stats;
  Map<String, dynamic> get subscriptionStats => _subscriptionStats;
  bool get p2pEnabled => _p2pEnabled;
  List<Peer> get discoveredPeers => _discoveredPeers;
  List<String> get externalRelays => _externalRelays;
  Map<String, bool> get relayConnections => _relayConnections;
  bool get isOnline => _isOnline;
  EmbeddedNostrRelay get relay => _relay;
  
  // Tor getters
  TorConfig get torConfig => _torConfig;
  bool get torForRelays => _torForRelays;
  bool get torForVideos => _torForVideos;
  bool get torAvailable {
    try {
      return TorSupport.isAvailable;
    } catch (e) {
      _logger.warning('Error checking Tor availability: $e');
      return false;
    }
  }

  RelayProvider() {
    _initConnectivityMonitoring();
    _loadTorSettings();
  }

  /// Initialize the embedded relay
  Future<void> initialize({
    Level logLevel = Level.INFO,
    bool enableGarbageCollection = true,
  }) async {
    if (_isInitialized || _isInitializing) return;
    
    _isInitializing = true;
    notifyListeners();
    
    try {
      _logger.info('Initializing embedded Nostr relay...');
      
      await _relay.initialize(
        logLevel: logLevel,
        enableGarbageCollection: enableGarbageCollection,
      );
      
      _isInitialized = true;
      _logger.info('Embedded Nostr relay initialized successfully');
      
      // Start periodic stats updates
      _startStatsTimer();
      
      // Add default relays if none are configured
      if (_externalRelays.isEmpty) {
        await _addDefaultRelays();
      }
      
    } catch (e) {
      _logger.severe('Failed to initialize relay', e);
      rethrow;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Shutdown the relay
  Future<void> shutdown() async {
    if (!_isInitialized) return;
    
    _logger.info('Shutting down embedded relay...');
    
    await _relay.shutdown();
    _isInitialized = false;
    
    // Cancel connectivity monitoring
    _connectivitySubscription?.cancel();
    
    notifyListeners();
  }

  /// Enable P2P synchronization
  Future<void> enableP2PSync({
    List<TransportType> transports = const [TransportType.ble, TransportType.wifiDirect],
  }) async {
    if (!_isInitialized) {
      throw StateError('Relay not initialized');
    }
    
    try {
      await _relay.enableP2PSync(
        transports: transports,
        onPeerDiscovered: _onPeerDiscovered,
        onPeerLost: _onPeerLost,
      );
      
      _p2pEnabled = true;
      _logger.info('P2P synchronization enabled with transports: $transports');
      notifyListeners();
      
    } catch (e) {
      _logger.severe('Failed to enable P2P sync', e);
      rethrow;
    }
  }

  /// Disable P2P synchronization
  Future<void> disableP2PSync() async {
    if (!_p2pEnabled) return;
    
    // TODO: Implement P2P disable when available in library
    _p2pEnabled = false;
    _discoveredPeers.clear();
    _logger.info('P2P synchronization disabled');
    notifyListeners();
  }

  /// Add an external relay
  Future<void> addExternalRelay(String url) async {
    if (!_isInitialized) {
      throw StateError('Relay not initialized');
    }
    
    if (_externalRelays.contains(url)) {
      return; // Already added
    }
    
    try {
      await _relay.addExternalRelay(url);
      _externalRelays.add(url);
      _relayConnections[url] = true; // Assume connected initially
      
      _logger.info('Added external relay: $url');
      notifyListeners();
      
    } catch (e) {
      _logger.warning('Failed to add external relay $url', e);
      _relayConnections[url] = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Remove an external relay
  Future<void> removeExternalRelay(String url) async {
    if (!_externalRelays.contains(url)) return;
    
    _externalRelays.remove(url);
    _relayConnections.remove(url);
    
    // TODO: Implement relay disconnection when available in library
    _logger.info('Removed external relay: $url');
    notifyListeners();
  }

  /// Update relay statistics
  Future<void> updateStats() async {
    if (!_isInitialized) return;
    
    try {
      _stats = await _relay.getStats();
      _subscriptionStats = _relay.getSubscriptionStats();
      notifyListeners();
    } catch (e) {
      _logger.warning('Failed to update stats', e);
    }
  }

  /// Get relay information
  RelayInfo getRelayInfo() {
    if (!_isInitialized) {
      throw StateError('Relay not initialized');
    }
    return _relay.getRelayInfo();
  }

  /// Enable/disable Tor for relay connections
  Future<void> setTorForRelays(bool enabled) async {
    if (_torForRelays == enabled) return;
    
    _torForRelays = enabled;
    await _saveTorSettings();
    
    // Update Tor config based on new setting
    _torConfig = _torConfig.copyWith(enabled: enabled);
    
    _logger.info('Tor for relays ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
    
    // Reconnect external relays with new Tor configuration
    if (_isInitialized) {
      await _reconnectExternalRelays();
    }
  }

  /// Enable/disable Tor for video loading
  Future<void> setTorForVideos(bool enabled) async {
    if (_torForVideos == enabled) return;
    
    _torForVideos = enabled;
    await _saveTorSettings();
    
    _logger.info('Tor for videos ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  /// Update Tor configuration
  Future<void> updateTorConfig(TorConfig newConfig) async {
    _torConfig = newConfig;
    await _saveTorSettings();
    
    _logger.info('Tor configuration updated');
    notifyListeners();
    
    // Reconnect external relays with new Tor configuration
    if (_isInitialized && _torForRelays) {
      await _reconnectExternalRelays();
    }
  }

  // Private methods

  void _initConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final wasOnline = _isOnline;
        _isOnline = results.any((result) => 
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet
        );
        
        if (wasOnline != _isOnline) {
          _logger.info('Connectivity changed: ${_isOnline ? 'online' : 'offline'}');
          notifyListeners();
        }
      },
    );
  }

  void _onPeerDiscovered(Peer peer) {
    if (!_discoveredPeers.any((p) => p.id == peer.id)) {
      _discoveredPeers.add(peer);
      _logger.info('Peer discovered: ${peer.name} (${peer.transport})');
      notifyListeners();
    }
  }

  void _onPeerLost(Peer peer) {
    _discoveredPeers.removeWhere((p) => p.id == peer.id);
    _logger.info('Peer lost: ${peer.name}');
    notifyListeners();
  }

  /// Load Tor settings from persistent storage
  Future<void> _loadTorSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _torForRelays = prefs.getBool('tor_for_relays') ?? false;
      _torForVideos = prefs.getBool('tor_for_videos') ?? false;
      
      // Load Tor config from JSON
      final configJson = prefs.getString('tor_config');
      if (configJson != null) {
        try {
          final configMap = Map<String, dynamic>.from(
            json.decode(configJson) as Map
          );
          _torConfig = TorConfig.fromJson(configMap);
        } catch (e) {
          _logger.warning('Failed to parse Tor config from storage', e);
          _torConfig = const TorConfig();
        }
      }
      
      _logger.info('Tor settings loaded: relays=$_torForRelays, videos=$_torForVideos');
      
      // Notify listeners that settings have been loaded
      notifyListeners();
    } catch (e) {
      _logger.warning('Failed to load Tor settings', e);
    }
  }

  /// Save Tor settings to persistent storage
  Future<void> _saveTorSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tor_for_relays', _torForRelays);
      await prefs.setBool('tor_for_videos', _torForVideos);
      await prefs.setString('tor_config', json.encode(_torConfig.toJson()));
      
      _logger.info('Tor settings saved');
    } catch (e) {
      _logger.warning('Failed to save Tor settings', e);
    }
  }

  /// Reconnect external relays with updated Tor configuration
  Future<void> _reconnectExternalRelays() async {
    if (_externalRelays.isEmpty) return;
    
    try {
      // TODO: Implement relay reconnection with new Tor config
      // This would involve disconnecting and reconnecting each relay
      // with the updated TorConfig
      _logger.info('Reconnecting ${_externalRelays.length} external relays with Tor config');
      
      for (final relayUrl in _externalRelays) {
        // For now, just update the connection status
        _relayConnections[relayUrl] = true;
      }
      
      notifyListeners();
    } catch (e) {
      _logger.warning('Failed to reconnect external relays', e);
    }
  }

  /// Add default popular relays for better user experience
  Future<void> _addDefaultRelays() async {
    final defaultRelays = [
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.nostr.band',
      'wss://nostr.wine',
      'wss://relay.snort.social',
    ];
    
    _logger.info('Adding ${defaultRelays.length} default relays');
    
    for (final relayUrl in defaultRelays) {
      try {
        await addExternalRelay(relayUrl);
      } catch (e) {
        _logger.warning('Failed to add default relay $relayUrl: $e');
        // Continue adding other relays even if one fails
      }
    }
  }

  Timer? _statsTimer;
  
  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      updateStats();
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}