Connection & PDO/Driver Execution Layer — Map for Performance Rewrite
1. The PDO adapter contract
Two-layer abstract contract that every adapter implements:

PDOExecutionContext (lib/src/pdo/core/pdo_execution_context.dart:5-14) — the per-context (connection OR transaction) surface:

late PDOInterface pdoInstance — back-pointer to the owning connection
Future<int> execute(String statement, [int? timeoutInSeconds]) — line 9
Future<PDOResults> query(String query, [dynamic params, int? timeoutInSeconds]) — line 10
PDOConfig getConfig() — line 13
PDOInterface extends PDOExecutionContext (lib/src/pdo/core/pdo_interface.dart:6-18) — the connection-level surface adds:

Future<PDOInterface> connect() — line 7
Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx), [int? timeoutInSeconds]) — line 8
Future close() — line 10
abstract PDOConfig config — line 17 (note: getConfig() at line 13-15 has a bug — it does throw config; instead of return config;; adapters like DpgsqlPDOTransaction override it correctly)
So a full adapter must implement 6 methods: connect, runInTransaction, execute, query, close, getConfig. A transaction context (e.g. DpgsqlPDOTransaction) only implements execute, query, getConfig.

PDOResults (lib/src/pdo/core/pdo_result.dart:4) is a ListBase<Map<String,dynamic>> wrapping List<Map<String,dynamic>> rows + int rowsAffected. Fully materialized — no lazy/streaming variant.

2. Connection query methods → PDO routing
All public query methods funnel through a single closure runner. Connection.run(query, bindings, callback, timeout) (connection.dart:597) → runQueryCallback (connection.dart:652) → await callback(this, query, bindings, timeout) (line 664).

select (connection.dart:275-295): callback picks getPdoForSelect(useReadPdo) (line 289 → getReadPdo()/getPdo() at 303-305), prepareBindings (line 290), then pdoL.query(query, params, timeout) (line 291). Casts result to List<Map<String,dynamic>>.
statement (connection.dart:356-370): getPdo() (write) → prepareBindings → pdoL.query(...). Returns PDOResults.
insert (connection.dart:314-317): delegates to statement. rawQuery (320) is an alias.
update (332) and delete (344): both delegate to affectingStatement.
affectingStatement (connection.dart:397-415): getPdo() → prepareBindings → _pdo.query(...) → returns res.rowsAffected (line 411).
execute (connection.dart:374-388) and unprepared (423-433): call pdoL.execute(query, timeout) instead of query.
Note every method routes through query() except execute/unprepared. So even inserts/updates go through the row-returning query() path and read rowsAffected off the result.

3. Transactions end to end
Connection.transaction(callback, [timeout]) (connection.dart:489-498) is thin:


this.pdo.pdoInstance.runInTransaction((pdoCtx) {
   final newConnection = Connection(pdoCtx, _databaseName, _tablePrefix, _config);
   return callback(newConnection);
});
It builds a brand-new Connection wrapping the transaction context and hands it to the user callback. Note: timeoutInSeconds param is accepted but never passed to runInTransaction.

Adapter side — DpgsqlPDO.runInTransaction (dpgsql_pdo.dart:39-70): opens a connection (pool or single via _openConnectionForOperation), beginTransaction(), wraps in DpgsqlPDOTransaction(connection, transaction, this), runs operation(context).timeout(timeout), commit(). On error it classifies _isConnectionFailure (line 324), marks connection unusable, otherwise rollback(); finally closes the connection back to pool if _dataSource != null.

DpgsqlPDOTransaction (dpgsql_pdo_transaction.dart) runs query/execute directly on the captured DpgsqlConnection (no re-acquire), reusing the static DpgsqlPDO.expectsRows/parametersFromBindings helpers.

Other adapters delegate to their driver's native tx: DargresPDO.runInTransaction → connection.runInTransaction (dargres_pdo.dart:63-69); PostgresV3PDO.runInTransaction → connection.runTx (postgres_v3_pdo.dart:109-122).

