import 'package:flutter_test/flutter_test.dart';
import 'package:airledger/models/view_schema.dart';
import 'package:airledger/services/schema_parser.dart';

const _meals = '''
name: meals
description: Daily meal log
datasource: gsheets
table: meals
date_field: eaten_at

entities:
  - name: meal_entry
    type: primary
    key: id

dimensions:
  - name: id
    type: string
    expr: id
    input:
      editable: false

  - name: eaten_at
    type: datetime
    expr: eaten_at
    input:
      widget: datetime
      default: now
      required: true

  - name: meal
    type: string
    expr: meal
    input:
      widget: text
      required: true
      placeholder: e.g. oatmeal

  - name: meal_type
    type: string
    expr: meal_type
    samples: [breakfast, lunch, dinner]
    input:
      widget: dropdown
      options: [breakfast, lunch, dinner]

  - name: calories
    type: number
    expr: calories
    input:
      widget: number
      required: true
      min: 0

list_display:
  title: meal
  subtitle: "\${calories} cal"

measures:
  - name: meal_count
    type: count
  - name: total_calories
    type: sum
    expr: calories
''';

void main() {
  group('parseViewSchema', () {
    test('parses a complete meals view', () {
      final view = parseViewSchema(_meals);

      expect(view.name, 'meals');
      expect(view.description, 'Daily meal log');
      expect(view.datasource, 'gsheets');
      expect(view.table, 'meals');
      expect(view.dateField, 'eaten_at');
    });

    test('parses entities', () {
      final view = parseViewSchema(_meals);

      expect(view.entities, hasLength(1));
      expect(view.entities[0].name, 'meal_entry');
      expect(view.entities[0].type, EntityType.primary);
      expect(view.entities[0].keys, ['id']);
    });

    test('parses dimensions with input specs', () {
      final view = parseViewSchema(_meals);

      expect(view.dimensions, hasLength(5));

      final eatenAt = view.dimensionByName('eaten_at')!;
      expect(eatenAt.type, DimensionType.datetime);
      expect(eatenAt.input!.widget, WidgetType.datetime);
      expect(eatenAt.input!.required, true);
      expect(eatenAt.input!.defaultValue, 'now');

      final meal = view.dimensionByName('meal')!;
      expect(meal.input!.placeholder, 'e.g. oatmeal');

      final mealType = view.dimensionByName('meal_type')!;
      expect(mealType.input!.widget, WidgetType.dropdown);
      expect(mealType.input!.options, ['breakfast', 'lunch', 'dinner']);
      expect(mealType.samples, ['breakfast', 'lunch', 'dinner']);

      final calories = view.dimensionByName('calories')!;
      expect(calories.input!.min, 0);
    });

    test('id field is non-editable', () {
      final view = parseViewSchema(_meals);

      final id = view.dimensionByName('id')!;
      expect(id.input!.editable, false);

      final editable = view.editableDimensions.map((d) => d.name).toList();
      expect(editable, isNot(contains('id')));
      expect(editable, contains('meal'));
    });

    test('parses list_display', () {
      final view = parseViewSchema(_meals);

      expect(view.listDisplay!.title, 'meal');
      expect(view.listDisplay!.subtitle, '\${calories} cal');
    });

    test('parses measures', () {
      final view = parseViewSchema(_meals);

      expect(view.measures, hasLength(2));
      expect(view.measures[0].type, MeasureType.count);
      expect(view.measures[1].type, MeasureType.sum);
      expect(view.measures[1].expr, 'calories');
    });

    test('defaults table to name and datasource to gsheets', () {
      final view = parseViewSchema('''
name: foo
entities:
  - name: e
    type: primary
    key: id
dimensions:
  - name: id
    type: string
''');
      expect(view.table, 'foo');
      expect(view.datasource, 'gsheets');
    });

    test('throws on unknown dimension type', () {
      expect(
        () => parseViewSchema('''
name: bad
entities: []
dimensions:
  - name: x
    type: nonsense
'''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
