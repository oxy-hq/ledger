/// Parsed representation of a `.view.yml` file from the schemas repo.
///
/// The schema combines two concerns in one file:
/// - The semantic layer (entities, dimensions, measures) — compatible with the
///   oxy/airlayer Cube-inspired format.
/// - The input layer (per-dimension `input:` block, top-level `date_field`,
///   `list_display`) — CRUD-specific extensions that the semantic-layer tools
///   ignore.
library;

enum DimensionType { string, number, date, datetime, boolean }

enum WidgetType { text, longtext, number, date, datetime, dropdown }

enum EntityType { primary, foreign }

enum MeasureType { count, sum, average, max, min, countDistinct }

class ViewSchema {
  final String name;
  final String? description;
  final String datasource;
  final String table;
  final String? dateField;
  final List<Entity> entities;
  final List<Dimension> dimensions;
  final List<Measure> measures;
  final ListDisplay? listDisplay;

  ViewSchema({
    required this.name,
    this.description,
    required this.datasource,
    required this.table,
    this.dateField,
    required this.entities,
    required this.dimensions,
    required this.measures,
    this.listDisplay,
  });

  Dimension? dimensionByName(String name) =>
      dimensions.where((d) => d.name == name).firstOrNull;

  /// Dimensions that should appear in the entry form (input.editable != false).
  List<Dimension> get editableDimensions =>
      dimensions.where((d) => d.input?.editable ?? true).toList();
}

class Entity {
  final String name;
  final EntityType type;
  final List<String> keys;

  Entity({required this.name, required this.type, required this.keys});
}

class Dimension {
  final String name;
  final DimensionType type;
  final String expr;
  final String? description;
  final List<String>? samples;
  final InputSpec? input;

  Dimension({
    required this.name,
    required this.type,
    required this.expr,
    this.description,
    this.samples,
    this.input,
  });
}

class InputSpec {
  final WidgetType widget;
  final bool required;
  final dynamic defaultValue;
  final num? min;
  final num? max;
  final List<String>? options;
  final String? placeholder;
  final bool editable;

  InputSpec({
    required this.widget,
    this.required = false,
    this.defaultValue,
    this.min,
    this.max,
    this.options,
    this.placeholder,
    this.editable = true,
  });
}

class Measure {
  final String name;
  final MeasureType type;
  final String? expr;
  final String? description;

  Measure({
    required this.name,
    required this.type,
    this.expr,
    this.description,
  });
}

class ListDisplay {
  final String title;
  final String? subtitle;

  ListDisplay({required this.title, this.subtitle});
}
