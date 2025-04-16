import 'abstract_asset.dart';
import 'table.dart';

/// Representa uma Sequence de banco de dados em memória.
/// Inspirado em Doctrine\DBAL\Schema\Sequence.
class Sequence extends AbstractAsset {
  /// O valor pelo qual a sequence é incrementada (CACHE em alguns bancos).
  /// Doctrine chama isso de allocationSize, mas CACHE é mais comum em SQL.
  int _cache; // Renomeado de allocationSize para cache

  /// O valor inicial da sequence.
  int _initialValue;

  /// Construtor principal.
  Sequence(
    String name, {
    int initialValue = 1,
    int cache = 1, // Default cache/allocationSize para 1
  })  : _initialValue = initialValue,
        _cache = cache {
    if (cache < 1) {
      throw ArgumentError(
          'Sequence cache/allocation size must be greater than 0.');
    }
    if (initialValue < 1 && cache > 1) {
      // Alguns bancos podem ter restrições sobre initial value e cache > 1
      print(
          "Warning: Using initial value < 1 with cache > 1 might not be supported by all databases for sequence '$name'.");
    }
    setName(name); // Método da classe base
  }

  // --- Getters ---

  /// Obtém o valor de incremento/cache (allocationSize do Doctrine).
  int getCache() {
    return _cache;
  }

  /// Obtém o valor inicial.
  int getInitialValue() {
    return _initialValue;
  }

  // --- Setters (para interface fluente, menos comum em Dart mas fiel ao PHP) ---

  /// Define o valor de incremento/cache.
  Sequence setCache(int cache) {
    if (cache < 1) {
      throw ArgumentError(
          'Sequence cache/allocation size must be greater than 0.');
    }
    _cache = cache;
    return this;
  }

  /// Define o valor inicial.
  Sequence setInitialValue(int initialValue) {
    // TODO: Adicionar validação se necessário (ex: >= min value se houver)
    _initialValue = initialValue;
    return this;
  }

  /// Verifica se esta sequence provavelmente é uma sequence de autoincremento
  /// implícita para uma coluna de chave primária de uma tabela.
  ///
  /// Usado pelo comparador para evitar reportar sequences implícitas como órfãs.
  /// A lógica assume a convenção de nomenclatura padrão do PostgreSQL (`<table>_<column>_seq`).
  /// Outros bancos (Oracle, SQL Server) têm mecanismos diferentes para autoincremento.
  bool isAutoIncrementsFor(Table table) {
    final primaryKey = table.getPrimaryKey();

    // Precisa de uma chave primária...
    if (primaryKey == null) {
      return false;
    }

    final pkColumns = primaryKey.getColumns();

    // ...que tenha exatamente uma coluna...
    if (pkColumns.length != 1) {
      return false;
    }

    final pkColumnName = pkColumns.first;
    // ...e essa coluna exista na tabela...
    if (!table.hasColumn(pkColumnName)) {
      return false; // Pouco provável, mas defensivo
    }
    final column = table.getColumn(pkColumnName);

    // ...e essa coluna esteja marcada como autoIncrement.
    if (!column.isAutoIncrement) {
      return false;
    }

    // Agora compara os nomes usando a convenção comum (ex: PostgreSQL)
    // Obtém nome da sequence e da tabela (sem schema/namespace)
    // Assume que getName() retorna o nome sem aspas e _parseIdentifier lida com isso.
    final sequenceName = getName().toLowerCase();
    final tableName = table.getName().toLowerCase();
    final columnName = column.getName().toLowerCase();

    // Constrói o nome esperado da sequence implícita
    final expectedSequenceName = '${tableName}_${columnName}_seq';

    return expectedSequenceName == sequenceName;
  }

  /// Cria uma cópia desta sequence.
  Sequence clone() {
    return Sequence(
      name, // Nome original
      initialValue: _initialValue,
      cache: _cache,
    );
  }
}
