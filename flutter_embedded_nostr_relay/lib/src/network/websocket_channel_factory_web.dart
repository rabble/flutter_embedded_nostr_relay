// ABOUTME: Web implementation of WebSocket channel factory for browser platform
// ABOUTME: Creates HtmlWebSocketChannel for web applications

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart';

/// Web implementation for browser platform
class WebSocketChannelFactoryImpl {
  static WebSocketChannel connect(Uri uri) {
    return HtmlWebSocketChannel.connect(uri);
  }
}