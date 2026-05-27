import 'dart:io';

import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:uuid/uuid.dart';

import '../models/view_schema.dart';
import 'cell_codec.dart';

/// One row from a sheet, keyed by dimension name.
typedef Record = Map<String, Object?>;

/// CRUD over Google Sheets. One workbook (spreadsheetId), one tab per view.
///
/// Convention:
/// - Tab name == view.table
/// - Row 1 is a header row whose values are the dimension `name`s
/// - Each subsequent row is a record; cells are positional, matching headers
/// - The `id` dimension is the primary key and must exist in the view
class SheetsRepository {
  final String spreadsheetId;
  final sheets.SheetsApi _api;
  static const _uuid = Uuid();

  // Cache header row per view to avoid re-reading on every write.
  final Map<String, List<String>> _headerCache = {};

  SheetsRepository._(this.spreadsheetId, this._api);

  /// Authenticates via a service account JSON key file and returns a client.
  static Future<SheetsRepository> connect({
    required String spreadsheetId,
    required String serviceAccountKeyPath,
  }) async {
    final keyJson = await File(serviceAccountKeyPath).readAsString();
    final credentials = ServiceAccountCredentials.fromJson(keyJson);
    final client = await clientViaServiceAccount(
      credentials,
      [sheets.SheetsApi.spreadsheetsScope],
    );
    final api = sheets.SheetsApi(client);
    return SheetsRepository._(spreadsheetId, api);
  }

  /// Ensures the sheet tab for [view] exists with a header row matching the
  /// view's dimensions. Adds missing headers if the tab exists but is shorter.
  /// Creates the tab if it doesn't exist.
  Future<void> ensureSheet(ViewSchema view) async {
    final ss = await _api.spreadsheets.get(spreadsheetId);
    final existing = ss.sheets?.firstWhere(
      (s) => s.properties?.title == view.table,
      orElse: () => sheets.Sheet(),
    );

    if (existing?.properties?.title != view.table) {
      // Create the tab.
      await _api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: view.table),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
    }

    final desiredHeaders = view.dimensions.map((d) => d.name).toList();
    await _api.spreadsheets.values.update(
      sheets.ValueRange(values: [desiredHeaders]),
      spreadsheetId,
      "'${view.table}'!A1",
      valueInputOption: 'RAW',
    );
    _headerCache[view.table] = desiredHeaders;
  }

  /// Lists all records for [view], optionally filtered to those whose
  /// `date_field` falls on [onDate].
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async {
    final values = await _readAll(view);
    if (values.isEmpty) return [];
    final headers = values.first.map((e) => e.toString()).toList();
    _headerCache[view.table] = headers;

    final records = <Record>[];
    for (var i = 1; i < values.length; i++) {
      final record = _rowToRecord(view, headers, values[i]);
      records.add(record);
    }

    if (onDate != null && view.dateField != null) {
      final filtered = records.where((r) {
        final v = r[view.dateField];
        if (v is! DateTime) return false;
        return v.year == onDate.year &&
            v.month == onDate.month &&
            v.day == onDate.day;
      }).toList();
      filtered.sort((a, b) {
        final av = a[view.dateField] as DateTime?;
        final bv = b[view.dateField] as DateTime?;
        if (av == null || bv == null) return 0;
        return bv.compareTo(av);
      });
      return filtered;
    }

    return records;
  }

  /// Inserts a new record. Assigns a UUID for `id` if missing.
  Future<Record> create(ViewSchema view, Record record) async {
    final headers = await _ensureHeaders(view);
    final toWrite = Map<String, Object?>.from(record);
    toWrite['id'] ??= _uuid.v4();

    final row = headers.map((h) {
      final dim = view.dimensionByName(h);
      if (dim == null) return '';
      return CellCodec.encode(dim.type, toWrite[h]);
    }).toList();

    await _api.spreadsheets.values.append(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      "'${view.table}'!A1",
      valueInputOption: 'RAW',
    );
    return toWrite;
  }

  /// Updates an existing record (matched by `id`).
  Future<void> update(ViewSchema view, Record record) async {
    final id = record['id'];
    if (id == null) {
      throw ArgumentError('Cannot update a record without an id');
    }
    final headers = await _ensureHeaders(view);
    final rowIndex = await _findRowIndex(view, id.toString());
    if (rowIndex == null) {
      throw StateError('No row with id=$id in ${view.table}');
    }

    final row = headers.map((h) {
      final dim = view.dimensionByName(h);
      if (dim == null) return '';
      return CellCodec.encode(dim.type, record[h]);
    }).toList();

    await _api.spreadsheets.values.update(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      // rowIndex is zero-based from the header row; sheet row is 1-based and
      // we offset by 1 for the header → 0-indexed data row N => sheet row N+2.
      "'${view.table}'!A${rowIndex + 2}",
      valueInputOption: 'RAW',
    );
  }

  /// Deletes the record with the given [id] by removing its sheet row.
  Future<void> delete(ViewSchema view, String id) async {
    final rowIndex = await _findRowIndex(view, id);
    if (rowIndex == null) return;

    final sheetId = await _sheetIdFor(view.table);
    await _api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            deleteDimension: sheets.DeleteDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: sheetId,
                dimension: 'ROWS',
                // Data row N (0-based) is sheet row N+1 (0-based, including
                // header). Delete that row.
                startIndex: rowIndex + 1,
                endIndex: rowIndex + 2,
              ),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  // --- internals ---

  Future<List<List<Object?>>> _readAll(ViewSchema view) async {
    final resp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'${view.table}'",
    );
    return (resp.values ?? <List<Object?>>[])
        .map((row) => row.cast<Object?>())
        .toList();
  }

  Future<List<String>> _ensureHeaders(ViewSchema view) async {
    final cached = _headerCache[view.table];
    if (cached != null) return cached;
    final resp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'${view.table}'!1:1",
    );
    final row = resp.values?.first ?? [];
    final headers = row.map((e) => e.toString()).toList();
    _headerCache[view.table] = headers;
    return headers;
  }

  Future<int?> _findRowIndex(ViewSchema view, String id) async {
    final values = await _readAll(view);
    if (values.isEmpty) return null;
    final headers = values.first.map((e) => e.toString()).toList();
    final idCol = headers.indexOf('id');
    if (idCol < 0) return null;
    for (var i = 1; i < values.length; i++) {
      if (i - 1 < 0) continue;
      final row = values[i];
      if (row.length > idCol && row[idCol].toString() == id) {
        return i - 1; // zero-based data row
      }
    }
    return null;
  }

  Future<int> _sheetIdFor(String tabName) async {
    final ss = await _api.spreadsheets.get(spreadsheetId);
    final match = ss.sheets?.firstWhere(
      (s) => s.properties?.title == tabName,
      orElse: () => sheets.Sheet(),
    );
    final id = match?.properties?.sheetId;
    if (id == null) {
      throw StateError('No sheet tab named "$tabName"');
    }
    return id;
  }

  Record _rowToRecord(
    ViewSchema view,
    List<String> headers,
    List<Object?> row,
  ) {
    final record = <String, Object?>{};
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i];
      final dim = view.dimensionByName(header);
      if (dim == null) continue;
      final raw = i < row.length ? row[i] : null;
      record[header] = CellCodec.decode(dim.type, raw);
    }
    return record;
  }
}
