# Project Structure

```
foodStore/
├── schema.sql          # DDL: all CREATE TYPE, CREATE TABLE, CREATE INDEX statements
└── datos_iniciales.sql # DML: seed data (INSERT statements for dev/testing)
```

## Conventions

### Naming
- All identifiers (tables, columns, constraints, indexes) are in **Spanish**, lowercase, using `snake_case`.
- Tables are singular nouns: `categoria`, `cliente`, `producto`, `pedido`, `detalle_pedido`.
- Foreign key columns follow the pattern `<referenced_table>_id` (e.g., `categoria_id`, `cliente_id`).
- Constraint names follow these patterns:
  - Primary keys: `pk_<table>` (only named when composite)
  - Foreign keys: `fk_<table>_<referenced_table>`
  - Check constraints: `chk_<table>_<column>`
  - Indexes: `idx_<table>_<column>`

### Schema design
- Every table has a `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` surrogate key, except `detalle_pedido` which uses a composite PK (`pedido_id`, `producto_id`).
- `categoria`, `cliente` y `producto` incluyen `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`; `pedido` usa `fecha` como marca temporal de la operación y `detalle_pedido` no incluye `created_at`.
- `precio_unitario` in `detalle_pedido` stores the price at the time of sale (denormalized by design).
- `activo BOOLEAN` is used for soft-delete on `categoria` and `producto`.
- All foreign keys use `ON DELETE RESTRICT`.

### Seed data (`datos_iniciales.sql`)
- References to other rows use subqueries on natural keys (e.g., `WHERE nombre = 'Pizzas'`, `WHERE email = '...'`) instead of hardcoded numeric IDs.
