# Roteiro para concluir Doctrine, Migrations e Console

Este roteiro organiza o trabalho para finalizar os módulos relacionados a introspecção de schema, migrations e comandos de console no port Dart do Eloquent.

Referências PHP principais:

- `C:\MyPhpProjects\teste_query_builder\vendor\illuminate\database\Connection.php`
- `C:\MyPhpProjects\teste_query_builder\vendor\illuminate\database\Migrations`
- `C:\MyPhpProjects\teste_query_builder\vendor\illuminate\database\Console`
https://github.com/laravel/framework/tree/5.4
https://github.com/doctrine/dbal
C:\MyPhpProjects\teste_query_builder\laravel-framework-5.4-official
C:\MyPhpProjects\teste_query_builder\doctrine-dbal-official
C:\MyPhpProjects\teste_query_builder\vendor_5.2

Código Dart alvo:

- `lib/src/doctrine`
- `lib/src/migrations`
- `lib/src/connection.dart`
- `lib/src/schema`
- `bin`

## Decisão sobre CLI em Dart

Sim: para seguir o padrão Dart, o ponto de entrada executável deve ficar em `bin/`.

Estrutura recomendada:

```text
bin/
  eloquent.dart
lib/
  src/
    console/
      eloquent_console.dart
      command.dart
      command_runner.dart
      migrations/
        migrate_command.dart
        migrate_make_command.dart
        install_command.dart
        rollback_command.dart
        reset_command.dart
        refresh_command.dart
        status_command.dart
      seeds/
        seed_command.dart
        seeder_make_command.dart
```

No `pubspec.yaml`, quando o CLI estiver pronto, expor:

```yaml
executables:
  eloquent: eloquent
```

Com isso, o usuário poderá executar:

```bash
dart run eloquent:migrate
dart run eloquent migrate
dart run eloquent make:migration create_users_table --create=users
```

A forma exata pode ser decidida ao implementar o command runner, mas o binário deve iniciar em `bin/eloquent.dart`.

## Fase 1 - Mapear compatibilidade com Laravel

Objetivo: criar uma matriz de equivalência antes de portar mais código.

Checklist:

- Mapear métodos de `Illuminate\Database\Connection.php` usados por schema, Doctrine e migrations.
- Mapear classes PHP de `Migrations` para classes Dart existentes.
- Mapear comandos PHP de `Console\Migrations` e `Console\Seeds` para comandos Dart.
- Marcar cada item como `feito`, `parcial`, `stub`, `faltando` ou `não aplicável`.

Arquivo sugerido:

- `doc/laravel_database_port_matrix.md`

Critério de aceite:

- A matriz deve listar pelo menos `Connection`, `Migrations`, `Console\Migrations`, `Console\Seeds`, `Schema\Builder`, `Schema\Blueprint` e `Schema\Grammars`.

## Fase 2 - Finalizar integração Doctrine usada pelo Eloquent

Objetivo: tornar `lib/src/doctrine` útil para `renameColumn`, `change`, introspecção e comparação de schema.

Referências PHP:

- `Connection.php`
  - `isDoctrineAvailable`
  - `getDoctrineColumn`
  - `getDoctrineSchemaManager`
  - `getDoctrineConnection`
- Doctrine DBAL usado indiretamente por Laravel Schema Grammar.

Estado atual no Dart:

- `lib/src/doctrine` já contém entidades como `Column`, `Table`, `Index`, `ForeignKeyConstraint`, `Comparator`, `AbstractSchemaManager`.
- `lib/src/connection.dart` já liga `getDoctrineConnection`, `getDoctrineSchemaManager` e `getDoctrineColumn` à camada Doctrine para PostgreSQL e MySQL.
- `lib/src/schema/grammars/schema_grammar.dart` ainda tem stubs `UnimplementedError` para recursos Doctrine.

Tarefas:

