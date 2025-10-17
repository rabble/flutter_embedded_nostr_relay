// ABOUTME: Tests for the inspect command that debugs and monitors Nostr relay connections
// ABOUTME: Validates relay connection, event streaming, filtering, and performance metrics
import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../lib/src/commands/inspect_command.dart';
import '../../lib/src/models/nostr_event.dart';

class MockWebSocketChannel implements WebSocketChannel {
  final StreamController<String> _controller = StreamController<String>();
  final StreamController<dynamic> _sinkController = StreamController<dynamic>();
  
  @override
  Stream<dynamic> get stream => _controller.stream;
  
  @override
  WebSocketSink get sink => MockWebSocketSink(_sinkController.sink);
  
  @override
  String? get protocol => null;
  
  @override
  int? get closeCode => null;
  
  @override
  String? get closeReason => null;
  
  @override
  Future<void> get ready => Future.value();
  
  // Implement missing methods with noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  
  void addEvent(Map<String, dynamic> event) {
    _controller.add('["EVENT", "sub1", ${jsonEncode(event)}]');
  }
  
  void addEose() {
    _controller.add('["EOSE", "sub1"]');
  }
  
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _controller.close();
    await _sinkController.close();
  }
}

class MockWebSocketSink implements WebSocketSink {
  final StreamSink<dynamic> _sink;
  
  MockWebSocketSink(this._sink);
  
  @override
  void add(dynamic data) => _sink.add(data);
  
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _sink.addError(error, stackTrace);
  
  @override
  Future<void> addStream(Stream<dynamic> stream) => _sink.addStream(stream);
  
  @override
  Future<void> close([int? closeCode, String? closeReason]) => _sink.close();
  
  @override
  Future<void> get done => _sink.done;
}

void main() {
  group('InspectCommand', () {
    late InspectCommand command;
    late MockWebSocketChannel mockChannel;

    setUp(() {
      mockChannel = MockWebSocketChannel();
      command = InspectCommand();
    });

    tearDown(() {
      mockChannel.close();
    });

    test('should connect to relay and receive events', () async {
      final events = <NostrEvent>[];
      
      // Mock a text note event
      final testEvent = {
        'id': 'test123',
        'pubkey': 'pubkey123',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'content': 'Hello, Nostr!',
        'sig': 'signature123'
      };

      // Start inspection in the background
      final inspectFuture = command.inspect(
        'ws://localhost:7447',
        onEvent: (event) => events.add(event),
        webSocketFactory: () => mockChannel,
      );

      // Simulate receiving an event
      mockChannel.addEvent(testEvent);
      mockChannel.addEose();
      
      // Wait a moment for processing
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(events.length, equals(1));
      expect(events.first.content, equals('Hello, Nostr!'));
      expect(events.first.kind, equals(1));

      await inspectFuture.timeout(Duration(seconds: 1));
    });

    test('should filter events by kind', () async {
      final events = <NostrEvent>[];
      
      final textEvent = {
        'id': 'text123',
        'pubkey': 'pubkey123',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'content': 'Text note',
        'sig': 'signature123'
      };
      
      final metadataEvent = {
        'id': 'meta123',
        'pubkey': 'pubkey123',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 0,
        'tags': [],
        'content': '{"name": "Alice"}',
        'sig': 'signature123'
      };

      final inspectFuture = command.inspect(
        'ws://localhost:7447',
        kindFilter: [1], // Only text notes
        onEvent: (event) => events.add(event),
        webSocketFactory: () => mockChannel,
      );

      mockChannel.addEvent(textEvent);
      mockChannel.addEvent(metadataEvent);
      mockChannel.addEose();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(events.length, equals(1));
      expect(events.first.kind, equals(1));
      expect(events.first.content, equals('Text note'));

      await inspectFuture.timeout(Duration(seconds: 1));
    });

    test('should filter events by author', () async {
      final events = <NostrEvent>[];
      final targetPubkey = 'target_pubkey';
      
      final targetEvent = {
        'id': 'target123',
        'pubkey': targetPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'content': 'From target author',
        'sig': 'signature123'
      };
      
      final otherEvent = {
        'id': 'other123',
        'pubkey': 'other_pubkey',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'content': 'From other author',
        'sig': 'signature123'
      };

      final inspectFuture = command.inspect(
        'ws://localhost:7447',
        authorFilter: [targetPubkey],
        onEvent: (event) => events.add(event),
        webSocketFactory: () => mockChannel,
      );

      mockChannel.addEvent(targetEvent);
      mockChannel.addEvent(otherEvent);
      mockChannel.addEose();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(events.length, equals(1));
      expect(events.first.pubkey, equals(targetPubkey));
      expect(events.first.content, equals('From target author'));

      await inspectFuture.timeout(Duration(seconds: 1));
    });

    test('should export events to JSON', () async {
      final events = <NostrEvent>[];
      
      final testEvent = {
        'id': 'export123',
        'pubkey': 'pubkey123',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1,
        'tags': [],
        'content': 'Export test',
        'sig': 'signature123'
      };

      final inspectFuture = command.inspect(
        'ws://localhost:7447',
        onEvent: (event) => events.add(event),
        webSocketFactory: () => mockChannel,
      );

      mockChannel.addEvent(testEvent);
      mockChannel.addEose();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final exportJson = command.exportEvents(events);
      expect(exportJson, isNotEmpty);
      expect(exportJson, contains('export123'));
      expect(exportJson, contains('Export test'));

      await inspectFuture.timeout(Duration(seconds: 1));
    });

    test('should calculate performance metrics', () async {
      final events = <NostrEvent>[];
      final startTime = DateTime.now();
      
      // Add multiple events with timing
      for (int i = 0; i < 5; i++) {
        final testEvent = {
          'id': 'perf$i',
          'pubkey': 'pubkey123',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'kind': 1,
          'tags': [],
          'content': 'Perf test $i',
          'sig': 'signature123'
        };
        mockChannel.addEvent(testEvent);
      }

      final inspectFuture = command.inspect(
        'ws://localhost:7447',
        onEvent: (event) => events.add(event),
        webSocketFactory: () => mockChannel,
      );

      mockChannel.addEose();
      await Future.delayed(Duration(milliseconds: 100));
      
      final metrics = command.calculateMetrics(events, startTime);
      expect(metrics['totalEvents'], equals(5));
      expect(metrics['eventsPerSecond'], greaterThan(0));
      expect(metrics['averageLatency'], isA<double>());

      await inspectFuture.timeout(Duration(seconds: 1));
    });
  });
}