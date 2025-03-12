import 'paginator.dart';

/// Define uma interface para um paginador "length aware" que estende [Paginator].
abstract class LengthAwarePaginator extends Paginator {
  /// Determina o número total de itens na fonte de dados.
  int total();

  /// Retorna o número da última página disponível.
  int lastPage();
}