- [x] Implementar `Connection.getDoctrineConnection()` retornando `DoctrineConnection` com dados reais da conexão atual.
- [x] Implementar `Connection.getDoctrineSchemaManager()` escolhendo `PostgresSchemaManager` ou `MySqlSchemaManager` conforme driver.
- [x] Implementar `Connection.getDoctrineColumn(table, column)` retornando `Column`.
- [x] Adicionar teste unitário sem banco para a ponte `Connection -> Doctrine SchemaManager`.
- Corrigir o diretório `patforms` para `platforms`, se possível como breaking change planejada. Se não for possível agora, criar exports compatíveis.
- Completar `AbstractPlatform` para tipos usados por `Blueprint`:
  - string, text, integer, bigInteger, boolean, decimal, float, double
  - date, datetime, timestamp, time
  - json, uuid, binary
  - increments e bigIncrements
- Completar `AbstractSchemaManager`:
  - `listDatabases`
  - `listNamespaceNames` ou schemas
  - `listTableNames`
  - `listTableDetails`
  - `listTableColumns`
  - `listTableIndexes`
  - `listTableForeignKeys`
  - `listSequences`
- Completar managers específicos:
  - `PostgresSchemaManager`
  - `MySqlSchemaManager`
- [x] Integrar `Comparator` com `TableDiff` e `ColumnDiff` para diferenças de coluna em fixtures.
- [x] Ligar os helpers Doctrine em `SchemaGrammar`:
  - `getDoctrineTableDiff`
  - `getRenamedDiff`
  - `getChangedDiff`
  - `getTableWithColumnChanges`
  - `getDoctrineColumnForChange`
  - `getDoctrineColumnChangeOptions`
  - `getDoctrineColumnType`
  - `calculateDoctrineTextLength`
  - `mapFluentOptionToDoctrine`
  - `mapFluentValueToDoctrine`
- Integrar `Comparator` com `SchemaDiff` para diffs completos de schema.
- [x] Ligar a geração de SQL por plataforma para `TableDiff` de colunas em PostgreSQL e MySQL:
  - colunas adicionadas
  - colunas removidas
  - colunas renomeadas
  - alterações simples de tipo, tamanho, precisão, escala, nullable e default
- [x] Completar geração básica de SQL por plataforma para índices, unique constraints e foreign keys em `TableDiff`:
  - criar/remover índices simples
  - criar/remover unique constraints simples
  - criar/remover foreign keys simples com `onDelete`/`onUpdate`
- [x] Completar casos avançados básicos de `TableDiff` do DBAL:
  - alteração de índices como drop/create
  - renomeação de índices em PostgreSQL/MySQL
  - alteração de unique constraints como drop/create
- [x] Completar compatibilidade avançada básica de `Index` do DBAL:
  - `isFulfilledBy` com equivalência entre índice comum, unique e primary
  - `overrules` para índices unique/primary com índice parcial
  - `hasOption/getOption` case-insensitive
  - `addFlag/removeFlag/isClustered`
  - `hasColumnAtPosition` ignorando aspas
  - comparação de `lengths` esparsos
- [x] Completar geração de SQL para índices avançados:
  - índices parciais emitindo `where` apenas em PostgreSQL
  - unique constraints sem `where`, seguindo o comportamento DBAL
  - prefix length de índice em MySQL, por exemplo `` `slug`(64) ``
- Completar casos avançados restantes de `TableDiff` do DBAL:
  - constraints compostas com opções avançadas
  - ordem pré/pós alteração para primary key com auto increment
  - cobertura mais ampla de flags específicas por plataforma, como clustered/nonclustered em SQL Server

Critérios de aceite:

- `schema.table(... renameColumn ...)` deve gerar SQL correto em PostgreSQL e MySQL.
- `schema.table(... change ...)` deve gerar SQL correto para alterações simples de tipo, nullable e default.
- `Connection.getDoctrineSchemaManager()` não deve retornar `null` em conexões suportadas.
- [x] Testes unitários devem cobrir introspecção sem banco usando fixtures.
- Testes de integração devem cobrir PostgreSQL e MySQL quando disponíveis.

## Fase 3 - Completar Schema Builder antes de Migrations

Objetivo: garantir que migrations usem uma API de schema suficientemente completa.

Tarefas:

- Revisar `lib/src/schema/blueprint.dart` contra o Blueprint PHP.
- Garantir suporte aos comandos:
  - `create`
  - `table`
  - `drop`
  - `dropIfExists`
  - `rename`
  - `renameColumn`
  - `dropColumn`
  - `change`
  - `primary`
  - `unique`
  - `index`
  - `foreign`
  - `dropForeign`
  - `dropIndex`
