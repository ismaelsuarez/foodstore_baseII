# Tech Stack

## Database
- **Engine:** PostgreSQL
- **SQL dialect:** Standard PostgreSQL SQL (uses `BIGINT GENERATED ALWAYS AS IDENTITY`, `TIMESTAMPTZ`, `NUMERIC`, `ENUM` types)

## Key PostgreSQL features in use
- Custom `ENUM` type (`forma_pago`: EFECTIVO, TARJETA, TRANSFERENCIA)
- `GENERATED ALWAYS AS IDENTITY` for surrogate primary keys
- `TIMESTAMPTZ` for all timestamps (timezone-aware)
- Named `CHECK` and `FOREIGN KEY` constraints
- `ON DELETE RESTRICT` on all foreign keys
- Indexes on foreign key columns used in frequent lookups

## Common commands

```sql
-- Apply schema
\i schema.sql

-- Load seed data
\i datos_iniciales.sql
```

Or from the shell (PowerShell):

```powershell
psql -U <user> -d <database> -f schema.sql
psql -U <user> -d <database> -f datos_iniciales.sql
```
