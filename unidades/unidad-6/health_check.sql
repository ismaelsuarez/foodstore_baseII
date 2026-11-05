-- Unidad 6 — chequeo de salud diario de Food Store.
--
-- Solo observa: no crea objetos, no modifica datos, no ejecuta mantenimiento y no
-- cambia configuración. Las consultas corren dentro de una transacción READ ONLY
-- que termina en ROLLBACK. READ ONLY es una protección complementaria a la revisión
-- del SQL, no una garantía absoluta: no bloquea escrituras en tablas temporales
-- ni funciones con efectos fuera de la transacción.
--
-- La base observada es la conectada (current_database()); el script no fija
-- ninguno de los nombres pendientes (CD-1).
--
-- Invocación prevista, sin conexión fija ni contraseñas en el archivo:
--   docker exec -i CONTENEDOR psql -X -v ON_ERROR_STOP=1 -U USUARIO -d BASE \
--     -f - < unidades/unidad-6/health_check.sql
--
-- Lectura de resultados:
-- - Las filas vivas y muertas de pg_stat_user_tables son ESTIMACIONES del sistema de
--   estadísticas, no conteos exactos. Para un conteo exacto se usa count(*).
-- - Los controles 2 y 4 dependen de los privilegios del ejecutor: sin superusuario ni
--   pg_read_all_stats, las sesiones de otros roles aparecen con columnas en NULL.
-- - Cero filas en el control 4 es un resultado válido: no hay sesiones fuera de idle.
-- - Este archivo no define umbrales VERDE/AMARILLO/ROJO; la interpretación se
--   registra aparte.

START TRANSACTION READ ONLY;

-- Control 1 — Tamaño de la base conectada.
SELECT
  '1_tamano'                                            AS control,
  current_database()                                    AS base,
  pg_database_size(current_database())                  AS tamano_bytes,
  pg_size_pretty(pg_database_size(current_database()))  AS tamano,
  now()                                                 AS observado_en;

-- Control 2a — Conexiones y transacciones acumuladas de la base (pg_stat_database).
-- Los contadores son acumulados desde stats_reset, no valores del día.
SELECT
  '2a_conexiones'                                AS control,
  d.datname                                      AS base,
  d.numbackends                                  AS conexiones_en_la_base,
  (SELECT count(*)
     FROM pg_stat_activity a
    WHERE a.backend_type = 'client backend')     AS conexiones_cliente_en_el_cluster,
  current_setting('max_connections')::int        AS max_connections_cluster,
  d.xact_commit,
  d.xact_rollback,
  d.deadlocks,
  d.conflicts,
  d.temp_files,
  d.temp_bytes,
  round(100.0 * d.blks_hit / nullif(d.blks_hit + d.blks_read, 0), 2)
                                                 AS cache_hit_pct,
  d.stats_reset
FROM pg_stat_database d
WHERE d.datname = current_database();

-- Control 2b — Sesiones cliente de la base agrupadas por estado.
-- Un estado NULL indica que el ejecutor no tiene privilegio para verlo.
SELECT
  '2b_sesiones_por_estado'                       AS control,
  coalesce(a.state, '(estado no visible)')       AS estado,
  count(*)                                       AS sesiones
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.backend_type = 'client backend'
GROUP BY a.state
ORDER BY sesiones DESC, estado;

-- Control 3a — Configuración de la que dependen las estadísticas de tablas.
-- Solo se lee con current_setting; no se modifica.
SELECT
  '3a_configuracion'                             AS control,
  current_setting('track_counts')                AS track_counts,
  current_setting('autovacuum')                  AS autovacuum;

-- Control 3b — Estado de tablas (pg_stat_user_tables).
-- filas_*_estimadas y pct_muertas_estimado son estimaciones, no conteos exactos.
-- Una fecha NULL significa que la operación no se registró desde el último
-- reinicio de estadísticas.
SELECT
  '3b_tablas'                                    AS control,
  t.schemaname                                   AS esquema,
  t.relname                                      AS tabla,
  t.n_live_tup                                   AS filas_vivas_estimadas,
  t.n_dead_tup                                   AS filas_muertas_estimadas,
  round(100.0 * t.n_dead_tup / nullif(t.n_live_tup + t.n_dead_tup, 0), 2)
                                                 AS pct_muertas_estimado,
  t.n_mod_since_analyze                          AS modificaciones_desde_analyze,
  t.last_vacuum,
  t.last_autovacuum,
  t.autovacuum_count,
  t.last_analyze,
  t.last_autoanalyze,
  t.autoanalyze_count,
  pg_size_pretty(pg_total_relation_size(t.relid)) AS tamano_total
FROM pg_stat_user_tables t
ORDER BY t.n_dead_tup DESC, t.schemaname, t.relname;

-- Control 4 — Sesiones fuera de idle en la base (state <> 'idle').
-- La columna categoria distingue consultas activas de sesiones idle in transaction.
-- Se excluye la propia sesión del chequeo, que siempre estaría activa.
--
-- No se selecciona pg_stat_activity.query: el texto SQL de otras sesiones puede
-- contener literales con datos personales o contraseñas. Para diagnosticar bastan
-- el estado, la espera, las duraciones, la antigüedad del xmin (que puede impedir
-- que VACUUM limpie filas muertas) y query_id, que identifica la consulta sin su
-- texto y es NULL si compute_query_id no está activo.
SELECT
  '4_sesiones_no_idle'                           AS control,
  CASE
    WHEN a.state = 'active'                         THEN 'consulta activa'
    WHEN a.state = 'idle in transaction'            THEN 'idle in transaction'
    WHEN a.state = 'idle in transaction (aborted)'  THEN 'idle in transaction (aborted)'
    ELSE 'otro estado'
  END                                            AS categoria,
  a.state                                        AS estado,
  a.pid,
  a.usename                                      AS usuario,
  a.application_name,
  a.client_addr,
  a.backend_type,
  a.wait_event_type,
  a.wait_event,
  a.xact_start,
  now() - a.xact_start                           AS duracion_transaccion,
  a.query_start,
  now() - a.query_start                          AS desde_inicio_ultima_consulta,
  now() - a.state_change                         AS tiempo_en_estado,
  age(a.backend_xmin)                            AS antiguedad_xmin,
  a.query_id
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.state <> 'idle'
  AND a.pid <> pg_backend_pid()
ORDER BY categoria, duracion_transaccion DESC NULLS LAST, a.pid;

ROLLBACK;
