import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/database_config.dart';
import '../models/view_schema.dart';
import 'cell_codec.dart';
import 'sheets_repository.dart' show Record, rowIndexKey;
import 'warehouse_connector.dart';

/// ClickHouse connector via the HTTP interface. Queries are sent as POST
/// bodies with `FORMAT JSON` appended; results parse to typed records.
///
/// ClickHouse is **OLAP-first** and doesn't support row-level UPDATE /
/// DELETE on standard MergeTree tables. We use `ALTER TABLE … UPDATE`
/// and `ALTER TABLE … DELETE` (the "mutations" path) which are
/// asynchronous but functionally correct for our CRUD shape. For
/// high-frequency mutations consider a ReplacingMergeTree or VersionedCollapsingMergeTree.
class ClickhouseConnector implements WarehouseConnector {
  @override
  final ClickhouseConfig config;

  final Uri _baseUri;
  final Map<String, String> _headers;

  ClickhouseConnector._(this.config, this._baseUri, this._headers);

  static Future<ClickhouseConnector> connect(ClickhouseConfig config) async {
    final host = config.host ?? 'localhost';
    final port = config.port ?? 8123;
    final scheme = port == 443 ? 'https' : 'http';
    final uri = Uri.parse(
      '$scheme://$host:$port/?database=${config.database ?? 'default'}',
    );
    final headers = <String, String>{
      'Content-Type': 'text/plain; charset=utf-8',
    };
    if (config.user != null) headers['X-ClickHouse-User'] = config.user!;
    if (config.password != null) headers['X-ClickHouse-Key'] = config.password!;
    final out = ClickhouseConnector._(config, uri, headers);
    // Sanity probe.
    await out._execute('SELECT 1');
    return out;
  }

  /// Sends [sql] to ClickHouse. Returns the raw response body — caller
  /// decides whether to parse JSON.
  Future<String> _execute(String sql) async {
    final resp = await http.post(_baseUri, headers: _headers, body: sql);
    if (resp.statusCode != 200) {
      throw StateError(
        'ClickHouse query failed (${resp.statusCode}): ${resp.body}',
      );
    }
    return resp.body;
  }

  Future<List<Map<String, dynamic>>> _query(String sql) async {
    final body = await _execute('$sql FORMAT JSON');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = (json['data'] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> ensureTable(ViewSchema view) async {
    final table = _quoteIdent(view.table);
    final cols = view.dimensions
        .map((d) => '${_quoteIdent(d.expr)} ${_chType(d.type)}')
        .join(', ');
    final orderBy = view.dimensionByName('id') != null
        ? _quoteIdent('id')
        : (view.dateField != null
            ? _quoteIdent(
                view.dimensionByName(view.dateField!)?.expr ?? view.dateField!)
            : 'tuple()');
    await _execute(
      'CREATE TABLE IF NOT EXISTS $table ($cols) '
      'ENGINE = MergeTree() ORDER BY $orderBy',
    );

    // Probe existing columns and ALTER for missing.
    final existing = await _query(
      "SELECT name FROM system.columns "
      "WHERE database = '${config.database ?? 'default'}' "
      "AND table = '${view.table}'",
    );
    final existingNames = <String>{
      for (final row in existing) row['name'].toString(),
    };
    for (final d in view.dimensions) {
      if (existingNames.contains(d.expr)) continue;
      await _execute(
        'ALTER TABLE $table ADD COLUMN ${_quoteIdent(d.expr)} ${_chType(d.type)}',
      );
    }
  }

  @override
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async {
    final table = _quoteIdent(view.table);
    final dateField = view.dateField == null
        ? null
        : view.dimensionByName(view.dateField!);
    final filter = dateField != null && onDate != null
        ? "WHERE ${_quoteIdent(dateField.expr)} = '${_dateString(onDate)}'"
        : '';

    final rows = await _query('SELECT * FROM $table $filter');
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
    if (filter.isNotEmpty && view.plannable != null) {
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
    final table = _quoteIdent(view.table);
    final toWrite = Map<String, Object?>.from(record);
    if (view.dimensionByName('id') != null && toWrite['id'] == null) {
      toWrite['id'] = _uuid();
    }
    final cols = <String>[];
    final values = <String>[];
    for (final d in view.dimensions) {
      if (!toWrite.containsKey(d.name)) continue;
      cols.add(_quoteIdent(d.expr));
      values.add(_literal(d.type, toWrite[d.name]));
    }
    await _execute(
      'INSERT INTO $table (${cols.join(', ')}) VALUES (${values.join(', ')})',
    );
    toWrite[rowIndexKey] = 0;
    return toWrite;
  }

  @override
  Future<void> update(ViewSchema view, Record record) async {
    final id = record['id'];
    if (id == null) {
      throw ArgumentError('ClickhouseConnector.update requires `id`');
    }
    final table = _quoteIdent(view.table);
    final sets = <String>[];
    for (final d in view.dimensions) {
      if (d.name == 'id') continue;
      if (!record.containsKey(d.name)) continue;
      sets.add('${_quoteIdent(d.expr)} = ${_literal(d.type, record[d.name])}');
    }
    await _execute(
      "ALTER TABLE $table UPDATE ${sets.join(', ')} "
      "WHERE id = '${id.toString().replaceAll("'", "''")}'",
    );
  }

  @override
  Future<void> delete(ViewSchema view, Record record) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final table = _quoteIdent(view.table);
    await _execute(
      "ALTER TABLE $table DELETE WHERE id = '${id.replaceAll("'", "''")}'",
    );
  }

  // ────── helpers ──────

  static String _quoteIdent(String s) => '`${s.replaceAll('`', '``')}`';

  static String _chType(DimensionType t) {
    switch (t) {
      case DimensionType.string:
        return 'String';
      case DimensionType.number:
        return 'Float64';
      case DimensionType.date:
        return 'Date';
      case DimensionType.datetime:
        return 'DateTime';
      case DimensionType.boolean:
        return 'UInt8';
    }
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _literal(DimensionType t, Object? v) {
    if (v == null) return 'NULL';
    switch (t) {
      case DimensionType.string:
        final s = v.toString().replaceAll("'", "''");
        return "'$s'";
      case DimensionType.number:
        return CellCodec.encode(t, v).toString();
      case DimensionType.date:
        final s = v is DateTime ? _dateString(v) : v.toString();
        return "'$s'";
      case DimensionType.datetime:
        final s = v is DateTime
            ? v.toIso8601String().replaceFirst('T', ' ').split('.').first
            : v.toString();
        return "'$s'";
      case DimensionType.boolean:
        return (v == true || v.toString().toLowerCase() == 'true') ? '1' : '0';
    }
  }

  static Object? _decodeValue(DimensionType t, dynamic raw) {
    if (raw == null) return null;
    switch (t) {
      case DimensionType.string:
        return raw.toString();
      case DimensionType.number:
        return raw is num ? raw : num.tryParse(raw.toString());
      case DimensionType.date:
      case DimensionType.datetime:
        return DateTime.tryParse(raw.toString().replaceFirst(' ', 'T'));
      case DimensionType.boolean:
        return raw == 1 || raw == '1' || raw == true;
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
