// File: C:\MyDartProjects\eloquent\lib\src\doctrine\schema.dart
import 'dart:collection'; // Para LinkedHashMap se a ordem for importante

import '../patforms/abstract_platform.dart'; // Dependência futura
// Importar as classes de schema e exceptions necessárias
import 'abstract_asset.dart';
import 'table.dart';
import 'sequence.dart';
import 'schema_config.dart';
import 'doctrine_schema_exceptions.dart'; // Arquivo para as exceptions

/// Object representation of a database schema.
///
/// Corresponds to Doctrine\DBAL\Schema\Schema.
/// Wraps a set of database objects like tables, sequences, etc.
class Schema extends AbstractAsset {
  /// The namespaces in this schema (lowercase name -> original name).
  final Map<String, String> _namespaces = LinkedHashMap();

  /// Tables in this schema (lowercase qualified name -> Table).
  final Map<String, Table> _tables = LinkedHashMap();

  /// Sequences in this schema (lowercase qualified name -> Sequence).
  final Map<String, Sequence> _sequences = LinkedHashMap();

  /// Configuration for this schema.
  late SchemaConfig _schemaConfig;

  /// Creates a new Schema instance.
  ///
  /// [tables] - Initial list of tables to add.
  /// [sequences] - Initial list of sequences to add.
  /// [schemaConfig] - Configuration settings for the schema.
  /// [namespaces] - Initial list of namespace names.
  Schema({
    List<Table> tables = const [],
    List<Sequence> sequences = const [],
    SchemaConfig? schemaConfig,
    List<String> namespaces = const [],
  }) {
    _schemaConfig = schemaConfig ?? SchemaConfig();

    final schemaName = _schemaConfig.getName();
    if (schemaName != null && schemaName.isNotEmpty) {
      // Use o método setName da classe base (SchemaAsset)
      setName(schemaName);
    } else {
      // Se o nome da configuração for nulo ou vazio, precisamos de um nome padrão
      // ou lançar um erro. Vamos definir um nome padrão temporário ou exigir um.
      // Poderia usar 'public' como padrão, mas depender do nome é mais seguro.
      // Lançar um erro pode ser melhor se um nome for sempre esperado.
      // Por agora, vamos definir um nome interno padrão se não houver um explícito.
      // Define um nome interno se não houver um nome explícito
      // A lógica de getName() deve retornar isso se _name não for definido
      name =
          'default_schema'; // Ou lance um erro: throw ArgumentError('Schema name is required.');
    }

    for (final namespace in namespaces) {
      createNamespace(namespace);
    }
    for (final table in tables) {
      _addTable(table);
    }
    for (final sequence in sequences) {
      _addSequence(sequence);
    }
  }

  /// Internal method to add a table, performing checks and normalization.
  void _addTable(Table table) {
    // TODO: Implement table.getNamespaceName() and table.isInDefaultNamespace()
    // String? namespaceName = table.getNamespaceName(); // Needs implementation in Table

    final tableName = _normalizeName(table);

    if (_tables.containsKey(tableName)) {
      throw TableAlreadyExistsException(tableName);
    }

    // TODO: Re-enable namespace check when Table methods are available
    /*
    if (namespaceName != null &&
        !table.isInDefaultNamespace(getName()) && // Needs implementation in Table
        !hasNamespace(namespaceName)) {
      createNamespace(namespaceName);
    }
    */

    _tables[tableName] = table;
    // TODO: Implement table.setSchemaConfig()
    // table.setSchemaConfig(_schemaConfig); // Needs implementation in Table
  }

  /// Internal method to add a sequence, performing checks and normalization.
  void _addSequence(Sequence sequence) {
    // TODO: Implement sequence.getNamespaceName() and sequence.isInDefaultNamespace()
    // String? namespaceName = sequence.getNamespaceName(); // Needs implementation in Sequence

    final seqName = _normalizeName(sequence);

    if (_sequences.containsKey(seqName)) {
      throw SequenceAlreadyExistsException(seqName);
    }

    // TODO: Re-enable namespace check when Sequence methods are available
    /*
    if (namespaceName != null &&
        !sequence.isInDefaultNamespace(getName()) && // Needs implementation in Sequence
        !hasNamespace(namespaceName)) {
      createNamespace(namespaceName);
    }
    */

    _sequences[seqName] = sequence;
  }

