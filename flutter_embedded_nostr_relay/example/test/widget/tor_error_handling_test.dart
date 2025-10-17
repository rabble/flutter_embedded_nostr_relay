// ABOUTME: TDD tests for Tor error handling scenarios and failure modes
// ABOUTME: Tests network failures, library errors, invalid configurations, and user error states

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

import '../../lib/src/providers/relay_provider.dart';
import '../../lib/src/widgets/tor_settings_widget.dart';
import '../../lib/src/constants/tor_strings.dart';

// Test-specific RelayProvider that can simulate errors
class TestErrorRelayProvider extends RelayProvider {
  Exception? _nextError;
  bool _torAvailableOverride = true;
  bool _torForRelaysOverride = false;
  bool _torForVideosOverride = false;

  void setNextError(Exception error) {
    _nextError = error;
  }

  void clearError() {
    _nextError = null;
  }

  void setTorAvailable(bool available) {
    _torAvailableOverride = available;
    notifyListeners();
  }

  void setTorForRelaysValue(bool value) {
    _torForRelaysOverride = value;
    notifyListeners();
  }

  void setTorForVideosValue(bool value) {
    _torForVideosOverride = value;
    notifyListeners();
  }

  @override
  bool get torAvailable => _torAvailableOverride;

  @override
  bool get torForRelays => _torForRelaysOverride;

  @override
  bool get torForVideos => _torForVideosOverride;

  @override
  Future<void> setTorForRelays(bool enabled) async {
    if (_nextError != null) {
      final error = _nextError!;
      _nextError = null; // Clear error after throwing
      throw error;
    }
    _torForRelaysOverride = enabled;
    notifyListeners();
  }

  @override
  Future<void> setTorForVideos(bool enabled) async {
    if (_nextError != null) {
      final error = _nextError!;
      _nextError = null; // Clear error after throwing
      throw error;
    }
    _torForVideosOverride = enabled;
    notifyListeners();
  }
}

