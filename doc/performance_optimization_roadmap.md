# Roteiro de otimização de performance do Eloquent

## Objetivo

Reduzir latência e alocações no caminho comum do Eloquent sem mudar contrato público dos drivers antigos. O foco inicial é o custo percebido via QueryBuilder/Connection, porque o benchmark de drivers PostgreSQL mostra que chamadas pequenas repetidas dominam o tempo total.

## Baseline atual

Benchmark usado:

```powershell
dart run benchmark\postgres_drivers_benchmark.dart
```

Ambiente do último resultado anexado:

- `PGHOST=localhost`
- `PGPORT=5432`
- `PGDATABASE=banco_teste`
- `PGUSER=dart`
- `PG_BENCH_ITERATIONS=200`
- `PG_BENCH_TX_ITERATIONS=50`
- `PG_BENCH_RESULT_ROWS=200`
- `PG_BENCH_POOL=false`

Resultados observados em duas rodadas sem pool:

| Driver | total ms rodada 1 | ops/s rodada 1 | total ms rodada 2 | ops/s rodada 2 |
|---|---:|---:|---:|---:|
| `postgres_fork` | 458.096 | 1855.506 | 426.451 | 1993.195 |
| `postgres` v3 | 820.209 | 1036.321 | 781.119 | 1088.182 |
| `dargres` | 3098.681 | 274.310 | 2763.522 | 307.579 |
| `dpgsql` | 279.994 | 3035.779 | 276.431 | 3074.908 |

Leitura:

- `result_set` de 200 linhas não é o gargalo principal neste benchmark.
- Os gargalos estão em `scalar_select`, `insert`, `select_by_id` e transações pequenas.
- O `dpgsql` lidera neste workload, especialmente em inserts e transações pequenas.
- O `dargres` está muito atrás em chamadas pequenas; investigar o driver C:\MyDartProjects\dargres> 

## Otimizações pequenas já aplicadas

- `QueryBuilder.insert()` monta bindings direto com `values.values.toList(growable: false)`.
- `QueryBuilder.cleanBindings()` retorna a própria lista quando não há `QueryExpression`.
- `QueryBuilder.addBinding()` usa `addAll()` em-place, sem recriar a lista inteira.
- `Connection.prepareBindings()` cacheia configuração derivada do driver e resolve `getDriverName()` só quando aparece `false`.
- `DpgsqlPDO.query()` adiciona parâmetros direto no comando, sem `DpgsqlParameterCollection` temporária.
- `DpgsqlPDO.expectsRows()` deixou de usar `RegExp` por execução para detectar `RETURNING`.

## Princípios

- Otimizar apenas com benchmark antes/depois no mesmo ambiente.
- Separar ganho de ruído: executar várias amostras e registrar p50/p95/p99.
- Preservar contrato de retorno: maps, tipos de `DateTime`, affected rows e transações.
- Não misturar refatoração ampla com mudança de performance.
- Cada mudança de hot path precisa de teste funcional e benchmark comparável.

## Fase 1: melhorar o laboratório de benchmark

Prioridade: alta.

1. Adicionar múltiplas amostras ao `benchmark/postgres_drivers_benchmark.dart`.
2. Registrar `min`, `median`, `p95`, `p99`, `avg` e desvio simples por workload.
3. Exportar JSON opcional para `benchmark/reports/`.
4. Adicionar modo AOT:

```powershell
dart compile exe benchmark\postgres_drivers_benchmark.dart -o build\postgres_drivers_benchmark.exe
```

5. Rodar matriz mínima:

- sem pool
- com pool
- `PG_BENCH_ITERATIONS=200`
- `PG_BENCH_ITERATIONS=2000`
- `PG_BENCH_RESULT_ROWS=200`
- `PG_BENCH_RESULT_ROWS=10000`

Critério de aceite:

- Variação menor que 5% em pelo menos 3 de 5 amostras ou resultado reportado como inconclusivo.

## Fase 2: QueryBuilder e bindings

Prioridade: alta.

### 2.1 `first()` sem passar pelo caminho completo de `get()`

Arquivo: `lib/src/query/query_builder.dart`.

Hoje `first()` chama `take(1).get()`, que:

- clona/restaura `columnsProp`;
- executa `processor.processSelect()`;
- retorna lista para depois pegar o primeiro item.

Roteiro:

1. Criar um caminho interno `runSelectOne()` ou `connection.selectOne()`.
2. Manter `limit 1`.
3. Evitar `processor.processSelect()` quando ele é no-op.
4. Garantir que `first()` preserve estado do builder como hoje.

Critério de aceite:

- `select_by_id` melhora sem quebrar testes de `first()`, `paginate()`, `chunk()` e queries com columns customizadas.

