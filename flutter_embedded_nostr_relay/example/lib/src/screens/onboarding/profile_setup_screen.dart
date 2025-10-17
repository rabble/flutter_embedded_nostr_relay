// ABOUTME: Profile setup screen for new users to configure their identity
// ABOUTME: Allows setting name, about, profile picture, and other metadata

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:image_picker/image_picker.dart'; // TODO: Add when implementing image upload
import '../../providers/user_provider.dart';
import '../timeline/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _websiteController = TextEditingController();
  final _nip05Controller = TextEditingController();
  
  bool _isSaving = false;
  String? _profilePicture;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _websiteController.dispose();
    _nip05Controller.dispose();
    super.dispose();
  }

  void _loadExistingProfile() {
    final userProvider = context.read<UserProvider>();
    final profile = userProvider.profile;
    
    if (profile != null) {
      _nameController.text = profile.name ?? '';
      _aboutController.text = profile.about ?? '';
      _websiteController.text = profile.website ?? '';
      _nip05Controller.text = profile.nip05 ?? '';
      _profilePicture = profile.picture;
    }
  }

  String? _validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }
    
    try {
      final uri = Uri.parse(value);
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        return 'Please enter a valid URL';
      }
    } catch (e) {
      return 'Please enter a valid URL';
    }
    
    return null;
  }

  String? _validateNip05(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional field
    }
    
    // Basic email-like format validation for NIP-05
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
      return 'Please enter a valid NIP-05 identifier (e.g., name@domain.com)';
    }
    
    return null;
  }

  Future<void> _selectProfilePicture() async {
    // TODO: Implement image picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image upload not yet implemented'),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final userProvider = context.read<UserProvider>();
      
      await userProvider.updateProfile(
        name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        about: _aboutController.text.trim().isEmpty ? null : _aboutController.text.trim(),
        website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
        nip05: _nip05Controller.text.trim().isEmpty ? null : _nip05Controller.text.trim(),
        picture: _profilePicture,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _skipSetup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Profile'),
        backgroundColor: colorScheme.surface,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _skipSetup,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Customize Your Identity',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Set up your profile to help others identify and connect with you on Nostr.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Profile picture section
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _selectProfilePicture,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: _profilePicture != null
                              ? ClipOval(
                                  child: Image.network(
                                    _profilePicture!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(
                                      Icons.person,
                                      size: 48,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.add_a_photo,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      TextButton.icon(
                        onPressed: _selectProfilePicture,
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Add Photo'),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'How should others see your name?',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                ),
                
                const SizedBox(height: 16),
                
                // About field
                TextFormField(
                  controller: _aboutController,
                  decoration: const InputDecoration(
                    labelText: 'About',
                    hintText: 'Tell others about yourself...',
                    prefixIcon: Icon(Icons.info_outline),
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                ),
                
                const SizedBox(height: 16),
                
                // Website field
                TextFormField(
                  controller: _websiteController,
                  validator: _validateUrl,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    hintText: 'https://your-website.com',
                    prefixIcon: Icon(Icons.language),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                
                const SizedBox(height: 16),
                
                // NIP-05 field
                TextFormField(
                  controller: _nip05Controller,
                  validator: _validateNip05,
                  decoration: const InputDecoration(
                    labelText: 'NIP-05 Identifier',
                    hintText: 'name@domain.com',
                    prefixIcon: Icon(Icons.verified_outlined),
                    helperText: 'Optional: Verify your identity with a domain',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saveProfile(),
                ),
                
                const SizedBox(height: 32),
                
                // Info card
                Card(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Public Key',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Consumer<UserProvider>(
                                builder: (context, userProvider, child) {
                                  return Text(
                                    userProvider.publicKey?.substring(0, 16) ?? 'Loading...',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: colorScheme.onSurface,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'This is your unique identifier on Nostr',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Skip button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isSaving ? null : _skipSetup,
                    child: const Text('Skip for now'),
                    style: TextButton.styleFrom(
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