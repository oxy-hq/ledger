import 'package:intl/intl.dart';

import '../models/view_schema.dart';

/// Returns the value to write into the [Plannable.logField] when the user
/// taps "Log now" on a planned row. Format depends on [Plannable.logFormat].
Object logNowValue(LogFormat format, [DateTime? now]) {
  final t = now ?? DateTime.now();
  switch (format) {
    case LogFormat.timeString:
      return DateFormat('h:mm:ss a').format(t);
    case LogFormat.isoTime:
      return DateFormat('HH:mm:ss').format(t);
    case LogFormat.isoDateTime:
      return t.toIso8601String();
  }
}

/// Whether [record] is "planned" for the view — i.e. its log_field is empty
/// or missing. Returns false if the view isn't plannable.
bool isPlanned(ViewSchema view, Map<String, Object?> record) {
  final p = view.plannable;
  if (p == null) return false;
  final v = record[p.logField];
  if (v == null) return true;
  if (v is String && v.isEmpty) return true;
  return false;
}
