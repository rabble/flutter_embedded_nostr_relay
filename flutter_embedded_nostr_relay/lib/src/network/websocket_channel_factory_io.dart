// ABOUTME: IO implementation of WebSocket channel factory for native platforms
// ABOUTME: Creates IOWebSocketChannel for mobile and desktop platforms

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// IO implementation for native platforms
class WebSocketChannelFactoryImpl {
  static WebSocketChannel connect(Uri uri) {
    return IOWebSocketChannel.connect(uri);
  }
}