# SPEC_U6 — Mantenimiento, respaldo y recuperación de Food Store

**Motor:** PostgreSQL 16 o superior. **Bases** (decisión del equipo del 2026-11-05,
sin confirmación docente; CD-1): `foodstore` (origen), `foodstore_restore_test`
(restauración) y `postgres` (administrativa). **Herramientas:** Kiro
(especificación) y Claude (implementación), autorizadas por el docente.

## Tareas, frecuencias y condición de éxito

| Tarea | Frecuencia | Éxito |
|---|---|---|
| Respaldo | Diaria | `.dump` con fecha y hora en el nombre; log con inicio y fin; código 0 solo si todo terminó bien |
| Salud | Diaria | `health_check.sql` sin errores; métricas registradas |
| Mantenimiento | Semanal | Diagnóstico registrado antes de actuar; acción segura justificada |
| Restauración | Semanal | Conteos iguales a la línea base; productos y detalles inválidos en 0 |

## Requisitos

- **Respaldo:** `pg_dump -Fc`. Antes, una línea base de conteos y controles asociada
  al respaldo. Requiere una ventana sin escrituras. La marca de inicio de `pg_dump`,
  no el `mtime`, mide la antigüedad. Ante un fallo: error en el log y código
  distinto de cero.
- **Salud:** tamaño, conexiones, estado de tablas (filas vivas y muertas,
  autovacuum, autoanalyze) y sesiones fuera de `idle`. Cero sesiones es válido.
  Registra métricas, sin semáforo.
- **Mantenimiento:** primero `pg_stat_user_tables`. Solo con selección,
  autorización y justificación explícitas, `ANALYZE` puntual sobre una tabla
  canónica.
- **Restauración:** en una base descartable nueva; si existe, detenerse sin
  borrarla. Las conexiones previas a la creación van a la base administrativa,
  no al origen. RTO: desde antes de `createdb` hasta el fin de las validaciones.
  Productos con `precio < 0 OR stock < 0` y detalles con
  `cantidad <= 0 OR precio_unitario < 0` deben dar 0. Un control fallido no se
  presenta como éxito.

## Objetivos (del equipo, no exigencias del docente)

| Objetivo | Meta | Medición por corrida |
|---|---|---|
| RPO | 24 h | Antigüedad del respaldo desde el inicio de `pg_dump`; no es pérdida efectiva |
| RTO | 20 min | Desde antes de `createdb` hasta el fin de las validaciones |

## Seguridad y alcance

- Sin contraseñas en los scripts (archivo pgpass); restauración solo sobre una
  base de prueba; revisión humana y prueba manual antes de programar.
- Prohibidos `VACUUM FULL` periódico, archivados físicos y cambios globales
  automáticos.
- Alcance: núcleo canónico (esquema, datos y objetos del TPI). No recupera
  propietarios ni permisos de U5. La programación diaria no está instalada.

**Entregables:** `SPEC_U6.md`, `backup_foodstore.sh`, `health_check.sql`
(no instala objetos), `maintenance.sql`, `informe_u6.pdf` y, como opcional,
`restore_test.sh`.
