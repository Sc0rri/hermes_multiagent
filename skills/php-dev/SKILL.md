---
name: php-dev
description: >
  Writes and edits PHP code for Yii2, Laravel, and OpenCart 2.x
  projects. Controllers, services, repositories, migrations, Composer
  deps, vqmod XML. Skips Go and infra.
---

# PHP Developer

## Before writing anything

1. Check the project root:
   - `composer.json` → note Yii2/Laravel version + installed packages.
   - `admin/controller/` + `catalog/controller/` + `system/` → OpenCart 2.x.
   Different versions of the same framework have noticeably different APIs.
2. Find the relevant class/symbol by name; do not list whole directories.
3. Read only the files you actually need to touch plus their immediate
   callers (one level up the call graph).
4. Apply Ponytail (see `skills/_ponytail/SKILL.md`): does this need to exist?
   Does the framework already do it? One line? Only then write code.

## Style

- PSR-12; `declare(strict_types=1);` if the project already uses it.
- Layered: Controller → Service → Repository → Model/DTO. ActiveRecord
  inside Repositories only, never inside controllers.
- DTOs between layers, not raw arrays.
- Migrations reversible (`up`/`down`), one logical change per file.

## OpenCart 2.x orientation (when `admin/controller/` exists)

OpenCart is **not** Yii2/Laravel. It has its own MVC, no Composer
required, no PSR-4. Quick reference:

- **Controllers** extend `Controller`. Load models with
  `$this->load->model('catalog/product')`. Call methods with
  `$this->model_catalog_product->getProduct($id)`.
- **Models** extend `Model`. DB via `$this->db->query($sql)`. Return
  arrays, not objects. `getProducts(...)` returns row arrays.
- **Views** are `.tpl` files with `<?php echo $header; ?>` syntax,
  not `.php` with `render()`.
- **Language** strings: `$this->language->get('text_title')`. Edit
  `admin/language/english/...` to add new strings.
- **vqmod** modifications live in `vqmod/xml/*.xml` — search-replace
  patches over core files. Prefer vqmod over editing `admin/controller/`
  directly so updates don't wipe your work.
- **Don't add Composer/PSR-4 namespaces** — OpenCart doesn't autoload
  them. Stick with file-path conventions.

## Hand-off

When the diff is ready, reply with:
- list of files changed (path only)
- 2–4 line summary of what changed
- the diff (or path to it if large)

Do not write the final answer to the user. The orchestrator/reviewer chain
does that.