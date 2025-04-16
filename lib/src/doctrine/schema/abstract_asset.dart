import 'package:eloquent/eloquent.dart';

/// Classe base abstrata para assets de schema (tabelas, colunas, etc.).
abstract class AbstractAsset {
  /// Nome original do asset, pode conter aspas.
  late String name;

  /// Indica se o nome original estava entre aspas.
  bool quoted = false;

  /// Obtém o nome não qualificado e sem aspas do asset.
  String getName() {
    return parseIdentifier(name);
  }

  /// Obtém o nome completo (potencialmente qualificado por namespace/schema) e sem aspas.
  String getFullName() {
    return name; // A subclasse pode precisar sobrescrever para lidar com namespace
  }

  /// Obtém o nome pronto para ser usado em SQL, com aspas se necessário.
  /// A lógica de cotação real geralmente depende da gramática específica do banco.
  String getQuotedName(SchemaGrammar grammar) {
    // Idealmente, passar o nome *original* para a gramática, pois ela
    // pode precisar saber se já estava cotado. Mas getName() retorna limpo.
    // Passar getName() é mais simples para a implementação atual.
    return grammar.wrap(getName());
  }

  /// Define o nome do asset, detectando se está entre aspas.
  /// Protegido para uso interno e por subclasses.
  //@protected
  void setName(String name) {
    _setName(name);
  }

  /// Lógica interna para definir o nome e detectar cotação.
  void _setName(String name) {
    name = name.trim();
    if (name.isEmpty) {
      throw ArgumentError('Asset name cannot be empty.');
    }
    quoted = isIdentifierQuoted(name);
    name = name; // Armazena o nome *original*
  }

  /// Verifica se um identificador está entre aspas (", `, []).
  bool isIdentifierQuoted(String identifier) {
    if (identifier.length < 2) return false; // Precisa de pelo menos 2 caracteres para as aspas
    final firstChar = identifier[0];
    final lastChar = identifier[identifier.length - 1];
    return (firstChar == '"' && lastChar == '"') ||
           (firstChar == '`' && lastChar == '`') ||
           (firstChar == '[' && lastChar == ']');
  }

  /// Remove as aspas delimitadoras (", `, []) de um identificador.
  /// Se não estiver cotado, retorna o identificador original.
  String trimQuotes(String identifier) { // <-- MÉTODO ADICIONADO/CORRIGIDO
    if (isIdentifierQuoted(identifier)) {
      // Remove o primeiro e o último caractere
      return identifier.substring(1, identifier.length - 1);
    }
    return identifier; // Retorna original se não estava cotado
  }

  /// Extrai o nome real (sem aspas) de um identificador.
  /// Privado, usado internamente por getName.
  String parseIdentifier(String name) {
    return trimQuotes(name); // Usa trimQuotes agora
  }

   /// Retorna o nome canônico (lowercase, sem aspas) para uso interno (chaves de mapa).
   String getCanonicalName() {
     return getName().toLowerCase();
   }

   /// Obtém o nome original como foi fornecido (pode incluir aspas).
   String getOriginalName() {
       return name;
   }
}