- Padronizar retorno de SQL em `toSql`.
- Remover `print` de warnings internos e trocar por exceções, callbacks de log ou objetos de resultado.

Critérios de aceite:

- Cada comando de Blueprint deve ter teste de SQL para PostgreSQL e MySQL.
- Comandos não suportados devem falhar com mensagem clara.

## Fase 4 - Concluir port de `Migrations`

Referências PHP:

- `Migrations\Migration.php`
- `Migrations\MigrationCreator.php`
- `Migrations\MigrationRepositoryInterface.php`
- `Migrations\DatabaseMigrationRepository.php`
- `Migrations\Migrator.php`
- `Migrations\stubs`

Estado atual no Dart:

- `lib/src/migrations` já existe, mas ainda depende de registry manual e tem vários TODOs.

Tarefas por classe:

### `Migration`

- Garantir `up()` e `down()` assíncronos.
- Definir `connectionName`.
- Expor `schema` de forma segura via `DatabaseManager` ou resolver.
- Definir contrato para migrations transacionais.

### `DatabaseMigrationRepository`

- Implementar criação da tabela `migrations`.
- Implementar:
  - `getRan`
  - `getMigrations`
  - `getLast`
  - `log`
  - `delete`
  - `getNextBatchNumber`
  - `getLastBatchNumber`
  - `repositoryExists`
  - `createRepository`
- Garantir compatibilidade com tabela padrão Laravel:

```text
migrations
  id
  migration
  batch
```

### `MigrationCreator`

- Trocar stubs inline por arquivos em `lib/src/migrations/stubs` ou `tool/stubs`.
- Gerar arquivos Dart idiomáticos.
- Gerar nomes de classe em PascalCase.
- Suportar:
  - migration em branco
  - `--create=table`
  - `--table=table`
- Definir estratégia para registrar migrations:
  - arquivo `migrations.dart` gerado
  - build manual pelo usuário
  - import dinâmico não é recomendado em Dart AOT

### `Migrator`

- Completar:
  - `run`
  - `runMigrationList`
  - `rollback`
  - `reset`
  - `refresh`
  - `status`
  - `pretend`
- Implementar execução transacional quando a conexão/grammar suportar.
- Resolver connection por migration.
- Evitar registry frágil: criar mecanismo documentado de registro.
- Retornar resultados estruturados além de `notes`, por exemplo `MigrationResult`.

Critérios de aceite:

- `migrate:install` cria a tabela de migrations.
- `migrate` executa pendentes na ordem correta.
- `migrate:rollback --step=N` reverte batches corretamente.
- `migrate:reset` reverte tudo.
- `migrate:refresh` faz reset + migrate.
- `migrate:status` mostra ran/pending.
- `--pretend` exibe SQL sem executar.
- Testes devem usar fake connection e pelo menos um teste real PostgreSQL.

## Fase 5 - Portar `Console\Migrations`

Referências PHP:

- `Console\Migrations\BaseCommand.php`
- `InstallCommand.php`
- `MigrateCommand.php`
- `MigrateMakeCommand.php`
- `RefreshCommand.php`
- `ResetCommand.php`
- `RollbackCommand.php`
- `StatusCommand.php`

Recomendação Dart:

- Usar `package:args` para parsing de comandos.
- Adicionar dependência quando iniciar a implementação:

```yaml
dependencies:
  args: ^2.0.0
```

Tarefas:

- Criar abstração simples:
  - `Command`
  - `CommandContext`
  - `CommandResult`
  - `CommandRunner`
- Implementar `bin/eloquent.dart`.
- Implementar comandos:
  - `migrate:install`
  - `migrate`
  - `make:migration`
  - `migrate:rollback`
  - `migrate:reset`
  - `migrate:refresh`
  - `migrate:status`
- Suportar opções:
  - `--database`
  - `--path`
  - `--realpath`
  - `--pretend`
  - `--force`
  - `--step`
  - `--seed`, se seeders forem suportados
- Definir formato de saída compatível com terminal, mas sem depender de Symfony Console.

