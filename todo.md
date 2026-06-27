Integração com o Resto do Pacote:
Connection.dart: Possui métodos como isDoctrineAvailable, getDoctrineColumn, getDoctrineSchemaManager, getDoctrineConnection. Todos eles retornam false ou null. Isso indica claramente que a funcionalidade de introspecção de schema via Doctrine não está integrada ao objeto Connection principal. A conexão não sabe como usar o SchemaManager que você implementou.
SchemaGrammar.dart (em lib/src/schema/grammars): A gramática base para gerar SQL de manipulação de schema (CREATE, ALTER, DROP) também possui métodos relacionados ao Doctrine DBAL (como getDoctrineTableDiff, compileChange baseado em diff) que estão não implementados (throw UnimplementedError). Isso significa que a geração de SQL de alteração de schema não está usando a lógica de comparação e diffing da sua pasta doctrine. Ela provavelmente se baseia apenas nos comandos explícitos definidos no Blueprint.
SchemaMySqlGrammar.dart (em lib/src/schema/grammars): Este arquivo está vazio. Falta a implementação da gramática para gerar SQL de schema para MySQL.

Benchmark mysql_dart 1.2.1 (antes do update para 2.0.0):
- Ambiente: localhost, database banco_teste, tabela eloquent_mysql_dart_benchmark.
- Script: tool/mysql_dart_benchmark.dart.
- Carga: 200 inserts, 200 selects por id, 50 inserts dentro de transação.
- setup_ms=47
- insert_200_ms=304
- select_by_id_200_ms=170
- transaction_insert_50_ms=24
- total_measured_ms=498
- ops_per_second=903.61
- row_count=250

Benchmark mysql_dart 2.0.0 (depois do update):
- Ambiente: localhost, database banco_teste, tabela eloquent_mysql_dart_benchmark.
- Script: tool/mysql_dart_benchmark.dart.
- Carga: 200 inserts, 200 selects por id, 50 inserts dentro de transação.
- setup_ms=18
- insert_200_ms=424
- select_by_id_200_ms=128
- transaction_insert_50_ms=26
- total_measured_ms=578
- ops_per_second=778.55
- row_count=250
- Observação: neste microbenchmark via Eloquent, 2.0.0 ficou mais lento que 1.2.1 no total medido, apesar do setup e dos selects terem melhorado.
