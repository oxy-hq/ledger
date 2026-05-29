import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:yaml/yaml.dart';

import '../models/template.dart';

/// Loads template YAML files from bundled assets. Templates live next to
/// their paired `.view.yml` using oxy-style basename pairing (mirrors
/// the agent + `.test.yml` precedent in oxy-internal):
///
///   views/strength.view.yml                  ← parent (semantic)
///   views/strength.input.yml                 ← paired input overlay
///   views/strength.cut_deadlift_heavy.template.yml   ← paired template
///   views/strength.cut_squat_heavy.template.yml
///
/// All synced into assets/schemas/ at build time by sync_assets.sh.
class TemplateLoader {
  static const _prefix = 'assets/schemas/';

  /// Returns all templates for [viewName], sorted by name.
  static Future<List<Template>> loadForView(String viewName) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where((k) => k.startsWith(_prefix) && _isTemplateFor(k, viewName))
        .toList();
    final templates = <Template>[];
    for (final path in paths) {
      final raw = await rootBundle.loadString(path);
      templates.add(_parse(raw, path, viewName));
    }
    templates.sort((a, b) => a.name.compareTo(b.name));
    return templates;
  }

  static bool _isTemplateFor(String path, String viewName) {
    final basename = path.split('/').last;
    if (!basename.endsWith('.template.yml')) return false;
    if (!basename.startsWith('$viewName.')) return false;
    final middle = basename.substring(
        viewName.length + 1, basename.length - '.template.yml'.length);
    return middle.isNotEmpty;
  }

  static Template _parse(String yamlText, String path, String expectedView) {
    final node = loadYaml(yamlText);
    if (node is! YamlMap) {
      throw const FormatException('Template YAML must be a map');
    }
    final target = node['target'];
    if (target is! String || !target.endsWith('.view.yml')) {
      throw FormatException(
        'Template $path: missing or malformed `target:`. '
        'Expected: target: <view_name>.view.yml',
      );
    }
    final declaredView =
        target.substring(0, target.length - '.view.yml'.length);
    if (declaredView != expectedView) {
      throw FormatException(
        'Template $path: target ($declaredView) does not match '
        'expected view ($expectedView)',
      );
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

    final variables = <TemplateVariable>[];
    final varsNode = node['variables'];
    if (varsNode is YamlList) {
      for (final v in varsNode) {
        if (v is! YamlMap) {
          throw const FormatException('Each variable must be a map');
        }
        variables.add(_parseVariable(v));
      }
    }

    final basename = path.split('/').last;
    final middle = basename.substring(
      expectedView.length + 1,
      basename.length - '.template.yml'.length,
    );
    return Template(
      name: (node['name'] as String?) ?? middle,
      view: expectedView,
      description: node['description'] as String?,
      variables: variables,
      entries: entries,
    );
  }

  static TemplateVariable _parseVariable(YamlMap v) {
    final name = v['name'] as String;
    final typeStr = (v['type'] as String?) ?? 'string';
    final type = typeStr == 'number'
        ? TemplateVarType.number
        : TemplateVarType.string;
    return TemplateVariable(
      name: name,
      label: (v['label'] as String?) ?? name,
      type: type,
      defaultValue: v['default'],
    );
  }
}
