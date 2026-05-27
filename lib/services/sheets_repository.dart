import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:uuid/uuid.dart';

import '../models/view_schema.dart';
import 'cell_codec.dart';

/// One row from a sheet, keyed by dimension name.
typedef Record = Map<String, Object?>;

/// CRUD over Google Sheets. Each [ViewSchema] picks a spreadsheet (its own
/// `spreadsheet_id` override or the default) and a tab (its `table`). Row 1
/// is the header row; cell columns are matched to dimensions by [Dimension.expr].
class SheetsRepository {
  final String defaultSpreadsheetId;
  final sheets.SheetsApi _api;
  static const _uuid = Uuid();

  /// Cache of headers per (spreadsheet, tab) so writes don't re-fetch row 1.
  final Map<String, List<String>> _headerCache = {};

  SheetsRepository._(this.defaultSpreadsheetId, this._api);

  /// Authenticates via a service account key and returns a client. Caller
  /// is responsible for sourcing the JSON (file, asset, etc).
  static Future<SheetsRepository> connectFromKey({
    required String defaultSpreadsheetId,
    required String serviceAccountKeyJson,
  }) async {
    final credentials = ServiceAccountCredentials.fromJson(
      serviceAccountKeyJson,
    );
    final client = await clientViaServiceAccount(
      credentials,
      [sheets.SheetsApi.spreadsheetsScope],
    );
    final api = sheets.SheetsApi(client);
    return SheetsRepository._(defaultSpreadsheetId, api);
  }

  String _spreadsheetIdFor(ViewSchema view) =>
      view.spreadsheetId ?? defaultSpreadsheetId;

  String _cacheKey(ViewSchema view) =>
      '${_spreadsheetIdFor(view)}|${view.table}';

  /// Ensures the sheet tab exists and has every header the view expects.
  /// Additive — preserves existing headers (and their order) and only appends
  /// missing columns at the end. Safe to run against pre-existing sheets.
  Future<void> ensureSheet(ViewSchema view) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final ss = await _api.spreadsheets.get(spreadsheetId);
    final tabExists = (ss.sheets ?? []).any(
      (s) => s.properties?.title == view.table,
    );

    if (!tabExists) {
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

    final hdrResp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'${view.table}'!1:1",
    );
    final existingHeaders = (hdrResp.values?.isEmpty ?? true)
        ? <String>[]
        : hdrResp.values!.first.map((e) => e.toString()).toList();
    final wantHeaders = view.dimensions.map((d) => d.expr).toList();
    final missing = wantHeaders.where((h) => !existingHeaders.contains(h)).toList();

    if (existingHeaders.isNotEmpty && missing.isEmpty) {
      _headerCache[_cacheKey(view)] = existingHeaders;
      return;
    }

