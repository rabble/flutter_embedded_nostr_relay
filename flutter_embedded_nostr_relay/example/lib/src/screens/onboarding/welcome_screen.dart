// ABOUTME: Welcome screen for new users to the Nostr Social app
// ABOUTME: Provides options to create new account or import existing keys

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/relay_provider.dart';
import 'key_import_screen.dart';
import 'profile_setup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isCreatingAccount = false;

  @override
  void initState() {
    super.initState();
    // Initialize relay when welcome screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeRelay();
    });
  }

  Future<void> _initializeRelay() async {
    final relayProvider = context.read<RelayProvider>();
    if (!relayProvider.isInitialized && !relayProvider.isInitializing) {
      try {
        await relayProvider.initialize();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to initialize relay: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _createNewAccount() async {
    setState(() {
      _isCreatingAccount = true;
    });

    try {
      final userProvider = context.read<UserProvider>();
      await userProvider.signInWithNewKey();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const ProfileSetupScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create account: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingAccount = false;
        });
      }
    }
  }

  void _importExistingKey() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const KeyImportScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Consumer<RelayProvider>(
          builder: (context, relayProvider, child) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(),
                  
                  // App logo/icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      size: 64,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // App title
                  Text(
                    'Nostr Social',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Subtitle
                  Text(
                    'Decentralized social networking\nwith embedded relay technology',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Relay status indicator
                  if (relayProvider.isInitializing)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Initializing embedded relay...'),
                          ],
                        ),
                      ),
                    )
                  else if (relayProvider.isInitialized)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Text('Embedded relay ready'),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // Action buttons
                  Column(
                    children: [
                      // Create new account button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: relayProvider.isInitialized && !_isCreatingAccount
                              ? _createNewAccount
                              : null,
                          icon: _isCreatingAccount
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add),
                          label: Text(_isCreatingAccount
                              ? 'Creating Account...'
                              : 'Create New Account'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Import existing key button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: relayProvider.isInitialized && !_isCreatingAccount
                              ? _importExistingKey
                              : null,
                          icon: const Icon(Icons.key),
                          label: const Text('Import Existing Key'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Info text
                  Text(
                    'Your keys are stored locally and never leave your device',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}