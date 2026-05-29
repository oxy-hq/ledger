import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../models/model_config.dart';

/// Runtime config bundled in the APK at `assets/config.yaml`.
/// Baked at build time by `tool/brand.dart` from the schemas repo's
/// `config.yml` + `.env`.
class AppConfig {
  final String spreadsheetId;
  final List<ModelConfig> models;

  AppConfig({required this.spreadsheetId, required this.models});

  static Future<AppConfig> load() async {
    final raw = await rootBundle.loadString('assets/config.yaml');
    final node = loadYaml(raw);
    if (node is! YamlMap) {
      throw const ConfigException(
        'assets/config.yaml: top-level must be a map',
      );
    }
    final spreadsheetId = node['spreadsheet_id'] as String?;
    if (spreadsheetId == null) {
      throw const ConfigException(
        'assets/config.yaml: missing spreadsheet_id',
      );
    }
    final modelsNode = node['models'];
    final models = <ModelConfig>[];
    if (modelsNode is YamlList) {
      for (final entry in modelsNode) {
        if (entry is! YamlMap) continue;
        models.add(ModelConfig.fromYaml(_yamlMapToJson(entry)));
      }
    }
    return AppConfig(spreadsheetId: spreadsheetId, models: models);
  }
}

Map<String, dynamic> _yamlMapToJson(YamlMap m) => {
      for (final entry in m.entries) entry.key.toString(): entry.value,
    };

class ConfigException implements Exception {
  final String message;
  const ConfigException(this.message);
  @override
  String toString() => message;
}
