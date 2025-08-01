// ABOUTME: Logging utility for the embedded relay with level control
// ABOUTME: Provides structured logging with timestamps and context

import 'package:logging/logging.dart';

class RelayLogger {
  static final Logger _logger = Logger('FlutterEmbeddedNostrRelay');
  static bool _initialized = false;
  
  /// Initialize the logger with the specified level
  static void init({Level level = Level.INFO}) {
    if (_initialized) return;
    
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      final time = record.time.toIso8601String();
      final level = record.level.name;
      final message = record.message;
      final error = record.error != null ? ' ERROR: ${record.error}' : '';
      final stack = record.stackTrace != null ? '\n${record.stackTrace}' : '';
      
      // ignore: avoid_print
      print('[$time] $level: $message$error$stack');
    });
    
    _initialized = true;
  }
  
  /// Log a debug message
  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.fine(message, error, stackTrace);
  }
  
  /// Log an info message
  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.info(message, error, stackTrace);
  }
  
  /// Log a warning message
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(message, error, stackTrace);
  }
  
  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
  
  /// Log WebSocket activity
  static void ws(String action, String details) {
    _logger.fine('WS: $action - $details');
  }
  
  /// Log database activity
  static void db(String action, String details) {
    _logger.finer('DB: $action - $details');
  }
  
  /// Log sync activity
  static void sync(String action, String details) {
    _logger.fine('SYNC: $action - $details');
  }
  
  /// Log event processing
  static void event(String action, String eventId, [String? details]) {
    final msg = details != null ? '$action: $eventId - $details' : '$action: $eventId';
    _logger.finer('EVENT: $msg');
  }
  
  /// Log subscription activity
  static void subscription(String action, String subscriptionId, [String? details]) {
    final msg = details != null ? '$action: $subscriptionId - $details' : '$action: $subscriptionId';
    _logger.fine('SUB: $msg');
  }
  
  /// Log performance metrics
  static void perf(String operation, Duration duration, [String? details]) {
    final msg = details != null 
        ? '$operation took ${duration.inMilliseconds}ms - $details'
        : '$operation took ${duration.inMilliseconds}ms';
    _logger.fine('PERF: $msg');
  }
}