import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:yaml/yaml.dart';

import '../models/template.dart';

/// Loads template YAML files bundled under `assets/templates/<view>/`.
///
/// Templates are populated from `~/repos/ledger-schemas/templates/` by
/// `tool/sync_assets.sh` before each build.
class TemplateLoader {
  static const _prefix = 'assets/templates/';

  /// Returns all templates for [viewName], sorted by name.
  static Future<List<Template>> loadForView(String viewName) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final viewPrefix = '$_prefix$viewName/';
    final paths = manifest
        .listAssets()
        .where((k) => k.startsWith(viewPrefix) && k.endsWith('.yml'))
        .toList();
    final templates = <Template>[];
    for (final path in paths) {
      final raw = await rootBundle.loadString(path);
      templates.add(_parse(raw));
    }
    templates.sort((a, b) => a.name.compareTo(b.name));
    return templates;
  }

  static Template _parse(String yamlText) {
    final node = loadYaml(yamlText);
    if (node is! YamlMap) {
      throw const FormatException('Template YAML must be a map');
    }
    final entriesNode = node['entries'];
    if (entriesNode is! YamlList) {
      throw const FormatException('Template must have an `entries` list');
    }
    final entries = <Map<String, Object?>>[];
    for (final e in entriesNode) {
      if (e is! YamlMap) {
        throw const FormatException('Each entry must be a map');
      }
      entries.add({for (final k in e.keys) k.toString(): e[k]});
    }
    return Template(
      name: node['name'] as String,
      view: node['view'] as String,
      description: node['description'] as String?,
      entries: entries,
    );
  }
}