  /// Returns the list of namespace names in this schema.
  List<String> getNamespaces() {
    return List.unmodifiable(_namespaces.values);
  }

  /// Gets all tables of this schema.
  List<Table> getTables() {
    return List.unmodifiable(_tables.values);
  }

  /// Gets a specific table by name.
  ///
  /// Throws [TableDoesNotExistException] if the table is not found.
  Table getTable(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    if (!_tables.containsKey(qualifiedName)) {
      throw TableDoesNotExistException(qualifiedName);
    }
    return _tables[qualifiedName]!;
  }

  /// Gets the fully qualified and normalized (lowercase) name for an asset.
  /// If the name is not qualified, it assumes the current schema's name.
  String _getFullQualifiedAssetName(String name) {
    final unquotedName = _getUnquotedAssetName(name);

    if (!unquotedName.contains('.')) {
      // getName() deve retornar o nome do schema atual (definido no construtor ou padrão)
      final currentSchemaName = getName(); // Método herdado de SchemaAsset
      if (currentSchemaName.isEmpty) {
        throw StateError(
            'Cannot qualify asset name "$unquotedName" because the current schema name is not set.');
      }
      return '$currentSchemaName.$unquotedName'.toLowerCase();
    }

    return unquotedName.toLowerCase();
  }

  /// Normalizes an asset's name to be qualified and lowercased.
  String _normalizeName(AbstractAsset asset) {
    // TODO: Implement asset.getNamespaceName() in subclasses of SchemaAsset if needed
    // String? namespaceName = asset.getNamespaceName(); // Needs implementation

    String assetName = asset.getName(); // Gets the unquoted name

    // TODO: Re-enable namespace logic when getNamespaceName is available
    /*
    if (namespaceName == null) {
      final currentSchemaName = getName(); // Método herdado
      if (currentSchemaName.isEmpty) {
         throw StateError('Cannot normalize asset name "${asset.name}" because the current schema name is not set.');
      }
      assetName = '$currentSchemaName.$assetName';
    } else {
      // Assumes getName() might already return qualified if namespace is set
      // Need consistent way to get qualified name from asset
      assetName = '$namespaceName.$assetName'; // Or use a dedicated getQualifiedName method
    }
    */

    // Simplified logic for now: qualify if not already qualified
    if (!assetName.contains('.')) {
      final currentSchemaName = getName();
      if (currentSchemaName.isEmpty) {
        throw StateError(
            'Cannot normalize asset name "${asset.name}" because the current schema name is not set.');
      }
      assetName = '$currentSchemaName.$assetName';
    }

    return assetName.toLowerCase();
  }

  /// Returns the unquoted representation of a given asset name.
  String _getUnquotedAssetName(String assetName) {
    // Reuse method from SchemaAsset
    return trimQuotes(assetName);
  }

  /// Checks if this schema has a namespace with the given name (case-insensitive).
  bool hasNamespace(String name) {
    final normalizedName = _getUnquotedAssetName(name).toLowerCase();
    return _namespaces.containsKey(normalizedName);
  }

  /// Checks if this schema has a table with the given name (case-insensitive, qualified).
  bool hasTable(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    return _tables.containsKey(qualifiedName);
  }

  /// Checks if this schema has a sequence with the given name (case-insensitive, qualified).
  bool hasSequence(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    return _sequences.containsKey(qualifiedName);
  }

  /// Gets a specific sequence by name.
  ///
  /// Throws [SequenceDoesNotExistException] if the sequence is not found.
  Sequence getSequence(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    if (!hasSequence(qualifiedName)) {
      // Pass qualified name to exception for clarity
      throw SequenceDoesNotExistException(qualifiedName);
    }
    return _sequences[qualifiedName]!;
  }

  /// Gets all sequences of this schema.
  List<Sequence> getSequences() {
    return List.unmodifiable(_sequences.values);
  }

  /// Creates a new namespace within the schema.
  ///
  /// Throws [NamespaceAlreadyExistsException] if the namespace already exists.
  Schema createNamespace(String name) {
    final unquotedName = _getUnquotedAssetName(name);
    final normalizedName = unquotedName.toLowerCase();

    if (_namespaces.containsKey(normalizedName)) {
      throw NamespaceAlreadyExistsException(normalizedName);
    }

    _namespaces[normalizedName] = name; // Store original name as value
    return this;
  }

