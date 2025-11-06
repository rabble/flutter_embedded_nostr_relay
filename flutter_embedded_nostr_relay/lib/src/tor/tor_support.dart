// ABOUTME: Tor support feature detection and platform-specific library path resolution
// ABOUTME: Provides runtime detection of Tor libraries with graceful fallback when not present

// Conditional imports for FFI (not available on web)
import 'tor_support_stub.dart'
  if (dart.library.io) 'tor_support_io.dart';

/// Static utility class for detecting Tor library availability at runtime
class TorSupport {
  
  /// Check if Tor libraries are available on this platform
  static bool get isAvailable => TorSupportImpl.isAvailable;
  
  /// Get the platform-specific library path for Tor/Arti
  static String get libraryPath => TorSupportImpl.libraryPath;
  
  /// Reset the availability check (useful for testing)
  static void resetCheck() => TorSupportImpl.resetCheck();
}