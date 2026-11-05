# SPEC_U6 — Mantenimiento, respaldo y recuperación de Food Store

**Motor:** PostgreSQL 16 o superior. **Base principal y de restauración:** nombres pendientes (CD-1). **Herramientas:** Kiro (especificación) y Claude (implementación), autorizadas por el docente.

---

## Tareas y frecuencias

| Tarea | Frecuencia | Condición de éxito |
|---|---|---|
| Respaldo | Diaria | Archivo `.dump` con fecha en nombre; log con marca de inicio y fin; exit code 0 si `pg_dump` OK |
| Salud | Diaria | `health_check.sql` ejecuta sin errores; resultados registrados |
| Mantenimiento | Semanal | Estado de autovacuum observado antes de actuar; acción segura justificada |
| Restauración | Semanal | Conteos coincidentes con línea base; productos y detalles inválidos en cero |

## Respaldo diario

`pg_dump -Fc` con fecha y hora en el nombre del archivo. El script registra la marca de inicio de `pg_dump` en un log; esa marca aproxima la antigüedad del respaldo para RPO (no el `mtime` del archivo). Si `pg_dump` falla, el script registra el error y finaliza con código distinto de cero. Sin contraseñas en el script; la autenticación desatendida usa `~/.pgpass` (permiso 600), no `\password` (interactivo).

## Chequeo de salud diario

`health_check.sql` consulta cuatro controles:

1. Tamaño de la base (`pg_database_size`).
2. Conexiones y transacciones (`pg_stat_database`).
3. Estado de tablas: `n_live_tup`, `n_dead_tup`, `last_autovacuum`, `last_autoanalyze` (`pg_stat_user_tables`).
4. Consultas activas (`pg_stat_activity WHERE state <> 'idle'`), que incluye `active` e `idle in transaction`.

Cero sesiones coincidentes es un resultado válido. Un chequeo que detecta AMARILLO o ROJO se ejecutó correctamente.

## Revisión de mantenimiento semanal

`maintenance.sql` consulta primero `pg_stat_user_tables`. Si la observación lo justifica, ejecuta `VACUUM` o `ANALYZE` (no `VACUUM FULL`) sobre las tablas que lo necesiten. La decisión se documenta con el estado observado antes de actuar.

## Restauración de prueba semanal

- Restaurar el último respaldo en una base descartable.
- Si la base de restauración ya existe, detenerse; no borrarla ni sobrescribirla automáticamente.
- Línea base: conteos registrados antes de iniciar `pg_dump`. Se propone una ventana sin escrituras durante la captura de la línea base y el respaldo.
- RTO: cronómetro desde inmediatamente antes de `createdb` del destino hasta terminar las validaciones.
- Validaciones: conteos coincidentes con línea base; productos con `precio < 0 OR stock < 0` = 0; detalles con `cantidad <= 0 OR precio_unitario < 0` = 0. Los controles fallidos no se presentan como éxito.

## Entregables obligatorios

| Archivo | Contenido |
|---|---|
| `SPEC_U6.md` | Esta especificación |
| `backup_foodstore.sh` | Script de respaldo probado, sin contraseñas |
| `health_check.sql` | Consultas de monitoreo (no instala objetos) |
| `maintenance.sql` | Revisión previa + acción segura justificada |
| `informe_u6.pdf` | Evidencias, RPO/RTO, resultado del simulacro, mejora, verificación de IA |

`restore_test.sh` es apoyo opcional.

## Seguridad

- Sin contraseñas en scripts. Autenticación desatendida con `~/.pgpass`.
- Restauración solo sobre base de prueba.
- `VACUUM FULL` prohibido como mantenimiento periódico.
- No se programan archivados físicos ni cambios globales automáticamente.
- Revisión humana antes de ejecutar; prueba manual antes de programar.

## RPO/RTO

| Objetivo | Meta (propuesta, pendiente de aprobación) | Medición |
|---|---|---|
| RPO | 24 h | Antigüedad del respaldo: marca de inicio de `pg_dump` al momento del simulacro. No representa datos efectivamente perdidos. |
| RTO | 20 min | Cronómetro desde inmediatamente antes de `createdb` del destino hasta fin de validaciones |

Los valores medidos y el cumplimiento de las metas se registran por separado. No son exigencias del docente ni resultados obtenidos.
