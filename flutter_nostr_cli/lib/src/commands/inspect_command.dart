// ABOUTME: Inspect command for debugging and monitoring Nostr relay connections and events
// ABOUTME: Provides real-time event streaming, filtering, performance metrics, and export capabilities
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:args/command_runner.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/nostr_event.dart';

typedef WebSocketFactory = WebSocketChannel Function();

class InspectCommand extends Command<int> {
  InspectCommand() {
    argParser.addOption(
      'events',
      abbr: 'e',
      help: 'Maximum number of events to collect',
      defaultsTo: '100',
    );
    argParser.addMultiOption(
      'kind',
      abbr: 'k',
      help: 'Filter by event kind (can be specified multiple times)',
    );
    argParser.addMultiOption(
      'author',
      abbr: 'a',
      help: 'Filter by author pubkey (can be specified multiple times)',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Export events to JSON file',
    );
    argParser.addFlag(
      'metrics',
      abbr: 'm',
      help: 'Show performance metrics',
      defaultsTo: true,
    );
    argParser.addFlag(
      'dry-run',
      help: 'Show what would be inspected without connecting',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'inspect';

  @override
  String get description => 'Inspect and debug Nostr relay connections';

  @override
  String get invocation => 'flutter_nostr inspect <relay-url> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    
    if (args.rest.isEmpty) {
      usageException('Relay URL is required');
    }

    final relayUrl = args.rest.first;
    final maxEvents = int.tryParse(args['events']) ?? 100;
    final kindFilter = args['kind'].map((k) => int.tryParse(k)).whereType<int>().toList();
    final authorFilter = args['author'] as List<String>;
    final outputFile = args['output'] as String?;
    final showMetrics = args['metrics'] as bool;
    final dryRun = args['dry-run'] as bool;

    if (dryRun) {
      print('Would inspect relay: $relayUrl');
      print('Max events: $maxEvents');
      if (kindFilter.isNotEmpty) print('Kind filter: $kindFilter');
      if (authorFilter.isNotEmpty) print('Author filter: $authorFilter');
      return 0;
    }

    final events = <NostrEvent>[];
    final startTime = DateTime.now();

    print('🔍 Inspecting relay: $relayUrl');
    print('Collecting up to $maxEvents events...');
    print('Press Ctrl+C to stop');
    print('');

    try {
      await inspect(
        relayUrl,
        maxEvents: maxEvents,
        kindFilter: kindFilter.isNotEmpty ? kindFilter : null,
        authorFilter: authorFilter.isNotEmpty ? authorFilter : null,
        onEvent: (event) {
          events.add(event);
          _printEvent(event, events.length);
        },
      );
    } catch (e) {
      io.stderr.writeln('Error connecting to relay: $e');
      return 1;
    }

    print('');
    print('📊 Collection complete');
    print('Total events received: ${events.length}');

    if (showMetrics) {
      final metrics = calculateMetrics(events, startTime);
      _printMetrics(metrics);
    }

    if (outputFile != null) {
      final exportJson = exportEvents(events);
      await io.File(outputFile).writeAsString(exportJson);
      print('💾 Events exported to: $outputFile');
    }

    return 0;
  }

  Future<void> inspect(
    String relayUrl, {
    int maxEvents = 100,
    List<int>? kindFilter,
    List<String>? authorFilter,
    Function(NostrEvent)? onEvent,
    WebSocketFactory? webSocketFactory,
  }) async {
    WebSocketChannel? channel;

    try {
      // Connect to relay
      if (webSocketFactory != null) {
        channel = webSocketFactory();
      } else {
        channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      }

      // Send subscription request
      final subId = 'inspect_${DateTime.now().millisecondsSinceEpoch}';
      final filters = <Map<String, dynamic>>[
        {
          if (kindFilter != null) 'kinds': kindFilter,
          if (authorFilter != null) 'authors': authorFilter,
          'limit': maxEvents,
        }
      ];

      final request = ['REQ', subId, ...filters];
      channel.sink.add(jsonEncode(request));

      final completer = Completer<void>();
      int eventCount = 0;

      // Listen for events
      channel.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            if (message is List && message.length >= 2) {
              final type = message[0];
              
              if (type == 'EVENT' && message.length >= 3) {
                final eventData = message[2] as Map<String, dynamic>;
                final event = NostrEvent.fromJson(eventData);
                
                onEvent?.call(event);
                eventCount++;
                
                if (eventCount >= maxEvents) {
                  completer.complete();
                }
              } else if (type == 'EOSE') {
                completer.complete();
              }
            }
          } catch (e) {
            io.stderr.writeln('Error parsing message: $e');
          }
        },
        onError: (error) {
          completer.completeError(error);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await completer.future;
    } finally {
      await channel?.sink.close();
    }
  }

  String exportEvents(List<NostrEvent> events) {
    final exportData = {
      'timestamp': DateTime.now().toIso8601String(),
      'count': events.length,
      'events': events.map((e) => e.toJson()).toList(),
    };
    return jsonEncode(exportData);
  }

  Map<String, dynamic> calculateMetrics(List<NostrEvent> events, DateTime startTime) {
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    final eventsPerSecond = events.length / duration.inSeconds;
    
    // Calculate average latency (rough estimate based on created_at vs received time)
    double totalLatency = 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    for (final event in events) {
      final eventAge = now - event.createdAt;
      totalLatency += eventAge;
    }
    
    final averageLatency = events.isNotEmpty ? totalLatency / events.length : 0;

    return {
      'totalEvents': events.length,
      'duration': duration.inSeconds,
      'eventsPerSecond': eventsPerSecond,
      'averageLatency': averageLatency,
    };
  }

  void _printEvent(NostrEvent event, int index) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);
    final timeString = timestamp.toLocal().toString().substring(11, 19);
    final shortId = event.id.substring(0, 8);
    final shortPubkey = event.pubkey.substring(0, 8);
    final content = event.content.length > 50 
        ? '${event.content.substring(0, 50)}...' 
        : event.content;

    print('[$index] $timeString | Kind ${event.kind} | $shortId | $shortPubkey | $content');
  }

  void _printMetrics(Map<String, dynamic> metrics) {
    print('');
    print('📈 Performance Metrics:');
    print('  Duration: ${metrics['duration']}s');
    print('  Events/sec: ${metrics['eventsPerSecond'].toStringAsFixed(2)}');
    print('  Avg latency: ${metrics['averageLatency'].toStringAsFixed(2)}s');
  }
}