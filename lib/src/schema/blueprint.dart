import 'package:eloquent/eloquent.dart';

/// namespace Illuminate\Database\Schema;
class Blueprint {
  ///
  /// The table the blueprint describes.
  ///
  /// @var string
  ///
  String? _table;

  ///
  /// The columns that should be added to the table.
  ///
  /// @var array
  ///
  List _columns = [];

  ///
  /// The commands that should be run for the table.
  ///
  /// @var array
  ///
  List<Fluent> _commands = [];

  ///
  /// The storage engine that should be used for the table.
  ///
  /// @var string
  ///
  String? engine;

  ///
  /// The default character set that should be used for the table.
  ///
  String? charset;

  ///
  /// The collation that should be used for the table.
  ///
  String? collation;

  ///
  /// Whether to make the table temporary.
  ///
  /// @var bool
  ///
  bool temporaryV = false;

  ///
  /// Create a new schema blueprint.
  ///
  /// @param  string  $table
  /// @param  \Closure|null  $callback
  /// @return void
  ///
  Blueprint(String tableP, [Function? callback]) {
    _table = tableP;

    if (!Utils.is_null(callback)) {
      callback!(this);
    }
  }

  ///
  /// Execute the blueprint against the database.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  /// @param  \Illuminate\Database\Schema\Grammars\Grammar $grammar
  /// @return void
  ///
  void build(Connection connection, SchemaGrammar grammar) {
    for (var statement in toSql(connection, grammar)) {
      connection.statement(statement);
    }
  }

  ///
  /// Get the raw SQL statements for the blueprint.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  /// @param  \Illuminate\Database\Schema\Grammars\Grammar  $grammar
  /// @return array
  ///
  List toSql(Connection connection, SchemaGrammar grammar) {
    addImpliedCommands();

    // var statements = [];
    // Each type of command has a corresponding compiler function on the schema
    // grammar which is used to build the necessary SQL statements to build
    // the blueprint element, so we'll just call that compilers function.
    // Cada tipo de comando tem uma função de compilação correspondente no esquema
    // gramática que é usada para construir as instruções SQL necessárias para construir
    // o elemento blueprint, então vamos chamar essa função de compiladores.
    //for (var command in _commands) {
    //  var method = 'compile' + Utils.ucfirst(command['name']);

    // if (Utils.method_exists(grammar, method)) {
    //   var sql =
    //       Utils.call_method(grammar, method, [this, command, connection]);
    //   if (!Utils.is_null(sql)) {
    //     statements = Utils.array_merge(statements, sql as List);
    //   }
    // }
    //}
    // return statements;
    throw UnimplementedError();
  }

  ///
  /// Add the commands that are implied by the blueprint.
  ///
  /// @return void
  ///
  void addImpliedCommands() {
    if (Utils.count(getAddedColumns()) > 0 && !creating()) {
      Utils.array_unshift(_commands, createCommand('add'));
    }

    if (Utils.count(getChangedColumns()) > 0 && !creating()) {
      Utils.array_unshift(_commands, createCommand('change'));
    }

    addFluentIndexes();
  }

  ///
  /// Add the index commands fluently specified on columns.
  ///
  /// @return void
  ///
  void addFluentIndexes() {
    // for (var column in columns  ) {
    //     for (var index in ['primary', 'unique', 'index'] ) {
    //         // If the index has been specified on the given column, but is simply
    //         // equal to "true" (boolean), no name has been specified for this
    //         // index, so we will simply call the index methods without one.
    //         if ($column->$index == true) {
    //             this.$index($column->name);

    //             continue 2;
    //         }

    //         // If the index has been specified on the column and it is something
    //         // other than boolean true, we will assume a name was provided on
    //         // the index specification, and pass in the name to the method.
    //         else if (isset($column->$index)) {
    //             this.$index($column->name, $column->$index);

    //             continue 2;
    //         }
    //     }
    // }
  }

  ///
  /// Determine if the blueprint has a create command.
  ///
  /// @return bool
  ///
  bool creating() {
    for (var command in _commands) {
      if (command['name'] == 'create') {
        return true;
      }
    }

    return false;
  }

