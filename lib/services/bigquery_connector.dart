import 'dart:math';

import 'package:googleapis/bigquery/v2.dart' as bq;
import 'package:googleapis_auth/auth_io.dart';

import '../models/database_config.dart';
import '../models/view_schema.dart';
import 'cell_codec.dart';
import 'sheets_repository.dart' show Record, rowIndexKey;
import 'warehouse_connector.dart';

/// BigQuery connector. Authenticates via a service account (same shape
/// as the Sheets connector — both use Google Cloud SA JSON). DDL is
/// idempotent; DML uses standard SQL `INSERT` / `UPDATE` / `DELETE`.
///
/// Note: BigQuery DML has a streaming-insert vs. batch trade-off. We
/// use synchronous DML which has slightly higher latency but is
/// immediately consistent (streaming inserts have a buffer that's
/// invisible to DML for ~90 minutes). For CRUD use cases (ledger),
/// consistency wins.
class BigQueryConnector implements WarehouseConnector {
  @override
  final BigQueryConfig config;

  final bq.BigqueryApi _api;
  final String _project;
  final String _dataset;

  BigQueryConnector._(this.config, this._api, this._project, this._dataset);

  static Future<BigQueryConnector> connect(
    BigQueryConfig config, {
    required String serviceAccountKeyJson,
  }) async {
    final creds = ServiceAccountCredentials.fromJson(serviceAccountKeyJson);
    final client = await clientViaServiceAccount(
      creds,
      [bq.BigqueryApi.bigqueryScope],
    );
    final api = bq.BigqueryApi(client);
    final project = config.project;
    final dataset = config.dataset;
    if (project == null || dataset == null) {
      throw StateError(
        'BigQueryConfig "${config.name}" needs both `project` and `dataset`',
      );
    }
    return BigQueryConnector._(config, api, project, dataset);
  }

