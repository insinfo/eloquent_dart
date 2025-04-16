/// The line used in the string representation of stack chains to represent
/// the gap between traces.
const chainGap = '===== asynchronous gap ===========================\n';

/// The line used in the string representation of VM stack chains to represent
/// the gap between traces.
final vmChainGap = RegExp(r'^<asynchronous suspension>\n?$', multiLine: true);


/// Whether we're running in a JS context.
const bool inJS = 0.0 is int;
