// ABOUTME: User profile screen showing current user's profile and posts
// ABOUTME: Allows editing profile information and viewing user statistics

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/user_provider.dart';
import '../../providers/relay_provider.dart';
import '../onboarding/profile_setup_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer2<UserProvider, RelayProvider>(
      builder: (context, userProvider, relayProvider, child) {
        final profile = userProvider.profile;
        final pubkey = userProvider.publicKey ?? '';

        return SingleChildScrollView(
          child: Column(
            children: [
              // Header with background
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.secondaryContainer,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        // Profile picture
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: colorScheme.surface,
                              backgroundImage: profile?.picture != null
                                  ? NetworkImage(profile!.picture!)
                                  : null,
                              child: profile?.picture == null
                                  ? Icon(
                                      Icons.person,
                                      size: 60,
                                      color: colorScheme.onSurface,
                                    )
                                  : null,
                            ),
                            
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: _editProfile,
                                  icon: Icon(
                                    Icons.edit,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Name
                        Text(
                          profile?.name ?? 'Anonymous',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // NIP-05 verification
                        if (profile?.nip05 != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                profile!.nip05!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        
                        // About
                        if (profile?.about != null) ...[
                          Text(
                            profile!.about!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Website link
                        if (profile?.website != null) ...[
                          InkWell(
                            onTap: () {
                              // TODO: Open website
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Opening ${profile!.website}...'),
                                ),
                              );
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.link,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  profile!.website!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              
              // Profile actions and info
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showQRCode,
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Share Profile'),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _editProfile,
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit Profile'),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Profile information cards
                    _buildInfoCard(
                      'Public Key',
                      pubkey,
                      Icons.key,
                      onTap: () => _copyToClipboard(pubkey, 'Public key'),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _buildInfoCard(
                      'Relay Status',
                      relayProvider.isInitialized ? 'Online' : 'Offline',
                      relayProvider.isInitialized ? Icons.cloud_done : Icons.cloud_off,
                      subtitle: relayProvider.isInitialized 
                          ? 'Embedded relay running'
                          : 'Relay not available',
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Statistics from relay
                    if (relayProvider.isInitialized) ...[
                      _buildStatsCard(relayProvider),
                      const SizedBox(height: 12),
                    ],
                    
                    // P2P Status
                    _buildInfoCard(
                      'P2P Sync',
                      relayProvider.p2pEnabled ? 'Enabled' : 'Disabled',
                      relayProvider.p2pEnabled ? Icons.device_hub : Icons.portable_wifi_off,
                      subtitle: relayProvider.p2pEnabled
                          ? '${relayProvider.discoveredPeers.length} peers discovered'
                          : 'Enable in settings for offline sync',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: colorScheme.primary),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: title == 'Public Key' ? 'monospace' : null,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        trailing: onTap != null ? const Icon(Icons.copy) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildStatsCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final stats = relayProvider.stats;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Relay Statistics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Events',
                    stats['event_count']?.toString() ?? '0',
                    Icons.event_note,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Authors',
                    stats['author_count']?.toString() ?? '0',
                    Icons.people,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Subscriptions',
                    relayProvider.subscriptionStats['activeSubscriptions']?.toString() ?? '0',
                    Icons.subscriptions,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Icon(
          icon,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _editProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProfileSetupScreen(),
      ),
    );
  }

  void _showQRCode() {
    final userProvider = context.read<UserProvider>();
    final pubkey = userProvider.publicKey ?? '';
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share Your Profile',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: pubkey,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
              
              const SizedBox(height: 16),
              
              Text(
                'Scan this QR code to follow this profile',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _copyToClipboard(pubkey, 'Public key'),
                      child: const Text('Copy Key'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}