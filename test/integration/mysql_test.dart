/// Integration test for [MysqlConnector] against a real MySQL.
///
/// Bring up via `scripts/test-db-up.sh`, then:
///   set -a && source .test-ports.env && set +a
///   flutter test test/integration/mysql_test.dart

import 'dart:io';

import 'package:airledger/models/database_config.dart';
import 'package:airledger/models/view_schema.dart';
import 'package:airledger/services/mysql_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MysqlConfig config;

  setUpAll(() {
    final raw = Platform.environment['AIRLEDGER_MYSQL_PORT'];
    if (raw == null) {
      throw StateError(
        'AIRLEDGER_MYSQL_PORT not set — run scripts/test-db-up.sh and '
        'source .test-ports.env first',
      );
    }
    config = MysqlConfig(
      name: 'test_mysql',
      host: '127.0.0.1',
      port: int.parse(raw),
      user: 'airledger',
      password: 'airledgertest',
      database: 'airledger_test',
    );
  });

  final view = ViewSchema(
    name: 'logs',
    datasource: 'test_mysql',
    table: 'logs_mysql',
    dateField: 'logged_at',
    entities: [
      Entity(name: 'log_row', type: EntityType.primary, keys: ['id']),
    ],
    dimensions: [
      Dimension(name: 'id', type: DimensionType.string, expr: 'id'),
      Dimension(name: 'logged_at', type: DimensionType.date, expr: 'logged_at'),
      Dimension(name: 'message', type: DimensionType.string, expr: 'message'),
      Dimension(name: 'count', type: DimensionType.number, expr: 'count'),
      Dimension(name: 'ok', type: DimensionType.boolean, expr: 'ok'),
    ],
    measures: const [],
  );

  test('full CRUD round-trip against real MySQL', () async {
    final db = await MysqlConnector.connect(config);
    addTearDown(db.close);

    await db.ensureTable(view);

    final today = DateTime(2026, 5, 28);

    final created = await db.create(view, {
      'logged_at': today,
      'message': 'first',
      'count': 42,
      'ok': true,
    });
    expect(created['id'], isA<String>());
    final id = created['id'] as String;
    expect(id.length, 36);

    final rows = await db.list(view, onDate: today);
    final ours = rows.where((r) => r['id'] == id).toList();
    expect(ours, hasLength(1));
    expect(ours.first['message'], 'first');
    expect((ours.first['count'] as num).toInt(), 42);
    expect(ours.first['ok'], true);

    await db.update(view, {
      'id': id,
      'message': 'updated',
      'count': 99,
    });
    final after = await db.list(view, onDate: today);
    final updated = after.firstWhere((r) => r['id'] == id);
    expect(updated['message'], 'updated');
    expect((updated['count'] as num).toInt(), 99);

    await db.delete(view, {'id': id});
    final final_ = await db.list(view, onDate: today);
    expect(final_.any((r) => r['id'] == id), isFalse);
  });
}
