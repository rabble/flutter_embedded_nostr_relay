// ABOUTME: Stub implementation of WebSocket channel factory
// ABOUTME: Fallback implementation when no platform is detected

import 'package:web_socket_channel/web_socket_channel.dart';

/// Stub implementation that throws an error
class WebSocketChannelFactoryImpl {
  static WebSocketChannel connect(Uri uri) {
    throw UnsupportedError('WebSocket not supported on this platform');
  }
}