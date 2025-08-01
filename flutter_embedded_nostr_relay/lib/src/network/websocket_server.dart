// ABOUTME: WebSocket server implementation for non-web platforms
// ABOUTME: Provides local relay endpoint on ws://localhost:7447

import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/logger.dart';
import '../core/constants.dart';

class WebSocketServer {
  HttpServer? _server;
  final Set<WebSocketChannel> _clients = {};
  
  /// Start the WebSocket server
  Future<void> start({
    String host = RelayConstants.defaultHost,
    int port = RelayConstants.defaultPort,
  }) async {
    if (_server != null) {
      RelayLogger.warning('WebSocket server already running');
      return;
    }
    
    final handler = webSocketHandler((WebSocketChannel webSocket) {
      _handleConnection(webSocket);
    });
    
    _server = await shelf_io.serve(
      handler,
      host,
      port,
    );
    
    RelayLogger.info('WebSocket server listening on ws://$host:$port');
  }
  
  /// Stop the WebSocket server
  Future<void> stop() async {
    if (_server == null) return;
    
    // Close all client connections
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
    
    // Stop server
    await _server!.close();
    _server = null;
    
    RelayLogger.info('WebSocket server stopped');
  }
  
  void _handleConnection(WebSocketChannel webSocket) {
    _clients.add(webSocket);
    RelayLogger.ws('client-connected', 'Total clients: ${_clients.length}');
    
    // Listen for messages
    webSocket.stream.listen(
      (message) {
        _handleMessage(webSocket, message);
      },
      onError: (error) {
        RelayLogger.error('WebSocket error', error);
      },
      onDone: () {
        _clients.remove(webSocket);
        RelayLogger.ws('client-disconnected', 'Total clients: ${_clients.length}');
      },
    );
  }
  
  void _handleMessage(WebSocketChannel client, dynamic message) {
    try {
      // TODO: Parse and handle Nostr protocol messages
      RelayLogger.ws('message-received', message.toString());
      
      // Echo for now
      client.sink.add('["NOTICE", "Message received"]');
      
    } catch (e) {
      RelayLogger.error('Failed to handle WebSocket message', e);
      client.sink.add('["NOTICE", "Invalid message format"]');
    }
  }
}