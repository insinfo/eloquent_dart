//
class SchemaConfig {
  int _maxIdentifierLength;
  String? _name;
  Map<String, dynamic> _defaultTableOptions;

  SchemaConfig(
      {int maxIdentifierLength = 63,
      String? name,
      Map<String, dynamic> defaultTableOptions = const {}})
      : _maxIdentifierLength = maxIdentifierLength,
        _name = name,
        _defaultTableOptions = defaultTableOptions;

  int getMaxIdentifierLength() => _maxIdentifierLength;
  String? getName() => _name;

  void setName(String? val) {
    _name = val;
  }

  Map<String, dynamic> getDefaultTableOptions() => _defaultTableOptions;
}
