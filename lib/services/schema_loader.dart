import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/view_schema.dart';

/// Loads `.view.yml` files from a directory and parses them into [ViewSchema]s.
class SchemaLoader {
  /// Loads every `.view.yml` file in [dir], returning views sorted by name.
  static Future<List<ViewSchema>> loadDir(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) {
      throw SchemaLoadException('Schemas directory not found: $dir');
    }
    final files = await directory
        .list()
        .where((e) => e is File && e.path.endsWith('.view.yml'))
        .cast<File>()
        .toList();
    final views = <ViewSchema>[];
    for (final file in files) {
      views.add(await loadFile(file.path));
    }
    views.sort((a, b) => a.name.compareTo(b.name));
    return views;
  }

  static Future<ViewSchema> loadFile(String path) async {
    final raw = await File(path).readAsString();
    try {
      return parse(raw);
    } catch (e) {
      throw SchemaLoadException('Failed to parse ${p.basename(path)}: $e');
    }
  }

  static ViewSchema parse(String yamlText) {
    final node = loadYaml(yamlText);
    if (node is! YamlMap) {
      throw const FormatException('Top-level YAML must be a map');
    }
    return _parseView(node);
  }
}

ViewSchema _parseView(YamlMap node) {
  final name = _requireString(node, 'name');
  return ViewSchema(
    name: name,
    description: node['description'] as String?,
    datasource: (node['datasource'] as String?) ?? 'gsheets',
    table: (node['table'] as String?) ?? name,
    dateField: node['date_field'] as String?,
    entities: _parseList(node['entities'], _parseEntity),
    dimensions: _parseList(node['dimensions'], _parseDimension),
    measures: _parseList(node['measures'], _parseMeasure),
    listDisplay: node['list_display'] == null
        ? null
        : _parseListDisplay(node['list_display'] as YamlMap),
  );
}

Entity _parseEntity(YamlMap node) {
  final keys = <String>[];
  if (node['key'] != null) keys.add(node['key'] as String);
  if (node['keys'] != null) {
    for (final k in (node['keys'] as YamlList)) {
      keys.add(k as String);
    }
  }
  return Entity(
    name: _requireString(node, 'name'),
    type: _parseEntityType(_requireString(node, 'type')),
    keys: keys,
  );
}

Dimension _parseDimension(YamlMap node) {
  return Dimension(
    name: _requireString(node, 'name'),
    type: _parseDimensionType(_requireString(node, 'type')),
    expr: (node['expr'] as String?) ?? _requireString(node, 'name'),
    description: node['description'] as String?,
    samples: node['samples'] == null
        ? null
        : (node['samples'] as YamlList).map((e) => e.toString()).toList(),
    input: node['input'] == null ? null : _parseInput(node['input'] as YamlMap),
  );
}

InputSpec _parseInput(YamlMap node) {
  return InputSpec(
    widget: _parseWidgetType((node['widget'] as String?) ?? 'text'),
    required: (node['required'] as bool?) ?? false,
    defaultValue: node['default'],
    min: node['min'] as num?,
    max: node['max'] as num?,
    options: node['options'] == null
        ? null
        : (node['options'] as YamlList).map((e) => e.toString()).toList(),
    placeholder: node['placeholder'] as String?,
    editable: (node['editable'] as bool?) ?? true,
  );
}

Measure _parseMeasure(YamlMap node) {
  return Measure(
    name: _requireString(node, 'name'),
    type: _parseMeasureType(_requireString(node, 'type')),
    expr: node['expr'] as String?,
    description: node['description'] as String?,
  );
}

ListDisplay _parseListDisplay(YamlMap node) {
  return ListDisplay(
    title: _requireString(node, 'title'),
    subtitle: node['subtitle'] as String?,
  );
}

List<T> _parseList<T>(dynamic node, T Function(YamlMap) fn) {
  if (node == null) return [];
  if (node is! YamlList) {
    throw const FormatException('Expected a list');
  }
  return node.map((e) => fn(e as YamlMap)).toList();
}

String _requireString(YamlMap node, String key) {
  final v = node[key];
  if (v is! String) {
    throw FormatException('Missing or non-string field: $key');
  }
  return v;
}

DimensionType _parseDimensionType(String s) {
  switch (s) {
    case 'string':
      return DimensionType.string;
    case 'number':
      return DimensionType.number;
    case 'date':
      return DimensionType.date;
    case 'datetime':
      return DimensionType.datetime;
    case 'boolean':
      return DimensionType.boolean;
    default:
      throw FormatException('Unknown dimension type: $s');
  }
}

WidgetType _parseWidgetType(String s) {
  switch (s) {
    case 'text':
      return WidgetType.text;
    case 'longtext':
      return WidgetType.longtext;
    case 'number':
      return WidgetType.number;
    case 'date':
      return WidgetType.date;
    case 'datetime':
      return WidgetType.datetime;
    case 'dropdown':
      return WidgetType.dropdown;
    default:
      throw FormatException('Unknown widget type: $s');
  }
}

EntityType _parseEntityType(String s) {
  switch (s) {
    case 'primary':
      return EntityType.primary;
    case 'foreign':
      return EntityType.foreign;
    default:
      throw FormatException('Unknown entity type: $s');
  }
}

MeasureType _parseMeasureType(String s) {
  switch (s) {
    case 'count':
      return MeasureType.count;
    case 'sum':
      return MeasureType.sum;
    case 'average':
      return MeasureType.average;
    case 'max':
      return MeasureType.max;
    case 'min':
      return MeasureType.min;
    case 'count_distinct':
      return MeasureType.countDistinct;
    default:
      throw FormatException('Unknown measure type: $s');
  }
}

class SchemaLoadException implements Exception {
  final String message;
  const SchemaLoadException(this.message);
  @override
  String toString() => 'SchemaLoadException: $message';
}