Critérios de aceite:

- `dart run eloquent migrate:install` funciona.
- `dart run eloquent make:migration create_users_table --create=users` cria arquivo Dart em `database/migrations`.
- `dart run eloquent migrate --pretend` lista SQL esperado.
- Códigos de saída:
  - `0` sucesso
  - `1` erro de validação ou execução
  - `2` configuração ausente

## Fase 6 - Portar `Console\Seeds`

Referências PHP:

- `Console\Seeds\SeedCommand.php`
- `Console\Seeds\SeederMakeCommand.php`
- `Console\Seeds\stubs\seeder.stub`
- `Seeder.php`
- `SeedServiceProvider.php`

Tarefas:

- Criar `lib/src/seeding/seeder.dart`.
- Criar contrato `Seeder.run()`.
- Criar `DatabaseSeeder` padrão opcional.
- Implementar comandos:
  - `db:seed`
  - `make:seeder`
- Definir registry de seeders compatível com Dart.

Critérios de aceite:

- `dart run eloquent make:seeder UserSeeder` cria arquivo.
- `dart run eloquent db:seed --class=UserSeeder` executa seeder registrado.

## Fase 7 - Configuração de aplicação para CLI

Problema: Laravel obtém configuração pelo container; em Dart o CLI precisa descobrir config.

Opções recomendadas:

1. Arquivo `eloquent_config.dart` exportando uma função.
2. Arquivo `database.dart` em `database/config`.
3. JSON/YAML para CLI e Dart code para migrations.

Recomendação inicial:

```text
database/
  migrations/
  seeders/
  eloquent_config.dart
```

Exemplo:

```dart
import 'package:eloquent/eloquent.dart';

Future<DatabaseManager> createDatabaseManager() async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'database': 'app',
    'username': 'postgres',
    'password': 'secret',
  });
  manager.setAsGlobal();
  return manager.getDatabaseManager();
}
```

O CLI pode aceitar:

```bash
dart run eloquent migrate --config=database/eloquent_config.dart
```

Se import dinâmico não for viável, a alternativa é gerar um entrypoint local:

```text
bin/migrate.dart
```

## Fase 8 - Ordem recomendada de implementação

1. Doctrine connection e schema manager funcionando.
2. Blueprint/SchemaGrammar com `renameColumn` e `change`.
3. Repository de migrations completo.
4. Migrator completo sem CLI.
5. MigrationCreator gerando arquivos Dart.
6. CLI em `bin/eloquent.dart`.
7. Comandos de migration.
8. Seeders.
9. Documentação de uso no README.
10. Exemplos em `example/`.

## Fase 9 - Testes mínimos

Unitários:

- `test/doctrine_schema_manager_test.dart`
- `test/schema_blueprint_sql_test.dart`
- `test/migration_repository_test.dart`
- `test/migrator_test.dart`
- `test/migration_creator_test.dart`
- `test/console_migration_command_test.dart`

Integração:

- PostgreSQL:
  - criar tabela
  - alterar coluna
  - renomear coluna
  - foreign key
  - migrations up/down
- MySQL:
  - criar tabela
  - alterar coluna
  - renomear coluna
  - migrations up/down

## Fase 10 - Breaking changes a decidir antes de publicar

- Renomear `lib/src/doctrine/patforms` para `platforms`.
- Remover APIs PHP-like que só existem por compatibilidade interna.
- Trocar `Map<String, dynamic>` internos de migrations/schema por classes tipadas.
- Definir se CLI será parte do pacote principal ou pacote separado.
- Definir se `bin/eloquent.dart` será exportado como executável no `pubspec.yaml`.

## Resultado esperado

Ao final, o pacote deve permitir:

```dart
await db.schema().create('users', (table) {
  table.id();
  table.string('name');
  table.timestamps();
});
```

E também:

```bash
dart run eloquent make:migration create_users_table --create=users
dart run eloquent migrate
dart run eloquent migrate:status
dart run eloquent migrate:rollback --step=1
```

Com introspecção suficiente para:

```dart
await db.schema().table('users', (table) {
  table.renameColumn('name', 'full_name');
  table.string('email').nullable().change();
});
```
