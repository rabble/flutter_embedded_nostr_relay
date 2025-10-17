// ABOUTME: Validation result model for event validation operations
// ABOUTME: Encapsulates validation status and error messages for structured error reporting
class ValidationResult {
  final bool isValid;
  final List<String> errors;

  ValidationResult({
    required this.isValid,
    required this.errors,
  });

  @override
  String toString() {
    if (isValid) {
      return 'ValidationResult(valid: true)';
    } else {
      return 'ValidationResult(valid: false, errors: ${errors.join(', ')})';
    }
  }
}