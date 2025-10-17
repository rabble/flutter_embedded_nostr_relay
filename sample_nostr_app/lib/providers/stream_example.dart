// ABOUTME: Example of using StreamProvider with the relay's event stream
// ABOUTME: Shows how to integrate relay streams with Provider or Riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

// Example using Provider's StreamProvider
class StreamExample extends StatelessWidget {
  final EmbeddedNostrRelay relay;
  
  const StreamExample({super.key, required this.relay});
  
  @override
  Widget build(BuildContext context) {
    return StreamProvider<NostrEvent?>(
      initialData: null,
      create: (_) => relay.eventStream,
      child: Consumer<NostrEvent?>(
        builder: (context, event, child) {
          if (event == null) {
            return const Text('Waiting for events...');
          }
          return Text('Latest event: ${event.content}');
        },
      ),
    );
  }
}

// For Riverpod (if you were using it), you would do:
/*
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Create a provider for the relay
final relayProvider = Provider<EmbeddedNostrRelay>((ref) {
  final relay = EmbeddedNostrRelay();
  relay.initialize();
  return relay;
});

// Create a stream provider for events
final eventStreamProvider = StreamProvider<NostrEvent>((ref) {
  final relay = ref.watch(relayProvider);
  return relay.eventStream;
});

// Use in a widget
class RiverpodExample extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider);
    
    return eventAsync.when(
      data: (event) => Text('Event: ${event.content}'),
      loading: () => CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
*/

// You can also create filtered streams
Stream<NostrEvent> getFilteredEventStream(EmbeddedNostrRelay relay, List<int> kinds) {
  return relay.eventStream.where((event) => kinds.contains(event.kind));
}

// Example: Stream of only kind 32222 events
Stream<NostrEvent> getAddressableVideoEvents(EmbeddedNostrRelay relay) {
  return relay.eventStream.where((event) => event.kind == 32222);
}