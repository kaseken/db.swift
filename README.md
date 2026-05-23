# db_tutorial_swift

A Swift implementation of [cstack/db_tutorial](https://cstack.github.io/db_tutorial/) — a step-by-step guide to building a simple database engine from scratch, originally written in C.  
Inspired by and based on [cstack](https://github.com/cstack)'s excellent tutorial.

## Build & Run

```bash
swift run
```

## Test

E2E integration tests launch the compiled binary as a subprocess, so a build step is required first.

```bash
swift build && swift test
```

## Usage

```
db > .exit       # exit the program
db > .tables     # (example of an unrecognized command)
```
