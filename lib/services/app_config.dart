import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

/// Runtime configuration bundled in the app at `assets/config.yaml`.
///
/// Populated by `tool/sync_assets.sh` from `~/.config/ledger/config.yaml`
/// before each build, so the same config drives both desktop and mobile.
class AppConfig {
  final String spreadsheetId;

  AppConfig({required this.spreadsheetId});

  static Future<AppConfig> load() async {
    final raw = await rootBundle.loadString('assets/config.yaml');
    final node = loadYaml(raw);
    if (node is! YamlMap) {
      throw const ConfigException('assets/config.yaml: top-level must be a map');
    }
    final spreadsheetId = node['spreadsheet_id'] as String?;
    if (spreadsheetId == null) {
      throw const ConfigException(
        'assets/config.yaml: missing spreadsheet_id. '
        'Run tool/sync_assets.sh after editing ~/.config/ledger/config.yaml.',
      );
    }
    return AppConfig(spreadsheetId: spreadsheetId);
  }
}

class ConfigException implements Exception {
  final String message;
  const ConfigException(this.message);
  @override
  String toString() => message;
}
