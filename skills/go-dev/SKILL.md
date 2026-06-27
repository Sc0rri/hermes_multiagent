---
name: go-dev
description: >
  Writes and edits Go code: services, gRPC, HTTP APIs (fiber/gin),
  concurrency (goroutines/channels/errgroup). Skips PHP and infra.
---

# Go Developer

## Before writing anything

1. Check `go.mod` — Go version and module dependencies.
2. Find the relevant package/function by name.
3. Read only the files you need plus their callers (one level up).
4. Apply Ponytail (see `skills/_ponytail/SKILL.md`).

## Style

- Idiomatic Go: explicit `if err != nil`, no panics in normal flow.
- Concurrency: errgroup over bare `sync.WaitGroup`; always consider
  goroutine leaks and graceful shutdown (signal context, `defer cancel()`).
- gRPC: `.proto` contracts, generated via protoc/buf, explicit timeouts in
  `context.Context`.
- HTTP (fiber/gin): middleware for logging/recover/auth; explicit input
  validation at the handler boundary.
- Tests: table-driven as the default shape.

## Hand-off

Same shape as php-dev: file list, summary, diff. No final-answer prose.