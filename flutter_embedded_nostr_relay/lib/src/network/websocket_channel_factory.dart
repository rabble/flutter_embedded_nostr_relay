// ABOUTME: Factory for creating platform-appropriate WebSocket channels
// ABOUTME: Provides cross-platform WebSocket creation using conditional imports

import 'package:web_socket_channel/web_socket_channel.dart';
import 'websocket_channel_factory_stub.dart'
  if (dart.library.io) 'websocket_channel_factory_io.dart'
  if (dart.library.html) 'websocket_channel_factory_web.dart';

/// Factory for creating WebSocket channels that work on all platforms
class WebSocketChannelFactory {
  /// Connect to a WebSocket server at the given URI
  static WebSocketChannel connect(Uri uri) {
    return WebSocketChannelFactoryImpl.connect(uri);
  }
}