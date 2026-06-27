---
name: explain-patterns
description: >
  Postgres/MySQL EXPLAIN patterns: index choices, N+1 detection,
  query rewrites. Use when database-dev runs EXPLAIN ANALYZE and
  needs to interpret the plan, or when picking an index for a slow
  query.
---

# EXPLAIN Patterns (Postgres + MySQL)

## Read this when

- The task says "slow query", "add index", "EXPLAIN", "query plan".
- A code review finds an N+1 loop (foreach fetch).
- You're choosing between B-tree / partial / composite / GIN index.

## Postgres — what to look for

```
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) <query>;
```

Costly nodes (top to bottom):

| Plan node        | What it means                                          |
|------------------|--------------------------------------------------------|
| `Seq Scan`       | No usable index. Either missing index, or table tiny.  |
| `Index Scan`     | Good.                                                  |
| `Index Only Scan`| Best — covering index, no heap visit.                  |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | OK between many OR conditions. |
| `Nested Loop`    | OK if outer is small. Suspicious if both legs > 1000.  |
| `Hash Join`      | OK for medium equality joins.                          |
| `Merge Join`     | OK on pre-sorted inputs.                              |
| `Sort`           | Watch for `Sort Method: external merge Disk` — spilling. |
| `Materialize`    | Often paired with bad N+1.                             |

Key columns:

- `actual rows` vs `rows` — `rows << actual rows` = bad stats. `ANALYZE table`.
- `loops=N` on a subplan — N+1 confirmed if N ≈ parent rows.
- `Buffers: read=` (disk) vs `hit=` (cache) — high read = cold cache or wrong index.

## MySQL — equivalent

```
EXPLAIN ANALYZE <query>;
```

| Column          | Watch for                                          |
|-----------------|----------------------------------------------------|
| `type`          | `ALL` = full table scan (bad). `range`/`ref`/`eq_ref` = OK. `const`/`system` = best. |
| `rows`          | Estimated row count. Multiplier of 10+ = bad stats. |
| `Extra`         | `Using filesort`, `Using temporary` — usually fixable. `Using index` — best. |

## Index picks

| Query shape                                  | Index                              |
|----------------------------------------------|------------------------------------|
| `WHERE user_id = ? AND status = ?`           | Composite `(user_id, status)` — order matters. Equality cols first, range last. |
| `WHERE created_at > ? ORDER BY id`           | Composite `(created_at, id)` or just `(created_at)` if `id` is PK cluster key (InnoDB). |
| `WHERE name ILIKE '%foo%'`                   | `pg_trgm` GIN index, not B-tree. |
| `WHERE tags @> ARRAY['a','b']`               | GIN on `tags`. |
| `JSONB field->>'key' = ?`                    | GIN on `(field->>'key')` expression, or `jsonb_path_ops`. |
| Soft-delete `WHERE deleted_at IS NULL`       | Partial index `WHERE deleted_at IS NULL` to skip tombstoned rows. |
| Full-text search                             | GIN with `to_tsvector('english', col)`. |

## N+1 detection

Classic in Yii2/Laravel with eager loading off, or in Go with naive `for _, x := range rows { getByID(x.ID) }`.

```sql
-- Fix: single query with JOIN, or subquery, or `WHERE id IN (...)`.
SELECT u.*, p.* FROM users u JOIN profiles p ON p.user_id = u.id WHERE u.active;
```

If you see `Materialize` with `loops` matching the outer count — that's the smoking gun.

## Things NOT to do

- Don't add `B-tree` on a low-cardinality column (`status`, `is_active`) — seq scan is faster.
- Don't index `text` columns with B-tree — use GIN/trigram.
- Don't trust `EXPLAIN` without `ANALYZE` — without it you get estimates, not reality.
- Don't drop an index because "queries are fast" — measure under load.