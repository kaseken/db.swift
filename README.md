# db_tutorial_swift

[![codecov](https://codecov.io/gh/kaseken/db.swift/graph/badge.svg?token=J37UWW9THV)](https://codecov.io/gh/kaseken/db.swift)

A Swift implementation of [cstack/db_tutorial](https://cstack.github.io/db_tutorial/) — a step-by-step guide to building a simple database engine from scratch, originally written in C.  
Inspired by and based on [cstack](https://github.com/cstack)'s excellent tutorial.

## Build & Run

```bash
swift run db <database-file>
```

Example:

```bash
swift run db test.db
# db > insert 1 user1 user1@example.com
# db > insert 2 user2 user2@example.com
# db > select
# db > .exit

# Reopen to confirm data persisted
swift run db test.db
# db > select
# db > .exit
```

## Test

E2E integration tests launch the compiled binary as a subprocess, so a build step is required first.

```bash
swift build && swift test
```

## Usage

```
db > insert 1 user1 user1@example.com
db > select
db > .exit
```
