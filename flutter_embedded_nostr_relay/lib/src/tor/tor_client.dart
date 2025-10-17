// ABOUTME: High-level Tor client that provides Dart-friendly interface to Arti
// ABOUTME: Manages Tor connections, bootstrapping, and error handling

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'arti_bindings.dart';
import 'tor_config.dart';
import '../utils/logger.dart';

/// High-level Tor client for connecting through Tor
class TorClient {
  final ArtiBindings _bindings = ArtiBindings();
  Pointer<ArtiTorClient>? _client;
  final Map<int, TorConnection> _connections = {};
  bool _initialized = false;
  bool _bootstrapped = false;
  
  /// Initialize the Tor client with configuration
  Future<void> initialize({
    required String stateDir,
    required String cacheDir,
    TorConfig? config,
  }) async {
    if (_initialized) {
      throw StateError('TorClient already initialized');
    }
    
    try {
      RelayLogger.info('Initializing Tor client');
      
      // Create default config if none provided
      final torConfig = config ?? const TorConfig();
      final configJson = json.encode(torConfig.toJson());
      
      // Create the Arti client
      _client = _bindings.createClient(configJson, stateDir, cacheDir);
      _initialized = true;
      
      RelayLogger.info('Tor client initialized successfully');
    } catch (e) {
      RelayLogger.error('Failed to initialize Tor client: $e');
      rethrow;
    }
  }
  
  /// Bootstrap the Tor connection
  Future<void> bootstrap({Duration? timeout}) async {
    if (!_initialized || _client == null) {
      throw StateError('TorClient not initialized');
    }
    
    if (_bootstrapped) {
      return; // Already bootstrapped
    }
    
    try {
      RelayLogger.info('Bootstrapping Tor connection');
      
      final result = await Future.sync(() => _bindings.bootstrap(_client!))
          .timeout(timeout ?? const Duration(minutes: 2));
      
      if (result != 0) {
        throw TorException('Tor bootstrap failed with code: $result');
      }
      
      _bootstrapped = true;
      RelayLogger.info('Tor bootstrap completed successfully');
    } catch (e) {
      RelayLogger.error('Tor bootstrap failed: $e');
      rethrow;
    }
  }
  
  /// Connect to a host through Tor
  Future<TorConnection> connect(String host, int port) async {
    if (!_bootstrapped) {
      throw StateError('Tor client not bootstrapped');
    }
    
    try {
      RelayLogger.info('Connecting to $host:$port through Tor');
      
      final connId = _bindings.connect(_client!, host, port);
      if (connId == 0) {
        throw TorException('Failed to connect to $host:$port');
      }
      
      final connection = TorConnection._(connId, _bindings, _client!);
      _connections[connId] = connection;
      
      RelayLogger.info('Successfully connected to $host:$port (conn_id: $connId)');
      return connection;
    } catch (e) {
      RelayLogger.error('Failed to connect to $host:$port: $e');
      rethrow;
    }
  }
  
  /// Get the number of active connections
  int get connectionCount => _connections.length;
  
  /// Check if the client is initialized
  bool get isInitialized => _initialized;
  
  /// Check if Tor is bootstrapped and ready
  bool get isBootstrapped => _bootstrapped;
  
  /// Get the Arti library version
  String get version => _bindings.getVersion();
  
  /// Clean up and dispose the Tor client
  Future<void> dispose() async {
    RelayLogger.info('Disposing Tor client');
    
    // Close all connections
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    
    // Destroy the native client
    if (_client != null) {
      _bindings.destroyClient(_client!);
      _client = null;
    }
    
    _initialized = false;
    _bootstrapped = false;
    
    RelayLogger.info('Tor client disposed');
  }
  
  /// Remove a connection from the tracked connections
  void _removeConnection(int connId) {
    _connections.remove(connId);
  }
}

/// Represents a connection through Tor
class TorConnection {
  final int id;
  final ArtiBindings _bindings;
  final Pointer<ArtiTorClient> _client;
  bool _closed = false;
  
  TorConnection._(this.id, this._bindings, this._client);
  
  /// Write data to the connection
  Future<void> write(Uint8List data) async {
    if (_closed) {
      throw StateError('Connection is closed');
    }
    
    try {
      final bytesWritten = _bindings.connectionWrite(_client, id, data);
      if (bytesWritten < 0) {
        throw TorException('Write failed with code: $bytesWritten');
      }
      if (bytesWritten != data.length) {
        throw TorException('Partial write: ${bytesWritten}/${data.length} bytes');
      }
    } catch (e) {
      throw TorException('Failed to write data: $e');
    }
  }
  
  /// Read data from the connection
  Future<Uint8List?> read([int maxBytes = 4096]) async {
    if (_closed) {
      throw StateError('Connection is closed');
    }
    
    try {
      final buffer = Uint8List(maxBytes);
      final bytesRead = _bindings.connectionRead(_client, id, buffer);
      
      if (bytesRead < 0) {
        throw TorException('Read failed with code: $bytesRead');
      }
      
      if (bytesRead == 0) {
        return null; // EOF or no data available
      }
      
      return buffer.sublist(0, bytesRead);
    } catch (e) {
      throw TorException('Failed to read data: $e');
    }
  }
  
  /// Close the connection
  Future<void> close() async {
    if (_closed) {
      return;
    }
    
    try {
      final result = _bindings.connectionClose(_client, id);
      if (result != 0) {
        RelayLogger.warning('Connection close returned code: $result');
      }
    } catch (e) {
      RelayLogger.error('Error closing connection: $e');
    } finally {
      _closed = true;
    }
  }
  
  /// Check if the connection is closed
  bool get isClosed => _closed;
}

/// Exception thrown by Tor operations
class TorException implements Exception {
  final String message;
  
  const TorException(this.message);
  
  @override
  String toString() => 'TorException: $message';
}