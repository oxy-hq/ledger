import '../models/database_config.dart';
import '../models/view_schema.dart';
import 'sheets_repository.dart' show Record;

/// CRUD operations every warehouse connector must implement.
///
/// Mirrors [SheetsRepository]'s shape — the existing sheets implementation
/// already conforms. Adding a new warehouse means implementing this
/// interface for the corresponding [DatabaseConfig] variant.
abstract class WarehouseConnector {
  /// The config this connector was built from. Useful for diagnostics
  /// and for the registry to identify connectors.
  DatabaseConfig get config;

  /// Idempotent — creates the destination table/tab if missing, adds any
  /// columns the view needs that aren't already there. Never removes
  /// columns. Run once per view at startup.
  Future<void> ensureTable(ViewSchema view);

  /// Returns all records for [view]. If [onDate] is provided and the view
  /// has a `date_field:`, filter to that day.
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate});

  /// Inserts a new record at the top of the data section (newest-first).
  /// Returns the inserted record with any auto-assigned fields populated
  /// (notably `id` if the view has one). Caller may need to shift
  /// in-memory row indexes after this; see [SheetsRepository.shiftRowIndexes].
  Future<Record> create(ViewSchema view, Record record);

  /// Updates an existing record. Resolution order is connector-specific
  /// but should at minimum support lookup by `id` if the view has one.
  Future<void> update(ViewSchema view, Record record);

  /// Deletes [record]. Connector-specific resolution; mirrors [update].
  Future<void> delete(ViewSchema view, Record record);
}

/// Stub connector used for [DatabaseConfig] variants ledger knows about but
/// doesn't yet implement (e.g. Snowflake, Databricks). Parses cleanly so
/// the app loads other views, throws clear errors only when something
/// tries to actually use it.
class UnimplementedConnector implements WarehouseConnector {
  @override
  final DatabaseConfig config;

  UnimplementedConnector(this.config);

  Never _bail(String op) => throw UnimplementedError(
        'Warehouse type "${config.typeName}" (datasource "${config.name}") '
        'is not yet supported by ledger. Attempted: $op',
      );

  @override
  Future<void> ensureTable(ViewSchema view) async => _bail('ensureTable');
  @override
  Future<List<Record>> list(ViewSchema view, {DateTime? onDate}) async =>
      _bail('list');
  @override
  Future<Record> create(ViewSchema view, Record record) async => _bail('create');
  @override
  Future<void> update(ViewSchema view, Record record) async => _bail('update');
  @override
  Future<void> delete(ViewSchema view, Record record) async => _bail('delete');
}
