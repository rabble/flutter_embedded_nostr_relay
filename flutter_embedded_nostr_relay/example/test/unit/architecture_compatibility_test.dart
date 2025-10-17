// ABOUTME: TDD tests for verifying architecture compatibility of Arti library
// ABOUTME: Ensures proper architecture matching between system and Tor library

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Architecture Compatibility TDD Tests', () {
    group('TDD: Arti Library Architecture Tests', () {
      test('FAIL: Arti library should match current system architecture', () async {
        // Get the current system architecture
        final systemArch = _getCurrentArchitecture();
        
        // Check the Arti library architecture
        final libraryPath = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/example/macos/Runner/Libraries/libarti_ffi.dylib';
        final libraryFile = File(libraryPath);
        
        expect(libraryFile.existsSync(), true, 
            reason: 'Arti library should exist');
        
        final libraryArch = await _getLibraryArchitecture(libraryPath);
        
        // The library should match system architecture or be universal
        expect(
          libraryArch.contains(systemArch) || libraryArch.contains('universal'),
          true,
          reason: 'Arti library architecture ($libraryArch) should be compatible with system architecture ($systemArch)'
        );
      });

      test('FAIL: should prefer native architecture over universal binary', () async {
        final systemArch = _getCurrentArchitecture();
        final libraryPath = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/example/macos/Runner/Libraries/libarti_ffi.dylib';
        
        final libraryArch = await _getLibraryArchitecture(libraryPath);
        
        // For best performance, native architecture is preferred
        if (systemArch == 'arm64') {
          expect(libraryArch, contains('arm64'),
              reason: 'On ARM64 systems, should use native ARM64 library for best performance');
        } else if (systemArch == 'x86_64') {
          expect(libraryArch, contains('x86_64'),
              reason: 'On x86_64 systems, should use native x86_64 library for best performance');
        }
      });

      test('FAIL: library from packages directory should be correct architecture', () async {
        final systemArch = _getCurrentArchitecture();
        final packageLibraryPath = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/packages/arti_ffi/target/release/libarti_ffi.dylib';
        
        final packageFile = File(packageLibraryPath);
        expect(packageFile.existsSync(), true,
            reason: 'Package library should exist');
        
        final packageLibraryArch = await _getLibraryArchitecture(packageLibraryPath);
        
        // The source library should be compatible
        expect(
          packageLibraryArch.contains(systemArch) || packageLibraryArch.contains('universal'),
          true,
          reason: 'Package library architecture ($packageLibraryArch) should be compatible with system ($systemArch)'
        );
      });

      test('FAIL: should detect and warn about architecture mismatches', () async {
        final systemArch = _getCurrentArchitecture();
        final libraryPath = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/example/macos/Runner/Libraries/libarti_ffi.dylib';
        
        final libraryArch = await _getLibraryArchitecture(libraryPath);
        
        // If there's a mismatch, we should be able to detect it
        final isCompatible = libraryArch.contains(systemArch) || libraryArch.contains('universal');
        
        if (!isCompatible) {
          // This test documents the current mismatch and will pass once fixed
          fail('Architecture mismatch detected: System=$systemArch, Library=$libraryArch. '
               'This test will pass once the library is updated to match the system architecture.');
        }
        
        expect(isCompatible, true,
            reason: 'No architecture mismatch should exist');
      });
    });

    group('TDD: Universal Binary Support Tests', () {
      test('PASS: should be able to create universal binary if needed', () async {
        // Check if both architecture variants exist in packages
        final arm64Path = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/packages/arti_ffi/target/release/libarti_ffi.dylib';
        final x86Path = '/Users/rabble/code/vine_fun/flutter_embedded_nostr_relay/flutter_embedded_nostr_relay/packages/arti_ffi/target/x86_64-apple-darwin/release/libarti_ffi.dylib';
        
        final arm64Exists = File(arm64Path).existsSync();
        final x86Exists = File(x86Path).existsSync();
        
        // At least one should exist
        expect(arm64Exists || x86Exists, true,
            reason: 'At least one architecture variant should exist');
        
        if (arm64Exists && x86Exists) {
          // Both exist, universal binary is possible
          final arm64Arch = await _getLibraryArchitecture(arm64Path);
          final x86Arch = await _getLibraryArchitecture(x86Path);
          
          expect(arm64Arch, contains('arm64'),
              reason: 'ARM64 variant should be ARM64 architecture');
          expect(x86Arch, contains('x86_64'),
              reason: 'x86_64 variant should be x86_64 architecture');
        }
      });
    });
  });
}

String _getCurrentArchitecture() {
  // Get current system architecture
  if (Platform.isIOS || Platform.isMacOS) {
    // For Apple platforms, check the native architecture
    final result = Process.runSync('uname', ['-m']);
    final arch = result.stdout.toString().trim();
    
    // Map to standard architecture names
    switch (arch) {
      case 'arm64':
      case 'aarch64':
        return 'arm64';
      case 'x86_64':
      case 'amd64':
        return 'x86_64';
      default:
        return arch;
    }
  }
  
  return 'unknown';
}

Future<String> _getLibraryArchitecture(String libraryPath) async {
  try {
    // Use 'file' command to check library architecture
    final result = await Process.run('file', [libraryPath]);
    final output = result.stdout.toString();
    
    if (output.contains('arm64')) {
      return 'arm64';
    } else if (output.contains('x86_64')) {
      return 'x86_64';
    } else if (output.contains('universal')) {
      return 'universal';
    } else {
      return 'unknown: $output';
    }
  } catch (e) {
    return 'error: $e';
  }
}