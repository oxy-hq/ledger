import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../models/view_schema.dart';
import 'schema_parser.dart';

/// Loads `.view.yml` files from the Flutter asset bundle (Flutter-only).
///
/// Schema files live under `assets/schemas/` and are populated from the
/// `ledger-schemas` repo by `tool/sync_assets.sh` before each build.
class SchemaLoader {
  static const _schemaAssetPrefix = 'assets/schemas/';

  /// Loads every `.view.yml` file bundled under `assets/schemas/`,
  /// returning views sorted by name.
  static Future<List<ViewSchema>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final viewPaths = manifest
        .listAssets()
        .where((k) => k.startsWith(_schemaAssetPrefix) && k.endsWith('.view.yml'))
        .toList();

    final views = <ViewSchema>[];
    for (final path in viewPaths) {
      final raw = await rootBundle.loadString(path);
      try {
        views.add(parseViewSchema(raw));
      } catch (e) {
        throw SchemaLoadException('Failed to parse $path: $e');
      }
    }
    views.sort((a, b) => a.name.compareTo(b.name));
    return views;
  }
}

class SchemaLoadException implements Exception {
  final String message;
  const SchemaLoadException(this.message);
  @override
  String toString() => 'SchemaLoadException: $message';
}
