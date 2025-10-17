// ABOUTME: Main entry point for the Nostr Social example app
// ABOUTME: Sets up providers, theme, and navigation with embedded relay integration

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'src/providers/relay_provider.dart';
import 'src/providers/user_provider.dart';
import 'src/providers/timeline_provider.dart';
import 'src/providers/messaging_provider.dart';
import 'src/screens/onboarding/welcome_screen.dart';
import 'src/screens/timeline/home_screen.dart';
import 'src/services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('Stack trace: ${record.stackTrace}');
    }
  });

  runApp(const NostrSocialApp());
}

class NostrSocialApp extends StatelessWidget {
  const NostrSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RelayProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProxyProvider<UserProvider, TimelineProvider>(
          create: (context) => TimelineProvider(),
          update: (context, userProvider, previous) {
            return previous ?? TimelineProvider()
              ..setUserProvider(userProvider);
          },
        ),
        ChangeNotifierProxyProvider2<UserProvider, RelayProvider, MessagingProvider>(
          create: (context) => MessagingProvider(),
          update: (context, userProvider, relayProvider, previous) {
            return previous ?? MessagingProvider()
              ..setProviders(userProvider, relayProvider);
          },
        ),
      ],
      child: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              return MaterialApp(
                title: 'Nostr Social',
                debugShowCheckedModeBanner: false,
                theme: ThemeService.getTheme(
                  brightness: Brightness.light,
                  dynamicColorScheme: lightDynamic,
                ),
                darkTheme: ThemeService.getTheme(
                  brightness: Brightness.dark,
                  dynamicColorScheme: darkDynamic,
                ),
                themeMode: ThemeMode.system,
                home: userProvider.isSignedIn 
                    ? const HomeScreen() 
                    : const WelcomeScreen(),
              );
            },
          );
        },
      ),
    );
  }
}