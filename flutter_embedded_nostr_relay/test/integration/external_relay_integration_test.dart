// ABOUTME: Integration tests for ExternalRelayClient with mock WebSocket server
// ABOUTME: Tests real WebSocket behavior without depending on external relays

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';

void main() {
  group('ExternalRelayClient Integration Tests', () {
    HttpServer? mockServer;
    List<WebSocket> connectedClients = [];
    
    setUpAll(() async {
      // Start a mock WebSocket server
      mockServer = await HttpServer.bind('localhost', 0);
      
      mockServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          connectedClients.add(ws);
          
          // Handle messages from client
          ws.listen((message) {
            final decoded = json.decode(message) as List;
            final messageType = decoded[0];
            
            switch (messageType) {
              case 'REQ':
                // Send back a test event
                ws.add(json.encode([
                  'EVENT',
                  decoded[1], // subscription ID
                  {
                    'id': 'mock_event_id',
                    'pubkey': 'mock_pubkey',
                    'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    'kind': 1,
                    'tags': [],
                    'content': 'Mock event from server',
                    'sig': 'mock_sig',
                  }
                ]));
                
                // Send EOSE
                Timer(Duration(milliseconds: 100), () {
                  ws.add(json.encode(['EOSE', decoded[1]]));
                });
                break;
                
              case 'EVENT':
                // Send back OK
                final event = decoded[1] as Map<String, dynamic>;
                ws.add(json.encode(['OK', event['id'], true, 'Event stored']));
                break;
                
              case 'CLOSE':
                // Just acknowledge
                break;
            }
          }, onDone: () {
            // Remove from connected clients when connection closes
            connectedClients.remove(ws);
          });
        }
      });
    });
    
    tearDownAll(() async {
      for (final client in connectedClients) {
        await client.close();
      }
      await mockServer?.close();
    });
    
    test('connects to mock relay and receives events', () async {
      final port = mockServer!.port;
      final client = ExternalRelayClient(url: 'ws://localhost:$port');
      
      final receivedEvents = <NostrEvent>[];
      String? eoseSubId;
      
      client.onEvent = (event) {
        receivedEvents.add(event);
      };
      
      client.onEose = (subId) {
        eoseSubId = subId;
      };
      
      // Connect
      await client.connect();
      expect(client.isConnected, true);
      
      // Send subscription
      final filter = Filter(kinds: [1], limit: 10);
      final sent = await client.sendRequest('test_sub', [filter]);
      expect(sent, true);
      
      // Wait for response
      await Future.delayed(Duration(milliseconds: 200));
      
      // Verify we received the event
      expect(receivedEvents.length, 1);
      expect(receivedEvents[0].content, 'Mock event from server');
      expect(eoseSubId, 'test_sub');
      
      // Disconnect
      await client.disconnect();
      expect(client.isConnected, false);
    });
    
    test('publishes event and receives OK', () async {
      final port = mockServer!.port;
      final client = ExternalRelayClient(url: 'ws://localhost:$port');
      
      String? okEventId;
      bool? okStatus;
      String? okMessage;
      
      client.onOk = (eventId, status, message) {
        okEventId = eventId;
        okStatus = status;
        okMessage = message;
      };
      
      await client.connect();
      
      // Create and send event
      final event = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 1,
        tags: [],
        content: 'Test event',
      );
      
      final sent = await client.sendEvent(event);
      expect(sent, true);
      
      // Wait for OK response
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(okEventId, event.id);
      expect(okStatus, true);
      expect(okMessage, 'Event stored');
      
      await client.disconnect();
    });
    
    test('handles disconnection and reconnection', () async {
      final port = mockServer!.port;
      final client = ExternalRelayClient(url: 'ws://localhost:$port');
      
      // First connection
      await client.connect();
      expect(client.isConnected, true);
      
      // Disconnect
      await client.disconnect();
      expect(client.isConnected, false);
      
      // Reconnect
      await client.connect();
      expect(client.isConnected, true);
      
      await client.disconnect();
    });
    
    test('handles server-initiated disconnection', () async {
      final port = mockServer!.port;
      final client = ExternalRelayClient(url: 'ws://localhost:$port');
      
      await client.connect();
      expect(client.isConnected, true);
      
      // Wait a bit for the server to register the connection
      await Future.delayed(Duration(milliseconds: 100));
      
      // Ensure we have a connection in the server list
      expect(connectedClients.isNotEmpty, true);
      
      // Server forcibly closes connection
      final serverSocket = connectedClients.last;
      await serverSocket.close(1000, 'Server initiated close'); // Normal close
      
      // Give time for client to detect disconnection
      await Future.delayed(Duration(milliseconds: 500));
      
      expect(client.isConnected, false);
    });
    
    test('sends CLOSE message', () async {
      final port = mockServer!.port;
      final client = ExternalRelayClient(url: 'ws://localhost:$port');
      
      await client.connect();
      
      final result = await client.closeSubscription('sub_to_close');
      expect(result, true);
      
      await client.disconnect();
    });
  });
  
  group('EmbeddedNostrRelay with External Relays', () {
    HttpServer? mockServer;
    List<WebSocket> connectedClients = [];
    List<String> serverReceivedMessages = [];
    
    setUpAll(() async {
      DatabaseHelper.enableTestMode();
      
      // Start mock server
      mockServer = await HttpServer.bind('localhost', 0);
      
      mockServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          connectedClients.add(ws);
          
          ws.listen((message) {
            serverReceivedMessages.add(message);
            
            final decoded = json.decode(message) as List;
            final messageType = decoded[0];
            
            if (messageType == 'EVENT') {
              final event = decoded[1] as Map<String, dynamic>;
              ws.add(json.encode(['OK', event['id'], true]));
            }
          });
        }
      });
    });
    
    tearDownAll(() async {
      for (final client in connectedClients) {
        await client.close();
      }
      await mockServer?.close();
    });
    
    test('embedded relay publishes to external relay', () async {
      final relay = EmbeddedNostrRelay();
      await relay.initialize();
      
      // Add mock external relay
      final port = mockServer!.port;
      await relay.addExternalRelay('ws://localhost:$port');
      
      expect(relay.connectedRelays.length, 1);
      expect(relay.connectedRelays[0], 'ws://localhost:$port');
      
      // Publish event
      final event = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 1,
        tags: [],
        content: 'Test from embedded relay',
      ).sign('0000000000000000000000000000000000000000000000000000000000000001');
      
      await relay.publish(event);
      
      // Wait for external relay to receive it
      await Future.delayed(Duration(milliseconds: 200));
      
      // Verify server received the event
      expect(serverReceivedMessages.any((msg) {
        final decoded = json.decode(msg) as List;
        return decoded[0] == 'EVENT' && 
               (decoded[1] as Map)['content'] == 'Test from embedded relay';
      }), true);
      
      await relay.shutdown();
    });
  });
}