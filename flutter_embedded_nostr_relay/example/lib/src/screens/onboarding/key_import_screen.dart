// ABOUTME: Screen for importing existing Nostr private keys
// ABOUTME: Supports hex keys, nsec format, and QR code scanning

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// import 'package:qr_code_scanner/qr_code_scanner.dart'; // TODO: Add when implementing QR
import '../../providers/user_provider.dart';
import '../timeline/home_screen.dart';
import 'profile_setup_screen.dart';

class KeyImportScreen extends StatefulWidget {
  const KeyImportScreen({super.key});

  @override
  State<KeyImportScreen> createState() => _KeyImportScreenState();
}

class _KeyImportScreenState extends State<KeyImportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  bool _isImporting = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String? _validatePrivateKey(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a private key';
    }

    // Remove common prefixes and whitespace
    final cleanKey = value
        .trim()
        .replaceAll('nsec1', '') // Remove nsec prefix if present
        .replaceAll('0x', '') // Remove hex prefix if present
        .replaceAll(' ', '') // Remove spaces
        .toLowerCase();

    // Check hex format (64 characters)
    if (cleanKey.length != 64) {
      return 'Private key must be 64 characters long';
    }

    if (!RegExp(r'^[0-9a-f]+$').hasMatch(cleanKey)) {
      return 'Private key must contain only hexadecimal characters';
    }

    return null;
  }

  String _cleanPrivateKey(String key) {
    return key
        .trim()
        .replaceAll('nsec1', '')
        .replaceAll('0x', '')
        .replaceAll(' ', '')
        .toLowerCase();
  }

  Future<void> _importKey() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final cleanKey = _cleanPrivateKey(_keyController.text);
      final userProvider = context.read<UserProvider>();
      
      await userProvider.signInWithPrivateKey(cleanKey);

      if (mounted) {
        // Check if user has a profile, if not go to profile setup
        if (userProvider.profile?.name == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const ProfileSetupScreen(),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const HomeScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import key: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) {
        _keyController.text = data!.text!;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to paste from clipboard: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showQRScanner() {
    // TODO: Implement QR code scanning
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR code scanning not yet implemented'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Private Key'),
        backgroundColor: colorScheme.surface,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Enter Your Private Key',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Import your existing Nostr private key to access your identity and posts.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Private key input
                TextFormField(
                  controller: _keyController,
                  validator: _validatePrivateKey,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'Private Key',
                    hintText: 'Enter your private key in hex format...',
                    helperText: 'Supports hex format and nsec1... format',
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Toggle visibility
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureKey = !_obscureKey;
                            });
                          },
                          icon: Icon(
                            _obscureKey ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                        // Paste button
                        IconButton(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste),
                        ),
                      ],
                    ),
                  ),
                  maxLines: _obscureKey ? 1 : 3,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _importKey(),
                ),
                
                const SizedBox(height: 24),
                
                // Alternative import methods
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alternative Import Methods',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // QR code scanner button
                        ListTile(
                          leading: const Icon(Icons.qr_code_scanner),
                          title: const Text('Scan QR Code'),
                          subtitle: const Text('Scan a QR code containing your private key'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _showQRScanner,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Security warning
                Card(
                  color: colorScheme.errorContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.security,
                          color: colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Security Notice',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Your private key will be stored securely on this device only. Never share it with anyone.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Import button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isImporting ? null : _importKey,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isImporting ? 'Importing...' : 'Import Key'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}