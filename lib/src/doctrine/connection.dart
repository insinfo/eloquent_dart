import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_execution_context.dart';

import 'server_version_provider.dart';

class DoctrineConnection implements ServerVersionProvider {
  final PDOExecutionContext pdo;
  final String driver;
  final String database;
  final Map<String, dynamic> config;

  DoctrineConnection({
    required this.pdo,
    required this.driver,
    required this.database,
    Map<String, dynamic> config = const {},
  }) : config = Map.unmodifiable(config);

  PDOConfig get pdoConfig => pdo.getConfig();

  @override
  String getServerVersion() {
    final configuredVersion =
        config['server_version'] ?? config['serverVersion'];
    return configuredVersion?.toString() ?? '';
  }
}
