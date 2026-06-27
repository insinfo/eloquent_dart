/// Common SQL tokens used by the query builder.
///
/// These constants intentionally remain strings so existing APIs keep accepting
/// custom operators, custom join types, and grammar-specific extensions.
abstract class SqlOperator {
  static const String equals = '=';
  static const String doubleEquals = '==';
  static const String notEquals = '!=';
  static const String notEqualsSql = '<>';
  static const String greater = '>';
  static const String greaterOrEqual = '>=';
  static const String less = '<';
  static const String lessOrEqual = '<=';
  static const String inList = 'in';
  static const String notInList = 'not in';
  static const String like = 'like';
  static const String likeBinary = 'like binary';
  static const String notLike = 'not like';
  static const String between = 'between';
  static const String ilike = 'ilike';
  static const String bitwiseAnd = '&';
  static const String bitwiseOr = '|';
  static const String bitwiseXor = '^';
  static const String shiftLeft = '<<';
  static const String shiftRight = '>>';
  static const String rlike = 'rlike';
  static const String regexp = 'regexp';
  static const String notRegexp = 'not regexp';
  static const String postgresRegex = '~';
  static const String postgresRegexAll = '~///';
  static const String postgresNotRegex = '!~';
  static const String postgresNotRegexAll = '!~///';
  static const String similarTo = 'similar to';
  static const String notSimilarTo = 'not similar to';
  static const String isOperator = 'is';

  static const List<String> defaults = [
    equals,
    less,
    greater,
    lessOrEqual,
    greaterOrEqual,
    notEqualsSql,
    notEquals,
    inList,
    like,
    likeBinary,
    notLike,
    between,
    ilike,
    bitwiseAnd,
    bitwiseOr,
    bitwiseXor,
    shiftLeft,
    shiftRight,
    rlike,
    regexp,
    notRegexp,
    postgresRegex,
    postgresRegexAll,
    postgresNotRegex,
    postgresNotRegexAll,
    similarTo,
    notSimilarTo,
  ];
}

abstract class SqlBool {
  static const String and = 'and';
  static const String or = 'or';
}

abstract class SqlSort {
  static const String asc = 'asc';
  static const String desc = 'desc';
}

abstract class SqlJoin {
  static const String inner = 'inner';
  static const String left = 'left';
  static const String right = 'right';
  static const String cross = 'cross';
}

abstract class SqlWhereType {
  static const String basic = 'Basic';
  static const String column = 'Column';
  static const String raw = 'raw';
  static const String between = 'between';
  static const String nested = 'Nested';
  static const String sub = 'Sub';
  static const String exists = 'Exists';
  static const String notExists = 'NotExists';
  static const String inList = 'In';
  static const String notInList = 'NotIn';
  static const String inSub = 'InSub';
  static const String notInSub = 'NotInSub';
  static const String isNull = 'Null';
  static const String isNotNull = 'NotNull';
}
