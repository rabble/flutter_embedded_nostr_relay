// ABOUTME: Identity onboarding screen for creating or importing Nostr identity
// ABOUTME: Uses Riverpod for state management and integrates with identityProvider

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/relay_providers.dart';

class IdentityScreen extends ConsumerStatefulWidget {
  const IdentityScreen({super.key});

  @override
  ConsumerState<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends ConsumerState<IdentityScreen> {
  final _privateKeyController = TextEditingController();
  bool _isImporting = false;
  String? _errorMessage;
  
  @override
  void dispose() {
    _privateKeyController.dispose();
    super.dispose();
  }
  
  Future<void> _generateNewIdentity() async {
    setState(() {
      _errorMessage = null;
    });
    
    try {
      await ref.read(identityProvider.notifier).generateNewIdentity();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to generate identity: $e';
      });
    }
  }
  
  Future<void> _importIdentity() async {
    final privateKey = _privateKeyController.text.trim();
    
    if (privateKey.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a private key';
      });
      return;
    }
    
    setState(() {
      _errorMessage = null;
    });
    
    try {
      await ref.read(identityProvider.notifier).importIdentity(privateKey);
    } catch (e) {
      setState(() {
        _errorMessage = 'Invalid private key format';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.fingerprint,
                size: 80,
                color: Colors.purple,
              ),
              const SizedBox(height: 32),
              Text(
                'Welcome to Nostr',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Create a new identity or import an existing one',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              if (!_isImporting) ...[
                FilledButton.icon(
                  onPressed: _generateNewIdentity,
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Identity'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isImporting = true;
                      _errorMessage = null;
                    });
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Import Existing Key'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _privateKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Private Key (hex format)',
                    hintText: 'Enter your 64-character hex private key',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  maxLength: 64,
                  onSubmitted: (_) => _importIdentity(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isImporting = false;
                            _errorMessage = null;
                            _privateKeyController.clear();
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _importIdentity,
                        child: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ],
              
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, 
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const Spacer(),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, 
                      color: Colors.amber.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your private key is stored locally and never sent to any server',
                        style: TextStyle(
                          color: Colors.amber.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}