### 2.2 `insertGetId()` e `update()` com menos listas temporárias

Arquivos:

- `lib/src/query/query_builder.dart`
- `lib/src/query/grammars/query_grammar.dart`

Roteiro:

1. Usar `toList(growable: false)` em `insertGetId()`.
2. Em `update()`, trocar spread `[...]` por lista pré-alocada ou `List.of(values, growable: true)..addAll(currentBindings)`.
3. Evitar `values.keys.toList()` e `values.values.toList()` duplicados em `compileInsert()`.
4. Criar helper interno que retorna colunas e bindings uma vez para `insert()` e `compileInsert()`.

Critério de aceite:

- Melhorar workload `insert` e não alterar SQL gerado nos testes de grammar.

### 2.3 `insertMany()` com lista pré-dimensionada

Arquivo: `lib/src/query/query_builder.dart`.

Hoje os bindings crescem via `add()`.

Roteiro:

1. Calcular `values.length * columns.length`.
2. Criar `List<dynamic>.filled(total, null, growable: false)`.
3. Preencher por índice.
4. Manter validação de chaves iguais como opção futura.

Critério de aceite:

- Reduzir alocação em batch inserts grandes.

### 2.4 `getBindings()` e `cleanBindings()`

Roteiro:

1. Medir frequência de `getBindings()` em selects simples.
2. Avaliar cache invalidável de bindings achatados por builder.
3. Invalidar cache em `addBinding()`, `setBindings()`, `mergeBindings()`, `where*`, joins, unions.

Critério de aceite:

- Só implementar cache se o benchmark mostrar custo relevante, porque invalidação incorreta gera bugs difíceis.

## Fase 3: compilação SQL/Grammar

Prioridade: média/alta.

### 3.1 Remover dispatch dinâmico de `compileComponents()`

Arquivo: `lib/src/query/grammars/query_grammar.dart`.

Hoje:

- percorre `selectComponents` como strings;
- chama `query.getProperty(component)`;
- monta `methodName`;
- usa `callMethod()`.

Roteiro:

1. Trocar por chamadas explícitas em ordem fixa:
   - expressions
   - aggregate
   - columns
   - from
   - joins
   - wheres
   - groups
   - havings
   - orders
   - limit
   - offset
   - unions
   - lock
2. Manter método antigo temporariamente atrás de teste comparativo, se necessário.
3. Cobrir com `pg_query_qrammar_test.dart`.

Critério de aceite:

- Mesmo SQL para todos os testes de grammar.
- Melhorar `scalar_select` e `select_by_id`.

### 3.2 Evitar mutação desnecessária em `compileSelect()`

Hoje `compileSelect()` seta `query.columnsProp = ['*']` e depois restaura.

Roteiro:

1. Passar columns efetivas para `compileColumns()` sem mutar o builder.
2. Manter comportamento com aggregate e CTEs.

Critério de aceite:

- Sem regressão em queries sem columns, aggregate, exists, union e pagination.

### 3.3 String building

Roteiro:

1. Trocar concatenação em loops por `StringBuffer` onde há crescimento repetido:
   - `compileUnions()`
   - joins complexos
   - where nested/raw
2. Evitar `Utils.implode()` quando `List.join()` basta.
3. Evitar `map(...).toList()` em `compileOrders()`.

Critério de aceite:

- Ganho medido em queries complexas com joins/unions, sem piorar selects simples.

## Fase 4: Connection hot path

Prioridade: alta.

### 4.1 `prepareBindings()`

Roteiro:

1. Guardar `grammar.getDateFormat()` em cache por connection/grammar.
2. Evitar obter grammar se a lista não contém `DateTime`.
3. Fast path: se não há `DateTime` nem `false`, retornar bindings sem loop de transformação.
4. Invalidar caches quando connection/grammar/config mudarem.

Critério de aceite:

- Melhorar `scalar_select` e `select_by_id`, onde bindings são pequenos e frequentes.
- Preservar `DateTime` como objeto quando `driver_implementation == dpgsql`.

### 4.2 `select()`/`statement()` closures

Roteiro:

1. Medir custo de `run()` + closure por query.
2. Criar fast path interno para execução normal quando não está `pretending()`.
3. Manter logging/reconnect behavior se existir dependência desses recursos.

Critério de aceite:

- Ganho em chamadas pequenas sem alterar tratamento de reconexão.

## Fase 5: adapters PDO

Prioridade: alta para `dpgsql` e `postgres_v3`; média para `postgres_fork`; investigativa para `dargres`.

### 5.1 `DpgsqlPDO`: configurar sessão no open do pool

Arquivo: `lib/src/pdo/dpgsql/dpgsql_pdo.dart`.

