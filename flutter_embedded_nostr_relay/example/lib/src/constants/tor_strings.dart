// ABOUTME: String constants for Tor-related UI text and messages
// ABOUTME: Centralizes all Tor UI strings for consistency and future localization support

class TorStrings {
  // Main title and labels
  static const privacySettingsTitle = 'Tor Privacy Settings';
  static const relayConnectionsLabel = 'Use Tor for relay connections';
  static const videoLoadingLabel = 'Use Tor for video loading';
  static const advancedSettingsButton = 'Advanced Settings';
  
  // Helper text
  static const relayConnectionsDescription = 'Route relay connections through Tor for privacy';
  static const videoLoadingDescription = 'Load videos through Tor for enhanced privacy';
  
  // Warnings and info
  static const performanceWarning = 'Tor traffic may be slower due to encryption and routing.';
  static const unavailableMessage = 'Tor support is not available in this build. Use the build_with_tor.sh script to compile with Tor support.';
  
  // Tooltips
  static const torUnavailableTooltip = 'Tor libraries not available';
  
  // Advanced dialog
  static const advancedDialogTitle = 'Advanced Tor Settings';
  static const currentConfigurationLabel = 'Current Configuration:';
  static const enabledLabel = 'Enabled:';
  static const forceTorLabel = 'Force Tor:';
  static const requiredLabel = 'Required:';
  static const timeoutLabel = 'Timeout:';
  static const torOnlyRelaysLabel = 'Tor-only Relays:';
  static const bridgesLabel = 'Bridges:';
  static const libraryStatusLabel = 'Library Status:';
  static const availableLabel = 'Available:';
  static const libraryPathLabel = 'Library Path:';
  static const noneConfiguredText = 'None configured';
  static const closeButton = 'Close';
  static const editConfigButton = 'Edit Config';
  static const advancedConfigComingSoon = 'Advanced Tor configuration editor coming soon!';
  
  // Time units
  static const minutesUnit = 'minutes';
}