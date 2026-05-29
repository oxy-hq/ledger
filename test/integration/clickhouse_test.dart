/// Integration test for [ClickhouseConnector] against a real ClickHouse.
/// ClickHouse mutations (ALTER UPDATE/DELETE) are async — we poll for the
/// expected state instead of asserting immediately.

import 'dart:io';

import 'package:airledger/models/database_config.dart';
import 'package:airledger/models/view_schema.dart';
import 'package:airledger/services/clickhouse_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ClickhouseConfig config;

  setUpAll(() {
    final raw = Platform.environment['AIRLEDGER_CH_HTTP_PORT'];
    if (raw == null) {
      throw StateError(
        'AIRLEDGER_CH_HTTP_PORT not set — run scripts/test-db-up.sh and '
        'source .test-ports.env first',
      );
    }
    config = ClickhouseConfig(
      name: 'test_ch',
      host: '127.0.0.1',
      port: int.parse(raw),
      database: 'default',
    );
  });

  final view = ViewSchema(
    name: 'logs',
    datasource: 'test_ch',
    table: 'logs_ch',
    dateField: 'logged_at',
    entities: [
      Entity(name: 'log_row', type: EntityType.primary, keys: ['id']),
    ],
    dimensions: [
      Dimension(name: 'id', type: DimensionType.string, expr: 'id'),
      Dimension(name: 'logged_at', type: DimensionType.date, expr: 'logged_at'),
      Dimension(name: 'message', type: DimensionType.string, expr: 'message'),
      Dimension(name: 'count', type: DimensionType.number, expr: 'count'),
    ],
    measures: const [],
  );

  Future<Map<String, Object?>?> _pollUntil(
    ClickhouseConnector ch,
    String id,
    bool Function(Map<String, Object?>?) predicate, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final rows = await ch.list(view);
      final match = rows.where((r) => r['id'] == id).firstOrNull;
      if (predicate(match)) return match;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Timed out waiting on ClickHouse mutation for id=$id');
  }

  test('full CRUD round-trip against real ClickHouse', () async {
    final ch = await ClickhouseConnector.connect(config);

    await ch.ensureTable(view);

    final today = DateTime(2026, 5, 28);
    final created = await ch.create(view, {
      'logged_at': today,
      'message': 'first',
      'count': 42,
    });
    final id = created['id'] as String;

    // Insert is synchronous in CH.
    final rows = await ch.list(view, onDate: today);
    final ours = rows.where((r) => r['id'] == id).toList();
    expect(ours, hasLength(1));
    expect(ours.first['message'], 'first');

    // Update is async (ALTER UPDATE).
    await ch.update(view, {'id': id, 'message': 'updated', 'count': 99});
    final after = await _pollUntil(
      ch,
      id,
      (r) => r != null && r['message'] == 'updated',
    );
    expect((after!['count'] as num).toInt(), 99);

    // Delete is async.
    await ch.delete(view, {'id': id});
    await _pollUntil(ch, id, (r) => r == null);
  });
}
