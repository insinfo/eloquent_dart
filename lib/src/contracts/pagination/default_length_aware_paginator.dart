// default_length_aware_paginator.dart
import 'length_aware_paginator.dart';
import 'paginator.dart';
import 'presenter.dart';

/// Exemplo de implementação concreta de LengthAwarePaginator.
class DefaultLengthAwarePaginator implements LengthAwarePaginator {
  final List<Map<String, dynamic>> _items;
  final int _total;
  final int _perPage;
  final int _currentPage;
  final Map<String, dynamic> _options;

  /// Construtor recebendo os valores necessários.
  DefaultLengthAwarePaginator(
    this._items,
    this._total,
    this._perPage,
    this._currentPage,
    this._options,
  );

  // ---------------------------------------------------------------------------
  // Métodos da interface LengthAwarePaginator:
  // ---------------------------------------------------------------------------

  @override
  int total() => _total;

  @override
  int lastPage() {
    // Cálculo simples: total / perPage (arredondando para cima).
    return (_total / _perPage).ceil();
  }

  // ---------------------------------------------------------------------------
  // Métodos da interface Paginator (que LengthAwarePaginator estende):
  // ---------------------------------------------------------------------------

  @override
  String url(int page) {
    // Exemplo simples, retornando apenas algo que demonstre a página
    // Em produção, você formaria uma URL real, com query strings etc.
    return '${_options["path"] ?? "/"}?page=$page';
  }

  @override
  Paginator appends(dynamic key, [String? value]) {
    // Implementação fictícia para exemplo:
    if (key is String && value != null) {
      _options[key] = value;
    } else if (key is Map<String, String>) {
      _options.addAll(key);
    }
    return this;
  }

  @override
  dynamic fragment([String? fragment]) {
    // Exemplo: se for passado algo, define; senão, retorna o atual
    if (fragment != null) {
      _options['fragment'] = fragment;
      return this;
    }
    return _options['fragment'];
  }

  @override
  String? nextPageUrl() {
    if (_currentPage < lastPage()) {
      return url(_currentPage + 1);
    }
    return null;
  }

  @override
  String? previousPageUrl() {
    if (_currentPage > 1) {
      return url(_currentPage - 1);
    }
    return null;
  }

  @override
  List<Map<String, dynamic>> items() => _items;

  @override
  int firstItem() {
    if (_items.isEmpty) return 0;
    return ((_currentPage - 1) * _perPage) + 1;
  }

  @override
  int lastItem() {
    if (_items.isEmpty) return 0;
    return ((_currentPage - 1) * _perPage) + _items.length;
  }

  @override
  int perPage() => _perPage;

  @override
  int currentPage() => _currentPage;

  @override
  bool hasPages() => lastPage() > 1;

  @override
  bool hasMorePages() => _currentPage < lastPage();

  @override
  bool isEmpty() => _items.isEmpty;

  @override
  String render([Presenter? presenter]) {
    // Aqui você poderia retornar HTML ou outro formato.
    // Exemplo básico:
    return 'Página $_currentPage de ${lastPage()}, total $_total registros.';
  }
}
