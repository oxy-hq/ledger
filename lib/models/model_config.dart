/// Parsed `models:` entry from `config.yml`. Mirrors oxy's model
/// declaration shape so the same config.yml is consumable by both:
///
/// ```yaml
/// models:
///   - vendor: openai
///     name: openai-mini
///     model_ref: gpt-4o-mini
///     api_key_var: OPENAI_API_KEY    # resolved by brand.dart
///     api_url: https://api.openai.com/v1
///   - vendor: anthropic
///     name: sonnet
///     model_ref: claude-3-5-sonnet-latest
///     api_key_var: ANTHROPIC_API_KEY
/// ```
///
/// At build time `_var` fields are resolved into concrete `api_key` etc.
/// values (see tool/build_config.dart). Runtime sees only the resolved
/// fields.
library;

enum ModelVendor { openai, anthropic }

class ModelConfig {
  /// Logical name referenced by `post_log.model:` in .input.yml.
  final String name;

  /// Which vendor's API to call.
  final ModelVendor vendor;

  /// Actual model identifier (e.g. `gpt-4o-mini`, `claude-3-5-sonnet-latest`).
  final String modelRef;

  /// Resolved API key.
  final String apiKey;

  /// API base URL — defaults are vendor-specific; explicit overrides
  /// (e.g. Azure OpenAI endpoints) are honored.
  final String apiUrl;

  ModelConfig({
    required this.name,
    required this.vendor,
    required this.modelRef,
    required this.apiKey,
    required this.apiUrl,
  });

  static ModelConfig fromYaml(Map<String, dynamic> json) {
    final vendorRaw = json['vendor'];
    if (vendorRaw is! String) {
      throw FormatException('models[].vendor must be a string, got $vendorRaw');
    }
    final vendor = switch (vendorRaw) {
      'openai' => ModelVendor.openai,
      'anthropic' => ModelVendor.anthropic,
      _ => throw FormatException('Unknown model vendor: $vendorRaw'),
    };
    final apiKey = json['api_key'];
    if (apiKey is! String || apiKey.isEmpty) {
      throw FormatException(
        'models[name=${json['name']}].api_key is missing — did you set '
        '`api_key_var:` and the corresponding env var?',
      );
    }
    return ModelConfig(
      name: json['name'] as String,
      vendor: vendor,
      modelRef: json['model_ref'] as String,
      apiKey: apiKey,
      apiUrl: (json['api_url'] as String?) ??
          (vendor == ModelVendor.openai
              ? 'https://api.openai.com/v1'
              : 'https://api.anthropic.com/v1'),
    );
  }
}
