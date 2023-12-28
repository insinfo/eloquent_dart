import '../../eloquent.dart';

abstract class Connector with DetectsLostConnections {
  ///
  /// The default PDO connection options.
  ///
  /// @var array
  ///
  Map<dynamic, dynamic> options = {};

  ///
  /// Get the PDO options based on the configuration.
  ///
  /// @param  array  $config
  /// @return array
  ///
  Map<dynamic, dynamic> getOptions(Map<dynamic, dynamic> config) {
    var optionsP = config['options'];

    //return array_diff_key(options, optionsP) + $options;
    //Utils.map_merge_sd(options, optionsP);
    if (optionsP != null) {
      return {...options, ...optionsP};
    }
    return options;
  }

  ///
  /// Create a new PDO connection.
  ///
  /// @param  string  $dsn
  /// @param  array   $config
  /// @param  array   $options
  /// @return \PDO
  ///
  dynamic createConnection(
      String dsn, Map<String, dynamic> config, Map<String, dynamic> options);
  // var username = config['username'];
  //var password = config['password'];

  // try {
  //     $pdo = new PDO($dsn, $username, $password, $options);
  // } catch (Exception e) {
  //     $pdo = $this->tryAgainIfCausedByLostConnection(
  //         $e, $dsn, $username, $password, $options
  //     );
  // }

  //}
}
