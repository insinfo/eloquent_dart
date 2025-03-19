import 'paginator.dart';
import 'presenter.dart';

/// Exemplo de implementação concreta de um paginador simples ("simple paginator").
class DefaultPaginator implements Paginator {
  /// Itens da página atual.
  final List<Map<String, dynamic>> _items;

  /// Quantidade de itens por página.
  final int _perPage;

  /// Página atual.
  final int _currentPage;

  /// Indica se ainda existe (ou não) outra página seguinte.
  final bool _hasMorePages;

  /// Opções adicionais (ex.: 'path', 'fragment', etc.).
  final Map<String, dynamic> _options;

  /// Construtor do paginador simples:
  /// [items] são os itens efetivamente desta página
  /// [perPage] é quantos itens por página
  /// [currentPage] é a página atual
  /// [hasMorePages] indica se existe uma próxima página
  /// [options] pode conter informação extra, como a 'path' base para gerar URL.
  DefaultPaginator(
    this._items,
    this._perPage,
    this._currentPage,
    this._hasMorePages,
    this._options,
  );

  //----------------------------------------------------------------------------
  // Implementações da interface Paginator:
  //----------------------------------------------------------------------------

  /// Gera a URL para uma página específica (ex.: ?page=2).
  @override
  String url(int page) {
    final base = _options['path'] ?? '/';
    return '$base?page=$page';
  }

  /// Anexa valores de query string ao paginador.
  /// Se [key] for Map, adiciona todos os pares. Se for String, adiciona ao [value].
  @override
  Paginator appends(dynamic key, [String? value]) {
    if (key is String && value != null) {
      _options[key] = value;
    } else if (key is Map<String, String>) {
      _options.addAll(key);
    }
    return this;
  }

  /// Define ou obtém o fragmento (âncora) na URL.
  @override
  dynamic fragment([String? fragment]) {
    if (fragment != null) {
      _options['fragment'] = fragment;
      return this;
    }
    return _options['fragment'];
  }

  /// URL para a próxima página, se existir.
  @override
  String? nextPageUrl() {
    if (_hasMorePages) {
      return url(_currentPage + 1);
    }
    return null;
  }

  /// URL para a página anterior, se existir.
  @override
  String? previousPageUrl() {
    if (_currentPage > 1) {
      return url(_currentPage - 1);
    }
    return null;
  }

  /// Retorna a lista de itens da página atual.
  @override
  List<Map<String, dynamic>> items() => _items;

  /// Índice (baseado em 1) do primeiro item desta página.
  /// Exemplo: se currentPage=2 e perPage=15, o firstItem() é 16.
  @override
  int firstItem() {
    if (_items.isEmpty) return 0;
    return ((_currentPage - 1) * _perPage) + 1;
  }

  /// Índice (baseado em 1) do último item desta página.
  @override
  int lastItem() {
    if (_items.isEmpty) return 0;
    return ((_currentPage - 1) * _perPage) + _items.length;
  }

  /// Quantos itens por página.
  @override
  int perPage() => _perPage;

  /// Página atual.
  @override
  int currentPage() => _currentPage;

  /// Indica se há mais de uma página (ou seja, se currentPage>1 ou se tem próxima).
  @override
  bool hasPages() {
    return (_currentPage > 1) || _hasMorePages;
  }

  /// Indica se há outra página depois desta (ou seja, se hasMorePages for true).
  @override
  bool hasMorePages() => _hasMorePages;

  /// Se está vazio.
  @override
  bool isEmpty() => _items.isEmpty;

  /// Renderiza o paginador. Se Presenter for passado, delega a ele; caso contrário, usa um texto básico.
  @override
  String render([Presenter? presenter]) {
    if (presenter != null) {
      return presenter.render();
    }
    // Exemplo simples de "renderização" textual:
    final totalItemsPage = _items.length;
    return 'Página $_currentPage - Exibindo $totalItemsPage itens.';
  }
}
