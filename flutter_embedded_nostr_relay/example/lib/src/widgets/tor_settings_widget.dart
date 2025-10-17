// ABOUTME: Dedicated widget for Tor privacy settings UI components
// ABOUTME: Extracted from RelayStatusScreen for better organization and reusability

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../providers/relay_provider.dart';
import '../constants/tor_strings.dart';

class TorSettingsWidget extends StatelessWidget {
  const TorSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RelayProvider>(
      builder: (context, relayProvider, child) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        
        final logger = Logger('TorSettingsWidget');
        bool torAvailable = false;
        try {
          torAvailable = relayProvider.torAvailable;
          logger.info('Building Tor settings widget - torAvailable: $torAvailable');
        } catch (e) {
          logger.warning('Error accessing torAvailable: $e');
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with title and warning icon
                Row(
                  children: [
                    Icon(
                      Icons.security,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TorStrings.privacySettingsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (!torAvailable)
                      Tooltip(
                        message: TorStrings.torUnavailableTooltip,
                        child: Icon(
                          Icons.warning_outlined,
                          color: colorScheme.error,
                          size: 20,
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Content based on Tor availability
                if (torAvailable) ...[
                  // Tor is available - show functional components
                  TorToggleSection(relayProvider: relayProvider),
                  
                  const SizedBox(height: 16),
                  
                  // Show performance warning if Tor is enabled
                  if (relayProvider.torForRelays || relayProvider.torForVideos) ...[
                    const TorPerformanceWarning(),
                    const SizedBox(height: 16),
                  ],
                  
                  // Advanced settings button
                  TorAdvancedButton(relayProvider: relayProvider),
                ] else ...[
                  // Tor not available - show message
                  const TorUnavailableMessage(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class TorToggleSection extends StatelessWidget {
  final RelayProvider relayProvider;
  
  const TorToggleSection({
    super.key,
    required this.relayProvider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Relay connections toggle
        Row(
          children: [
            Expanded(
              child: Text(
                TorStrings.relayConnectionsLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              key: const Key('tor_relay_switch'),
              value: relayProvider.torForRelays,
              onChanged: (enabled) => _toggleTorForRelays(context, enabled),
            ),
          ],
        ),
        
        Text(
          TorStrings.relayConnectionsDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Video loading toggle
        Row(
          children: [
            Expanded(
              child: Text(
                TorStrings.videoLoadingLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              key: const Key('tor_video_switch'),
              value: relayProvider.torForVideos,
              onChanged: (enabled) => _toggleTorForVideos(context, enabled),
            ),
          ],
        ),
        
        Text(
          TorStrings.videoLoadingDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _toggleTorForRelays(BuildContext context, bool enabled) async {
    try {
      await relayProvider.setTorForRelays(enabled);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                  ? 'Tor enabled for relay connections' 
                  : 'Tor disabled for relay connections'
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle Tor for relays: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _toggleTorForVideos(BuildContext context, bool enabled) async {
    try {
      await relayProvider.setTorForVideos(enabled);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                  ? 'Tor enabled for video loading' 
                  : 'Tor disabled for video loading'
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle Tor for videos: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

class TorPerformanceWarning extends StatelessWidget {
  const TorPerformanceWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              TorStrings.performanceWarning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TorUnavailableMessage extends StatelessWidget {
  const TorUnavailableMessage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TorStrings.unavailableMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          'Debug info: torAvailable = ${context.read<RelayProvider>().torAvailable}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class TorAdvancedButton extends StatelessWidget {
  final RelayProvider relayProvider;
  
  const TorAdvancedButton({
    super.key,
    required this.relayProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _showTorAdvancedSettings(context),
            child: const Text(TorStrings.advancedSettingsButton),
          ),
        ),
      ],
    );
  }

  void _showTorAdvancedSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(TorStrings.advancedDialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                TorStrings.currentConfigurationLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('${TorStrings.enabledLabel} ${relayProvider.torConfig.enabled}'),
              Text('${TorStrings.forceTorLabel} ${relayProvider.torConfig.forceTor}'),
              Text('${TorStrings.requiredLabel} ${relayProvider.torConfig.required}'),
              Text('${TorStrings.timeoutLabel} ${relayProvider.torConfig.timeout.inMinutes} ${TorStrings.minutesUnit}'),
              
              const SizedBox(height: 16),
              
              Text(
                TorStrings.torOnlyRelaysLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                relayProvider.torConfig.torOnlyRelays.isEmpty
                    ? TorStrings.noneConfiguredText
                    : relayProvider.torConfig.torOnlyRelays.join('\n'),
              ),
              
              const SizedBox(height: 16),
              
              Text(
                TorStrings.bridgesLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                relayProvider.torConfig.bridges.isEmpty
                    ? TorStrings.noneConfiguredText
                    : relayProvider.torConfig.bridges.join('\n'),
              ),
              
              const SizedBox(height: 16),
              
              Text(
                TorStrings.libraryStatusLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text('${TorStrings.availableLabel} ${relayProvider.torAvailable}'),
              if (relayProvider.torAvailable) ...[
                Text('${TorStrings.libraryPathLabel} ${_getTorLibraryPath()}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(TorStrings.closeButton),
          ),
          if (relayProvider.torAvailable)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showTorConfigEditor(context);
              },
              child: const Text(TorStrings.editConfigButton),
            ),
        ],
      ),
    );
  }

  String _getTorLibraryPath() {
    try {
      // Access TorSupport through the library
      return 'Dynamic library path';  // Simplified for now
    } catch (e) {
      return 'Error accessing library path';
    }
  }

  void _showTorConfigEditor(BuildContext context) {
    // TODO: Implement advanced Tor configuration editor
    // This would allow editing forceTor, torOnlyRelays, bridges, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(TorStrings.advancedConfigComingSoon),
      ),
    );
  }
}