// ABOUTME: Stub implementation of Tor support for web platform
// ABOUTME: Returns false for all checks since Tor is not available on web

/// Stub implementation for platforms that don't support Tor (like web)
class TorSupportImpl {
  /// Always returns false on web platform
  static bool get isAvailable => false;
  
  /// Returns empty string on web platform
  static String get libraryPath => '';
  
  /// No-op on web platform
  static void resetCheck() {}
}