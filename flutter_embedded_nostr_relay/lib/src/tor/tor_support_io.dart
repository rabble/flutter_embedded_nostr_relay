// ABOUTME: IO implementation of Tor support with FFI for native platforms
// ABOUTME: Provides runtime detection of Tor libraries for mobile and desktop platforms

import 'dart:ffi';
import 'dart:io';

/// IO implementation for platforms that support Tor (mobile/desktop)
class TorSupportImpl {
  static bool _checked = false;
  static bool _available = false;
  
  /// Check if Tor libraries are available on this platform
  static bool get isAvailable {
    if (!_checked) {
      _checked = true;
      try {
        // Try to load the Tor library
        final lib = DynamicLibrary.open(libraryPath);
        // Look for a known Arti function to verify it's the right library
        _available = lib.lookup('arti_client_create') != null;
      } catch (_) {
        // Library not found or doesn't have expected symbols
        _available = false;
      }
    }
    return _available;
  }
  
  /// Get the platform-specific library path for Tor/Arti
  static String get libraryPath {
    if (Platform.isAndroid) return 'libarti_ffi.so';
    if (Platform.isIOS) return 'ArtiFFI.framework/ArtiFFI';
    if (Platform.isMacOS) {
      // For development/debug, try the absolute path first
      final absolutePath = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/packages/arti_ffi/target/release/libarti_ffi.dylib';
      final file = File(absolutePath);
      if (file.existsSync()) {
        return absolutePath;
      }
      // Fall back to relative path for production builds
      return 'libarti_ffi.dylib';
    }
    if (Platform.isWindows) return 'arti_ffi.dll';
    if (Platform.isLinux) return 'libarti_ffi.so';
    throw UnsupportedError('Platform ${Platform.operatingSystem} not supported for Tor');
  }
  
  /// Reset the availability check (useful for testing)
  static void resetCheck() {
    _checked = false;
    _available = false;
  }
}