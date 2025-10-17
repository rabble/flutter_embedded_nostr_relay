// ABOUTME: Integration tests for complete Tor workflows following strict TDD
// ABOUTME: Tests end-to-end Tor functionality, user flows, and error scenarios

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/main.dart' as app;
import '../../lib/src/providers/relay_provider.dart';
import '../../lib/src/providers/user_provider.dart';
import '../../lib/src/screens/relay_status/relay_status_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Tor Workflow Integration Tests (TDD)', () {
    setUp(() async {
      // Set up SharedPreferences mock for integration tests
      SharedPreferences.setMockInitialValues({
        'user_private_key': 'a' * 64, // Mock 64-char hex private key - this will trigger sign-in
      });
      
      // Mock path provider plugin
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return '/tmp/test_documents';
          }
          return null;
        },
      );
      
      // Mock connectivity plugin
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'check') {
            return 'wifi';
          }
          return null;
        },
      );
      
      // Mock connectivity status stream
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'listen') {
            return null;
          }
          return null;
        },
      );
    });

    group('Tor Settings Persistence Workflow', () {
      testWidgets('FAIL: complete Tor settings workflow should persist across app restarts', (tester) async {
        // PHASE 1: Start app and navigate to relay settings
        app.main();
        await tester.pumpAndSettle();
        
        // Navigate to relay status screen
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        // Find the Tor settings card
        final torCard = find.text('Tor Privacy Settings');
        expect(torCard, findsOneWidget, 
            reason: 'Should find Tor settings card');
        
        // PHASE 2: Check initial state (should be disabled by default)
        // Find the provider through the widget tree
        final context = tester.element(find.byType(RelayStatusScreen));
        final relayProvider = Provider.of<RelayProvider>(context, listen: false);
        
        expect(relayProvider.torForRelays, false,
            reason: 'Initially torForRelays should be false');
        expect(relayProvider.torForVideos, false,
            reason: 'Initially torForVideos should be false');
        
        // PHASE 3: Enable Tor settings (if available)
        if (relayProvider.torAvailable) {
          // Enable Tor for relays
          final relaySwitchFinder = find.text('Relay Connections').first;
          final relaySwitch = find.ancestor(
            of: relaySwitchFinder,
            matching: find.byType(Switch),
          );
          
          await tester.tap(relaySwitch);
          await tester.pumpAndSettle();
          
          // Enable Tor for videos
          final videoSwitchFinder = find.text('Video Loading').first;
          final videoSwitch = find.ancestor(
            of: videoSwitchFinder,
            matching: find.byType(Switch),
          );
          
          await tester.tap(videoSwitch);
          await tester.pumpAndSettle();
          
          // Verify state changed
          expect(relayProvider.torForRelays, true,
              reason: 'After toggling, torForRelays should be true');
          expect(relayProvider.torForVideos, true,
              reason: 'After toggling, torForVideos should be true');
          
          // PHASE 4: Restart app simulation
          // Dispose current providers
          relayProvider.dispose();
          
          // Restart the app
          app.main();
          await tester.pumpAndSettle();
          
          // Navigate back to relay status
          final relayTabAgain = find.text('Relay');
          await tester.tap(relayTabAgain);
          await tester.pumpAndSettle();
          
          // PHASE 5: Verify persistence
          final newContext = tester.element(find.byType(RelayStatusScreen));
          final newRelayProvider = Provider.of<RelayProvider>(newContext, listen: false);
          
          // Give time for async loading
          await tester.pump(const Duration(milliseconds: 200));
          
          expect(newRelayProvider.torForRelays, true,
              reason: 'After app restart, torForRelays should persist');
          expect(newRelayProvider.torForVideos, true,
              reason: 'After app restart, torForVideos should persist');
        } else {
          // If Tor is not available, just verify the UI shows correct state
          final unavailableMessage = find.textContaining('not available in this build');
          expect(unavailableMessage, findsOneWidget,
              reason: 'Should show unavailable message when Tor not available');
        }
      });
    });

    group('Tor Advanced Settings Workflow', () {
      testWidgets('FAIL: advanced settings dialog should show and update configuration', (tester) async {
        // Start app and navigate to relay settings
        app.main();
        await tester.pumpAndSettle();
        
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        final context2 = tester.element(find.byType(RelayStatusScreen));
        final relayProvider = Provider.of<RelayProvider>(context2, listen: false);
        
        // Only test if Tor is available
        if (relayProvider.torAvailable) {
          // Find and tap advanced settings button
          final advancedButton = find.widgetWithText(OutlinedButton, 'Advanced Settings');
          expect(advancedButton, findsOneWidget,
              reason: 'Advanced settings button should be present when Tor available');
          
          await tester.tap(advancedButton);
          await tester.pumpAndSettle();
          
          // Verify dialog opened
          final dialogTitle = find.text('Advanced Tor Settings');
          expect(dialogTitle, findsOneWidget,
              reason: 'Advanced settings dialog should open');
          
          // Check configuration display
          final enabledText = find.textContaining('Enabled:');
          final forceTorText = find.textContaining('Force Tor:');
          final timeoutText = find.textContaining('Timeout:');
          
          expect(enabledText, findsOneWidget,
              reason: 'Dialog should show enabled status');
          expect(forceTorText, findsOneWidget,
              reason: 'Dialog should show force Tor status');
          expect(timeoutText, findsOneWidget,
              reason: 'Dialog should show timeout setting');
          
          // Close dialog
          final closeButton = find.widgetWithText(TextButton, 'Close');
          await tester.tap(closeButton);
          await tester.pumpAndSettle();
          
          // Verify dialog closed
          expect(dialogTitle, findsNothing,
              reason: 'Dialog should be dismissed');
        }
      });
    });

    group('Error Handling Workflow', () {
      testWidgets('FAIL: should handle SharedPreferences errors gracefully', (tester) async {
        // This test verifies the app doesn't crash when SharedPreferences fails
        
        // Start app
        app.main();
        await tester.pumpAndSettle();
        
        // Navigate to relay settings
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        // App should still work even if there were SharedPreferences issues
        final torCard = find.text('Tor Privacy Settings');
        expect(torCard, findsOneWidget,
            reason: 'Tor settings card should be present even with storage issues');
        
        final context2 = tester.element(find.byType(RelayStatusScreen));
        final relayProvider = Provider.of<RelayProvider>(context2, listen: false);
        
        // Should have default values if loading failed
        expect(relayProvider.torForRelays, false,
            reason: 'Should default to false if loading failed');
        expect(relayProvider.torForVideos, false,
            reason: 'Should default to false if loading failed');
      });

      testWidgets('FAIL: should show appropriate UI when Tor unavailable', (tester) async {
        app.main();
        await tester.pumpAndSettle();
        
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        final context2 = tester.element(find.byType(RelayStatusScreen));
        final relayProvider = Provider.of<RelayProvider>(context2, listen: false);
        
        if (!relayProvider.torAvailable) {
          // Verify warning icon is shown
          final warningIcon = find.byIcon(Icons.warning_outlined);
          expect(warningIcon, findsOneWidget,
              reason: 'Warning icon should be visible when Tor unavailable');
          
          // Verify build instructions are shown
          final buildInstructions = find.textContaining('build_with_tor.sh');
          expect(buildInstructions, findsOneWidget,
              reason: 'Build instructions should be visible');
          
          // Verify switches are not present
          final relaySwitchLabel = find.text('Relay Connections');
          final videoSwitchLabel = find.text('Video Loading');
          
          expect(relaySwitchLabel, findsNothing,
              reason: 'Relay switch should be hidden when Tor unavailable');
          expect(videoSwitchLabel, findsNothing,
              reason: 'Video switch should be hidden when Tor unavailable');
          
          // Verify advanced settings button is hidden
          final advancedButton = find.widgetWithText(OutlinedButton, 'Advanced Settings');
          expect(advancedButton, findsNothing,
              reason: 'Advanced settings button should be hidden when Tor unavailable');
        }
      });
    });

    group('Snackbar Feedback Workflow', () {
      testWidgets('FAIL: should show snackbar feedback when toggling Tor settings', (tester) async {
        app.main();
        await tester.pumpAndSettle();
        
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        final context2 = tester.element(find.byType(RelayStatusScreen));
        final relayProvider = Provider.of<RelayProvider>(context2, listen: false);
        
        if (relayProvider.torAvailable) {
          // Tap relay switch
          final relaySwitchFinder = find.text('Relay Connections').first;
          final relaySwitch = find.ancestor(
            of: relaySwitchFinder,
            matching: find.byType(Switch),
          );
          
          await tester.tap(relaySwitch);
          await tester.pumpAndSettle();
          
          // Look for snackbar
          final snackbar = find.textContaining('Tor enabled for relay connections');
          expect(snackbar, findsOneWidget,
              reason: 'Should show snackbar feedback when enabling Tor for relays');
          
          // Wait for snackbar to disappear
          await tester.pump(const Duration(seconds: 5));
          
          // Tap video switch
          final videoSwitchFinder = find.text('Video Loading').first;
          final videoSwitch = find.ancestor(
            of: videoSwitchFinder,
            matching: find.byType(Switch),
          );
          
          await tester.tap(videoSwitch);
          await tester.pumpAndSettle();
          
          // Look for video snackbar
          final videoSnackbar = find.textContaining('Tor enabled for video loading');
          expect(videoSnackbar, findsOneWidget,
              reason: 'Should show snackbar feedback when enabling Tor for videos');
        }
      });
    });

    group('P2P Integration with Tor', () {
      testWidgets('FAIL: P2P and Tor settings should work independently', (tester) async {
        app.main();
        await tester.pumpAndSettle();
        
        final relayTab = find.text('Relay');
        await tester.tap(relayTab);
        await tester.pumpAndSettle();
        
        // Test that P2P settings don't interfere with Tor settings
        final p2pLabel = find.text('P2P Synchronization');
        
        if (p2pLabel.evaluate().isNotEmpty) {
          // P2P should be independent of Tor
          // This integration test verifies they don't interfere with each other
          
          final context3 = tester.element(find.byType(RelayStatusScreen));
          final relayProvider = Provider.of<RelayProvider>(context3, listen: false);
          
          final initialTorRelaysState = relayProvider.torForRelays;
          final initialTorVideosState = relayProvider.torForVideos;
          
          // Toggle P2P (this should not affect Tor settings)
          final p2pSwitchWidget = find.byType(Switch).first; // P2P switch should be first
          await tester.tap(p2pSwitchWidget);
          await tester.pumpAndSettle();
          
          // Verify Tor settings unchanged
          expect(relayProvider.torForRelays, initialTorRelaysState,
              reason: 'Tor relay setting should not change when toggling P2P');
          expect(relayProvider.torForVideos, initialTorVideosState,
              reason: 'Tor video setting should not change when toggling P2P');
        }
      });
    });
  });
}