Hoje `_configureSession()` roda em `_openConnectionForOperation()` quando usa `DpgsqlDataSource`. Isso pode executar `SET search_path`, `SET timezone`, `SET application_name` etc. em toda operação.

Roteiro:

1. Verificar se `DpgsqlDataSource` suporta callback/hook de abertura física (`onOpen` ou equivalente).
2. Se suportar, mover `_configureSession()` para abertura física da conexão.
3. Se não suportar, cachear por conexão física com marcação de sessão configurada, se a API permitir identificar conexão.
4. Se não for possível com segurança, documentar custo e manter como está.

Critério de aceite:

- Melhorar modo pool sem mudar sessão por operação.
- Garantir que conexões retornadas pelo pool sempre estejam com schema/timezone corretos.

### 5.2 `DpgsqlPDO`: detecção de tipo de comando

Roteiro:

1. Substituir `trimLeft().toLowerCase()` por scanner ASCII que identifica primeiro token e `RETURNING` sem criar string inteira minúscula.
2. Medir impacto. Este custo pode ser pequeno frente à rede.

Critério de aceite:

- Não piorar legibilidade se ganho for irrelevante.

### 5.3 `postgres_v3` adapter

Arquivo: `lib/src/pdo/postgres_v3/postgres_v3_pdo.dart`.

Roteiro:

1. Medir custo de `Sql.indexed(query, substitution: '?')` por execução.
2. Avaliar cache de `Sql` compilado por string SQL para queries repetidas.
3. Evitar reconstrução de maps quando valor não é `UndecodedBytes`.
4. Criar fast path para selects sem `UndecodedBytes`.

Critério de aceite:

- Melhorar `postgres` v3 em `scalar_select` e `select_by_id`.

### 5.4 `postgres_fork` adapter

Arquivo: `lib/src/pdo/postgres/postgres_pdo.dart`.

Roteiro:

1. Evitar `rs.map(...).toList()` quando o resultado já puder ser iterado para lista com pré-alocação.
2. Verificar se `toColumnMap()` cria mapa novo sempre e se existe acesso mais direto.
3. Medir diferença entre pool e conexão simples.

### 5.5 `dargres` adapter

Arquivo: `lib/src/pdo/dargres/dargres_pdo.dart`.

Roteiro:

1. Investigar por que chamadas pequenas estão muito lentas.
2. Separar custo do driver puro vs adapter Eloquent.
3. Verificar `queryNamed()` com placeholder `?`, conversão `toMaps()` e transação.
4. Se o gargalo for driver, documentar e evitar otimizações no Eloquent para mascarar.

Critério de aceite:

- Ter diagnóstico claro antes de mudar código.

## Fase 6: retorno de rows e processamento

Prioridade: média.

Roteiro:

1. Confirmar se `Processor.processSelect()` é no-op na maioria dos drivers.
2. Pular processor quando for exatamente `Processor` base.
3. Avaliar API interna para `selectFirst()` que não materializa lista inteira.
4. Para result sets grandes, avaliar streaming/chunk real por driver.

Critério de aceite:

- Melhorar `first()` e reduzir memória em result sets grandes.

## Fase 7: API de benchmark para regressão

Prioridade: alta.

Roteiro:

1. Criar `benchmark/reports/`.
2. Criar script de comparação:

```powershell
dart run benchmark\postgres_drivers_benchmark.dart > benchmark\reports\before.json
dart run benchmark\postgres_drivers_benchmark.dart > benchmark\reports\after.json
```

3. Criar parser que ignore a tabela textual e leia apenas JSON.
4. Alertar regressões acima de 5% por workload.
5. Salvar baseline por driver.

Critério de aceite:

- Cada PR de performance mostra antes/depois com workload afetado.

## Ordem sugerida de execução

1. Melhorar benchmark com múltiplas amostras e percentis.
2. Implementar `first()` fast path.
3. Otimizar `compileComponents()` sem dispatch dinâmico.
4. Otimizar `compileInsert()`/`update()`/`insertMany()` com menos listas temporárias.
5. Investigar `DpgsqlDataSource` para configurar sessão no open do pool.
6. Investigar cache de `Sql.indexed()` no adapter `postgres_v3`.
7. Diagnosticar `dargres` isolando driver puro vs adapter Eloquent.
8. Avaliar fast path de `Connection.select()`/`statement()`.

## Checklist para cada otimização

- [ ] Benchmark antes/depois no mesmo terminal.
- [ ] Pelo menos 3 amostras ou percentis.
- [ ] Teste unitário/integração do caminho alterado.
- [ ] Sem mudança de contrato público.
- [ ] Sem alteração de comportamento entre drivers antigos.
- [ ] Resultado documentado no PR ou no `todo.md`.

