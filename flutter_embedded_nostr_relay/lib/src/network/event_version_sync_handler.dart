// ABOUTME: Handles bidirectional event version synchronization between relays
// ABOUTME: Ensures network consistency by pushing newer versions back when receiving older ones

import '../storage/event_store.dart';
import '../network/external_relay_client.dart';
import '../models/nostr_event.dart';
import '../utils/logger.dart';

/// Actions that can be taken when processing an incoming event
enum SyncAction {
  /// Event was stored successfully (new or newer version)
  stored,
  
  /// Event was rejected as duplicate (same ID)
  duplicate,
  
  /// Event was rejected, pushed back our newer version
  pushedBackNewer,
  
  /// Event was ignored (same timestamp)
  sameVersion,
  
  /// Ephemeral event was processed but not stored
  ephemeralProcessed,
  
  /// Protocol violation detected (same ID, different content)
  protocolViolation,
  
  /// Error occurred during processing
  error,
}

/// Result of processing an incoming event
class SyncResult {
  final SyncAction action;
  final String? reason;
  
  const SyncResult(this.action, [this.reason]);
  
  @override
  String toString() => 'SyncResult($action${reason != null ? ': $reason' : ''})';
}

/// Handles bidirectional event version synchronization.
/// 
/// When receiving events from external relays, this handler:
/// - Stores new events normally
/// - For replaceable events: compares versions and either stores newer or pushes back our newer version
/// - Detects protocol violations (same ID with different content)
/// - Handles ephemeral events without storing them
/// 
/// This ensures network consistency by preventing older versions from overwriting newer ones
/// and actively propagating newer versions back to relays that have outdated data.
class EventVersionSyncHandler {
  final EventStore eventStore;
  final ExternalRelayClient relayClient;
  
  EventVersionSyncHandler({
    required this.eventStore,
    required this.relayClient,
  });
  
  /// Handle an incoming event from an external relay.
  /// 
  /// This method implements the core bidirectional sync logic:
  /// 1. Check if we already have this exact event (by ID)
  /// 2. For replaceable events, compare versions with our stored version
  /// 3. Store newer incoming events
  /// 4. Push back our newer version if incoming is older
  /// 5. Handle ephemeral events without storage
  /// 6. Detect protocol violations
  /// 
  /// Parameters:
  /// - [event]: The incoming event to process
  /// 
  /// Returns a [SyncResult] indicating what action was taken.
  Future<SyncResult> handleIncomingEvent(NostrEvent event) async {
    try {
      // Handle ephemeral events first (they're never stored)
      if (event.isEphemeral) {
        RelayLogger.event('ephemeral-processed', event.id, 'kind: ${event.kind}');
        return const SyncResult(SyncAction.ephemeralProcessed);
      }
      
      // Check if we already have this exact event
      final existingEvent = await eventStore.getEventById(event.id);
      if (existingEvent != null) {
        // Verify this isn't a protocol violation (same ID, different content)
        if (existingEvent.content != event.content ||
            existingEvent.pubkey != event.pubkey ||
            existingEvent.kind != event.kind ||
            existingEvent.createdAt != event.createdAt) {
          RelayLogger.warning('Protocol violation: same ID different content', 
              'ID: ${event.id}');
          return const SyncResult(SyncAction.protocolViolation, 
              'same ID different content');
        }
        
        // Exact duplicate
        return const SyncResult(SyncAction.duplicate);
      }
      
      // Handle regular events (not replaceable)
      if (!event.isReplaceable && !event.isParameterizedReplaceable) {
        final success = await eventStore.storeEvent(event);
        if (success) {
          return const SyncResult(SyncAction.stored);
        } else {
          return const SyncResult(SyncAction.error, 'Failed to store event');
        }
      }
      
      // Handle replaceable events (10000-19999)
      if (event.isReplaceable) {
        return await _handleReplaceableEvent(event);
      }
      
      // Handle parameterized replaceable events (30000-39999)
      if (event.isParameterizedReplaceable) {
        return await _handleParameterizedReplaceableEvent(event);
      }
      
      // Fallback: store the event
      final success = await eventStore.storeEvent(event);
      return SyncResult(success ? SyncAction.stored : SyncAction.error);
      
    } catch (e) {
      RelayLogger.error('Error handling incoming event: ${event.id}', e);
      return SyncResult(SyncAction.error, 'Exception: $e');
    }
  }
  
  Future<SyncResult> _handleReplaceableEvent(NostrEvent incomingEvent) async {
    final localEvent = await eventStore.getLatestReplaceableEvent(
        incomingEvent.kind, incomingEvent.pubkey);
    
    if (localEvent == null) {
      // No local version, store the incoming event
      final success = await eventStore.storeEvent(incomingEvent);
      return SyncResult(success ? SyncAction.stored : SyncAction.error);
    }
    
    // Compare timestamps
    if (incomingEvent.createdAt > localEvent.createdAt) {
      // Incoming is newer, store it
      final success = await eventStore.storeEvent(incomingEvent);
      return SyncResult(success ? SyncAction.stored : SyncAction.error, 
          'newer version');
    } else if (incomingEvent.createdAt < localEvent.createdAt) {
      // Incoming is older, push back our newer version
      try {
        await relayClient.sendEvent(localEvent);
        RelayLogger.event('pushed-back', localEvent.id, 
            'pushed newer version to relay');
        return const SyncResult(SyncAction.pushedBackNewer, 
            'pushed newer version');
      } catch (e) {
        RelayLogger.error('Failed to push back newer event', e);
        return SyncResult(SyncAction.error, 'Failed to push back: $e');
      }
    } else {
      // Same timestamp, ignore
      return const SyncResult(SyncAction.sameVersion);
    }
  }
  
  Future<SyncResult> _handleParameterizedReplaceableEvent(NostrEvent incomingEvent) async {
    final dTag = incomingEvent.dTagValue ?? '';
    final localEvent = await eventStore.getLatestParameterizedReplaceableEvent(
        incomingEvent.kind, incomingEvent.pubkey, dTag);
    
    if (localEvent == null) {
      // No local version, store the incoming event
      final success = await eventStore.storeEvent(incomingEvent);
      return SyncResult(success ? SyncAction.stored : SyncAction.error);
    }
    
    // Compare timestamps
    if (incomingEvent.createdAt > localEvent.createdAt) {
      // Incoming is newer, store it
      final success = await eventStore.storeEvent(incomingEvent);
      return SyncResult(success ? SyncAction.stored : SyncAction.error, 
          'newer version');
    } else if (incomingEvent.createdAt < localEvent.createdAt) {
      // Incoming is older, push back our newer version
      try {
        await relayClient.sendEvent(localEvent);
        RelayLogger.event('pushed-back', localEvent.id, 
            'pushed newer parameterized replaceable to relay');
        return const SyncResult(SyncAction.pushedBackNewer, 
            'pushed newer version');
      } catch (e) {
        RelayLogger.error('Failed to push back newer parameterized replaceable', e);
        return SyncResult(SyncAction.error, 'Failed to push back: $e');
      }
    } else {
      // Same timestamp, ignore
      return const SyncResult(SyncAction.sameVersion);
    }
  }
}