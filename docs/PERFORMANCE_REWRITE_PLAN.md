# Plano de Reescrita Focada em Performance — `eloquent_dart`

> Branch: **`performace`**
> Objetivo geral: evoluir a biblioteca de um _port_ literal do Illuminate/Laravel para um
> data-access layer de alta performance para Dart, **sem code generation**, com:
> Query Builder mais rápido e mais expressivo (UPSERT / `ON CONFLICT ... DO UPDATE ... RETURNING`),
> **streaming/cursor** server-side, **acesso direto ao driver** (COPY, pipelining, batch, LISTEN/NOTIFY),
> **migrations** utilizáveis de ponta a ponta, **seeds/seeders**, **schema-diff → ALTER** e novos
> recursos do PostgreSQL. O driver primário-alvo é o [`dpgsql`](https://github.com/insinfo/dpgsql);
> `dargres`/`pg8000`/`postgres_v3` são secundários.

---

## 0. Diagnóstico do estado atual (baseline)

Levantamento feito diretamente sobre o código em `lib/src`.

### 0.1 Query Builder (`lib/src/query/query_builder.dart`, 2821 linhas)
- Port literal do Illuminate. Superfície pública ampla (select/where/join/aggregates/CTE/unions/locks/paginate).
- **Sem UPSERT / `ON CONFLICT`.** O que mais se aproxima é `updateOrInsert` (linha ~2324): emulação em 2–3 round-trips (`SELECT EXISTS` + `INSERT`/`UPDATE`), **não atômica**, com race condition e efeito colateral de duplicar cláusulas `where` no `this`.
- **`RETURNING` só existe no caminho `insertGetId`** (`QueryPostgresGrammar.compileInsertGetId`), fixo em uma coluna. Não há `returning()` genérico nem `RETURNING ... INTO`.
- **Sem streaming/cursor/lazy.** `chunk()` é `LIMIT/OFFSET` (O(n²) em tabelas grandes), `chunkById()` é keyset — ambos re-executam a query e materializam páginas inteiras. `ConnectionInterface.select` devolve `Future<List<Map>>` (buffer completo).
- **Hot-path de compilação custoso:**
  - Concatenação de `String` com `+` em todas as gramáticas (sem `StringBuffer`).
  - Cláusulas armazenadas como `List<Map<String,dynamic>>` — cada acesso é hash-lookup + cast dinâmico.
  - Dispatch "reflection-like" por nome: `callMethod`/`getProperty` fazem lookup em `Map<String,Function>` por string em cada cláusula; `compileComponents` monta `'compile'+ucfirst(component)` por componente por compilação.
  - Cópias repetidas de listas (`getBindings()` re-aloca 8 segmentos; `clone()` deep-copia todos os maps).
- **Sem acesso ao driver** a partir do builder: só conhece `ConnectionInterface` (métodos `select/insert/update/delete/statement`).
- Bug de compilação: `QueryPostgresGrammar.compileInsert` no branch de valores vazios gera `"insert into $table} DEFAULT VALUES"` (chave `}` perdida).

### 0.2 Camada Connection / PDO
- `PDOExecutionContext` mínima: só `execute(sql)` e `query(sql, params)` (ambos bufferizados). `PDOInterface` adiciona `connect`, `runInTransaction`, `close`.
- `Connection.select/insert/affectingStatement` → `run()` → `runQueryCallback()` → `pdo.query(...)`. `prepareBindings()` converte `DateTime`→string e `false`→`0` (exceto pgsql).
- `Connection.getPdo()` devolve `PDOExecutionContext` (ponto de extensão existente, mas não tipado por driver).
- Seleção de driver em `postgres_connector.dart:191` via `driver_implementation` (`postgres` | `postgres_v3` | `dargres` | `dpgsql`). Cada PDO guarda a conexão nativa própria (`DpgsqlConnection`, `dargres.ConnectionInterface`, postgres v3 `Connection`/`Pool`).
- Transações: `Connection.transaction` → `pdo.pdoInstance.runInTransaction`, criando uma `Connection` nova envolta no contexto transacional. No dpgsql o contexto transacional carrega o `DpgsqlConnection` vivo (essencial para COPY/stream dentro de transação).

### 0.3 Capacidades do driver `dpgsql` **não expostas** hoje
O pacote já oferece (via `package:dpgsql/dpgsql.dart`):
- `DpgsqlConnection.executeReader()` → `DpgsqlDataReader` com `read()` linha-a-linha ⇒ **cursor/streaming real**.
- `beginBinaryImport` / `beginBinaryExport` / `beginRawBinaryCopy` / `beginTextImport` / `beginTextExport` ⇒ **COPY** binário e texto.
- `executeQueryPipelined` / `executeBatchPipelined` / `executeCommandsPipelined` ⇒ **pipelining**.
- `DpgsqlBatch` ⇒ batch de comandos.
- `LargeObjectManager` ⇒ large objects.
- `DpgsqlReplicationConnection` + protocolo de replicação lógica ⇒ CDC / LISTEN.
- `prepare(named)`, `executeScalar`, `executeRows`, `executePgRows`, tipos ricos (geometric, tsvector, tsquery, range).

### 0.4 Migrations / Schema / Doctrine
- **Migrator** (`migrations/migrator.dart`) estruturalmente completo (`run/rollback/reset/pretend/batching`), mas: sem CLI, classes **não exportadas** em `eloquent.dart`, `migration.db` nunca é injetado (o getter `schema` lançaria em runtime), e `migrationRegistry` (mapa nome→factory) precisa ser preenchido à mão — **não há gerador**.
- **Seeds/Seeders/Factories: 0%** — não existe nada.
- **Doctrine schema-diff:** introspecção (Postgres/MySQL) + modelo de diff (`Comparator`, `TableDiff`, `SchemaDiff`) reais e substanciais; `Connection` já está integrado (`getDoctrineSchemaManager` funciona). Porém a geração **diff → ALTER SQL** é o elo que falta: `schema.dart:319/329` (`toSql`) lançam `UnimplementedError` e os `compileChange` das gramáticas **não** consomem o `Comparator` (geram ALTER direto do Blueprint, com warning em runtime).
- `todo.md` está **desatualizado**: `schema_mysql_grammar.dart` é completo (~24 KB), `getDoctrineTableDiff` está implementado.

---

## 1. Objetivos e princípios de design

1. **Sem code generation.** Nada de `build_runner`/macros. Metadados de entidade via API fluente/mapas em runtime; `migrationRegistry` gerado por _scanner_ opcional em tempo de execução (não em build).
2. **Zero-cost quando não usado.** Recursos novos (stream, COPY, driver access) não podem penalizar o caminho comum `get()`.
3. **Compatibilidade retroativa.** A API pública atual (`db.table(...).where(...).get()`) continua funcionando; melhorias são aditivas ou trocas internas transparentes.
4. **Fim do dispatch por string no hot-path.** Cláusulas tipadas + `StringBuffer` + dispatch direto.
5. **Capacidades específicas do driver via _capability interface_**, com _feature detection_ e `UnsupportedError` claro em drivers que não suportam.
6. **Cada fase entrega valor testável isoladamente** (com testes e, quando possível, benchmark antes/depois).

---

## 2. Arquitetura alvo (visão)

```
QueryBuilder ──► QueryGrammar (compile, StringBuffer, dispatch direto)
     │                 └─ PostgresGrammar (UPSERT, RETURNING, JSONB, arrays…)
     │
     ├─► ConnectionInterface (select/insert/update/delete/statement)      [existente]
     │        + selectStream(sql,bindings)  → Stream<Map>                  [NOVO]
     │        + driver() → DriverAccess?                                   [NOVO]
     │
     └─► Connection ──► PDOExecutionContext
                              ├─ execute / query                          [existente]
                              ├─ queryStream(sql,params) → Stream<Map>    [NOVO, opt-in]
                              └─ driverAccess → DriverAccess?             [NOVO, opt-in]

DriverAccess (capability interface, por driver):
   - copyIn / copyOut (COPY texto e binário)
   - pipeline(...)   - batch(...)
   - rawConnection() (escape hatch tipado p/ dpgsql)
   - listen/notify (LISTEN/NOTIFY)         [dpgsql]
```

Módulos novos:
```
lib/src/streaming/         row_stream.dart, cursor_options.dart
lib/src/driver/            driver_access.dart, copy_options.dart, dpgsql_driver_access.dart
lib/src/seeds/             seeder.dart, seeder_runner.dart, factory.dart
lib/src/migrations/cli/    migrate_command.dart, registry_scanner.dart
bin/eloquent.dart          CLI (migrate / seed / make:*)
```

---

## 3. Roadmap por fases

Ordem escolhida por **valor entregue × risco × dependências**. Cada item = 1+ commit com testes.

### Fase 0 — Infra e baseline (habilitador)
- [ ] Exportar em `lib/eloquent.dart`: migrations, seeders, `DriverAccess`, streaming, `Migration`, `Blueprint`/grammars de schema faltantes, `SchemaMysqlGrammar`.
- [ ] Corrigir bug `compileInsert` (`$table}` → `$table`).
- [ ] Script de benchmark de compilação (`benchmark/query_compile_benchmark.dart`) para medir antes/depois do hot-path.
- [ ] Baseline de I/O com `dpgsql` (insert/select/upsert/copy) em `benchmark/`.

### Fase 1 — Query Builder: UPSERT / ON CONFLICT / RETURNING *(alta prioridade, pedido explícito)*
Entrega o caso do usuário:
```sql
INSERT INTO processos_sequences (ano, last_id)
VALUES (?, 1)
ON CONFLICT (ano) DO UPDATE SET last_id = processos_sequences.last_id + 1
RETURNING last_id;
```
- [ ] `QueryBuilder.upsert(values, uniqueBy, {update})` — Laravel-style, atômico.
- [ ] `QueryBuilder.insertOrIgnore(values)` → `ON CONFLICT DO NOTHING`.
- [ ] `QueryBuilder.onConflict(...)` fluente de baixo nível para casos avançados (`DO UPDATE SET col = tabela.col + 1`, `WHERE`, `DO NOTHING`, `ON CONSTRAINT`).
- [ ] `QueryBuilder.returning([cols])` genérico (aplica a `insert`/`update`/`delete`/`upsert`), retornando as linhas do `RETURNING`.
- [ ] `compileUpsert` + `compileInsertReturning` em `QueryPostgresGrammar` e `QueryMySqlGrammar` (MySQL: `ON DUPLICATE KEY UPDATE`).
- [ ] Testes de SQL gerado (grammar) + testes de integração com `dpgsql`.

> **`RETURNING ... INTO`** é sintaxe de **PL/pgSQL** (dentro de funções/DO blocks), não de SQL client. A tradução idiomática em client-side é `RETURNING col` cujo valor é lido no Dart (equivalente ao `INTO v_seq`). O plano cobre isso via `returning()` + leitura do resultado. Para quem realmente escreve funções, adicionaremos helper `db.plpgsql(...)`/`db.doBlock(...)` para blocos anônimos.

### Fase 2 — Hot-path de compilação (performance)
- [ ] Introduzir classes de cláusula tipadas (`WhereClause`, `JoinClause`, `OrderClause`, …) internas, mantendo a API pública.
- [ ] Trocar concatenação por `StringBuffer` nas gramáticas.
- [ ] Substituir `callMethod`/`getProperty` por dispatch direto (switch/tipo), eliminando `Map<String,Function>` e montagem de nomes por string.
- [ ] Reduzir alocações em `getBindings()`/`clone()`.
- [ ] Comparar no benchmark de compilação (meta: ≥2× no throughput de `toSql()` de queries médias).

### Fase 3 — Streaming / Cursor server-side
- [ ] `PDOExecutionContext.queryStream(sql, params, {int fetchSize})` → `Stream<Map<String,dynamic>>` (default: `UnsupportedError`; sobrescrito no dpgsql via `executeReader().read()`).
- [ ] Em drivers sem reader nativo: fallback com cursor SQL (`DECLARE ... FETCH`) dentro de transação.
- [ ] `ConnectionInterface.selectStream(...)` + `Connection.cursor(...)`.
- [ ] `QueryBuilder.cursor()` → `Stream<Map>` e `lazy()/lazyById()` construídos sobre o cursor (substituem `chunk` OFFSET por backpressure real).
- [ ] Testes: consumir 100k linhas com memória ~constante.

### Fase 4 — Acesso direto ao driver: COPY, pipelining, batch, LISTEN/NOTIFY
- [ ] Interface `DriverAccess` + `Connection.driver()` / `QueryBuilder.driver()`.
- [ ] `DpgsqlDriverAccess`:
  - `copyInText/copyInBinary(table, columns, rows/stream)` e `copyOutText/copyOutBinary(query)` → COPY.
  - `pipeline([...])`, `batch([...])`.
  - `listen(channel)` → `Stream<Notification>`, `notify(channel, payload)`.
  - `rawConnection()` → `DpgsqlConnection` (escape hatch tipado).
- [ ] Helper de alto nível `QueryBuilder.copyInto(rows)` para carga em massa (usa COPY quando disponível, cai para `insertMany` senão).
- [ ] Testes de COPY round-trip e de LISTEN/NOTIFY.

### Fase 5 — Migrations utilizáveis de ponta a ponta *(sem codegen)*
- [ ] Exportar `Migration`, `Migrator`, `MigrationCreator`, repositório.
- [ ] Injetar `migration.db` em `_runUp/_runDown` (corrige o getter `schema`).
- [ ] `registry_scanner.dart`: em runtime, o app registra migrations num `Map` (padrão explícito, sem reflexão) **ou** usamos um _barrel_ gerado por comando CLI (`make:migration` já cria o arquivo; um comando `migrate:sync` regenera o barrel `migrations.dart` com os imports+registro). Isso mantém "sem code generation" no sentido de build-time/macros — é geração de texto simples opcional via CLI.
- [ ] CLI `bin/eloquent.dart`: `migrate`, `migrate:rollback`, `migrate:reset`, `migrate:status`, `make:migration`.
- [ ] Transação por migration (TODO em `migrator.dart:111`).
- [ ] Testes do ciclo up/down contra `dpgsql`.

### Fase 6 — Seeds / Seeders / Factories
- [ ] `abstract class Seeder { Future<void> run(); }` + `call(otherSeeder)`.
- [ ] `SeederRunner` + registro explícito (mesmo padrão das migrations).
- [ ] `Factory<T>` leve (definição via callback, `count`, `state`, `make`/`create`) — usa `insertMany`/COPY para volume.
- [ ] CLI: `db:seed`, `make:seeder`.
- [ ] Testes.

### Fase 7 — Schema diff → ALTER (fechar o loop Doctrine)
- [ ] Implementar `CreateSchemaObjectsSQLBuilder`/`DropSchemaObjectsSQLBuilder` (`schema.dart:319/329`).
- [ ] Rotear `compileChange`/`compileRenameColumn` pelo `Comparator`/`SchemaDiff` quando houver schema manager.
- [ ] Refinar igualdade de colunas (hoje "SIMPLIFICADO").
- [ ] `parsePortableTableIndexDefinition` (postgres_schema_manager.dart:534).
- [ ] Comando CLI `schema:diff` (introspecção viva vs. schema desejado).

### Fase 8 — ORM leve sem code generation (opcional, camada fina)
- [ ] Mapeamento por convenção + configuração fluente (`EntityMap`), sem macros.
- [ ] `Repository<T>` sobre o QueryBuilder: `find/all/save/delete`, hidratação map→objeto via callback do usuário (sem reflexão).
- [ ] Identity map opcional e _change tracking_ leve para `save()` gerar UPDATE mínimo.
- [ ] Relacionamentos carregados sob demanda via query builder (sem lazy-proxies mágicos).

### Fase 9 — Recursos PostgreSQL de query builder
- [ ] JSON/JSONB: `whereJsonContains`, `->`/`->>`, `jsonb_set`, path updates.
- [ ] Arrays: operadores `@>`, `&&`, `ANY`, `unnest`.
- [ ] Ranges e tipos ricos do dpgsql.
- [ ] `LATERAL` (parcial já existe), window functions helpers, full-text (`tsvector`/`tsquery`), `DISTINCT ON`.
- [ ] `INSERT ... FROM SELECT` com RETURNING; `MERGE` (PG 15+).

---

## 4. Esboços de API (concretos)

### 4.1 UPSERT idiomático (Laravel-style)
```dart
await db.table('processos_sequences').upsert(
  [{'ano': 2026, 'last_id': 1}],
  ['ano'],                                   // conflito
  {'last_id': db.raw('processos_sequences.last_id + 1')}, // DO UPDATE SET
);
```

### 4.2 Caso exato do usuário (baixo nível + RETURNING)
```dart
final rows = await db.table('processos_sequences')
  .onConflict(['ano'])
  .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
  .returning(['last_id'])
  .insert({'ano': 2026, 'last_id': 1});

final seq = rows.first['last_id']; // equivalente ao "INTO v_seq"
```

### 4.3 Streaming / cursor
```dart
await for (final row in db.table('big_table').where('ativo', '=', true).cursor()) {
  process(row); // memória ~constante
}
```

### 4.4 Acesso direto ao driver + COPY
```dart
final drv = db.driver();                     // DriverAccess? (null se indisponível)
if (drv != null && drv.supportsCopy) {
  await drv.copyInText('temp_location', ['id','city'], rowsStream);
  final out = drv.copyOutText('COPY (SELECT * FROM t) TO STDOUT');
}
final DpgsqlConnection raw = (drv as DpgsqlDriverAccess).rawConnection(); // escape hatch
```

### 4.5 LISTEN/NOTIFY
```dart
final sub = db.driver()!.listen('canal').listen((n) => print(n.payload));
await db.driver()!.notify('canal', 'ping');
```

---

## 5. Compatibilidade retroativa
- Nenhuma assinatura pública existente é removida nesta reescrita; `chunk`/`each` permanecem (marcados como legado quando `cursor()/lazy()` existirem).
- Novos métodos em `PDOExecutionContext`/`ConnectionInterface` têm **implementação default** (`UnsupportedError`) para não quebrar drivers/consumidores externos.
- `DriverAccess` é _opt-in_ e retorna `null` quando o driver não suporta.

## 6. Critérios de aceite e métricas
- Fase 1: SQL gerado idêntico ao esperado nos testes; upsert atômico validado contra `dpgsql`.
- Fase 2: ≥2× throughput em `toSql()` no benchmark de compilação; sem regressão de testes.
- Fase 3: 100k linhas com memória estável (sem materializar tudo).
- Fase 4: COPY round-trip correto e mais rápido que `insertMany` para ≥10k linhas.
- Todas as fases: `dart analyze` limpo e testes verdes.

## 7. Riscos e mitigação
- **Diferenças entre drivers** (só dpgsql tem COPY/reader nativo) → capability interface + fallback + `UnsupportedError` explícito.
- **"Sem code generation" vs. migrations** → registro explícito em runtime é o padrão; o "gerador" é apenas emissão de texto via CLU opcional (não build-time/macros).
- **Reescrita do hot-path** pode introduzir regressões sutis de SQL → cobertura de testes de grammar antes de refatorar.
- **Escopo grande** → fases independentes e commitáveis; entregar valor incrementalmente.

---

## 8. Ordem de execução imediata (primeiros commits neste branch)
1. `docs/PERFORMANCE_REWRITE_PLAN.md` (este arquivo) + fix `compileInsert`.  ← commit 1
2. Fase 1: `upsert` / `insertOrIgnore` / `onConflict` / `returning` + grammar + testes.  ← commits 2–3
3. Fase 3: `cursor()`/streaming no dpgsql + testes.  ← commit 4
4. Fase 4: `DriverAccess` + COPY no dpgsql + testes.  ← commit 5
5. Fase 5–6: migrations end-to-end + seeders + CLI.  ← commits seguintes
