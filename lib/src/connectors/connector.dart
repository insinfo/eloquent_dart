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
  dynamic createConnection(Map<String, dynamic> config);
}
