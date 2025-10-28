// ABOUTME: Batching write queue that prevents database lock contention from concurrent writes
// ABOUTME: Single writer process with time-based and size-based batch triggers

import 'dart:async';
import 'dart:collection';

import '../models/nostr_event.dart';
import '../utils/logger.dart';
import 'event_store.dart';

/// Write queue for batching Nostr events to prevent database lock contention.
///
/// External relays can send hundreds of events simultaneously, which would
/// create concurrent write transactions and "database is locked" errors.
/// This queue ensures a single writer with intelligent batching.
///
/// Features:
/// - Time-based batching (100ms interval)
/// - Size-based batching (100 events threshold)
/// - Completer-based async notification (no Future.delayed)
/// - Drain queue before shutdown to prevent data loss
/// - Back-pressure monitoring (warns if queue grows >1000)
///
/// Usage:
/// ```dart
/// final queue = EventWriteQueue(eventStore);
///
/// // Enqueue event (returns Future<bool> when written)
/// final stored = await queue.enqueue(event);
///
/// // Drain before shutdown
/// await queue.drain();
/// ```
class EventWriteQueue {
  EventWriteQueue(this._eventStore);

  final EventStore _eventStore;
  final Queue<_PendingWrite> _queue = Queue();
  Timer? _batchTimer;
  bool _isProcessing = false;
  bool _isDisposed = false;

  // Configuration
  static const int maxBatchSize = 1000;
  static const int batchSizeThreshold = 100;
  static const Duration batchInterval = Duration(milliseconds: 100);
  static const int backPressureWarningThreshold = 1000;

  /// Enqueue an event for batched writing.
  /// Returns a Future that completes with true if stored, false if duplicate/rejected.
  Future<bool> enqueue(NostrEvent event) {
    if (_isDisposed) {
      return Future.error(
          StateError('Cannot enqueue events after queue is disposed'));
    }

    final completer = Completer<bool>();
    _queue.add(_PendingWrite(event, completer));

    // Back-pressure warning
    if (_queue.length > backPressureWarningThreshold) {
      RelayLogger.warning(
          '[EventWriteQueue] Write queue growing large: ${_queue.length} events pending');
    }

    _scheduleBatch();
    return completer.future;
  }

  /// Schedule a batch write based on triggers:
  /// 1. Size threshold (100 events) - immediate
  /// 2. Time threshold (100ms) - delayed
  void _scheduleBatch() {
    // Already processing or timer pending
    if (_isProcessing || _batchTimer != null || _isDisposed) return;

    // Trigger 1: Size threshold - process immediately
    if (_queue.length >= batchSizeThreshold) {
      _processBatch();
      return;
    }

    // Trigger 2: Time threshold - schedule for later
    _batchTimer = Timer(batchInterval, () {
      _batchTimer = null;
      if (!_isDisposed) {
        _processBatch();
      }
    });
  }

  /// Process a batch of events in a single database transaction.
  Future<void> _processBatch() async {
    if (_isProcessing || _queue.isEmpty || _isDisposed) return;

    _isProcessing = true;
    final batch = <_PendingWrite>[];

    try {
      // Dequeue up to maxBatchSize events
      while (_queue.isNotEmpty && batch.length < maxBatchSize) {
        batch.add(_queue.removeFirst());
      }

      RelayLogger.db(
          'batch-write', 'Processing batch of ${batch.length} events');

      // SINGLE transaction for entire batch
      final events = batch.map((w) => w.event).toList();
      final storedCount = await _eventStore.storeEvents(events);

      // Complete all futures with true
      // Note: storeEvents returns true for both stored and duplicate events
      // We can't distinguish per-event results in batch mode, so all succeed
      for (final write in batch) {
        write.completer.complete(true);
      }

      RelayLogger.db('batch-write',
          'Wrote $storedCount/${batch.length} events (${_queue.length} remaining in queue)');
    } catch (e, stack) {
      // Fail all pending writes in this batch
      RelayLogger.error('Batch write failed for ${batch.length} events: $e',
          e, stack);
      for (final write in batch) {
        if (!write.completer.isCompleted) {
          write.completer.completeError(e, stack);
        }
      }
    } finally {
      _isProcessing = false;

      // Process next batch if queue not empty
      if (_queue.isNotEmpty && !_isDisposed) {
        _scheduleBatch();
      }
    }
  }

  /// Drain the queue by processing all pending writes.
  /// CRITICAL: Must be called before closing the database to prevent
  /// "Cannot add new events after calling close" errors.
  Future<void> drain() async {
    RelayLogger.info(
        '[EventWriteQueue] Draining write queue (${_queue.length} events pending)');

    // Cancel pending timer
    _batchTimer?.cancel();
    _batchTimer = null;

    // Process all remaining batches
    while (_queue.isNotEmpty && !_isDisposed) {
      await _processBatch();
    }

    RelayLogger.info('[EventWriteQueue] Write queue drained');
  }

  /// Dispose the queue and reject any future enqueue attempts.
  void dispose() {
    _isDisposed = true;
    _batchTimer?.cancel();
    _batchTimer = null;

    // Complete any remaining pending writes with error
    while (_queue.isNotEmpty) {
      final write = _queue.removeFirst();
      if (!write.completer.isCompleted) {
        write.completer.completeError(
            StateError('Queue disposed before event could be written'));
      }
    }
  }

  // Metrics for monitoring and testing

  /// Number of events waiting to be written
  int get queueSize => _queue.length;

  /// Whether the queue is idle (no pending writes, not processing)
  bool get isIdle => _queue.isEmpty && !_isProcessing;

  /// Whether currently processing a batch
  bool get isProcessing => _isProcessing;
}

/// Internal class to track a pending write operation
class _PendingWrite {
  _PendingWrite(this.event, this.completer);

  final NostrEvent event;
  final Completer<bool> completer;
}
