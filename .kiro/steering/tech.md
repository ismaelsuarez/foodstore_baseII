# Tech Stack

## Base de datos

- **Motor:** PostgreSQL 17.
- **Cliente:** `psql`.
- **Control de versiones:** Git.
- **Shell de ejemplo:** PowerShell (los comandos de este repositorio
  usan su sintaxis; adaptar según el shell real si es distinto).

No hay backend, frontend, ORM ni framework de testing: todo el
proyecto es SQL y documentación Markdown.

## Características de PostgreSQL en uso

### Base canónica (`schema.sql`)
- Tipo `ENUM` propio (`forma_pago`: `EFECTIVO`, `TARJETA`, `TRANSFERENCIA`).
- `GENERATED ALWAYS AS IDENTITY` para claves primarias autogeneradas.
- `TIMESTAMPTZ` para toda columna de fecha/hora (con zona horaria).
- `NUMERIC` para valores monetarios.
- Restricciones `CHECK` y `FOREIGN KEY` nombradas explícitamente.
- `ON DELETE RESTRICT` en todas las claves foráneas de la base canónica.
- Índices sobre columnas de clave foránea usadas en búsquedas frecuentes.

### Artefactos de laboratorio (bajo `unidades/`)
Cada unidad introdujo, sobre su propia copia de la base, un subconjunto
de estas técnicas — el README local de cada unidad indica cuáles:

- Índices B-tree parciales (`WHERE ...`) y de expresión (`lower(...)`).
- Índices con `INCLUDE` para cobertura (`Index Only Scan`).
- `CREATE OR REPLACE VIEW` para vistas convencionales.
- `CREATE MATERIALIZED VIEW ... WITH DATA` + índice `UNIQUE` para
  permitir `REFRESH ... CONCURRENTLY`.
- Triggers y funciones `PL/pgSQL` para mantener sincronizada una
  columna redundante (Unidad 4).
- `EXPLAIN (ANALYZE, BUFFERS)` como herramienta de medición real.
- Transacciones (`BEGIN` / `COMMIT` / `ROLLBACK`) para migraciones y
  pruebas reversibles.

**Distinción importante:** las técnicas de la sección "Base canónica"
están vigentes en `schema.sql` para toda la base de datos. Las técnicas
de "Artefactos de laboratorio" viven exclusivamente dentro del
`sql/` de cada unidad, aplicadas sobre una copia — no están fusionadas
al esquema base salvo que el README de esa unidad diga lo contrario.

## Comandos seguros desde la raíz

```powershell
# Crear la base y aplicar la fundación canónica
createdb -U postgres foodstore

psql -U postgres -d foodstore -v ON_ERROR_STOP=1 -f .\schema.sql

psql -U postgres -d foodstore -v ON_ERROR_STOP=1 -f .\datos_iniciales.sql
```

O desde `psql` interactivo:

```sql
\i schema.sql
\i datos_iniciales.sql
```

Esto reconstruye únicamente la base canónica. **No** ejecuta ningún
script de `unidades/` automáticamente — cada unidad documenta, en su
propio README, cómo reproducir su volumen de datos y sus objetos
adicionales, y en qué orden hacerlo de forma segura.
