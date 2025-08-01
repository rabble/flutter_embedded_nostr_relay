// ABOUTME: Abstract transport layer for P2P synchronization
// ABOUTME: Defines interface for BLE and WiFi Direct transports

import 'dart:async';

abstract class Transport {
  /// Discover nearby peers
  Stream<TransportPeer> discoverPeers();
  
  /// Connect to a peer
  Future<TransportConnection> connect(TransportPeer peer);
  
  /// Start advertising as available for connections
  Future<void> startAdvertising({required String name});
  
  /// Stop advertising
  Future<void> stopAdvertising();
  
  /// Cleanup resources
  Future<void> dispose();
}

class TransportPeer {
  final String id;
  final String name;
  final Map<String, dynamic> metadata;
  
  TransportPeer({
    required this.id,
    required this.name,
    this.metadata = const {},
  });
}

abstract class TransportConnection {
  /// Send data to peer
  Future<void> send(List<int> data);
  
  /// Receive data from peer
  Stream<List<int>> get dataStream;
  
  /// Connection state
  Stream<bool> get isConnected;
  
  /// Close connection
  Future<void> close();
}