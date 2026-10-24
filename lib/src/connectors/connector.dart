import '../../eloquent.dart';

abstract class Connector with DetectsLostConnections {
  /// The default connection options.
  Map<dynamic, dynamic> options = {};

  /// Returns [options] overridden by the `options` key of [config], if any.
  Map<dynamic, dynamic> getOptions(Map<dynamic, dynamic> config) {
    var optionsP = config['options'];
    if (optionsP != null) {
      return {...options, ...optionsP as Map};
    }
    return options;
  }

  /// Opens a new driver connection with the settings in [config].
  dynamic createConnection(Map<String, dynamic> config);
}
