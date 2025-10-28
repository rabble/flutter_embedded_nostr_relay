// ABOUTME: Platform detection utilities that work across all platforms including web
// ABOUTME: Provides safe platform checks using kIsWeb to avoid Platform errors on web

import 'package:flutter/foundation.dart';
import 'platform_utils_stub.dart'
  if (dart.library.io) 'platform_utils_io.dart';

/// Platform detection utilities that work on all platforms
class PlatformUtils {
  /// Check if running on Android
  static bool get isAndroid => PlatformUtilsImpl.isAndroid;
  
  /// Check if running on iOS
  static bool get isIOS => PlatformUtilsImpl.isIOS;
  
  /// Check if running on macOS
  static bool get isMacOS => PlatformUtilsImpl.isMacOS;
  
  /// Check if running on Windows
  static bool get isWindows => PlatformUtilsImpl.isWindows;
  
  /// Check if running on Linux
  static bool get isLinux => PlatformUtilsImpl.isLinux;
  
  /// Check if running on web browser
  static bool get isWeb => kIsWeb;
  
  /// Check if running on desktop (macOS, Windows, Linux)
  static bool get isDesktop => isMacOS || isWindows || isLinux;
  
  /// Check if running on mobile (iOS, Android)
  static bool get isMobile => isIOS || isAndroid;
  
  /// Get operating system name
  static String get operatingSystem => PlatformUtilsImpl.operatingSystem;
  
  /// Get operating system version
  static String get operatingSystemVersion => PlatformUtilsImpl.operatingSystemVersion;
}