// ABOUTME: Main entry point for the Nostr sample app
// ABOUTME: Sets up providers and launches the app with embedded relay

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/nostr_provider.dart';
import 'providers/timeline_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runZonedGuarded(() {
    runApp(const NostrSampleApp());
  }, (error, stack) {
    // Log but don't crash on unhandled async errors
    print('Unhandled error: $error');
    print('Stack trace: $stack');
  });
}

class NostrSampleApp extends StatelessWidget {
  const NostrSampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NostrProvider(),
        ),
        ChangeNotifierProxyProvider<NostrProvider, TimelineProvider>(
          create: (context) => TimelineProvider(
            context.read<NostrProvider>(),
          ),
          update: (context, nostrProvider, previous) =>
              previous ?? TimelineProvider(nostrProvider),
        ),
      ],
      child: MaterialApp(
        title: 'Nostr Sample',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
