// ABOUTME: Settings screen for app configuration and user preferences
// ABOUTME: Provides options for theme, notifications, privacy, and data management

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/relay_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer2<UserProvider, RelayProvider>(
        builder: (context, userProvider, relayProvider, child) {
          return ListView(
            children: [
              // Account section
              _buildSectionHeader('Account'),
              
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                subtitle: Text(userProvider.profile?.name ?? 'Anonymous'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Navigate to profile edit
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile editing available from Profile tab')),
                  );
                },
              ),
              
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Export Private Key'),
                subtitle: const Text('Backup your private key'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showExportKeyDialog(),
              ),
              
              const Divider(),
              
              // Relay section
              _buildSectionHeader('Relay'),
              
              SwitchListTile(
                secondary: const Icon(Icons.device_hub),
                title: const Text('P2P Synchronization'),
                subtitle: Text(
                  relayProvider.p2pEnabled
                      ? 'Sync with nearby devices'
                      : 'Enable offline sync via Bluetooth/WiFi',
                ),
                value: relayProvider.p2pEnabled,
                onChanged: relayProvider.isInitialized ? _toggleP2P : null,
              ),
              
              ListTile(
                leading: const Icon(Icons.cloud),
                title: const Text('External Relays'),
                subtitle: Text('${relayProvider.externalRelays.length} configured'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Navigate to relay management
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Relay management available from Relay tab')),
                  );
                },
              ),
              
              const Divider(),
              
              // Appearance section
              _buildSectionHeader('Appearance'),
              
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Theme'),
                subtitle: const Text('System default'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showThemeDialog(),
              ),
              
              const Divider(),
              
              // Privacy section
              _buildSectionHeader('Privacy & Security'),
              
              SwitchListTile(
                secondary: const Icon(Icons.analytics),
                title: const Text('Analytics'),
                subtitle: const Text('Help improve the app with usage data'),
                value: false, // TODO: Implement analytics setting
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Analytics setting not yet implemented')),
                  );
                },
              ),
              
              SwitchListTile(
                secondary: const Icon(Icons.bug_report),
                title: const Text('Crash Reports'),
                subtitle: const Text('Automatically send crash reports'),
                value: false, // TODO: Implement crash reporting setting
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Crash reporting setting not yet implemented')),
                  );
                },
              ),
              
              const Divider(),
              
              // Data section
              _buildSectionHeader('Data'),
              
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Clear Cache'),
                subtitle: const Text('Free up storage space'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showClearCacheDialog(),
              ),
              
              ListTile(
                leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
                title: Text('Clear All Data', style: TextStyle(color: theme.colorScheme.error)),
                subtitle: const Text('Delete all local events and profiles'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showClearDataDialog(),
              ),
              
              const Divider(),
              
              // About section
              _buildSectionHeader('About'),
              
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Version'),
                subtitle: const Text('1.0.0+1'),
                onTap: () => _showAboutDialog(),
              ),
              
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Licenses'),
                subtitle: const Text('Open source licenses'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showLicensesDialog(),
              ),
              
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help & Support'),
                subtitle: const Text('Get help using the app'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showHelpDialog(),
              ),
              
              const SizedBox(height: 32),
              
              // Sign out button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: OutlinedButton.icon(
                  onPressed: () => _showSignOutDialog(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showExportKeyDialog() {
    final userProvider = context.read<UserProvider>();
    final privateKey = userProvider.privateKey ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Private Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WARNING: Never share your private key with anyone. Store it securely.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Your private key:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                privateKey,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: privateKey));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Private key copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _toggleP2P(bool enabled) async {
    final relayProvider = context.read<RelayProvider>();
    
    try {
      if (enabled) {
        await relayProvider.enableP2PSync();
      } else {
        await relayProvider.disableP2PSync();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${enabled ? 'enable' : 'disable'} P2P sync: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showThemeDialog() {    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('System default'),
              value: 'system',
              groupValue: 'system', // TODO: Get from settings
              onChanged: (value) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Theme setting not yet implemented')),
                );
              },
            ),
            RadioListTile<String>(
              title: const Text('Light'),
              value: 'light',
              groupValue: 'system',
              onChanged: (value) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Theme setting not yet implemented')),
                );
              },
            ),
            RadioListTile<String>(
              title: const Text('Dark'),
              value: 'dark',
              groupValue: 'system',
              onChanged: (value) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Theme setting not yet implemented')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('This will clear cached images and temporary data. Your posts and profile will not be affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache clearing not yet implemented')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text('This will permanently delete all local events, profiles, and cached data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Data clearing not yet implemented')),
              );
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Nostr Social',
      applicationVersion: '1.0.0+1',
      applicationIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.hub_outlined,
          size: 32,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      children: [
        const Text('A comprehensive Flutter example app showcasing the embedded Nostr relay library.'),
        const SizedBox(height: 16),
        const Text('Features:'),
        const Text('• Embedded Nostr relay'),
        const Text('• P2P synchronization'),
        const Text('• Timeline and messaging'),
        const Text('• Material Design 3'),
      ],
    );
  }

  void _showLicensesDialog() {
    showLicensePage(context: context);
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Getting Started:'),
            Text('• Create or import your Nostr identity'),
            Text('• Follow users to see their posts'),
            Text('• Enable P2P sync for offline usage'),
            Text(''),
            Text('Need help?'),
            Text('• Check the documentation'),
            Text('• Report issues on GitHub'),
            Text('• Join the community discussions'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out? Your private key will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Close settings screen
              await context.read<UserProvider>().signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}