// ABOUTME: Transport stub for web platform
// ABOUTME: P2P sync not available on web platform

import 'dart:async';
import 'transport.dart';
import '../utils/logger.dart';

class BleTransport implements Transport {
  @override
  Stream<TransportPeer> discoverPeers() {
    RelayLogger.warning('BLE transport not supported on web platform');
    return Stream.empty();
  }
  
  @override
  Future<TransportConnection> connect(TransportPeer peer) async {
    throw UnsupportedError('BLE not supported on web');
  }
  
  @override
  Future<void> startAdvertising({required String name}) async {
    RelayLogger.warning('BLE advertising not supported on web');
  }
  
  @override
  Future<void> stopAdvertising() async {}
  
  @override
  Future<void> dispose() async {}
}

class WifiDirectTransport implements Transport {
  @override
  Stream<TransportPeer> discoverPeers() {
    RelayLogger.warning('WiFi Direct not supported on web platform');
    return Stream.empty();
  }
  
  @override
  Future<TransportConnection> connect(TransportPeer peer) async {
    throw UnsupportedError('WiFi Direct not supported on web');
  }
  
  @override
  Future<void> startAdvertising({required String name}) async {
    RelayLogger.warning('WiFi Direct advertising not supported on web');
  }
  
  @override
  Future<void> stopAdvertising() async {}
  
  @override
  Future<void> dispose() async {}
}