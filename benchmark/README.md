# PostgreSQL driver benchmark

Compara o custo dos drivers PostgreSQL via a API do Eloquent:

- `postgres_fork` (`driver_implementation: postgres`, dependency `postgres_fork: ^2.8.5`)
- `postgres` (`driver_implementation: postgres_v3`, dependency `postgres: ^3.5.4`)
- `dargres` (`driver_implementation: dargres`, dependency `dargres: ^3.1.2`)
- `dpgsql` (`driver_implementation: dpgsql`, dependency local `../dpgsql`)

## Rodar

```powershell
dart run benchmark\postgres_drivers_benchmark.dart
```

Defaults:

- `PGHOST=localhost`
- `PGPORT=5432`
- `PGDATABASE=banco_teste`
- `PGUSER=dart`
- `PGPASSWORD=dart`
- `PGSCHEMA=public`
- `PG_BENCH_ITERATIONS=200`
- `PG_BENCH_TX_ITERATIONS=50`
- `PG_BENCH_RESULT_ROWS=200`
- `PG_BENCH_POOL=false`

Exemplo com outro database:

```powershell
$env:PGDATABASE='dart_test'
dart run benchmark\postgres_drivers_benchmark.dart
```

Exemplo filtrando drivers:

```powershell
$env:PG_BENCH_DRIVERS='postgres,postgres_v3,dpgsql'
dart run benchmark\postgres_drivers_benchmark.dart
```

Exemplo com pool:

```powershell
$env:PG_BENCH_POOL='true'
$env:PG_BENCH_POOL_SIZE='4'
dart run benchmark\postgres_drivers_benchmark.dart
```

O script imprime uma tabela resumida e, em seguida, um JSON completo com tempos por workload. Se um driver falhar, ele registra o erro daquele driver e continua os demais.
