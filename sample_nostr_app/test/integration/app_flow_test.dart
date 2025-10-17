// ABOUTME: Integration tests for complete app flows using embedded relay
// ABOUTME: Tests user journey from onboarding to posting and viewing timeline

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sample_nostr_app/main.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('App Flow Integration Tests', () {
    testWidgets('complete user journey from onboarding to posting', (tester) async {
      // Start the app
      await tester.pumpWidget(NostrSampleApp());
      await tester.pumpAndSettle();
      
      // Verify onboarding screen
      expect(find.text('Welcome to Nostr'), findsOneWidget);
      
      // Generate new identity
      await tester.tap(find.text('Generate New Identity'));
      await tester.pumpAndSettle();
      
      // Should now see the timeline
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      
      // Create a post
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      
      // Enter post content
      await tester.enterText(find.byType(TextField), 'My first Nostr post!');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      
      // Wait for post to appear
      await tester.pump(Duration(milliseconds: 300));
      
      // Verify post appears in timeline
      expect(find.text('My first Nostr post!'), findsOneWidget);
      
      // Navigate to profile
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Public Key'), findsOneWidget);
      
      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Relay Status'), findsOneWidget);
    });
    
    testWidgets('import existing identity flow', (tester) async {
      await tester.pumpWidget(NostrSampleApp());
      await tester.pumpAndSettle();
      
      // Choose import option
      await tester.tap(find.text('Import Existing'));
      await tester.pumpAndSettle();
      
      // Enter private key
      final testPrivateKey = '0' * 64;
      await tester.enterText(find.byType(TextField), testPrivateKey);
      
      // Import
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      
      // Should be on timeline now
      expect(find.text('Timeline'), findsOneWidget);
    });
    
    testWidgets('profile update flow', (tester) async {
      await tester.pumpWidget(NostrSampleApp());
      await tester.pumpAndSettle();
      
      // Quick setup
      await tester.tap(find.text('Generate New Identity'));
      await tester.pumpAndSettle();
      
      // Go to profile
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      
      // Edit profile
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      
      // Update name
      await tester.enterText(
        find.widgetWithText(TextField, 'Display Name'),
        'Test User',
      );
      
      // Update bio
      await tester.enterText(
        find.widgetWithText(TextField, 'About'),
        'Testing the app',
      );
      
      // Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      
      // Verify updates
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('Testing the app'), findsOneWidget);
    });
    
    testWidgets('relay statistics monitoring', (tester) async {
      await tester.pumpWidget(NostrSampleApp());
      await tester.pumpAndSettle();
      
      // Quick setup
      await tester.tap(find.text('Generate New Identity'));
      await tester.pumpAndSettle();
      
      // Create some events
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Post $i');
        await tester.tap(find.text('Post'));
        await tester.pumpAndSettle();
      }
      
      // Go to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      
      // Check relay stats
      await tester.tap(find.text('Relay Status'));
      await tester.pumpAndSettle();
      
      expect(find.textContaining('Events:'), findsOneWidget);
      expect(find.textContaining('Subscriptions:'), findsOneWidget);
      expect(find.text('Embedded Relay'), findsOneWidget);
    });
  });
}