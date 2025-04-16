import 'package:eloquent/eloquent.dart';
import 'abstract_asset.dart';

/// Representa um identificador de banco de dados (como nome de tabela, coluna, índice).
///
/// Esta classe encapsula um nome de identificador e lida com a lógica
/// básica de detecção e remoção de aspas, além de fornecer um método
/// para obter a versão cotada (com aspas) de acordo com a gramática do banco.
/// Inspirado em Doctrine\DBAL\Schema\Identifier.
class Identifier extends AbstractAsset {
  // Estende SchemaAsset

  /// Construtor.
  ///
  /// [identifier]: O nome do identificador (ex: "my_column", `"MyColumn"`, `[My Column]`).
  /// [quote]: Se definido como `true`, força a adição de aspas duplas (") ao
  ///          redor do identificador, *a menos que* ele já esteja cotado.
  ///          Geralmente, é melhor deixar a gramática decidir se precisa cotar.
  Identifier(String identifier, {bool quote = false}) {
    // Chama o método _setName da classe base, que já detecta se está cotado
    // e armazena o nome original em _name e o status em _quoted.
    setName(identifier);

    // Se forçar a cotação E o identificador ainda não estiver cotado
    if (quote && !quoted) {
      // Define novamente o nome, desta vez adicionando aspas duplas.
      // Nota: Isso assume aspas duplas. A gramática específica pode usar
      // outros caracteres (`, []). A cotação real deve vir da gramática.
      // Esta lógica de 'quote=true' é raramente usada diretamente;
      // getQuotedName é a forma preferida.
      setName(
          '"${getName()}"'); // Usa getName() para obter o nome *sem* aspas antes de adicionar novas
      quoted = true; // Marca como cotado agora
    }
  }

  /// Obtém o nome do identificador sem aspas.
  /// Sobrescreve o método da classe base para garantir que sempre retorne
  /// o nome limpo.
  @override
  String getName() {
    return parseIdentifier(name);
  }

  /// Obtém o nome original como foi fornecido (pode incluir aspas).
  String getOriginalName() {
    return name;
  }

  /// Obtém o nome cotado (com aspas) de acordo com a gramática fornecida.
  /// Este é o método preferido para obter o nome formatado para SQL.
  @override
  String getQuotedName(SchemaGrammar grammar) {
    // Delega para o método wrap da gramática, que sabe quais caracteres de
    // cotação usar (", `, []) e se o identificador *precisa* ser cotado
    // (por exemplo, se for uma palavra reservada ou contiver caracteres especiais).
    return grammar.wrap(getName()); // Passa o nome limpo para a gramática cotar
  }

  /// Retorna se o identificador foi originalmente fornecido entre aspas.
  bool isQuoted() {
    return quoted;
  }
}
