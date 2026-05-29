import 'dart:math';

import 'package:mysql_client/mysql_client.dart';

import '../models/database_config.dart';
import '../models/view_schema.dart';
import 'cell_codec.dart';
import 'sheets_repository.dart' show Record, rowIndexKey;
import 'warehouse_connector.dart';

/// MySQL connector. Mirrors [PostgresConnector]'s shape but uses
/// mysql_client and `:name` parameter syntax.
class MysqlConnector implements WarehouseConnector {
  @override
  final MysqlConfig config;

  final MySQLConnection _conn;

  MysqlConnector._(this.config, this._conn);

  static Future<MysqlConnector> connect(MysqlConfig config) async {
    final host = config.host;
    if (host == null) {
      throw StateError('MysqlConfig "${config.name}" has no host');
    }
    final conn = await MySQLConnection.createConnection(
      host: host,
      port: config.port ?? 3306,
      userName: config.user ?? 'root',
      password: config.password ?? '',
      databaseName: config.database,
      secure: false,
    );
    await conn.connect();
    return MysqlConnector._(config, conn);
  }

  Future<void> close() => _conn.close();

  @override
  Future<void> ensureTable(ViewSchema view) async {
    final table = _quoteIdent(view.table);
    final createCols = view.dimensions
        .map((d) => '${_quoteIdent(d.expr)} ${_mysqlType(d.type)}')
        .join(', ');
    final pk = view.dimensionByName('id') != null
        ? ', PRIMARY KEY (${_quoteIdent('id')})'
        : '';
    await _conn.execute('CREATE TABLE IF NOT EXISTS $table ($createCols$pk)');

    // MySQL doesn't support ADD COLUMN IF NOT EXISTS in all versions, so
    // probe with INFORMATION_SCHEMA first.
    final existingCols = await _conn.execute(
      "SELECT column_name FROM information_schema.columns "
      "WHERE table_schema = :db AND table_name = :tbl",
      {'db': config.database ?? '', 'tbl': view.table},
    );
    final existing = <String>{
      for (final row in existingCols.rows)
        (row.colAt(0) ?? '').toString(),
    };
    for (final d in view.dimensions) {
      if (existing.contains(d.expr)) continue;
      await _conn.execute(
        'ALTER TABLE $table ADD COLUMN ${_quoteIdent(d.expr)} ${_mysqlType(d.type)}',
      );
    }
  }

  @override
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async {
    final table = _quoteIdent(view.table);
    final dateField = view.dateField == null
        ? null
        : view.dimensionByName(view.dateField!);
    final useFilter = dateField != null && onDate != null;
    final sql = useFilter
        ? 'SELECT * FROM $table WHERE ${_quoteIdent(dateField.expr)} = :d'
        : 'SELECT * FROM $table';
    final params = useFilter
        ? {'d': _dateToString(onDate)}
        : const <String, dynamic>{};
    final result = await _conn.execute(sql, params);

    final records = <Record>[];
    var i = 0;
    for (final row in result.rows) {
      final record = <String, Object?>{};
      final assoc = row.assoc();
      for (final entry in assoc.entries) {
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
    final table = _quoteIdent(view.table);
    final toWrite = Map<String, Object?>.from(record);
    if (view.dimensionByName('id') != null && toWrite['id'] == null) {
      toWrite['id'] = _uuid();
    }
    final cols = <String>[];
    final names = <String>[];
    final params = <String, dynamic>{};
    var idx = 0;
    for (final d in view.dimensions) {
      if (!toWrite.containsKey(d.name)) continue;
      cols.add(_quoteIdent(d.expr));
      final paramName = 'p$idx';
      names.add(':$paramName');
      params[paramName] = _encodeValue(d.type, toWrite[d.name]);
      idx++;
    }
    await _conn.execute(
      'INSERT INTO $table (${cols.join(', ')}) VALUES (${names.join(', ')})',
      params,
    );
    toWrite[rowIndexKey] = 0;
    return toWrite;
  }

  @override
  Future<void> update(ViewSchema view, Record record) async {
    final id = record['id'];
    if (id == null) {
      throw ArgumentError('MysqlConnector.update requires `id`');
    }
    final table = _quoteIdent(view.table);
    final sets = <String>[];
    final params = <String, dynamic>{};
    var idx = 0;
    for (final d in view.dimensions) {
      if (d.name == 'id') continue;
      if (!record.containsKey(d.name)) continue;
      final paramName = 'p$idx';
      sets.add('${_quoteIdent(d.expr)} = :$paramName');
      params[paramName] = _encodeValue(d.type, record[d.name]);
      idx++;
    }
    params['id'] = id.toString();
    await _conn.execute(
      'UPDATE $table SET ${sets.join(', ')} WHERE id = :id',
      params,
    );
  }

  @override
  Future<void> delete(ViewSchema view, Record record) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final table = _quoteIdent(view.table);
    await _conn.execute(
      'DELETE FROM $table WHERE id = :id',
      {'id': id},
    );
  }

  // ────── helpers ──────

  static String _quoteIdent(String s) => '`${s.replaceAll('`', '``')}`';

  static String _mysqlType(DimensionType t) {
    switch (t) {
      case DimensionType.string:
        // VARCHAR(255) for PK columns, TEXT for the rest. MySQL needs
        // a fixed length for PRIMARY KEY/index columns; using VARCHAR
        // for everything keeps things simple.
        return 'VARCHAR(255)';
      case DimensionType.number:
        return 'DOUBLE';
      case DimensionType.date:
        return 'DATE';
      case DimensionType.datetime:
        return 'DATETIME';
      case DimensionType.boolean:
        return 'BOOLEAN';
    }
  }

  static String _dateToString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Object? _encodeValue(DimensionType t, Object? v) {
    if (v == null) return null;
    if (t == DimensionType.date && v is DateTime) return _dateToString(v);
    if (t == DimensionType.datetime && v is DateTime) {
      return v.toIso8601String().replaceFirst('T', ' ').split('.').first;
    }
    if (t == DimensionType.boolean) {
      return (v == true || v.toString().toLowerCase() == 'true') ? 1 : 0;
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
        return DateTime.tryParse(s.replaceFirst(' ', 'T'));
      case DimensionType.boolean:
        return s == '1' || s.toLowerCase() == 'true';
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
