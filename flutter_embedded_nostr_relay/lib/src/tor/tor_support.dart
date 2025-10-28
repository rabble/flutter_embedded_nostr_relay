// ABOUTME: Tor support feature detection and platform-specific library path resolution
// ABOUTME: Provides runtime detection of Tor libraries with graceful fallback when not present

import 'dart:io' if (dart.library.html) 'dart:html';

// Conditional imports for FFI (not available on web)
import 'tor_support_stub.dart' 
  if (dart.library.io) 'tor_support_io.dart';

/// Static utility class for detecting Tor library availability at runtime
class TorSupport {
  static bool _checked = false;
  static bool _available = false;
  
  /// Check if Tor libraries are available on this platform
  static bool get isAvailable => TorSupportImpl.isAvailable;
  
  /// Get the platform-specific library path for Tor/Arti
  static String get libraryPath => TorSupportImpl.libraryPath;
  
  /// Reset the availability check (useful for testing)
  static void resetCheck() => TorSupportImpl.resetCheck();
}