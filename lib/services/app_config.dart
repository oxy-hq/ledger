import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Runtime configuration loaded from `~/.config/ledger/config.yaml`.
class AppConfig {
  final String schemasDir;
  final String serviceAccountKeyPath;
  final String spreadsheetId;

  AppConfig({
    required this.schemasDir,
    required this.serviceAccountKeyPath,
    required this.spreadsheetId,
  });

  static String get defaultPath {
    final home = Platform.environment['HOME']!;
    return p.join(home, '.config', 'ledger', 'config.yaml');
  }

  /// Loads from [path] (defaults to [defaultPath]).
  /// Throws [ConfigException] with a user-friendly message if anything is wrong.
  static Future<AppConfig> load({String? path}) async {
    final configPath = path ?? defaultPath;
    final file = File(configPath);
    if (!await file.exists()) {
      throw ConfigException(
        'Config file not found at $configPath.\n\n'
        'Create it with:\n'
        '  mkdir -p ${p.dirname(configPath)}\n'
        '  cat > $configPath <<EOF\n'
        'schemas_dir: /Users/<you>/repos/ledger-schemas/views\n'
        'service_account_key_path: ${p.dirname(configPath)}/service-account.json\n'
        'spreadsheet_id: <your-google-sheet-id>\n'
        'EOF\n\n'
        'See SETUP.md in the ledger repo for service account setup.',
      );
    }
    final raw = await file.readAsString();
    final node = loadYaml(raw);
    if (node is! YamlMap) {
      throw ConfigException('$configPath: top-level YAML must be a map');
    }

    final schemasDir = node['schemas_dir'] as String?;
    final serviceAccountKeyPath = node['service_account_key_path'] as String?;
    final spreadsheetId = node['spreadsheet_id'] as String?;

    final missing = <String>[];
    if (schemasDir == null) missing.add('schemas_dir');
    if (serviceAccountKeyPath == null) missing.add('service_account_key_path');
    if (spreadsheetId == null) missing.add('spreadsheet_id');
    if (missing.isNotEmpty) {
      throw ConfigException(
        '$configPath: missing required keys: ${missing.join(', ')}',
      );
    }

    return AppConfig(
      schemasDir: schemasDir!,
      serviceAccountKeyPath: serviceAccountKeyPath!,
      spreadsheetId: spreadsheetId!,
    );
  }
}

class ConfigException implements Exception {
  final String message;
  const ConfigException(this.message);
  @override
  String toString() => message;
}
