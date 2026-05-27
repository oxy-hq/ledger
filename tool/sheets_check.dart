import 'dart:io';

import 'package:ledger/services/app_config.dart';
import 'package:ledger/services/schema_loader.dart';
import 'package:ledger/services/sheets_repository.dart';

/// End-to-end smoke test that does NOT touch the UI:
///   1. Loads app config + schemas
///   2. Connects to the Google Sheets workbook as the service account
///   3. Calls ensureSheet for each view (creates tabs + writes headers)
///   4. Creates a probe record, lists today's records, deletes the probe
Future<void> main() async {
  final config = await AppConfig.load();
  print('config loaded:');
  print('  schemas_dir: ${config.schemasDir}');
  print('  spreadsheet_id: ${config.spreadsheetId}');

  final views = await SchemaLoader.loadDir(config.schemasDir);
  print('\n${views.length} views loaded: ${views.map((v) => v.name).join(", ")}');

  final repo = await SheetsRepository.connect(
    spreadsheetId: config.spreadsheetId,
    serviceAccountKeyPath: config.serviceAccountKeyPath,
  );

  for (final view in views) {
    print('\n--- ensureSheet: ${view.name} ---');
    await repo.ensureSheet(view);
    print('OK: tab "${view.table}" ready');
  }

  // Probe write/read/delete on the meals view.
  final meals = views.firstWhere((v) => v.name == 'meals');
  print('\n--- probe write/read/delete on meals ---');

  final probe = await repo.create(meals, {
    'eaten_at': DateTime.now(),
    'meal': '[smoke test probe — safe to delete]',
    'meal_type': 'snack',
    'calories': 1,
  });
  print('created probe id=${probe['id']}');

  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final rows = await repo.list(meals, onDate: todayDate);
  print('listed ${rows.length} rows for today');

  await repo.delete(meals, probe['id'] as String);
  print('deleted probe');

  print('\nALL OK');
  exit(0);
}