  /// Creates a new table and adds it to the schema.
  /// Applies default table options from the schema configuration.
  Table createTable(String name) {
    final table = Table(name, schemaConfig: _schemaConfig); // Pass config
    _addTable(table);

    // Apply default options AFTER adding (addTable might set config)
    final defaultOptions = _schemaConfig.getDefaultTableOptions();
    defaultOptions.forEach((option, value) {
      // TODO: Implement table.addOption()
      // table.addOption(option, value); // Needs implementation in Table
      print(
          "TODO: Apply default table option '$option' = '$value' to table '${table.name}' via table.addOption()");
    });

    return table;
  }

  /// Renames a table within the schema.
  Schema renameTable(String oldName, String newName) {
    final table = getTable(oldName); // Throws if oldName doesn't exist

    // TODO: Implement table.setName() - Ensure it updates the internal name correctly
    // table.setName(newName); // Needs implementation in Table
    table.name =
        newName; // Direct modification for now, assuming `name` is public/settable

    dropTable(oldName); // Remove the old entry
    _addTable(
        table); // Add the table back with the potentially new normalized key

    return this;
  }

  /// Drops a table from the schema.
  Schema dropTable(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    getTable(qualifiedName); // Ensure it exists before dropping
    _tables.remove(qualifiedName);
    return this;
  }

  /// Creates a new sequence and adds it to the schema.
  ///
  /// [cache] corresponds to Doctrine's allocationSize.
  Sequence createSequence(String name, {int cache = 1, int initialValue = 1}) {
    final seq = Sequence(name, cache: cache, initialValue: initialValue);
    _addSequence(seq);
    return seq;
  }

  /// Drops a sequence from the schema.
  Schema dropSequence(String name) {
    final qualifiedName = _getFullQualifiedAssetName(name);
    // Optionally check existence before removing
    if (hasSequence(qualifiedName)) {
      _sequences.remove(qualifiedName);
    } else {
      print(
          "Warning: Attempted to drop non-existent sequence '$qualifiedName'.");
      // Or throw SequenceDoesNotExistException(qualifiedName);
    }
    return this;
  }

  /// Returns an array of necessary SQL queries to create the schema on the given platform.
  /// **NOTE:** Requires `AbstractPlatform` and `CreateSchemaObjectsSQLBuilder` implementations.
  List<String> toSql(AbstractPlatform platform) {
    // TODO: Implement CreateSchemaObjectsSQLBuilder similar to Doctrine
    // final builder = CreateSchemaObjectsSQLBuilder(platform);
    // return builder.buildSQL(this);
    throw UnimplementedError(
        'Schema.toSql requires CreateSchemaObjectsSQLBuilder implementation.');
  }

  /// Returns an array of necessary SQL queries to drop the schema on the given platform.
  /// **NOTE:** Requires `AbstractPlatform` and `DropSchemaObjectsSQLBuilder` implementations.
  List<String> toDropSql(AbstractPlatform platform) {
    // TODO: Implement DropSchemaObjectsSQLBuilder similar to Doctrine
    // final builder = DropSchemaObjectsSQLBuilder(platform);
    // return builder.buildSQL(this);
    throw UnimplementedError(
        'Schema.toDropSql requires DropSchemaObjectsSQLBuilder implementation.');
  }

  /// Creates a deep clone of the Schema and its contained assets.

  Schema clone() {
    final clonedTables = _tables.values.map((table) => table.clone()).toList();
    final clonedSequences =
        _sequences.values.map((seq) => seq.clone()).toList();
    final clonedNamespaces = List<String>.from(_namespaces.values);

    // Clone config or share reference? Let's share reference for now.
    // If config is mutable, it should be cloned too.
    final clonedSchemaConfig = _schemaConfig; //.clone();

    return Schema(
      tables: clonedTables,
      sequences: clonedSequences,
      schemaConfig: clonedSchemaConfig,
      namespaces: clonedNamespaces,
    );
    // Note: The original constructor sets the name from config.
    // If the cloned config has the name, it should be set correctly.
    // If the original schema name was set manually after construction,
    // the clone might need manual name setting too if config doesn't have it.
  }
}
