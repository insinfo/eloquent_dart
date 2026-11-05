# Issues found in `package:postgres`

Findings from using [`postgres`](https://pub.dev/packages/postgres) as one of the PostgreSQL drivers of [`eloquent`](https://pub.dev/packages/eloquent), a Laravel-style query builder for Dart. It is meant as input for a report to the package's author.

Everything below was run against **two versions**, so that nothing already fixed gets reported:

| Version | Dart | Why |
| --- | --- | --- |
| 3.5.7 | 3.6.2 | What `eloquent` uses: 3.5.8 and later require Dart `^3.9.0`, and its minimum is `^3.6.0` |
| 3.6.0 | 3.13.7 | The latest release |

Environment: Windows 11, PostgreSQL 16.7 on loopback. Nothing was run on Linux. The fake servers mentioned below are local sockets that speak just enough of the protocol. For 3.5.8 to 3.5.20, only the CHANGELOG was read, so where a fix landed exactly was not checked.

## Summary

| # | Issue | 3.5.7 | 3.6.0 |
| --- | --- | --- | --- |
| 1 | Two result sets in `QueryMode.simple` fail with `Future already completed` | uncaught error | **connection lost** |
| 2 | The password is sent in clear text over an unverified TLS connection, with no way to refuse | yes | **yes** |
| 3 | A stalled TLS handshake leaves the socket open after the timeout | yes | **yes** |
| 4 | Common types return bytes that `UndecodedBytes.asString` turns into garbage or an exception | yes | **yes** |
| 5 | Array values change runtime type with their content | yes | **yes** |
| 6 | The transaction status of the server is not exposed | yes | **yes** |
| 7 | A statement during `runTx` throws instead of waiting | yes | **yes** |
| 8 | A lost connection is only recognizable by its message | yes | **yes** |
| 9 | `SslMode` has no `prefer`, `allow` or `verify-ca` | yes | **yes** |
| 10 | Security fixes only reach users on a recent Dart SDK: `^3.9.0` since a patch release | - | **from 3.5.8** |
| 11 | `PoolSettings.securityContext` was ignored | yes | fixed |
| 12 | `runTx` rolled back after a recovered `ROLLBACK TO SAVEPOINT` | yes | fixed |
| 13 | A write to a reset socket became an uncaught error | yes | fixed |
| 14 | Malformed server messages caused uncaught errors | yes | fixed |
| 15 | `infinity` dates: a wrong date, or an uncaught error that ended the process | yes | fixed |

Issues 1 to 10 are open in 3.6.0. Issues 11 to 15 are only context: they explain workarounds in the adapter, and need no report.

## Open in 3.6.0

### 1. Two result sets in `QueryMode.simple` lose the connection

Most important of the list, and worse in the latest version.

```dart
final c = await Connection.open(endpoint, settings: settings);
await c.execute('select 1 as a; select 2 as b', queryMode: QueryMode.simple);
await c.execute('select 9');
```

| | First statement | Next statement |
| --- | --- | --- |
| 3.6.0 | throws `Bad state: Future already completed` | throws `Attempting to execute query, but connection is not open.` |
| 3.5.7 | returns 2 rows under the schema of the first result (`columns [a]`, also when the second has other columns), and the same error escapes as **uncaught** | works |

It needs two statements that return rows: `select 1 as a`, and `create temporary table t (id int); insert into t values (1), (2)`, both work on both versions.

The simple protocol is the one that allows several statements, so this is its main use. `eloquent` sends scripts this way (`db.execute`, `db.unprepared`), so this blocks its upgrade to 3.6.0.

**Suggestion:** return the rows of the results, or at least of the last one, without closing the connection.

### 2. The password goes in clear text over unverified TLS

`AuthenticationCleartextPassword` is answered whenever the transport is TLS or the mode is `disable`:

```dart
// lib/src/v3/connection.dart, 3.5.7
case AuthenticationMessageType.clearTextPassword:
  if (!_hasSecureTransport &&
      !connection._settings.sslMode.allowCleartextPassword) {
```

Result against a fake server that asks for it:

| `SslMode` | Password sent |
| --- | --- |
| `disable` | yes |
| `require` | yes |
| `verifyFull`, verified certificate | yes |

`require` does not verify the certificate, so anyone between client and server can present any certificate and ask for the password in clear. A server using SCRAM never asks for that, and the client cannot tell. It turns an interception into the password itself, not only the session.

`verifyFull` is fine: the server was verified. `disable` is documented ("implies that password may be sent as plaintext"), but it has no way to refuse either.

There may be a reason, as libpq sends it too unless `require_auth` is used (libpq 16+; this comes from its documentation, it was not tested).

**Suggestion:** an option such as `allowCleartextPassword` or an equivalent of `require_auth`, refusing by default when the server was not verified. Servers using LDAP, PAM or `password` need it, hence the option.

### 3. A stalled TLS handshake leaves the socket open

A server that answers `S` to the SSLRequest and then says nothing:

```dart
await Connection.open(endpoint, settings: ConnectionSettings(
    sslMode: SslMode.require, connectTimeout: Duration(seconds: 2)));
```

The call fails on time (`TimeoutException: SSL handshake timed out` on 3.6.0), but the server side of the socket was still open 5 s later, the longest that was waited. The cause seems to be that `SecureSocket.secure` takes the socket over, so destroying the original reference does nothing. The CHANGELOG of 3.5.15 and 3.5.16 fixes the cases of a handshake that fails or succeeds late, not this one.

It needs a malicious server or someone in the middle, and the application does get its error, so the impact is low: a socket per attempt until the peer closes it.

**Suggestion:** `RawSecureSocket.secure` over a `RawSocket` the driver keeps, which can be closed at the deadline. `mysql_dart` 4.0 does this.

### 4. Common types are hard to read with the default registry

These come back as `UndecodedBytes` in binary, same on both versions:

| Type | `asString` |
| --- | --- |
| `inet`, `money`, `timetz`, `bit`, `varbit`, `regclass`, `numeric[]`, `interval[]` | throws `FormatException` |
| `cidr`, `macaddr`, `oid`, `money[]`, `enum[]` | returns garbage, without an error |
| `enum` | works: its binary form is its text |

The garbage is the worst case: `'08:00:2b:01:02:03'::macaddr` and `12345::oid` give a `String` of control characters, which looks like a value. An application reading `inet` has to cast it to `text` in every query.

`asString` decoding binary bytes as text is the root of it: it can only be right for types whose binary form is their text.

**Suggestions**, any of them:

- decoders for these types (`oid` and `regclass` are a 4-byte integer, `inet`, `cidr` and `macaddr` have simple layouts);
- request them in text format;
- make `asString` throw a clear error for binary values, or offer a `text`/`bytes` split that makes the difference visible.

`date`/`timestamp` `infinity` also come back as binary `UndecodedBytes` on 3.6.0. That is a fair way to fail (see item 15), although `asString` then throws too.

### 5. Array values change runtime type with their content

| Value | Runtime type |
| --- | --- |
| `array[1, 2]` | `CastList<int?, int>` |
| `array[1, null]` | `List<int?>` |
| `array['a', 'b']` | `CastList<String?, String>` |

The static type of a column should not depend on whether a row holds a NULL: `value as List<int>` works on one row and fails on the next. `CastList` also adds a check per access. The CHANGELOG of 3.5.19 fixes this for empty arrays only.

**Suggestion:** always `List<T?>`.

### 6. The transaction status is not exposed

`ReadyForQuery` carries it, but there is no public way to read it (no `transactionStatus` in the public API of either version).

It matters because after an error PostgreSQL answers `COMMIT` with `ROLLBACK`, not with an error. Whoever runs its own `BEGIN`/`COMMIT` must track that by hand, which `eloquent` does (see below).

**Suggestion:** a getter on `Connection`, like libpq's `PQtransactionStatus`.

### 7. A statement during `runTx` throws

```dart
final tx = c.runTx((tx) async { await Future.delayed(ms300); });
await c.execute('select 2');
// throws at once: Attempting to execute query on connection while inside a `runTx` call.
```

The CHANGELOG of 3.5.17 made a second `runTx` wait instead of throwing, but a plain statement still throws. In a server sharing one connection, a request arriving during another's transaction fails. Waiting would match the other drivers tested (`postgres_fork`, `dargres`, `dpgsql`, `mysql_dart`) and `runTx` itself. A call from inside the callback should keep failing fast.

### 8. A lost connection is only recognizable by its message

`Attempting to execute query, but connection is not open.` is a plain `PgException`, with no SQLSTATE or type of its own. Retry logic has to match the text of the message, which breaks if it is ever reworded.

**Suggestion:** a distinct exception type, or a code such as `08006`.

### 9. `SslMode` has only `disable`, `require` and `verifyFull`

Users coming from libpq expect `prefer`, `allow` and `verify-ca`. The first two need the client to fall back to plain text; `verify-ca` is not possible with `dart:io`, which checks chain and host together, so it could be documented as such.

### 10. Security fixes only reach users on a recent Dart SDK

3.5.8 raised the minimum SDK from `>=3.4.0` to `^3.9.0`, in a patch release, two days after 3.5.7. All of the 14 releases since then require it, so none of their fixes reach anyone on an older SDK, and some of those fixes are security-relevant, such as the socket leaks and the SCRAM signature comparison.

This is my case. My applications and my AngularDart (`ngdart`) ecosystem depend on Dart 3.6.2, which stops me from moving to a newer SDK, so I am stuck on 3.5.7. For me, the items listed below as fixed in 3.6.0 are still open, including the uncaught errors, which can end a process.

It would be very helpful if fixes in the driver did not force new Dart versions: raising the minimum SDK only when a release really needs it, and in a minor or major version, or keeping a maintenance branch that receives the security fixes for older SDKs.

## Fixed by 3.6.0

Reported here only as context.

| # | Issue on 3.5.7 | On 3.6.0 |
| --- | --- | --- |
| 11 | `Pool.withEndpoints(settings: PoolSettings(securityContext: ...))` did not reach the connections: `securityContext = settings?.securityContext`, with no fallback. A private CA failed on a pool | Reaches the server |
| 12 | `runTx` rolled back after any SQL error, even one a `ROLLBACK TO SAVEPOINT` recovered from: rows `[]` | Rows `[1, 2]` |
| 13 | A write to a socket the server reset: the error of `socket.done` was uncaught | No uncaught error |
| 14 | Replaying captured conversations with one mutation: 6 uncaught errors in 690 runs (`RangeError`, `Not enough bytes to read`, a null check) | 0 in 784 runs, no hangs |
| 15 | `'infinity'::date` was the `DateTime` `36070-01-11`. `'infinity'::timestamp` gave no row and an uncaught `RangeError`, which ended the test process | `UndecodedBytes` |

Performance also improved: on a local server, in AOT, median of 5 rounds, without TLS:

| | 3.5.7 | 3.6.0 |
| --- | --- | --- |
| `select 1`/s | 3,115 | 6,053 |
| Query with a parameter/s | 2,998 | 5,601 |
| Rows/s, 10k rows | 284,876 | 444,275 |

For comparison, in the same conditions on 3.5.7's Dart, the other Dart drivers do 9,700 to 11,000 `select 1`/s and 1.2 to 1.9 million rows/s. The difference between them comes from design choices we did not analyze, so it is only a data point.

## What the `eloquent` adapter does because of this

All of it is in `lib/src/pdo/postgres_v3/`.

| Adaptation | Why | With 3.6.0 |
| --- | --- | --- |
| Sends `BEGIN`/`COMMIT` itself on a reserved connection, instead of `runTx` | Issue 12: nested transactions could not survive an error | May go, after testing |
| `PostgresV3PDOTransaction.abortedBy`: an error sets it, a successful `ROLLBACK TO SAVEPOINT` clears it; if set at the end, `ROLLBACK` and an error, because `COMMIT` would report success | Issue 6 | Needed unless `runTx` is used |
| Closes the session when `COMMIT` or `ROLLBACK` fails without an answer, as its state is unknown | Same reason | Needed unless `runTx` is used |
| `OperationLock` around the single connection | Issue 7 | Needed |
| `securityContext` passed on each call to `Pool.withConnection`, as `Pool.execute` has no settings | Issue 11 | Can go |
| A `TypeRegistry` with codecs for `time`, `timetz`, `interval`, `inet`, `cidr`, `macaddr`, `money`, geometric types, `bit`, `tsvector`, ranges, `oid` and `reg*`, reading the binary forms itself | Issue 4, and to return the same types as the other drivers | Needed |
| `postgresV3Value`: `UndecodedBytes` becomes the array literal, or text decoded carefully | Issue 4 | Needed |
| `postgresV3Rows`: rebuilds arrays as `List<T?>` | Issue 5 | Needed |
| `date`, `timestamp` and `timestamptz` decoded by its own codec, which replaces the built-in one for those types and their arrays | Item 15: a wrong date, or an uncaught error | Needed: on 3.6.0 they are `UndecodedBytes` |
| Opens its sockets in a zone of its own, whose uncaught errors are dropped, and runs the caller's code outside it | Item 1 and the other errors no caller can catch | Needed while such errors exist |
| `QueryMode.simple` in `execute`, for scripts | The extended protocol refuses several statements, which is the server's rule, not an issue | Needed, and blocked by issue 1 |
| `resolvePgSslMode`: its own SSLRequest on a separate socket, to give `allow` and `prefer` a meaning; `verify-ca` maps to `verifyFull` | Issue 9 | Needed |
| Matches the message of a lost connection | Issue 8 | Needed |
| `SET client_encoding`, `search_path`, `timezone`, `application_name` and session timeouts in `onOpen` | A round trip per setting, where startup parameters could carry them. Not a bug | Needed |
| A timeout passed on each query | The adapter's own default, not an issue | Needed |

`README.md` of `eloquent` tells users that `postgres_v3` sends the password in clear (issue 2) and has no option against it.

## How to reproduce

The snippets above are enough for items 1, 3 and 7. For the others:

- **Items 2 and 11**: a fake server over `ServerSocket`, answering `S` to the SSLRequest and `R` with type 3 to the startup, with `SecureSocket.secureServer` and a certificate of a private CA.
- **Items 4, 5 and 15**: `select <value>` and printing `runtimeType` and `asString`.
- **Item 12**: `runTx` with `savepoint s`, a `select 1/0` caught by the callback, `rollback to savepoint s` and an insert.
- **Item 13**: a `Socket` wrapper through `IOOverrides.runZoned(socketConnect: ...)`, whose `done` future fails on a write. On real sockets it depends on timing: it was seen on Linux in CI, in `dargres`, the same kind of bug.
- **Item 14**: a proxy records the server's replies, then a fake server replays them with one change (a length, a message type, a truncation), closing the socket when the client stops writing.
