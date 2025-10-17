// ABOUTME: Negentropy protocol implementation for efficient set reconciliation
// ABOUTME: Enables bandwidth-efficient P2P synchronization of events

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../utils/logger.dart';

/// Negentropy protocol for efficient Nostr event synchronization
/// Based on the set reconciliation algorithm optimized for bandwidth efficiency
class NegentropySync {
  
  /// Calculate XOR fingerprint for a range of event IDs
  /// This creates a compact representation of the event set for comparison
  static String calculateFingerprint(List<String> eventIds) {
    if (eventIds.isEmpty) {
      return '0' * 64; // Return zero hash for empty set
    }
    
    RelayLogger.sync('fingerprint', 'Calculating for ${eventIds.length} events');
    
    // Sort event IDs to ensure deterministic fingerprinting
    final sortedIds = List<String>.from(eventIds)..sort();
    
    // XOR all event ID hashes together
    final result = Uint8List(32); // 256-bit result
    
    for (final eventId in sortedIds) {
      final hash = sha256.convert(utf8.encode(eventId)).bytes;
      for (int i = 0; i < 32; i++) {
        result[i] ^= hash[i];
      }
    }
    
    final fingerprint = result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    RelayLogger.sync('fingerprint', 'Generated fingerprint: ${fingerprint.substring(0, 16)}...');
    
    return fingerprint;
  }
  
  /// Find differences between local and remote event sets using range-based approach
  static Future<NegentropyDiff> findDifferences(
    List<String> localEventIds,
    Map<String, dynamic> remoteFingerprints,
  ) async {
    RelayLogger.sync('negentropy', 'Finding differences with remote peer');
    
    final sortedLocal = List<String>.from(localEventIds)..sort();
    final toSend = <String>[];
    final toRequest = <String>[];
    
    // Split into ranges for efficient comparison
    const rangeSize = 100; // Events per range for fingerprint comparison
    
    for (int i = 0; i < sortedLocal.length; i += rangeSize) {
      final endIndex = (i + rangeSize < sortedLocal.length) ? i + rangeSize : sortedLocal.length;
      final range = sortedLocal.sublist(i, endIndex);
      final rangeKey = '${i}-${endIndex}';
      
      final localFingerprint = calculateFingerprint(range);
      final remoteFingerprint = remoteFingerprints[rangeKey] as String?;
      
      if (remoteFingerprint == null) {
        // Remote doesn't have this range, send all events
        toSend.addAll(range);
        RelayLogger.sync('negentropy', 'Range $rangeKey: sending ${range.length} events (remote missing)');
      } else if (localFingerprint != remoteFingerprint) {
        // Fingerprints differ, need detailed comparison
        // For now, send all events in range (can be optimized with recursive subdivision)
        toSend.addAll(range);
        RelayLogger.sync('negentropy', 'Range $rangeKey: sending ${range.length} events (fingerprint mismatch)');
      } else {
        RelayLogger.sync('negentropy', 'Range $rangeKey: synchronized (${range.length} events)');
      }
    }
    
    // Check for ranges remote has that we don't
    for (final remoteRangeKey in remoteFingerprints.keys) {
      final parts = remoteRangeKey.split('-');
      if (parts.length != 2) continue;
      
      final startIndex = int.tryParse(parts[0]);
      final endIndex = int.tryParse(parts[1]);
      
      if (startIndex != null && endIndex != null) {
        if (startIndex >= sortedLocal.length) {
          // We don't have events in this range, request them
          toRequest.add(remoteRangeKey);
          RelayLogger.sync('negentropy', 'Requesting range $remoteRangeKey (we are missing)');
        }
      }
    }
    
    RelayLogger.sync('negentropy', 'Sync analysis: ${toSend.length} to send, ${toRequest.length} ranges to request');
    
    return NegentropyDiff(
      eventsToSend: toSend,
      rangesToRequest: toRequest,
    );
  }
  
  /// Generate fingerprint map for all local event ranges
  static Map<String, String> generateFingerprintMap(List<String> eventIds) {
    final result = <String, String>{};
    final sortedIds = List<String>.from(eventIds)..sort();
    
    const rangeSize = 100;
    
    for (int i = 0; i < sortedIds.length; i += rangeSize) {
      final endIndex = (i + rangeSize < sortedIds.length) ? i + rangeSize : sortedIds.length;
      final range = sortedIds.sublist(i, endIndex);
      final rangeKey = '${i}-${endIndex}';
      
      result[rangeKey] = calculateFingerprint(range);
    }
    
    RelayLogger.sync('negentropy', 'Generated fingerprint map with ${result.length} ranges');
    return result;
  }
  
  /// Create a sync message for P2P transmission
  static Map<String, dynamic> createSyncMessage({
    required Map<String, String> fingerprintMap,
    List<String>? eventIds,
    String? syncType,
  }) {
    return {
      'type': syncType ?? 'negentropy_sync',
      'fingerprints': fingerprintMap,
      'events': eventIds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
  
  /// Parse a sync message from P2P transmission
  static NegentropyMessage? parseSyncMessage(Map<String, dynamic> data) {
    try {
      final type = data['type'] as String?;
      final fingerprints = data['fingerprints'] as Map<String, dynamic>?;
      final events = data['events'] as List<dynamic>?;
      final timestamp = data['timestamp'] as int?;
      
      if (type == null || fingerprints == null) {
        RelayLogger.sync('negentropy', 'Invalid sync message format');
        return null;
      }
      
      return NegentropyMessage(
        type: type,
        fingerprints: fingerprints.cast<String, String>(),
        eventIds: events?.cast<String>(),
        timestamp: timestamp ?? 0,
      );
    } catch (e) {
      RelayLogger.sync('negentropy', 'Failed to parse sync message: $e');
      return null;
    }
  }
}

/// Result of negentropy difference calculation
class NegentropyDiff {
  final List<String> eventsToSend;
  final List<String> rangesToRequest;
  
  NegentropyDiff({
    required this.eventsToSend,
    required this.rangesToRequest,
  });
  
  bool get hasChanges => eventsToSend.isNotEmpty || rangesToRequest.isNotEmpty;
}

/// Negentropy sync message structure
class NegentropyMessage {
  final String type;
  final Map<String, String> fingerprints;
  final List<String>? eventIds;
  final int timestamp;
  
  NegentropyMessage({
    required this.type,
    required this.fingerprints,
    this.eventIds,
    required this.timestamp,
  });
}