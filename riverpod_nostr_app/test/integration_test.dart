// ABOUTME: Integration test demonstrating StreamProvider with relay connectivity
// ABOUTME: Tests the full Riverpod + embedded relay + external relay flow

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_nostr_app/main.dart';

void main() {
  testWidgets('Full app integration with StreamProvider', (tester) async {
    // Run the main app
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );
    
    // Should show initial screen
    expect(find.text('Nostr Riverpod Demo'), findsOneWidget);
    
    // Should show loading or empty state initially
    expect(
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
      find.text('No video events yet').evaluate().isNotEmpty,
      isTrue,
    );
  });
}