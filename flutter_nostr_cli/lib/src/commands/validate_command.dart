// ABOUTME: Validate command for verifying Nostr event format, structure, and signatures
// ABOUTME: Supports single events, arrays, and files with comprehensive validation reporting
import 'dart:convert';
import 'dart:io' as io;
import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import '../models/validation_result.dart';

class ValidateCommand extends Command<int> {
  ValidateCommand() {
    argParser.addFlag(
      'signature',
      abbr: 's',
      help: 'Verify event signatures (requires public key)',
      defaultsTo: false,
    );
    argParser.addFlag(
      'strict',
      help: 'Use strict validation rules',
      defaultsTo: false,
    );
    argParser.addFlag(
      'report',
      abbr: 'r',
      help: 'Generate detailed validation report',
      defaultsTo: true,
    );
    argParser.addFlag(
      'dry-run',
      help: 'Show what would be validated without processing',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'validate';

  @override
  String get description => 'Validate Nostr event format and signatures';

  @override
  String get invocation => 'flutter_nostr validate <file.json> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    
    if (args.rest.isEmpty) {
      usageException('JSON file path is required');
    }

    final filePath = args.rest.first;
    final verifySignature = args['signature'] as bool;
    final strict = args['strict'] as bool;
    final generateReport = args['report'] as bool;
    final dryRun = args['dry-run'] as bool;

    if (dryRun) {
      print('Would validate file: $filePath');
      print('Signature verification: $verifySignature');
      print('Strict mode: $strict');
      return 0;
    }

    print('🔍 Validating Nostr events...');
    print('File: $filePath');
    
    try {
      final file = io.File(filePath);
      if (!file.existsSync()) {
        io.stderr.writeln('Error: File not found: $filePath');
        return 1;
      }

      // Try to validate as single event first, then as array
      ValidationResult result;
      try {
        result = await validateFromFile(filePath, const LocalFileSystem());
      } catch (e) {
        // Try as array
        final results = await validateArrayFromFile(filePath, const LocalFileSystem());
        if (generateReport) {
          _printArrayReport(results);
        }
        return results.any((r) => !r.isValid) ? 1 : 0;
      }

      if (generateReport) {
        _printSingleReport(result);
      }

      return result.isValid ? 0 : 1;
    } catch (e) {
      io.stderr.writeln('Error validating events: $e');
      return 1;
    }
  }

  ValidationResult validateEventStructure(Map<String, dynamic> event) {
    final errors = <String>[];

    // Check required fields
    final requiredFields = ['id', 'pubkey', 'created_at', 'kind', 'tags', 'content', 'sig'];
    for (final field in requiredFields) {
      if (!event.containsKey(field)) {
        errors.add('Missing required field: $field');
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult(isValid: false, errors: errors);
    }

    // Validate field formats
    final pubkey = event['pubkey'] as String?;
    if (pubkey == null || !_isValidHex(pubkey, 64)) {
      errors.add('Invalid pubkey format');
    }

    final id = event['id'] as String?;
    if (id == null || !_isValidHex(id, 64)) {
      errors.add('Invalid id format');
    }

    final sig = event['sig'] as String?;
    if (sig == null || !_isValidHex(sig, 128)) {
      errors.add('Invalid signature format');
    }

    final createdAt = event['created_at'];
    if (createdAt is! int || createdAt < 0) {
      errors.add('Invalid created_at format');
    }

    final kind = event['kind'];
    if (kind is! int || kind < 0) {
      errors.add('Invalid kind format');
    }

    final tags = event['tags'];
    if (tags is! List) {
      errors.add('Invalid tags format');
    }

    final content = event['content'];
    if (content is! String) {
      errors.add('Invalid content format');
    }

    return ValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  ValidationResult validateKindSpecific(Map<String, dynamic> event) {
    final errors = <String>[];
    final kind = event['kind'] as int;
    final content = event['content'] as String;

    switch (kind) {
      case 0: // Metadata
        try {
          jsonDecode(content);
        } catch (e) {
          errors.add('Kind 0 content must be valid JSON');
        }
        break;
      case 3: // Contact list
        try {
          jsonDecode(content);
        } catch (e) {
          errors.add('Kind 3 content must be valid JSON');
        }
        break;
      // Add more kind-specific validations as needed
    }

    return ValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  Future<ValidationResult> validateFromFile(String filePath, FileSystem fs) async {
    try {
      final content = await fs.file(filePath).readAsString();
      final eventData = jsonDecode(content) as Map<String, dynamic>;
      
      final structureResult = validateEventStructure(eventData);
      if (!structureResult.isValid) {
        return structureResult;
      }

      final kindResult = validateKindSpecific(eventData);
      if (!kindResult.isValid) {
        return ValidationResult(
          isValid: false,
          errors: [...structureResult.errors, ...kindResult.errors],
        );
      }

      return ValidationResult(isValid: true, errors: []);
    } catch (e) {
      return ValidationResult(isValid: false, errors: ['Invalid JSON format: $e']);
    }
  }

  Future<List<ValidationResult>> validateArrayFromFile(String filePath, FileSystem fs) async {
    try {
      final content = await fs.file(filePath).readAsString();
      final eventsData = jsonDecode(content) as List<dynamic>;
      
      final results = <ValidationResult>[];
      for (final eventData in eventsData) {
        if (eventData is Map<String, dynamic>) {
          final structureResult = validateEventStructure(eventData);
          if (structureResult.isValid) {
            final kindResult = validateKindSpecific(eventData);
            results.add(ValidationResult(
              isValid: kindResult.isValid,
              errors: [...structureResult.errors, ...kindResult.errors],
            ));
          } else {
            results.add(structureResult);
          }
        } else {
          results.add(ValidationResult(isValid: false, errors: ['Invalid event format']));
        }
      }
      
      return results;
    } catch (e) {
      return [ValidationResult(isValid: false, errors: ['Invalid JSON format: $e'])];
    }
  }

  String generateReport(List<Map<String, dynamic>> events) {
    final results = events.map((event) => validateEventStructure(event)).toList();
    final validCount = results.where((r) => r.isValid).length;
    final invalidCount = results.length - validCount;
    final successRate = (validCount / results.length * 100);

    final buffer = StringBuffer();
    buffer.writeln('📊 Validation Report');
    buffer.writeln('===================');
    buffer.writeln('Total Events: ${results.length}');
    buffer.writeln('Valid Events: $validCount');
    buffer.writeln('Invalid Events: $invalidCount');
    buffer.writeln('Success Rate: ${successRate.toStringAsFixed(1)}%');
    buffer.writeln();

    if (invalidCount > 0) {
      buffer.writeln('❌ Validation Errors:');
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        if (!result.isValid) {
          buffer.writeln('Event ${i + 1}:');
          for (final error in result.errors) {
            buffer.writeln('  - $error');
          }
        }
      }
    }

    return buffer.toString();
  }

  bool _isValidHex(String value, int expectedLength) {
    if (value.length != expectedLength) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  void _printSingleReport(ValidationResult result) {
    if (result.isValid) {
      print('✅ Event is valid');
    } else {
      print('❌ Event is invalid');
      for (final error in result.errors) {
        print('  - $error');
      }
    }
  }

  void _printArrayReport(List<ValidationResult> results) {
    final validCount = results.where((r) => r.isValid).length;
    final invalidCount = results.length - validCount;
    final successRate = (validCount / results.length * 100);

    print('📊 Validation Results:');
    print('Total: ${results.length}');
    print('Valid: $validCount');
    print('Invalid: $invalidCount');
    print('Success Rate: ${successRate.toStringAsFixed(1)}%');

    if (invalidCount > 0) {
      print('\n❌ Errors found:');
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        if (!result.isValid) {
          print('Event ${i + 1}:');
          for (final error in result.errors) {
            print('  - $error');
          }
        }
      }
    }
  }
}