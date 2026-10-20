import 'dart:collection';

import '../platforms/abstract_platform.dart';
import 'abstract_asset.dart';
import 'doctrine_schema_exceptions.dart';
import 'schema_config.dart';
import 'sequence.dart';
import 'table.dart';

/// A set of tables, sequences and namespaces (database schemas).
/// Corresponds to Doctrine\DBAL\Schema\Schema.
///
/// Unqualified names belong to the schema's own name (its default
/// namespace, `public` unless [SchemaConfig] names another one); a table
/// named `vendas.pedido` creates the `vendas` namespace.
///
/// ```dart
/// final schema = Schema();
/// final users = schema.createTable('users');
/// users.addColumn('id', 'integer', options: {'autoIncrement': true});
/// users.setPrimaryKey(['id']);
/// for (final sql in schema.toSql(PostgreSQLPlatform())) {
///   await db.execute(sql);
/// }
/// ```
class Schema extends AbstractAsset {
  Schema({
    List<Table> tables = const [],
    List<Sequence> sequences = const [],
    SchemaConfig? schemaConfig,
    List<String> namespaces = const [],
  }) : _schemaConfig = schemaConfig ?? SchemaConfig() {
    final schemaName = _schemaConfig.getName();
    setName(schemaName == null || schemaName.isEmpty ? 'public' : schemaName);
    for (final namespace in namespaces) {
      if (!hasNamespace(namespace)) createNamespace(namespace);
    }
    tables.forEach(_addTable);
    sequences.forEach(_addSequence);
  }

  final SchemaConfig _schemaConfig;
  final Map<String, String> _namespaces = LinkedHashMap();
  final Map<String, Table> _tables = LinkedHashMap();
  final Map<String, Sequence> _sequences = LinkedHashMap();

  SchemaConfig get schemaConfig => _schemaConfig;

  void _addTable(Table table) {
    final key = _normalizeName(table);
    if (_tables.containsKey(key)) throw TableAlreadyExistsException(key);
    _addNamespaceOf(table);
    table.setSchemaConfig(_schemaConfig);
    _tables[key] = table;
  }

  void _addSequence(Sequence sequence) {
    final key = _normalizeName(sequence);
    if (_sequences.containsKey(key)) {
      throw SequenceAlreadyExistsException(key);
    }
    _addNamespaceOf(sequence);
    _sequences[key] = sequence;
  }

  /// A qualified asset outside the default namespace brings its namespace.
  void _addNamespaceOf(AbstractAsset asset) {
    final namespace = asset.getNamespaceName();
    if (namespace != null &&
        !asset.isInDefaultNamespace(getName()) &&
        !hasNamespace(namespace)) {
      createNamespace(namespace);
    }
  }

  /// `namespace.name` in lower case, the key of tables and sequences.
  String _normalizeName(AbstractAsset asset) =>
      _qualify(asset.getName()).toLowerCase();

  String _qualify(String name) {
    final unquoted = trimQuotes(name);
    return unquoted.contains('.') ? unquoted : '${getName()}.$unquoted';
  }

  String _key(String name) => _qualify(name).toLowerCase();

  // ---------------------------------------------------------- namespaces

  List<String> getNamespaces() => List.unmodifiable(_namespaces.values);

  bool hasNamespace(String name) =>
      _namespaces.containsKey(trimQuotes(name).toLowerCase());

  Schema createNamespace(String name) {
    final key = trimQuotes(name).toLowerCase();
    if (_namespaces.containsKey(key)) {
      throw NamespaceAlreadyExistsException(key);
    }
    _namespaces[key] = name;
    return this;
  }

  // -------------------------------------------------------------- tables

  List<Table> getTables() => List.unmodifiable(_tables.values);

  bool hasTable(String name) => _tables.containsKey(_key(name));

  Table getTable(String name) =>
      _tables[_key(name)] ?? (throw TableDoesNotExistException(_key(name)));

  /// A new table with the default table options of the [SchemaConfig].
  Table createTable(String name) {
    final table = Table(name, schemaConfig: _schemaConfig);
    _schemaConfig.getDefaultTableOptions().forEach(table.addOption);
    _addTable(table);
    return table;
  }

  Schema renameTable(String oldName, String newName) {
    final table = getTable(oldName);
    _tables.remove(_key(oldName));
    table.setName(newName);
    _addTable(table);
    return this;
  }

  Schema dropTable(String name) {
    getTable(name);
    _tables.remove(_key(name));
    return this;
  }

  // ----------------------------------------------------------- sequences

  List<Sequence> getSequences() => List.unmodifiable(_sequences.values);

  bool hasSequence(String name) => _sequences.containsKey(_key(name));

  Sequence getSequence(String name) =>
      _sequences[_key(name)] ??
      (throw SequenceDoesNotExistException(_key(name)));

  Sequence createSequence(String name, {int cache = 1, int initialValue = 1}) {
    final sequence = Sequence(name, cache: cache, initialValue: initialValue);
    _addSequence(sequence);
    return sequence;
  }

  Schema dropSequence(String name) {
    getSequence(name);
    _sequences.remove(_key(name));
    return this;
  }

  // ----------------------------------------------------------------- SQL

  /// The statements that create this schema on [platform].
  List<String> toSql(AbstractPlatform platform) =>
      platform.getCreateSchemaObjectsSQL(this);

  /// The statements that drop this schema's objects on [platform].
  List<String> toDropSql(AbstractPlatform platform) =>
      platform.getDropSchemaObjectsSQL(this);

  /// A deep copy.
  Schema clone() => Schema(
        tables: [for (final table in _tables.values) table.clone()],
        sequences: [for (final sequence in _sequences.values) sequence.clone()],
        schemaConfig: _schemaConfig,
        namespaces: List.of(_namespaces.values),
      );
}
