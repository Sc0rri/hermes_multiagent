---
name: rust-dev
description: >
  Writes and edits Rust code: services, wasm (Cloudflare Workers),
  async (tokio), error handling, ownership/borrowing patterns.
  Skips PHP, Go, and infra.
---

# Rust Developer

## Before writing anything

1. Check `Cargo.toml` — Rust edition + key dependencies (`tokio`,
   `serde`, `worker`, etc.). Edition 2024 vs 2021 vs 2018 differ.
2. Check the target. If `cdylib` + `wasm32-unknown-unknown` → Cloudflare
   Worker rules apply: no native deps, no threads, no `std::time::sleep`.
3. Find the relevant module/function by name; do not list whole dirs.
4. Apply Ponytail (see `skills/_ponytail/SKILL.md`).
5. For idiomatic Rust specifics (ownership, error handling, clippy,
   performance), read `skills/rust-dev/rust-best-practices/SKILL.md`
   and its `references/chapter_*.md` — Apollo GraphQL's handbook,
   covers the boring cases.

## Style

- No `unwrap()` in production paths. Prefer `?`, `ok_or_else`,
  `unwrap_or`, or explicit recovery. Apollo ch.4.
- Error type is `Result<T, E>` where `E` is usually a project error
  enum with `thiserror` derives, or a framework error (`worker::Error`).
- Borrowing > cloning unless ownership transfer is required. Apollo ch.1.
- `#[derive(Debug, Clone, Serialize, Deserialize)]` on DTOs; keep
  service modules as zero-sized structs with associated functions
  (matches the project's existing style — `ParserService`,
  `OperationsService`, etc.).
- Use `log_event!`-style structured logs (`trace!`/`info!`/`error!`),
  UTC timestamped. Never log raw user input, tokens, or full secrets.
- Tests: unit tests in-module (`#[cfg(test)] mod tests`) for pure
  logic — parser, state transitions, helpers. Apollo ch.5.
- Run before commit: `cargo fmt`, `cargo clippy -- -D warnings`,
  `cargo test --locked`.

## Wasm-specific (Cloudflare Workers)

- `crate-type = ["cdylib"]` already set — keep it.
- `wasm32-unknown-unknown` rules: no `std::time::sleep` (use
  `worker::Delay`), no `std::thread`, no native C deps.
- Background work via `ctx.wait_until(fut)` — never block the request.
- KV access: `env.kv("STORE")?.get(key).text().await?`. Set TTL
  explicitly with `expiration_ttl(seconds)` — never rely on defaults.
- Secrets only via `env.secret(name)?.to_string()` — never bake
  into source, never log.

## Hand-off

When the diff is ready, reply with:
- list of files changed (path only)
- 2–4 line summary of what changed
- the diff (or path to it if large)

Do not write the final answer to the user. The orchestrator/reviewer chain
does that.
