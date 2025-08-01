// ABOUTME: WebSocket server stub for web platform
// ABOUTME: WebSocket server not available on web platform

import 'dart:async';
import '../utils/logger.dart';

class WebSocketServer {
  /// Start the WebSocket server (not supported on web)
  Future<void> start({String host = 'localhost', int port = 7447}) async {
    RelayLogger.warning('WebSocket server not supported on web platform');
  }
  
  /// Stop the WebSocket server (no-op on web)
  Future<void> stop() async {
    // No-op on web
  }
}