  ///
  /// Indicate that the table needs to be created.
  ///
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent create() {
    return addCommand('create');
  }

  ///
  /// Indicate that the table needs to be temporary.
  ///
  /// @return void
  ///
  void temporary() {
    temporaryV = true;
  }

  ///
  /// Indicate that the table should be dropped.
  ///
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent drop() {
    return addCommand('drop');
  }

  ///
  /// Indicate that the table should be dropped if it exists.
  ///
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropIfExists() {
    return addCommand('dropIfExists');
  }

  ///
  /// Indicate that the given columns should be dropped.
  ///
  /// @param  array|mixed  $columns
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropColumn(dynamic columnsP,
      [dynamic col1, dynamic col2, dynamic col3, dynamic col4, dynamic col5]) {
    var func_get_args = [];
    if (col1 != null) {
      func_get_args.add(col1);
    }
    if (col2 != null) {
      func_get_args.add(col2);
    }
    if (col3 != null) {
      func_get_args.add(col3);
    }
    if (col4 != null) {
      func_get_args.add(col4);
    }
    if (col5 != null) {
      func_get_args.add(col5);
    }
    var cols =
        Utils.is_array(columnsP) ? columnsP : func_get_args; //func_get_args()

    return addCommand('dropColumn', {'columns': cols});
  }

  ///
  /// Indicate that the given columns should be renamed.
  ///
  /// @param  string  $from
  /// @param  string  $to
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent renameColumn(String from, String to) {
    return addCommand('renameColumn', {'from': from, 'to': to});
  }

  ///
  /// Indicate that the given primary key should be dropped.
  ///
  /// @param  string|array  $index
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropPrimary([dynamic index = null]) {
    return dropIndexCommand('dropPrimary', 'primary', index);
  }

  ///
  /// Indicate that the given unique key should be dropped.
  ///
  /// @param  string|array  $index
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropUnique(dynamic index) {
    return dropIndexCommand('dropUnique', 'unique', index);
  }

  ///
  /// Indicate that the given index should be dropped.
  ///
  /// @param  string|array  $index
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropIndex(dynamic index) {
    return dropIndexCommand('dropIndex', 'index', index);
  }

  ///
  /// Indicate that the given foreign key should be dropped.
  ///
  /// @param  string  $index
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent dropForeign(String index) {
    return dropIndexCommand('dropForeign', 'foreign', index);
  }

  ///
  /// Indicate that the timestamp columns should be dropped.
  ///
  /// @return void
  ///
  void dropTimestamps() {
    dropColumn('created_at', 'updated_at');
  }

  ///
  /// Indicate that the timestamp columns should be dropped.
  ///
  /// @return void
  ///
  void dropTimestampsTz() {
    dropTimestamps();
  }

  ///
  /// Indicate that the soft delete column should be dropped.
  ///
  /// @return void
  ///
  void dropSoftDeletes() {
    dropColumn('deleted_at');
  }

  ///
  /// Indicate that the remember token column should be dropped.
  ///
  /// @return void
  ///
  void dropRememberToken() {
    dropColumn('remember_token');
  }

  ///
  /// Rename the table to a given name.
  ///
  /// @param  string  $to
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent rename(String to) {
    return addCommand('rename', {'to': to});
  }

  ///
  /// Specify the primary key(s) for the table.
  ///
  /// @param  string|array  $columns
  /// @param  string  $name
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent primary(dynamic columns, [String? name]) {
    return indexCommand('primary', columns, name);
  }

  ///
  /// Specify a unique index for the table.
  ///
  /// @param  string|array  $columns
  /// @param  string  $name
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent unique(dynamic columns, [String? name]) {
    return indexCommand('unique', columns, name);
  }

  ///
  /// Specify an index for the table.
  ///
  /// @param  string|array  $columns
  /// @param  string  $name
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent index(dynamic columns, [String? name]) {
    return indexCommand('index', columns, name);
  }

  ///
  /// Specify a foreign key for the table.
  ///
  /// @param  string|array  $columns
  /// @param  string  $name
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent foreign(dynamic columns, [String? name]) {
    return indexCommand('foreign', columns, name);
  }

