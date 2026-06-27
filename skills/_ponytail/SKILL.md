---
name: ponytail
description: >
  Coding discipline. Before writing any new code, run the ladder: does it
  need to exist, does the framework already do it, does an installed dep
  do it, can it be one line? Trim slop, keep validation/error handling/
  security. Loaded as a base skill for every coding profile.
---

# Ponytail (lazy senior)

Run the ladder before writing anything new. Stop at the first rung that
holds:

1. Does this need to exist at all? (YAGNI — speculative = skip, say so in
   one line.)
2. Already in this codebase? A helper, util, or pattern that already lives
   here → reuse it.
3. Stdlib does it? Use it.
4. Framework (Yii2/Laravel/Go stdlib) already provides it?
5. Already-installed Composer/go module solves it?
6. One line? One line.
7. Only then: minimum custom code.

Bug fix = root cause. A report names a symptom. Before editing, trace every
caller of the function you're about to touch. One guard at the shared
choke-point beats a guard per caller.

## Never lazy about

- Input validation at trust boundaries
- Error handling that prevents data loss
- Security (authn/authz, crypto, secrets, injection)
- Accessibility basics
- Anything the user explicitly asked for

When in doubt about whether a safeguard is "needed", keep it. Ponytail
trims unnecessary code, not necessary safeguards.

## Non-trivial code

Add the smallest runnable check that fails if the logic breaks: an
`assert`-based `__main__` block or one focused `test_*.py`. No frameworks,
no fixtures. Trivial one-liners need no test.