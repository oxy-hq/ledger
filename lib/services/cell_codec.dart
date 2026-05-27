import '../models/view_schema.dart';

/// Converts between typed Dart values and the strings the Sheets API exchanges.
///
/// Sheets cells round-trip as `Object?` (typically String, num, or bool). We
/// normalize to ISO 8601 for date/datetime so values are human-readable in the
/// sheet and unambiguous when read back.
class CellCodec {
  /// Converts a Dart value to the string form to write to Sheets.
  static String encode(DimensionType type, Object? value) {
    if (value == null) return '';
    switch (type) {
      case DimensionType.string:
        return value.toString();
      case DimensionType.number:
        if (value is num) return value.toString();
        return value.toString();
      case DimensionType.date:
        if (value is DateTime) {
          final d = value;
          return '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
        }
        return value.toString();
      case DimensionType.datetime:
        if (value is DateTime) return value.toIso8601String();
        return value.toString();
      case DimensionType.boolean:
        if (value is bool) return value ? 'true' : 'false';
        return value.toString();
    }
  }

  /// Decodes a cell value (Object? from Sheets) into a typed Dart value.
  /// Returns null for empty cells.
  static Object? decode(DimensionType type, Object? raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    switch (type) {
      case DimensionType.string:
        return s;
      case DimensionType.number:
        return num.tryParse(s) ?? 0;
      case DimensionType.date:
        return DateTime.tryParse(s);
      case DimensionType.datetime:
        return DateTime.tryParse(s);
      case DimensionType.boolean:
        return s.toLowerCase() == 'true';
    }
  }
}
