/// A reusable preset that fans out into N partially-filled records when
/// applied. Drives the "predefined workouts" feature.
///
/// Templates live in `assets/templates/<view>/<name>.yml`. The `entries`
/// list contains maps of dimension-name → value; missing fields are left
/// blank when records are created.
class Template {
  final String name;
  final String view;
  final String? description;
  final List<Map<String, Object?>> entries;

  Template({
    required this.name,
    required this.view,
    this.description,
    required this.entries,
  });
}
