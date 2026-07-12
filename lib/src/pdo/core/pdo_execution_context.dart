import '../../driver/driver_access.dart';
import 'pdo_config.dart';
import 'pdo_interface.dart';
import 'pdo_result.dart';

abstract class PDOExecutionContext {
  late PDOInterface pdoInstance;

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]);
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]);

  /// Stream rows from a query using a server-side cursor / incremental reader,
  /// keeping memory roughly constant regardless of result-set size.
  ///
  /// Default: [UnsupportedError]. Driver adapters that expose an incremental
  /// reader (e.g. dpgsql's `executeReader`) override this. [fetchSize] is a
  /// hint for the number of rows to buffer per network round-trip.
  Stream<Map<String, dynamic>> queryStream(String query,
      [dynamic params, int? fetchSize]) {
    throw UnsupportedError(
      'Streaming (cursor) is not supported by this driver adapter.',
    );
  }

  /// Direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY, raw
  /// connection). Returns `null` when the adapter has no such capabilities.
  DriverAccess? driverAccess() => null;

  PDOConfig getConfig();
}
