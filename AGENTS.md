# AGENTS.md — foodStore

## What this is

PostgreSQL-only academic project (UTN – Base de Datos II). No app code, no build system, no test framework. Two SQL files: schema + seed data.

## Database engine

PostgreSQL. Uses dialect-specific features: `GENERATED ALWAYS AS IDENTITY`, custom ENUM type, `TIMESTAMPTZ`.

## Load order (matters)

```powershell
psql -U <user> -d <database> -f schema.sql        # DDL first
psql -U <user> -d <database> -f datos_iniciales.sql # DML second
```

`datos_iniciales.sql` depends on `schema.sql` — tables and the `forma_pago` ENUM must exist first.

## Naming conventions (non-negotiable)

- All identifiers in **Spanish**, lowercase, `snake_case`
- Tables: singular nouns (`categoria`, `cliente`, `producto`, `pedido`, `detalle_pedido`)
- FK columns: `<referenced_table>_id`
- Constraint naming: `pk_<table>`, `fk_<table>_<ref>`, `chk_<table>_<column>`, `idx_<table>_<column>`
- Composite PK on `detalle_pedido` (`pedido_id`, `producto_id`) — no surrogate key there

## Schema design facts

- `ON DELETE RESTRICT` on all foreign keys — deletes will fail if referenced rows exist
- `precio_unitario` in `detalle_pedido` is denormalized (snapshot at time of sale, not a FK to current price)
- `activo` boolean on `categoria` and `producto` = soft-delete pattern
- Seed data uses subqueries on natural keys (email, name) — no hardcoded IDs

## Detailed docs

See `.kiro/steering/` for product, tech stack, and structure details.
