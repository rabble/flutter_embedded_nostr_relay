// ABOUTME: Unit tests for FunctionChannelRelay - direct function interface
// ABOUTME: Tests session creation, message processing, and event delivery

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([SubscriptionManager, EventStore, EmbeddedNostrRelay])
import 'function_channel_relay_test.mocks.dart';

void main() {
  group('FunctionChannelRelay', () {
    late FunctionChannelRelay relay;
    late MockSubscriptionManager mockSubscriptionManager;
    late MockEventStore mockEventStore;
    late MockEmbeddedNostrRelay mockEmbeddedRelay;

    setUp(() {
      mockSubscriptionManager = MockSubscriptionManager();
      mockEventStore = MockEventStore();
      mockEmbeddedRelay = MockEmbeddedNostrRelay();

      relay = FunctionChannelRelay(
        subscriptionManager: mockSubscriptionManager,
        eventStore: mockEventStore,
        embeddedRelay: mockEmbeddedRelay,
      );
    });

    group('Session Management', () {
      test('should create a new session with unique ID', () {
        final session1 = relay.createSession();
        final session2 = relay.createSession();

        expect(session1, isNotNull);
        expect(session2, isNotNull);
        expect(session1.sessionId, isNot(equals(session2.sessionId)));
      });

      test('should close session and cleanup resources', () async {
        final session = relay.createSession();
        final sessionId = session.sessionId;

        await relay.closeSession(sessionId);

        // Trying to send message to closed session should be ignored
        await relay.processMessage(sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        verifyNever(mockSubscriptionManager.handleReq(any, any));
      });

      test('should provide response stream for events', () async {
        final session = relay.createSession();
        final events = <RelayResponse>[];

        session.responseStream.listen(events.add);

        // Simulate event delivery through a REQ/response cycle
        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => [NostrEvent.create(
          pubkey: 'test_pubkey',
          kind: 1,
          content: 'test content',
          tags: [],
        )]);

        await relay.processMessage(session.sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        await Future.delayed(Duration(milliseconds: 10));

        // Should have received event and EOSE
        expect(events.length, 2);
        expect(events.first, isA<EventResponse>());
        expect((events.first as EventResponse).subscriptionId, 'sub1');
      });
    });

    group('REQ Message Processing', () {
      test('should handle REQ message and create subscription', () async {
        final session = relay.createSession();
        final filter = Filter(kinds: [1], limit: 10);
        final req = ReqMessage(
          subscriptionId: 'test_sub',
          filters: [filter],
        );

        // Mock handleReq to return a subscription
        final mockSubscription = Subscription(
          id: 'test_sub',
          filters: [filter],
        );
        when(mockSubscriptionManager.handleReq(any, any))
            .thenAnswer((_) async => mockSubscription);

        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => []);

        await relay.processMessage(session.sessionId, req);

        verify(mockSubscriptionManager.handleReq(
          session.sessionId,
          argThat(isA<ReqMessage>()
              .having((r) => r.subscriptionId, 'subscriptionId', 'test_sub')),
        )).called(1);
      });

      test('should query existing events for new subscription', () async {
        final session = relay.createSession();
        final existingEvent = NostrEvent.create(
          pubkey: 'author1',
          kind: 1,
          content: 'existing event',
          tags: [],
        );

        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => [existingEvent]);

        final events = <RelayResponse>[];
        session.responseStream.listen(events.add);

        await relay.processMessage(session.sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        await Future.delayed(Duration(milliseconds: 10));

        // Should receive the existing event and EOSE
        expect(events.where((e) => e is EventResponse).length, 1);
        expect(events.where((e) => e is EoseResponse).length, 1);
      });

      test('should send EOSE after delivering stored events', () async {
        final session = relay.createSession();
        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => []);

        final responses = <RelayResponse>[];
        session.responseStream.listen(responses.add);

        await relay.processMessage(session.sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        await Future.delayed(Duration(milliseconds: 10));

        expect(responses.any((r) => r is EoseResponse), isTrue);
      });
    });

    group('CLOSE Message Processing', () {
      test('should handle CLOSE message and remove subscription', () async {
        final session = relay.createSession();

        // First create a subscription
        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => []);

        await relay.processMessage(session.sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        // Then close it
        await relay.processMessage(session.sessionId, CloseMessage(
          subscriptionId: 'sub1',
        ));

        verify(mockSubscriptionManager.handleClose(
          session.sessionId,
          argThat(isA<CloseMessage>()
              .having((c) => c.subscriptionId, 'subscriptionId', 'sub1')),
        )).called(1);
      });
    });

    group('EVENT Message Processing', () {
      test('should validate and store valid events', () async {
        final session = relay.createSession();
        final event = NostrEvent.create(
          pubkey: 'author1',
          kind: 1,
          content: 'test event',
          tags: [],
        ).sign('private_key'); // In real code, use proper signing

        when(mockEventStore.storeEvent(any))
            .thenAnswer((_) async => true);

        final responses = <RelayResponse>[];
        session.responseStream.listen(responses.add);

        await relay.processMessage(session.sessionId, ClientEventMessage(
          event: event,
        ));

        await Future.delayed(Duration(milliseconds: 10));

        verify(mockEventStore.storeEvent(event)).called(1);
        verify(mockSubscriptionManager.routeEvent(event)).called(1);

        final okResponse = responses.firstWhere((r) => r is OkResponse) as OkResponse;
        expect(okResponse.success, isTrue);
        expect(okResponse.eventId, event.id);
      });

      test('should reject invalid events', () async {
        final session = relay.createSession();

        // Create event with invalid signature
        final event = NostrEvent.create(
          pubkey: 'author1',
          kind: 1,
          content: 'test event',
          tags: [],
        );
        // Don't sign it, so verification will fail

        final responses = <RelayResponse>[];
        session.responseStream.listen(responses.add);

        await relay.processMessage(session.sessionId, ClientEventMessage(
          event: event,
        ));

        await Future.delayed(Duration(milliseconds: 10));

        verifyNever(mockEventStore.storeEvent(any));
        verifyNever(mockSubscriptionManager.routeEvent(any));

        final okResponse = responses.firstWhere((r) => r is OkResponse) as OkResponse;
        expect(okResponse.success, isFalse);
        expect(okResponse.message, contains('signature verification failed'));
      });
    });

    group('Error Handling', () {
      test('should handle errors gracefully and send NOTICE', () async {
        final session = relay.createSession();

        when(mockEventStore.queryEvents(any))
            .thenThrow(Exception('Database error'));

        final responses = <RelayResponse>[];
        session.responseStream.listen(responses.add);

        await relay.processMessage(session.sessionId, ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        await Future.delayed(Duration(milliseconds: 10));

        final notice = responses.firstWhere((r) => r is NoticeResponse) as NoticeResponse;
        expect(notice.message, contains('Error processing subscription'));
      });

      test('should ignore messages from unknown sessions', () async {
        await relay.processMessage('unknown_session', ReqMessage(
          subscriptionId: 'sub1',
          filters: [Filter(kinds: [1])],
        ));

        verifyNever(mockSubscriptionManager.handleReq(any, any));
        verifyNever(mockEventStore.queryEvents(any));
      });
    });

    group('Performance', () {
      test('should handle high-throughput event processing', () async {
        final session = relay.createSession();
        final eventCount = 100; // Reduced for practicality
        final receivedOkResponses = <OkResponse>[];

        session.responseStream
            .where((r) => r is OkResponse)
            .cast<OkResponse>()
            .listen(receivedOkResponses.add);

        when(mockEventStore.storeEvent(any))
            .thenAnswer((_) async => true);

        final stopwatch = Stopwatch()..start();

        final futures = <Future>[];
        for (int i = 0; i < eventCount; i++) {
          final event = NostrEvent.create(
            pubkey: 'author$i',
            kind: 1,
            content: 'Event $i',
            tags: [],
          ).sign('test_key'); // Mock signing

          futures.add(relay.processMessage(session.sessionId, ClientEventMessage(
            event: event,
          )));
        }

        await Future.wait(futures);
        stopwatch.stop();

        expect(receivedOkResponses.length, eventCount);
        expect(stopwatch.elapsedMilliseconds, lessThan(1000),
            reason: 'Direct function calls should be very fast');
      });

      test('should handle concurrent subscriptions efficiently', () async {
        final session = relay.createSession();
        final subscriptionCount = 100;

        when(mockEventStore.queryEvents(any))
            .thenAnswer((_) async => []);

        final stopwatch = Stopwatch()..start();

        final futures = <Future>[];
        for (int i = 0; i < subscriptionCount; i++) {
          futures.add(relay.processMessage(session.sessionId, ReqMessage(
            subscriptionId: 'sub$i',
            filters: [Filter(kinds: [1])],
          )));
        }

        await Future.wait(futures);
        stopwatch.stop();

        verify(mockSubscriptionManager.handleReq(any, any))
            .called(subscriptionCount);
        expect(stopwatch.elapsedMilliseconds, lessThan(1000),
            reason: 'Should handle many subscriptions quickly');
      });
    });
  });
}