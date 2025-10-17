// ABOUTME: Screen showing embedded relay status, statistics, and P2P connections
// ABOUTME: Provides monitoring and management of relay functionality

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import '../../providers/relay_provider.dart';
import '../../widgets/tor_settings_widget.dart';

class RelayStatusScreen extends StatefulWidget {
  const RelayStatusScreen({super.key});

  @override
  State<RelayStatusScreen> createState() => _RelayStatusScreenState();
}

class _RelayStatusScreenState extends State<RelayStatusScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh stats when screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RelayProvider>().updateStats();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<RelayProvider>(
      builder: (context, relayProvider, child) {
        return RefreshIndicator(
          onRefresh: () async {
            await relayProvider.updateStats();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Relay status overview
                _buildStatusCard(relayProvider),
                
                const SizedBox(height: 16),
                
                // Statistics
                if (relayProvider.isInitialized) ...[
                  _buildStatsCard(relayProvider),
                  const SizedBox(height: 16),
                ],
                
                // P2P sync status
                _buildP2PCard(relayProvider),
                
                const SizedBox(height: 16),
                
                // External relays
                _buildExternalRelaysCard(relayProvider),
                
                const SizedBox(height: 16),
                
                // Tor settings
                const TorSettingsWidget(),
                
                const SizedBox(height: 16),
                
                // Network status
                _buildNetworkCard(relayProvider),
                
                const SizedBox(height: 16),
                
                // Actions
                _buildActionsCard(relayProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: relayProvider.isInitialized 
                        ? Colors.green 
                        : colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Embedded Relay',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Text(
              relayProvider.isInitialized 
                  ? 'Running and accepting connections'
                  : relayProvider.isInitializing
                      ? 'Initializing...'
                      : 'Offline',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            
            if (relayProvider.isInitialized) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your device is running a local Nostr relay for instant responses',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final stats = relayProvider.stats;
    final subscriptionStats = relayProvider.subscriptionStats;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statistics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Events',
                    stats['event_count']?.toString() ?? '0',
                    Icons.event_note,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Unique Authors',
                    stats['author_count']?.toString() ?? '0',
                    Icons.people,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Active Subscriptions',
                    subscriptionStats['activeSubscriptions']?.toString() ?? '0',
                    Icons.subscriptions,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Connected Clients',
                    subscriptionStats['connectedClients']?.toString() ?? '0',
                    Icons.devices,
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
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildP2PCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'P2P Synchronization',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: relayProvider.p2pEnabled,
                  onChanged: relayProvider.isInitialized ? _toggleP2P : null,
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Text(
              relayProvider.p2pEnabled
                  ? 'Syncing with nearby devices via Bluetooth and WiFi Direct'
                  : 'Enable to sync with nearby devices when offline',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            
            if (relayProvider.p2pEnabled) ...[
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Icon(
                    Icons.device_hub,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${relayProvider.discoveredPeers.length} peers discovered',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              
              if (relayProvider.discoveredPeers.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...relayProvider.discoveredPeers.map((peer) => ListTile(
                  leading: Icon(
                    peer.transport == TransportType.ble 
                        ? Icons.bluetooth 
                        : Icons.wifi,
                    size: 20,
                  ),
                  title: Text(peer.name),
                  subtitle: Text(peer.transport.toString().split('.').last.toUpperCase()),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                )),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExternalRelaysCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final relays = relayProvider.externalRelays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'External Relays',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _addExternalRelay,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            if (relays.isEmpty) ...[
              Text(
                'No external relays configured. Add relays to sync with the broader Nostr network.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              ...relays.map((relay) => ListTile(
                leading: Icon(
                  relayProvider.relayConnections[relay] == true
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  color: relayProvider.relayConnections[relay] == true
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                title: Text(relay),
                subtitle: Text(
                  relayProvider.relayConnections[relay] == true
                      ? 'Connected'
                      : 'Disconnected',
                ),
                trailing: IconButton(
                  onPressed: () => _removeExternalRelay(relay),
                  icon: const Icon(Icons.delete),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Icon(
                  relayProvider.isOnline ? Icons.wifi : Icons.wifi_off,
                  color: relayProvider.isOnline ? Colors.green : colorScheme.error,
                ),
                const SizedBox(width: 12),
                Text(
                  relayProvider.isOnline ? 'Online' : 'Offline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Text(
              relayProvider.isOnline
                  ? 'Device has internet connectivity'
                  : 'No internet connection - using local relay only',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(RelayProvider relayProvider) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: relayProvider.isInitialized 
                        ? () => relayProvider.updateStats()
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Stats'),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showRelayInfo,
                    icon: const Icon(Icons.info),
                    label: const Text('Relay Info'),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  void _addExternalRelay() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add External Relay'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Relay URL',
            hintText: 'wss://relay.example.com',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.of(context).pop();
                try {
                  await context.read<RelayProvider>().addExternalRelay(url);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added relay: $url')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add relay: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeExternalRelay(String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Relay'),
        content: Text('Remove $url from external relays?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<RelayProvider>().removeExternalRelay(url);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showRelayInfo() {
    final relayProvider = context.read<RelayProvider>();
    
    if (!relayProvider.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relay not initialized')),
      );
      return;
    }
    
    final relayInfo = relayProvider.getRelayInfo();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relay Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${relayInfo.name}'),
            const SizedBox(height: 8),
            Text('Description: ${relayInfo.description}'),
            const SizedBox(height: 8),
            Text('Version: ${relayInfo.version}'),
            const SizedBox(height: 8),
            Text('Supported NIPs: ${relayInfo.supportedNips?.join(', ') ?? 'None'}'),
            const SizedBox(height: 8),
            Text('Software: ${relayInfo.software}'),
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
}