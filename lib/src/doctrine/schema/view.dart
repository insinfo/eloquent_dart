import 'abstract_asset.dart'; // Importa a classe base abstrata

/// Representa uma View de banco de dados em memória.
/// Inspirado em Doctrine\DBAL\Schema\View.
class View extends AbstractAsset {
  /// A instrução SQL que define a view (o corpo da view após CREATE VIEW ... AS).
  String sql;

  /// Construtor principal.
  ///
  /// [name]: O nome da view (pode ser qualificado pelo schema, ex: "public.my_view").
  /// [sql]: A string SQL que define a consulta da view.
  View(String name, this.sql) {
    // Define o nome usando o método da classe base,
    // que lida com a detecção de aspas e armazena o nome original.
    setName(name);

    // Validação adicional pode ser feita aqui se necessário (ex: SQL não vazio)
    if (sql.trim().isEmpty) {
      print("Warning: Creating view '$name' with empty SQL definition.");
      // Ou lançar ArgumentError se uma definição SQL for obrigatória
      // throw ArgumentError('SQL definition for view cannot be empty.');
    }
  }

  /// Retorna a string SQL que define a consulta da view.
  String getSql() {
    return sql;
  }

  /// Cria uma cópia desta view.
  View clone() {
    return View(
      name, // Nome original da classe base
      sql, // SQL é imutável (String)
    );
  }

  // Os métodos getName(), getOriginalName(), getCanonicalName(), getQuotedName(),
  // isIdentifierQuoted(), trimQuotes() são herdados de SchemaAsset.
}
