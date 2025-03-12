import 'presenter.dart';

/// Define a interface para o paginador básico.
abstract class Paginator {
  /// Retorna a URL para uma determinada página.
  String url(int page);

  /// Adiciona um conjunto de valores de query string ao paginador.
  /// O parâmetro [key] pode ser uma String ou um Map<String, String>.
  Paginator appends(dynamic key, [String? value]);

  /// Obtém ou define o fragmento da URL a ser anexado.
  /// Se [fragment] for informado, define e retorna a instância; caso contrário, retorna o fragmento atual.
  dynamic fragment([String? fragment]);

  /// Retorna a URL para a próxima página, ou null se não houver.
  String? nextPageUrl();

  /// Retorna a URL para a página anterior, ou null se não houver.
  String? previousPageUrl();

  /// Retorna todos os itens que estão sendo paginados.
  List<Map<String, dynamic>> items();

  /// Retorna o índice do primeiro item paginado.
  int firstItem();

  /// Retorna o índice do último item paginado.
  int lastItem();

  /// Retorna a quantidade de itens exibidos por página.
  int perPage();

  /// Retorna a página atual.
  int currentPage();

  /// Indica se há páginas suficientes para dividir os resultados.
  bool hasPages();

  /// Indica se existem mais itens na fonte de dados.
  bool hasMorePages();

  /// Retorna se a lista de itens está vazia.
  bool isEmpty();

  /// Renderiza o paginador utilizando um Presenter (opcional).
  String render([Presenter? presenter]);
}