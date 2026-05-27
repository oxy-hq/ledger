import 'package:intl/intl.dart';

import '../models/view_schema.dart';

/// Runs a [Derive] spec against a source value and returns the derived value.
/// Returns null if the source is null or of the wrong type for the format.
Object? runDerive(Derive derive, Object? source) {
  if (source == null) return null;
  switch (derive.format) {
    case DeriveFormat.weekdayLong:
      if (source is! DateTime) return null;
      return DateFormat('EEEE').format(source);
    case DeriveFormat.weekdayShort:
      if (source is! DateTime) return null;
      return DateFormat('EEE').format(source);
    case DeriveFormat.isoDate:
      if (source is! DateTime) return null;
      return DateFormat('yyyy-MM-dd').format(source);
    case DeriveFormat.isoDateTime:
      if (source is! DateTime) return null;
      return source.toIso8601String();
  }
}

/// Applies all derived dimensions in [view] to [record] in place.
/// Skips derived fields that already have a value.
void applyDerives(ViewSchema view, Map<String, Object?> record) {
  for (final dim in view.derivedDimensions) {
    if (record[dim.name] != null) continue;
    final source = record[dim.derive!.from];
    final derived = runDerive(dim.derive!, source);
    if (derived != null) record[dim.name] = derived;
  }
}