void main() {
  group('Tor Error Handling TDD Tests', () {
    late TestErrorRelayProvider testRelayProvider;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      testRelayProvider = TestErrorRelayProvider();
      
      // Default state - Tor is available and settings are false
      testRelayProvider.setTorAvailable(true);
      testRelayProvider.setTorForRelaysValue(false);
      testRelayProvider.setTorForVideosValue(false);
    });

    Widget createTestWidget() {
      return MaterialApp(
        home: ChangeNotifierProvider<RelayProvider>.value(
          value: testRelayProvider,
          child: const Scaffold(
            body: TorSettingsWidget(),
          ),
        ),
      );
    }

    group('TDD: SharedPreferences Failure Tests', () {
      testWidgets('FAIL: should handle SharedPreferences save failure gracefully', (tester) async {
        // Arrange: Set up error to be thrown
        testRelayProvider.setNextError(Exception('SharedPreferences save failed'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        expect(relaySwitch, findsOneWidget);
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show error snackbar
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget,
            reason: 'Should show error message when SharedPreferences fails');
        expect(find.textContaining('SharedPreferences save failed'), findsOneWidget,
            reason: 'Should show specific error details');
      });

      testWidgets('FAIL: should handle SharedPreferences save failure for videos', (tester) async {
        // Arrange: Mock setTorForVideos to throw a SharedPreferences error
        testRelayProvider.setNextError(Exception('SharedPreferences save failed'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the video Tor switch
        final videoSwitch = find.byKey(const Key('tor_video_switch'));
        expect(videoSwitch, findsOneWidget);
        await tester.tap(videoSwitch);
        await tester.pumpAndSettle();

        // Assert: Should show error snackbar
        expect(find.textContaining('Failed to toggle Tor for videos'), findsOneWidget,
            reason: 'Should show error message when SharedPreferences fails');
      });
    });

    group('TDD: Tor Library Failure Tests', () {
      testWidgets('FAIL: should handle Tor library connection failure', (tester) async {
        // Arrange: Mock setTorForRelays to throw a Tor library error
        testRelayProvider.setNextError(Exception('Tor library connection failed'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show specific error message for library failures
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Tor library connection failed'), findsOneWidget);
      });

      testWidgets('FAIL: should show helpful message when Tor unavailable', (tester) async {
        // Arrange: Mock Tor as unavailable
        testRelayProvider.setTorAvailable(false);
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert: Should show unavailable message and instructions
        expect(find.text(TorStrings.unavailableMessage), findsOneWidget,
            reason: 'Should show unavailable message when Tor not available');
        expect(find.textContaining('build_with_tor.sh'), findsOneWidget,
            reason: 'Should show build instructions');
        
        // Should not show switches when unavailable
        expect(find.byKey(const Key('tor_relay_switch')), findsNothing,
            reason: 'Should hide switches when Tor unavailable');
        expect(find.byKey(const Key('tor_video_switch')), findsNothing,
            reason: 'Should hide video switch when Tor unavailable');
      });
    });

    group('TDD: Network Connectivity Failure Tests', () {
      testWidgets('FAIL: should handle network timeout gracefully', (tester) async {
        // Arrange: Mock setTorForRelays to throw a timeout error
        testRelayProvider.setNextError(Exception('Network timeout'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show network error message
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Network timeout'), findsOneWidget);
      });

      testWidgets('FAIL: should handle relay connection failure', (tester) async {
        // Arrange: Mock setTorForRelays to throw a relay connection error
        testRelayProvider.setNextError(Exception('Failed to connect to relay through Tor'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show relay connection error
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Failed to connect to relay through Tor'), findsOneWidget);
      });
    });

    group('TDD: Configuration Error Tests', () {
      testWidgets('FAIL: should handle invalid Tor configuration', (tester) async {
        // Arrange: Mock setTorForRelays to throw a configuration error
        testRelayProvider.setNextError(Exception('Invalid Tor configuration'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show configuration error
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Invalid Tor configuration'), findsOneWidget);
      });

      testWidgets('FAIL: should handle bridge configuration failure', (tester) async {
        // Arrange: Mock setTorForRelays to throw a bridge error
        testRelayProvider.setNextError(Exception('Bridge configuration failed'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show bridge error
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Bridge configuration failed'), findsOneWidget);
      });
    });

    group('TDD: User Experience Error Tests', () {
      testWidgets('FAIL: should maintain UI state when operations fail', (tester) async {
        // Arrange: Set initial state and error
        testRelayProvider.setTorForRelaysValue(false);
        testRelayProvider.setTorForVideosValue(false);
        testRelayProvider.setNextError(Exception('Operation failed'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        final switchWidget = tester.widget<Switch>(relaySwitch);
        expect(switchWidget.value, false, reason: 'Initially should be false');
        
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Switch should remain in original state after failure
        final switchWidgetAfter = tester.widget<Switch>(relaySwitch);
        expect(switchWidgetAfter.value, false,
            reason: 'Switch should remain false when operation fails');
        
        // And error message should be shown
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
      });

      testWidgets('FAIL: should provide recovery suggestions in error messages', (tester) async {
        // Arrange: Mock to throw a specific error with suggestion
        testRelayProvider.setNextError(Exception('Tor bootstrap failed. Check your network connection.'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Tap the relay Tor switch
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should show helpful error message with suggestion
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Check your network connection'), findsOneWidget,
            reason: 'Should provide recovery suggestions');
      });

      testWidgets('FAIL: should handle rapid switch toggling gracefully', (tester) async {
        // Arrange: Mock to delay and potentially fail on rapid calls
        // For this test, we'll just set the error normally
        testRelayProvider.setNextError(Exception('Rate limited'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: Rapidly tap the switch multiple times
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.tap(relaySwitch);
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Should handle gracefully without crashing
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Rate limited'), findsOneWidget);
      });
    });

    group('TDD: Error Recovery Tests', () {
      testWidgets('FAIL: should allow retry after error', (tester) async {
        // Arrange: Set up to fail first, then succeed on retry
        testRelayProvider.setNextError(Exception('Temporary failure'));
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Act: First tap fails
        final relaySwitch = find.byKey(const Key('tor_relay_switch'));
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Error shown
        expect(find.textContaining('Failed to toggle Tor for relays'), findsOneWidget);
        expect(find.textContaining('Temporary failure'), findsOneWidget);

        // Act: Wait for snackbar to auto-dismiss, then try again  
        await tester.pumpAndSettle(const Duration(seconds: 5)); // Wait for snackbar to dismiss
        
        // No error set for second attempt, so it should succeed
        await tester.tap(relaySwitch);
        await tester.pumpAndSettle();

        // Assert: Second attempt should succeed (relay provider state should change)
        expect(testRelayProvider.torForRelays, true,
            reason: 'Should allow retry after initial failure and succeed');
      });
    });
  });
}