    final newHeaders = existingHeaders.isEmpty
        ? wantHeaders
        : [...existingHeaders, ...missing];
    await _api.spreadsheets.values.update(
      sheets.ValueRange(values: [newHeaders]),
      spreadsheetId,
      "'${view.table}'!A1",
      valueInputOption: 'RAW',
    );
    _headerCache[_cacheKey(view)] = newHeaders;
  }

  /// Lists all records for [view], optionally filtered to those whose
  /// `date_field` falls on [onDate].
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final values = await _readAll(spreadsheetId, view.table);
    if (values.isEmpty) return [];
    final headers = values.first.map((e) => e.toString()).toList();
    _headerCache[_cacheKey(view)] = headers;

    final records = <Record>[];
    for (var i = 1; i < values.length; i++) {
      records.add(_rowToRecord(view, headers, values[i]));
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

  /// Appends a new record. Assigns a UUID for `id` if the view has an id
  /// dimension and the record doesn't already have one.
  Future<Record> create(ViewSchema view, Record record) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final headers = await _ensureHeaders(view);
    final toWrite = Map<String, Object?>.from(record);
    if (view.dimensionByName('id') != null) {
      toWrite['id'] ??= _uuid.v4();
    }

    final row = headers.map((h) {
      final dim = view.dimensionByExpr(h);
      if (dim == null) return '';
      return CellCodec.encode(dim.type, toWrite[dim.name]);
    }).toList();

    await _api.spreadsheets.values.append(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      "'${view.table}'!A1",
      valueInputOption: 'RAW',
    );
    return toWrite;
  }

  /// Updates an existing record (matched by `id`). Preserves cells in columns
  /// we don't know about — only overwrites cells whose header maps to one of
  /// the view's dimensions.
  Future<void> update(ViewSchema view, Record record) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final id = record['id'];
    if (id == null) {
      throw ArgumentError('Cannot update a record without an id');
    }
    final headers = await _ensureHeaders(view);
    final rowIndex = await _findRowIndex(view, id.toString());
    if (rowIndex == null) {
      throw StateError('No row with id=$id in ${view.table}');
    }
    final existingRow = await _readRow(spreadsheetId, view.table, rowIndex);

    final row = <String>[];
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      final dim = view.dimensionByExpr(h);
      if (dim != null) {
        row.add(CellCodec.encode(dim.type, record[dim.name]));
      } else {
        row.add(i < existingRow.length ? existingRow[i].toString() : '');
      }
    }

    await _api.spreadsheets.values.update(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      "'${view.table}'!A${rowIndex + 2}",
      valueInputOption: 'RAW',
    );
  }

  /// Deletes the record with the given [id] by removing its sheet row.
  Future<void> delete(ViewSchema view, String id) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final rowIndex = await _findRowIndex(view, id);
    if (rowIndex == null) return;
    final sheetId = await _sheetIdFor(spreadsheetId, view.table);
    await _api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            deleteDimension: sheets.DeleteDimensionRequest(
              range: sheets.DimensionRange(
                sheetId: sheetId,
                dimension: 'ROWS',
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

  Future<List<List<Object?>>> _readAll(String spreadsheetId, String table) async {
    final resp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'$table'",
    );
    return (resp.values ?? <List<Object?>>[])
        .map((row) => row.cast<Object?>())
        .toList();
  }

  Future<List<Object?>> _readRow(
    String spreadsheetId,
    String table,
    int rowIndex,
  ) async {
    final resp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'$table'!${rowIndex + 2}:${rowIndex + 2}",
    );
    final rows = resp.values ?? [];
    return rows.isEmpty ? [] : rows.first.cast<Object?>();
  }

  Future<List<String>> _ensureHeaders(ViewSchema view) async {
    final cached = _headerCache[_cacheKey(view)];
    if (cached != null) return cached;
    final spreadsheetId = _spreadsheetIdFor(view);
    final resp = await _api.spreadsheets.values.get(
      spreadsheetId,
      "'${view.table}'!1:1",
    );
    final row = resp.values?.first ?? [];
    final headers = row.map((e) => e.toString()).toList();
    _headerCache[_cacheKey(view)] = headers;
    return headers;
  }

  Future<int?> _findRowIndex(ViewSchema view, String id) async {
    final spreadsheetId = _spreadsheetIdFor(view);
    final idDim = view.dimensionByName('id');
    if (idDim == null) return null;
    final values = await _readAll(spreadsheetId, view.table);
    if (values.isEmpty) return null;
    final headers = values.first.map((e) => e.toString()).toList();
    final idCol = headers.indexOf(idDim.expr);
    if (idCol < 0) return null;
    for (var i = 1; i < values.length; i++) {
      final row = values[i];
      if (row.length > idCol && row[idCol].toString() == id) {
        return i - 1;
      }
    }
    return null;
  }

  Future<int> _sheetIdFor(String spreadsheetId, String tabName) async {
    final ss = await _api.spreadsheets.get(spreadsheetId);
    for (final s in ss.sheets ?? <sheets.Sheet>[]) {
      if (s.properties?.title == tabName) {
        return s.properties!.sheetId!;
      }
    }
    throw StateError('No sheet tab named "$tabName"');
  }

  Record _rowToRecord(
    ViewSchema view,
    List<String> headers,
    List<Object?> row,
  ) {
    final record = <String, Object?>{};
    for (var i = 0; i < headers.length; i++) {
      final dim = view.dimensionByExpr(headers[i]);
      if (dim == null) continue;
      final raw = i < row.length ? row[i] : null;
      record[dim.name] = CellCodec.decode(dim.type, raw);
    }
    return record;
  }
}
