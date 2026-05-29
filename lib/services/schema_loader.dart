import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../models/view_schema.dart';
import 'input_parser.dart';
import 'schema_parser.dart';

/// Loads `.view.yml` files paired with `.input.yml` overlays from the
/// bundled assets. Schemas are baked into the APK at build time by
/// `tool/brand.dart` — there's no runtime cache or refresh path.
class SchemaLoader {
  static const _schemaAssetPrefix = 'assets/schemas/';

  static Future<List<ViewSchema>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = manifest.listAssets().toSet();
    final viewPaths = allAssets
        .where((k) =>
            k.startsWith(_schemaAssetPrefix) && k.endsWith('.view.yml'))
        .toList();

    final views = <ViewSchema>[];
    for (final path in viewPaths) {
      final raw = await rootBundle.loadString(path);
      try {
        final view = parseViewSchema(raw);
        final inputPath =
            path.replaceAll(RegExp(r'\.view\.yml$'), '.input.yml');
        if (allAssets.contains(inputPath)) {
          final inputRaw = await rootBundle.loadString(inputPath);
          final overlay = parseInputOverlay(inputRaw);
          views.add(applyInputOverlay(view, overlay));
        } else {
          views.add(view);
        }
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
