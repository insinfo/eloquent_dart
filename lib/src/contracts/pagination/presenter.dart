/// Interface para renderizar o paginador.
abstract class Presenter {
  /// Renderiza o paginador.
  /// Pode retornar uma String ou um objeto que implemente uma renderização compatível.
  String render();

  /// Retorna true se o paginador possuir páginas para exibir.
  bool hasPages();
}