The classic beginTransaction/commit/rollBack/transactionLevel state machine is commented out in Connection (connection.dart:505-554); transactions counter stays 0, so getReadPdo() (897) never sees an in-tx state via this path (the new Connection instance carries the tx pdo directly instead).

4. Streaming / cursor / COPY / raw-driver access — NONE surfaced
Searched copy|stream|cursor|Stream<|COPY across lib/src. Findings:

Zero streaming/COPY/cursor capability in the Connection or PDO abstraction layer. The contract only exposes query (returns fully-materialized PDOResults) and execute (returns int).
Grep hits are all irrelevant to the driver contract: text codecs (utils/codecs/*), the bundled postgres-v2 dependency tree (pdo/postgres/dependencies/*, e.g. postgres_pool.dart:342 Stream<PgPoolEvent> get events), and doctrine platform keyword tables.
No raw-driver accessor exists — the underlying driver connections (_connection/_dataSource in dpgsql, connection in dargres/v3) are private/unexposed. There is no way for a caller to reach DpgsqlConnection, a DpgsqlDataReader, or a COPY stream through the eloquent API.
5. driver_implementation selection
Two-stage. ConnectionFactory.createConnector (connection_factory.dart:161-186) switches on config['driver'] only ('pgsql' → PostgresConnector, 'mysql' → MySqlConnector). The actual adapter is chosen inside PostgresConnector.createConnection (postgres_connector.dart:180-209) by switching on conf['driver_implementation']:

'postgres' → PostgresV2PDO
'postgres_v3' → PostgresV3PDO
'dargres' → DargresPDO
'dpgsql' → DpgsqlPDO
default (missing/unknown) → PostgresV2PDO
Then await pdo.connect() (line 207). Separately, Connection.getDriverName() (connection.dart:977-1003) maps all four implementations back to logical 'pgsql' for grammar/schema-manager selection (_createDoctrineSchemaManager at 863-881 accepts postgres_v3/dargres/dpgsql → PostgreSQLSchemaManager).

6. dpgsql package capabilities NOT surfaced
The adapter imports package:dpgsql/dpgsql.dart (dpgsql_pdo.dart:4) but uses only a tiny slice: DpgsqlConnection, DpgsqlDataSource, createCommand/executeNonQuery, executeMaps, DpgsqlParameter(Collection), DpgsqlConnectionStringBuilder, DpgsqlTransaction. The package (dpgsql-1.0.1/lib/dpgsql.dart exports) exposes substantial unused capability:

COPY (bulk): beginBinaryImport(copyFromCommand) → DpgsqlBinaryImporter (startRow/write<T>/writeNull/complete), beginBinaryExport → DpgsqlBinaryExporter, beginRawBinaryCopy, beginTextImport, beginTextExport → DpgsqlRawCopyStream (dpgsql_connection.dart:386-465). This is the biggest missing perf lever for bulk inserts.
Streaming / cursor-style reads: executeReader(...) → DpgsqlDataReader with incremental Future<bool> read() plus readAllMaps() (dpgsql_data_reader.dart:7,25); forEachPgRow / forEachPgRowSync (dpgsql_connection.dart:315-336); executePgRows. The adapter instead always calls executeMaps (buffers all rows).
Pipeline mode: enterPipelineMode/exitPipelineMode/pipelineSync/executeQueryPipelined/getPipelineReader/executeBatchPipelined (dpgsql_connection.dart:483-632) — batch multiple statements without per-round-trip latency.
Batch: createBatch()/executeBatch() → DpgsqlBatch/DpgsqlBatchCommand.
Prepared statements: prepare(commandText, statementName, ...) (line 353) and the builder's maxAutoPrepare = 128/autoPrepareMinUsages = 2 (set at dpgsql_pdo.dart:249-250) — auto-prepare is on but the adapter never names/reuses statements explicitly.
Scalar fast path: executeScalar (dpgsql_connection.dart:262) — unused; count/exists queries still go through full map materialization.
Large objects, replication, notifications: DpgsqlLargeObjectManager/Stream, DpgsqlReplicationConnection + logical replication, notifications/notices streams (dpgsql_connection.dart:78,83). All unexposed.
Rich types: dpgsql_geometric, dpgsql_tsvector, dpgsql_tsquery, dpgsql_range — bindings only ever pass through DpgsqlParameter(name, value) generically.
7. Performance concerns in the hot path
Per-query allocation / boxing:

Every call allocates a fresh closure for run's callback (e.g. select at connection.dart:282, statement at 359, affectingStatement at 400). Four positional args captured per call.
run → runQueryCallback is an extra async hop with var result boxing per query (connection.dart:597-675); both are Future<dynamic> so every result is boxed and then cast (res as List<Map<String,dynamic>> at line 294, resp as PDOResults at 369, resp as int at 414).
DpgsqlPDO.query allocates a Duration and a new DpgsqlParameterCollection on every call (dpgsql_pdo.dart:86,176), plus _withConnection wraps another closure + try/finally (line 114-129). For pooled mode, every query does openConnection() + close() round-trip to the pool (line 132-134, 125-127).
PDOResults extends ListBase and always fully materializes rows — no streaming, so large result sets are entirely in memory.
prepareBindings cost (connection.dart:441-470): runs a full loop over bindings on every query even when there are no DateTime/false values, mutating the list in place. It calls getQueryGrammar() and lazily getDateFormat(). The false→0 branch calls _resolvedDriverName() (cached via _cachedDriverName, line 472-474) — fine after first call. Main waste: unconditional iteration + the fact that select/statement call it even for zero-binding queries.

expectsRows string scan (dpgsql_pdo.dart:106-112): every dpgsql query does trimLeft().toLowerCase() (allocates a lowercased copy of the whole SQL string) plus _containsReturningKeyword which indexOf('returning')-scans repeatedly. This runs on the hot path for every statement.

Routing inefficiency: inserts/updates/deletes route through query() (row-returning path) rather than execute(), so DpgsqlPDO.query still builds/returns a PDOResults([], affected) and, for non-row statements, creates a command + parameter collection anyway (dpgsql_pdo.dart:99-102).

Logging / events: logQuery (759) is effectively dead (guarded by loggingQueries, default false) and run has its timing/logging commented out (connection.dart:606,635-637) — so little logging overhead currently, but fireConnectionEvent/listen/getEventDispatcher all throw UnimplementedError() (782,803,1069), meaning there is no event hook infrastructure to build on.

Reconnect path: run's catch (connection.dart:616-630) calls causedByLostConnection(e) (string/type matching) on every error and has a hardcoded Future.delayed(1000ms); the alternate tryAgainIfCausedByLostConnection (688) has a bug — it increments/zeros tryReconnectLimit instead of tryReconnectCount (lines 701-703).

Transaction allocation: each transaction() call builds a whole new Connection object (re-running useDefaultQueryGrammar() + useDefaultPostProcessor() in the constructor, connection.dart:142-143) per transaction.

Key files
c:\MyDartProjects\eloquent_dart\lib\src\connection.dart
c:\MyDartProjects\eloquent_dart\lib\src\connection_interface.dart
c:\MyDartProjects\eloquent_dart\lib\src\pdo\core\pdo_execution_context.dart, pdo_interface.dart, pdo_config.dart, pdo_result.dart
c:\MyDartProjects\eloquent_dart\lib\src\pdo\dpgsql\dpgsql_pdo.dart, dpgsql_pdo_transaction.dart
c:\MyDartProjects\eloquent_dart\lib\src\pdo\dargres\dargres_pdo.dart, pdo\postgres_v3\postgres_v3_pdo.dart
c:\MyDartProjects\eloquent_dart\lib\src\connectors\connection_factory.dart, postgres_connector.dart
dpgsql package: C:\Users\pmro\AppData\Local\Pub\Cache\hosted\pub.dev\dpgsql-1.0.1\lib\dpgsql.dart (+ src\dpgsql_connection.dart, dpgsql_binary_importer.dart, dpgsql_data_reader.dart)