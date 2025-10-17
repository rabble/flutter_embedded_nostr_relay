// ABOUTME: Template manager for organizing and applying different project templates
// ABOUTME: Manages template selection, validation, and provides template metadata and configuration
class TemplateManager {
  static const Map<String, TemplateInfo> _templates = {
    'minimal': TemplateInfo(
      name: 'minimal',
      description: 'Minimal Flutter app with basic Nostr relay integration',
      features: ['Basic relay setup', 'Simple event handling'],
    ),
    'social': TemplateInfo(
      name: 'social',
      description: 'Social media app template with feed and profiles',
      features: ['Feed screen', 'Profile management', 'Follow system', 'Social interactions'],
    ),
    'chat': TemplateInfo(
      name: 'chat',
      description: 'Chat application with direct messaging',
      features: ['Chat list', 'Direct messaging', 'Message history', 'Real-time updates'],
    ),
  };

  List<String> get availableTemplates => _templates.keys.toList();

  TemplateInfo? getTemplateInfo(String templateName) {
    return _templates[templateName];
  }

  bool isValidTemplate(String templateName) {
    return _templates.containsKey(templateName);
  }

  Map<String, TemplateInfo> get allTemplates => Map.from(_templates);
}

class TemplateInfo {
  final String name;
  final String description;
  final List<String> features;

  const TemplateInfo({
    required this.name,
    required this.description,
    required this.features,
  });

  @override
  String toString() {
    return '$name: $description\nFeatures: ${features.join(', ')}';
  }
}