  ///
  /// Create a new auto-incrementing integer (4-byte) column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent increments(String column) {
    return unsignedInteger(column, true);
  }

  ///
  /// Create a new auto-incrementing small integer (2-byte) column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent smallIncrements(String column) {
    return unsignedSmallInteger(column, true);
  }

  ///
  /// Create a new auto-incrementing medium integer (3-byte) column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  mediumIncrements(String column) {
    return unsignedMediumInteger(column, true);
  }

  ///
  /// Create a new auto-incrementing big integer (8-byte) column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  bigIncrements(String column) {
    return unsignedBigInteger(column, true);
  }

  ///
  /// Create a new char column on the table.
  ///
  /// @param  string  $column
  /// @param  int  $length
  /// @return \Illuminate\Support\Fluent
  ///
  char(String column, [int length = 255]) {
    return this.addColumn('char', column, {'length': length});
  }

  ///
  /// Create a new string column on the table.
  ///
  /// @param  string  $column
  /// @param  int  $length
  /// @return \Illuminate\Support\Fluent
  ///
  string(String column, [int length = 255]) {
    return this.addColumn('string', column, {'length': length});
  }

  ///
  /// Create a new text column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  text(String column) {
    return this.addColumn('text', column);
  }

  ///
  /// Create a new medium text column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  mediumText(String column) {
    return this.addColumn('mediumText', column);
  }

  ///
  /// Create a new long text column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  longText(String column) {
    return this.addColumn('longText', column);
  }

  ///
  /// Create a new integer (4-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @param  bool  $unsigned
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent integer(String column,
      [bool autoIncrement = false, bool unsigned = false]) {
    return addColumn('integer', column,
        {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  }

  ///
  /// Create a new tiny integer (1-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @param  bool  $unsigned
  /// @return \Illuminate\Support\Fluent
  ///
  tinyInteger(String column, [bool autoIncrement = false, unsigned = false]) {
    return addColumn('tinyInteger', column,
        {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  }

  ///
  /// Create a new small integer (2-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @param  bool  $unsigned
  /// @return \Illuminate\Support\Fluent
  ///
  smallInteger(String column,
      [bool autoIncrement = false, bool unsigned = false]) {
    return addColumn('smallInteger', column,
        {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  }

  ///
  /// Create a new medium integer (3-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @param  bool  $unsigned
  /// @return \Illuminate\Support\Fluent
  ///
  mediumInteger(String column,
      [bool autoIncrement = false, bool unsigned = false]) {
    return addColumn('mediumInteger', column,
        {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  }

  ///
  /// Create a new big integer (8-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @param  bool  $unsigned
  /// @return \Illuminate\Support\Fluent
  ///
  bigInteger(String column,
      [bool autoIncrement = false, bool unsigned = false]) {
    return addColumn('bigInteger', column,
        {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  }

  ///
  /// Create a new unsigned tiny integer (1-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @return \Illuminate\Support\Fluent
  ///
  unsignedTinyInteger(String column, [bool autoIncrement = false]) {
    return tinyInteger(column, autoIncrement, true);
  }

  ///
  /// Create a new unsigned small integer (2-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @return \Illuminate\Support\Fluent
  ///
  unsignedSmallInteger(String column, [bool autoIncrement = false]) {
    return smallInteger(column, autoIncrement, true);
  }

  ///
  /// Create a new unsigned medium integer (3-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @return \Illuminate\Support\Fluent
  ///
  unsignedMediumInteger(String column, [bool autoIncrement = false]) {
    return mediumInteger(column, autoIncrement, true);
  }

  ///
  /// Create a new unsigned integer (4-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @return \Illuminate\Support\Fluent
  ///
  unsignedInteger(String column, [bool autoIncrement = false]) {
    return integer(column, autoIncrement, true);
  }

  ///
  /// Create a new unsigned big integer (8-byte) column on the table.
  ///
  /// @param  string  $column
  /// @param  bool  $autoIncrement
  /// @return \Illuminate\Support\Fluent
  ///
  unsignedBigInteger(String column, [bool autoIncrement = false]) {
    return bigInteger(column, autoIncrement, true);
  }

  ///
  /// Create a new float column on the table.
  ///
  /// @param  string  $column
  /// @param  int     $total
  /// @param  int     $places
  /// @return \Illuminate\Support\Fluent
  ///
  float(String column, [int total = 8, int places = 2]) {
    return addColumn('float', column, {'total': total, 'places': places});
  }

  ///
  /// Create a new double column on the table.
  ///
  /// @param  string   $column
  /// @param  int|null    $total
  /// @param  int|null $places
  /// @return \Illuminate\Support\Fluent
  ///
  double(String column, [int? total = null, int? places = null]) {
    return addColumn('double', column, {'total': total, 'places': places});
  }

  ///
  /// Create a new decimal column on the table.
  ///
  /// @param  string  $column
  /// @param  int     $total
  /// @param  int     $places
  /// @return \Illuminate\Support\Fluent
  ///
  decimal(String column, [int total = 8, int places = 2]) {
    return addColumn('decimal', column, {'total': total, 'places': places});
  }

  ///
  /// Create a new boolean column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  boolean(String column) {
    return addColumn('boolean', column);
  }

  ///
  /// Create a new enum column on the table.
  ///
  /// @param  string  $column
  /// @param  array   $allowed
  /// @return \Illuminate\Support\Fluent
  ///
  enumeration(String column, allowed) {
    return addColumn('enum', column, {'allowed': allowed});
  }

  ///
  /// Create a new json column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  json(String column) {
    return addColumn('json', column);
  }

  ///
  /// Create a new jsonb column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  jsonb(String column) {
    return addColumn('jsonb', column);
  }

  ///
  /// Create a new date column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  date(String column) {
    return addColumn('date', column);
  }

  ///
  /// Create a new date-time column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  dateTime(String column) {
    return addColumn('dateTime', column);
  }

  ///
  /// Create a new date-time column (with time zone) on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  dateTimeTz(String column) {
    return addColumn('dateTimeTz', column);
  }

  ///
  /// Create a new time column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  time(String column) {
    return addColumn('time', column);
  }

  ///
  /// Create a new time column (with time zone) on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  timeTz(String column) {
    return addColumn('timeTz', column);
  }

  ///
  /// Create a new timestamp column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent timestamp(String column) {
    return addColumn('timestamp', column);
  }

  ///
  /// Create a new timestamp (with time zone) column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  timestampTz(String column) {
    return addColumn('timestampTz', column);
  }

  ///
  /// Add nullable creation and update timestamps to the table.
  ///
  /// @return void
  ///
  nullableTimestamps() {
    // this.timestamp('created_at')->nullable();
    // this.timestamp('updated_at')->nullable();
  }

  ///
  /// Add creation and update timestamps to the table.
  ///
  /// @return void
  ///
  timestamps() {
    this.timestamp('created_at');
    this.timestamp('updated_at');
  }

  ///
  /// Add creation and update timestampTz columns to the table.
  ///
  /// @return void
  ///
  timestampsTz() {
    this.timestampTz('created_at');
    this.timestampTz('updated_at');
  }

  ///
  /// Add a "deleted at" timestamp for the table.
  ///
  /// @return \Illuminate\Support\Fluent
  ///
  softDeletes() {
    //return this.timestamp('deleted_at')->nullable();
  }

  ///
  /// Create a new binary column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  binary($column) {
    return this.addColumn('binary', $column);
  }

  ///
  /// Create a new uuid column on the table.
  ///
  /// @param  string  $column
  /// @return \Illuminate\Support\Fluent
  ///
  uuid($column) {
    return this.addColumn('uuid', $column);
  }

  ///
  /// Add the proper columns for a polymorphic table.
  ///
  /// @param  string  $name
  /// @param  string|null  $indexName
  /// @return void
  ///
  morphs(String name, [String? indexName]) {
    this.unsignedInteger("${name}_id");

    this.string("${name}_type");

    this.index(["${name}_id", "${name}_type"], indexName);
  }

  ///
  /// Adds the `remember_token` column to the table.
  ///
  /// @return \Illuminate\Support\Fluent
  ///
  rememberToken() {
    //return this.string('remember_token', 100)->nullable();
  }

  ///
  /// Create a new drop index command on the blueprint.
  ///
  /// @param  string  $command
  /// @param  string  $type
  /// @param  string|array  $index
  /// @return \Illuminate\Support\Fluent
  ///
  dropIndexCommand(String command, String type, dynamic index) {
    var cols = [];

    // If the given "index" is actually an array of columns, the developer means
    // to drop an index merely by specifying the columns involved without the
    // conventional name, so we will build the index name from the columns.
    if (Utils.is_array(index)) {
      cols = index;

      index = this.createIndexName(type, cols);
    }

    return this.indexCommand(command, cols, index);
  }

  ///
  /// Add a new index command to the blueprint.
  ///
  /// @param  string        $type
  /// @param  string|array  $columns
  /// @param  string        $index
  /// @return \Illuminate\Support\Fluent
  ///
  indexCommand(String type, dynamic columnsP, String? index) {
    var cols = columnsP;

    // If no name was specified for this index, we will create one using a basic
    // convention of the table name, followed by the columns, followed by an
    // index type, such as primary or index, which makes the index unique.
    if (Utils.is_null(index)) {
      index = this.createIndexName(type, cols);
    }

    return this.addCommand(type, {'index': index, 'columns': cols});
  }

  ///
  /// Create a default index name for the table.
  ///
  /// @param  string  $type
  /// @param  array   $columns
  /// @return string
  ///
  createIndexName(String type, List columns) {
    var index = Utils.strtolower(
        this._table! + '_' + Utils.implode('_', columns) + '_' + type);

    return Utils.str_replace(['-', '.'], '_', index);
  }

  ///
  /// Add a new column to the blueprint.
  ///
  /// @param  string  $type
  /// @param  string  $name
  /// @param  array   $parameters
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent addColumn(String type, String name,
      [Map<String, dynamic> parameters = const {}]) {
    var attributes =
        Utils.map_merge_sd({'type': type, 'name': name}, parameters);
    var column = new Fluent(attributes);
    this._columns.add(column);
    return column;
  }

  ///
  /// Remove a column from the schema blueprint.
  ///
  /// @param  string  $name
  /// @return $this
  ///
  removeColumn(String name) {
    // this.columns = array_values(array_filter(this.columns, function ($c) use ($name) {
    //     return $c['attributes']['name'] != $name;
    // }));

    return this;
  }

  ///
  /// Add a new command to the blueprint.
  ///
  /// @param  string  $name
  /// @param  array  $parameters
  /// @return \Illuminate\Support\Fluent
  ///
  Fluent addCommand(String name, [Map<String, dynamic>? parameters]) {
    var command = createCommand(name, parameters);
    _commands.add(command);

    return command;
  }

  ///
  /// Create a new Fluent command.
  ///
  /// [name]  String
  /// [parameters]  Map
  /// Return \Support\Fluent
  ///
  Fluent createCommand(String name, [Map<String, dynamic>? parameters]) {
    var attributesP = <String, dynamic>{'name': name};
    if (parameters != null) {
      attributesP.addAll(parameters);
    }
    return Fluent(attributesP);
  }

  ///
  /// Get the table the blueprint describes.
  ///
  /// @return string
  ///
  String getTable() {
    return _table!;
  }

  ///
  /// Get the columns on the blueprint.
  ///
  /// @return array
  ///
  List getColumns() {
    return _columns;
  }

  ///
  /// Get the commands on the blueprint.
  ///
  /// @return array
  ///
  List getCommands() {
    return _commands;
  }

  ///
  /// Get the columns on the blueprint that should be added.
  ///
  /// @return array
  ///
  List getAddedColumns() {
    return Utils.array_filter(this._columns, (column) {
      return !column['change'];
    });
    //return [];
  }

  ///
  /// Get the columns on the blueprint that should be changed.
  ///
  /// @return array
  ///
  List getChangedColumns() {
    return Utils.array_filter(this._columns, (column) {
      return column['change'];
    });
  }
}
