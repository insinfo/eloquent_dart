import 'package:eloquent/eloquent.dart';

/// in PHP is \Illuminate\Database\Schema\Grammars\Grammar
class SchemaGrammar extends BaseGrammar {
  ///
  /// The possible column modifiers.
  ///
  /// @var array
  ///
  List<String> modifiers = [];

  ///
  /// Compile the query to determine if a table exists.
  ///
  /// @return string
  ///
  String compileTableExists() {
    return 'select * from information_schema.tables where table_name = ?';
  }

  ///
  /// Compile the query to determine the list of columns.
  ///
  /// @param  string  $table
  /// @return string
  ///
  String compileColumnExists(String table) {
    return "select column_name from information_schema.columns where table_name = '$table'";
  }

  ///
  /// Compile a rename column command.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Illuminate\Support\Fluent  $command
  /// @param  \Illuminate\Database\Connection  $connection
  /// @return array
  ///
  dynamic compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    var schema = connection.getDoctrineSchemaManager();

    var table = this.getTablePrefix() + blueprint.getTable();

    var column = connection.getDoctrineColumn(table, command['from']);

    var tableDiff = this.getRenamedDiff(blueprint, command, column, schema);

    return schema.getDatabasePlatform().getAlterTableSQL(tableDiff);
  }

  ///
  /// Get a new column instance with the new column name.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Illuminate\Support\Fluent  $command
  /// @param  \Doctrine\DBAL\Schema\Column  $column
  /// @param  \Doctrine\DBAL\Schema\AbstractSchemaManager  $schema
  /// @return \Doctrine\DBAL\Schema\TableDiff
  ///
  dynamic getRenamedDiff(
      Blueprint blueprint, Fluent command, dynamic column, dynamic schema) {
    var tableDiff = this.getDoctrineTableDiff(blueprint, schema);
    return this.setRenamedColumns(tableDiff, command, column);
  }

  ///
  /// Set the renamed columns on the table diff.
  ///
  /// @param  \Doctrine\DBAL\Schema\TableDiff  $tableDiff
  /// @param  \Illuminate\Support\Fluent  $command
  /// @param  \Doctrine\DBAL\Schema\Column  $column
  /// @return \Doctrine\DBAL\Schema\TableDiff
  ///
  dynamic setRenamedColumns(dynamic tableDiff, Fluent command, dynamic column) {
    // $newColumn = new Column($command->to, $column->getType(), $column->toArray());
    // $tableDiff->renamedColumns = [$command->from => $newColumn];
    // return $tableDiff;
  }

  ///
  /// Compile a foreign key command.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Illuminate\Support\Fluent  $command
  /// @return string
  ///
  String compileForeign(Blueprint $blueprint, Fluent command) {
    var table = this.wrapTable($blueprint);

    var on = this.wrapTable(command['on']);

    // We need to prepare several of the elements of the foreign key definition
    // before we can create the SQL, such as wrapping the tables and convert
    // an array of columns to comma-delimited strings for the SQL queries.
    var columns = this.columnize(command['columns']);

    var onColumns = this.columnize(command['references']);

    var sql = "alter table {$table} add constraint {$command->index} ";

    sql += "foreign key (${columns}) references ${on} (${onColumns})";

    // Once we have the basic foreign key creation statement constructed we can
    // build out the syntax for what should happen on an update or delete of
    // the affected columns, which will get something like "cascade", etc.
    if (!Utils.is_null(command['onDelete'])) {
      sql += " on delete ${command['onDelete']}";
    }

    if (!Utils.is_null(command['onUpdate'])) {
      sql += " on update {$command['onUpdate']}";
    }

    return sql;
  }

  ///
  /// Compile the blueprint's column definitions.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint $blueprint
  /// @return array
  ///
  dynamic getColumns(Blueprint blueprint) {
    var columns = [];

    for (var column in blueprint.getAddedColumns()) {
      // Each of the column types have their own compiler functions which are tasked
      // with turning the column definition into its SQL format for this platform
      // used by the connection. The column's modifiers are compiled and added.
      var sql = this.wrap(column) + ' ' + this.getType(column);

      columns.add(this.addModifiers(sql, blueprint, column));
    }

    return columns;
  }

  ///
  /// Add the column modifiers to the definition.
  ///
  /// @param  string  $sql
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Illuminate\Support\Fluent  $column
  /// @return string
  ///
  String addModifiers(sql, Blueprint blueprint, Fluent column) {
    // for (var modifier in this.modifiers) {
    //   var method = "modify${modifier}";
    //   // if (Utils.method_exists(this, method)) {
    //   //   //sql += this.{$method}(blueprint, column);
    //   //   sql += Utils.call_method(this, method, [blueprint, column]);
    //   // }

    // }
    // return sql;

    throw UnimplementedError();
  }

  ///
  /// Get the primary key command if it exists on the blueprint.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  string  $name
  /// @return \Illuminate\Support\Fluent|null
  ///
  dynamic getCommandByName(Blueprint blueprint, String name) {
    var commands = this.getCommandsByName(blueprint, name);

    if (Utils.count(commands) > 0) {
      // return reset(commands);
      return commands;
    }
  }

  ///
  /// Get all of the commands with a given name.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  string  $name
  /// @return array
  ///
  List getCommandsByName(Blueprint blueprint, name) {
    return Utils.array_filter(blueprint.getCommands(), (value) {
      return value['name'] == name;
    });
  }

  ///
  /// Get the SQL for the column data type.
  ///
  /// @param  \Illuminate\Support\Fluent  $column
  /// @return string
  ///
  String getType(Fluent column) {
    //return this.{'type'.ucfirst($column->type)}($column);
    // return Utils.call_method(
    //     this, 'type' + Utils.ucfirst(column['type']), [column]);
    throw UnimplementedError();
  }

  ///
  /// Add a prefix to an array of values.
  ///
  /// @param  string  $prefix
  /// @param  array   $values
  /// @return array
  ///
  List prefixArray(String prefix, List values) {
    return Utils.array_map((value) {
      return prefix + ' ' + value;
    }, values);
  }

  ///
  /// Wrap a table in keyword identifiers.
  ///
  /// @param  mixed   $table
  /// @return string
  ///
  String wrapTable(dynamic table) {
    if (table is Blueprint) {
      table = table.getTable();
    }

    return super.wrapTable(table);
  }

  ///
  /// {@inheritdoc}
  ///
  String wrap(dynamic value, [bool prefixAlias = false]) {
    if (value is Fluent) {
      value = value['name'];
    }

    return super.wrap(value, prefixAlias);
  }

  ///
  /// Format a value so that it can be used in "default" clauses.
  ///
  /// @param  mixed   $value
  /// @return string
  ///
  dynamic getDefaultValue(dynamic value) {
    if (value is QueryExpression) {
      return value;
    }

    if (Utils.is_bool(value)) {
      return "'" + value + "'";
    }

    return "'" + Utils.strval(value) + "'";
  }

  ///
  /// Create an empty Doctrine DBAL TableDiff from the Blueprint.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Doctrine\DBAL\Schema\AbstractSchemaManager  $schema
  /// @return \Doctrine\DBAL\Schema\TableDiff
  ///
  dynamic getDoctrineTableDiff(Blueprint blueprint, dynamic schema) {
    // $table = this.getTablePrefix().$blueprint->getTable();
    // $tableDiff = new TableDiff($table);
    // $tableDiff->fromTable = $schema->listTableDetails($table);
    // return $tableDiff;
  }

  ///
  /// Compile a change column command into a series of SQL statements.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Illuminate\Support\Fluent  $command
  /// @param  \Illuminate\Database\Connection $connection
  /// @return array
  ///
  dynamic compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    // if (! $connection->isDoctrineAvailable()) {
    //     throw new RuntimeException(sprintf(
    //         'Changing columns for table "%s" requires Doctrine DBAL; install "doctrine/dbal".',
    //         $blueprint->getTable()
    //     ));
    // }

    // $schema = $connection->getDoctrineSchemaManager();

    // $tableDiff = this.getChangedDiff($blueprint, $schema);

    // if ($tableDiff !== false) {
    //     return (array) $schema->getDatabasePlatform()->getAlterTableSQL($tableDiff);
    // }

    // return [];
  }

  ///
  /// Get the Doctrine table difference for the given changes.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Doctrine\DBAL\Schema\AbstractSchemaManager  $schema
  /// @return \Doctrine\DBAL\Schema\TableDiff|bool
  ///
  dynamic getChangedDiff(Blueprint blueprint, dynamic schema) {
    // $table = $schema->listTableDetails(this.getTablePrefix().$blueprint->getTable());
    // return (new Comparator)->diffTable($table, this.getTableWithColumnChanges($blueprint, $table));
  }

  ///
  /// Get a copy of the given Doctrine table after making the column changes.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @param  \Doctrine\DBAL\Schema\Table  $table
  /// @return \Doctrine\DBAL\Schema\TableDiff
  ///
  dynamic getTableWithColumnChanges(Blueprint blueprint, dynamic table) {
    // $table = clone $table;
    // foreach ($blueprint->getChangedColumns() as $fluent) {
    //     $column = this.getDoctrineColumnForChange($table, $fluent);

    //     // Here we will spin through each fluent column definition and map it to the proper
    //     // Doctrine column definitions - which is necessary because Laravel and Doctrine
    //     // use some different terminology for various column attributes on the tables.
    //     foreach ($fluent->getAttributes() as $key => $value) {
    //         if (! is_null($option = this.mapFluentOptionToDoctrine($key))) {
    //             if (method_exists($column, $method = 'set'.ucfirst($option))) {
    //                 $column->{$method}(this.mapFluentValueToDoctrine($option, $value));
    //             }
    //         }
    //     }
    // }
    // return $table;
  }

  ///
  /// Get the Doctrine column instance for a column change.
  ///
  /// @param  \Doctrine\DBAL\Schema\Table  $table
  /// @param  \Illuminate\Support\Fluent  $fluent
  /// @return \Doctrine\DBAL\Schema\Column
  ///
  dynamic getDoctrineColumnForChange(dynamic table, Fluent fluent) {
    // return $table->changeColumn(
    //     $fluent['name'], this.getDoctrineColumnChangeOptions($fluent)
    // )->getColumn($fluent['name']);
  }

  ///
  /// Get the Doctrine column change options.
  ///
  /// @param  \Illuminate\Support\Fluent  $fluent
  /// @return array
  ///
  dynamic getDoctrineColumnChangeOptions(Fluent fluent) {
    // $options = ['type' => this.getDoctrineColumnType($fluent['type'])];

    // if (in_array($fluent['type'], ['text', 'mediumText', 'longText'])) {
    //     $options['length'] = this.calculateDoctrineTextLength($fluent['type']);
    // }

    // return $options;
  }

  ///
  /// Get the doctrine column type.
  ///
  /// @param  string  $type
  /// @return \Doctrine\DBAL\Types\Type
  ///
  dynamic getDoctrineColumnType($type) {
    // $type = strtolower($type);

    // switch ($type) {
    //     case 'biginteger':
    //         $type = 'bigint';
    //         break;
    //     case 'smallinteger':
    //         $type = 'smallint';
    //         break;
    //     case 'mediumtext':
    //     case 'longtext':
    //         $type = 'text';
    //         break;
    // }

    // return Type::getType($type);
  }

  ///
  /// Calculate the proper column length to force the Doctrine text type.
  ///
  /// @param  string  $type
  /// @return int
  ///
  dynamic calculateDoctrineTextLength(String type) {
    switch (type) {
      case 'mediumText':
        return 65535 + 1;

      case 'longText':
        return 16777215 + 1;

      default:
        return 255 + 1;
    }
  }

  ///
  /// Get the matching Doctrine option for a given Fluent attribute name.
  ///
  /// @param  string  $attribute
  /// @return string|null
  ///
  dynamic mapFluentOptionToDoctrine($attribute) {
    switch ($attribute) {
      case 'type':
      case 'name':
        return;

      case 'nullable':
        return 'notnull';

      case 'total':
        return 'precision';

      case 'places':
        return 'scale';

      default:
        return $attribute;
    }
  }

  ///
  /// Get the matching Doctrine value for a given Fluent attribute.
  ///
  /// @param  string  $option
  /// @param  mixed  $value
  /// @return mixed
  ///
  dynamic mapFluentValueToDoctrine(String option, dynamic value) {
    return option == 'notnull' ? !value : value;
  }
}
