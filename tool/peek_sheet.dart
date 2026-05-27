// ignore_for_file: avoid_print

import 'dart:io';

import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

/// Peek at any spreadsheet: list tabs, then for each tab show row 1 (headers)
/// and the first 3 data rows. Used to figure out the schema of an existing
/// sheet before writing a .view.yml.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/peek_sheet.dart <spreadsheet_id>');
    exit(1);
  }
  final spreadsheetId = args[0];
  final home = Platform.environment['HOME']!;
  final keyJson = await File('$home/.config/ledger/service-account.json').readAsString();
  final creds = ServiceAccountCredentials.fromJson(keyJson);
  final client = await clientViaServiceAccount(creds, [sheets.SheetsApi.spreadsheetsScope]);
  try {
    final api = sheets.SheetsApi(client);
    final ss = await api.spreadsheets.get(spreadsheetId);
    print('Spreadsheet: "${ss.properties?.title}"');
    print('Tabs: ${ss.sheets?.map((s) => s.properties?.title).join(", ")}');
    for (final s in ss.sheets ?? []) {
      final tab = s.properties?.title ?? '';
      print('\n=== tab: $tab ===');
      final resp = await api.spreadsheets.values.get(
        spreadsheetId,
        "'$tab'!1:4",
      );
      final rows = resp.values ?? [];
      for (var i = 0; i < rows.length; i++) {
        final label = i == 0 ? 'header' : 'row$i';
        print('  $label: ${rows[i]}');
      }
    }
  } finally {
    client.close();
  }
}