  @override
  Future<void> ensureTable(ViewSchema view) async {
    final tableId = view.table;
    final wantFields = view.dimensions
        .map((d) => bq.TableFieldSchema(
              name: d.expr,
              type: _bqType(d.type),
              mode: 'NULLABLE',
            ))
        .toList();

    try {
      final existing = await _api.tables.get(_project, _dataset, tableId);
      final existingFields = existing.schema?.fields ?? <bq.TableFieldSchema>[];
      final existingNames = existingFields.map((f) => f.name).toSet();
      final missing =
          wantFields.where((f) => !existingNames.contains(f.name)).toList();
      if (missing.isEmpty) return;
      final merged = [...existingFields, ...missing];
      await _api.tables.patch(
        bq.Table(schema: bq.TableSchema(fields: merged)),
        _project,
        _dataset,
        tableId,
      );
    } on bq.DetailedApiRequestError catch (e) {
      if (e.status != 404) rethrow;
      // Table doesn't exist — create it.
      await _api.tables.insert(
        bq.Table(
          tableReference: bq.TableReference(
            projectId: _project,
            datasetId: _dataset,
            tableId: tableId,
          ),
          schema: bq.TableSchema(fields: wantFields),
        ),
        _project,
        _dataset,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _query(
    String sql, [
    List<bq.QueryParameter>? parameters,
  ]) async {
    final resp = await _api.jobs.query(
      bq.QueryRequest(
        query: sql,
        useLegacySql: false,
        queryParameters: parameters,
        parameterMode: parameters == null ? null : 'NAMED',
      ),
      _project,
    );
    if (resp.rows == null) return const [];
    final fieldNames =
        resp.schema?.fields?.map((f) => f.name ?? '').toList() ??
            const <String>[];
    return resp.rows!.map((r) {
      final out = <String, dynamic>{};
      for (var i = 0; i < fieldNames.length; i++) {
        out[fieldNames[i]] = r.f?[i].v;
      }
      return out;
    }).toList();
  }

  @override
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async {
    final tableRef = '`$_project.$_dataset.${view.table}`';
    final dateField = view.dateField == null
        ? null
        : view.dimensionByName(view.dateField!);
    final useFilter = dateField != null && onDate != null;
    final sql = useFilter
        ? 'SELECT * FROM $tableRef WHERE `${dateField.expr}` = @d'
        : 'SELECT * FROM $tableRef';
    final params = useFilter
        ? [
            bq.QueryParameter(
              name: 'd',
              parameterType: bq.QueryParameterType(type: 'DATE'),
              parameterValue:
                  bq.QueryParameterValue(value: _dateString(onDate)),
            )
          ]
        : null;
    final rows = await _query(sql, params);

    final records = <Record>[];
    var i = 0;
    for (final row in rows) {
      final record = <String, Object?>{};
      for (final entry in row.entries) {
        final dim = view.dimensionByExpr(entry.key);
        if (dim == null) continue;
        record[dim.name] = _decodeValue(dim.type, entry.value);
      }
      record[rowIndexKey] = i++;
      records.add(record);
    }
    if (useFilter && view.plannable != null) {
      final logField = view.plannable!.logField;
      records.sort((a, b) {
        final av = a[logField]?.toString() ?? '';
        final bv = b[logField]?.toString() ?? '';
        if (av.isEmpty && bv.isEmpty) return 0;
        if (av.isEmpty) return 1;
        if (bv.isEmpty) return -1;
        return av.compareTo(bv);
      });
    }
    return records;
  }

  @override
  Future<Record> create(ViewSchema view, Record record) async {
    final tableRef = '`$_project.$_dataset.${view.table}`';
    final toWrite = Map<String, Object?>.from(record);
    if (view.dimensionByName('id') != null && toWrite['id'] == null) {
      toWrite['id'] = _uuid();
    }
    final cols = <String>[];
    final paramRefs = <String>[];
    final params = <bq.QueryParameter>[];
    var idx = 0;
    for (final d in view.dimensions) {
      if (!toWrite.containsKey(d.name)) continue;
      cols.add('`${d.expr}`');
      final pName = 'p$idx';
      paramRefs.add('@$pName');
      params.add(_makeParam(pName, d.type, toWrite[d.name]));
      idx++;
    }
    await _query(
      'INSERT $tableRef (${cols.join(', ')}) VALUES (${paramRefs.join(', ')})',
      params,
    );
    toWrite[rowIndexKey] = 0;
    return toWrite;
  }

  @override
  Future<void> update(ViewSchema view, Record record) async {
    final id = record['id'];
    if (id == null) {
      throw ArgumentError('BigQueryConnector.update requires `id`');
    }
    final tableRef = '`$_project.$_dataset.${view.table}`';
    final sets = <String>[];
    final params = <bq.QueryParameter>[];
    var idx = 0;
    for (final d in view.dimensions) {
      if (d.name == 'id') continue;
      if (!record.containsKey(d.name)) continue;
      final pName = 'p$idx';
      sets.add('`${d.expr}` = @$pName');
      params.add(_makeParam(pName, d.type, record[d.name]));
      idx++;
    }
    params.add(bq.QueryParameter(
      name: 'id',
      parameterType: bq.QueryParameterType(type: 'STRING'),
      parameterValue: bq.QueryParameterValue(value: id.toString()),
    ));
    await _query(
      'UPDATE $tableRef SET ${sets.join(', ')} WHERE id = @id',
      params,
    );
  }

  @override
  Future<void> delete(ViewSchema view, Record record) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final tableRef = '`$_project.$_dataset.${view.table}`';
    await _query(
      'DELETE $tableRef WHERE id = @id',
      [
        bq.QueryParameter(
          name: 'id',
          parameterType: bq.QueryParameterType(type: 'STRING'),
          parameterValue: bq.QueryParameterValue(value: id),
        )
      ],
    );
  }

  // ────── helpers ──────

  static String _bqType(DimensionType t) {
    switch (t) {
      case DimensionType.string:
        return 'STRING';
      case DimensionType.number:
        return 'FLOAT64';
      case DimensionType.date:
        return 'DATE';
      case DimensionType.datetime:
        return 'TIMESTAMP';
      case DimensionType.boolean:
        return 'BOOL';
    }
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bq.QueryParameter _makeParam(
    String name,
    DimensionType t,
    Object? value,
  ) {
    final bqType = _bqType(t);
    final encoded = _encodeValue(t, value);
    return bq.QueryParameter(
      name: name,
      parameterType: bq.QueryParameterType(type: bqType),
      parameterValue: bq.QueryParameterValue(value: encoded?.toString()),
    );
  }

  static Object? _encodeValue(DimensionType t, Object? v) {
    if (v == null) return null;
    if (t == DimensionType.date && v is DateTime) return _dateString(v);
    if (t == DimensionType.datetime && v is DateTime) {
      return v.toUtc().toIso8601String();
    }
    if (t == DimensionType.boolean) {
      return (v == true || v.toString().toLowerCase() == 'true') ? 'TRUE' : 'FALSE';
    }
    return CellCodec.encode(t, v);
  }

  static Object? _decodeValue(DimensionType t, dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    switch (t) {
      case DimensionType.string:
        return s;
      case DimensionType.number:
        return num.tryParse(s);
      case DimensionType.date:
      case DimensionType.datetime:
        // BigQuery returns timestamps as epoch-seconds-with-fractional, or
        // ISO-8601 — try both.
        final asNum = num.tryParse(s);
        if (asNum != null) {
          return DateTime.fromMillisecondsSinceEpoch(
            (asNum * 1000).round(),
            isUtc: true,
          );
        }
        return DateTime.tryParse(s);
      case DimensionType.boolean:
        return s.toLowerCase() == 'true';
    }
  }

  static final _rand = Random.secure();
  static String _uuid() {
    final r = List<int>.generate(16, (_) => _rand.nextInt(256));
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = r.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
