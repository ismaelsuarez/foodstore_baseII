\set ON_ERROR_STOP on

-- Unidad 6 — diagnóstico y mantenimiento puntual de Food Store.
-- Estado: implementado; pendiente de prueba funcional con Food Store.
--
-- Primero observa el mantenimiento automático y las tablas de public. Sin selección,
-- autorización y justificación explícitas, no ejecuta mantenimiento.
-- La única acción disponible es ANALYZE sobre una de las cinco tablas canónicas.
-- La justificación la registra el operador al ejecutar el laboratorio, a partir
-- del estado observado; este archivo no anticipa observaciones ni resultados.
-- Conservar la salida para documentar la decisión y la comprobación posterior.
--
-- Solo diagnóstico (salida 0, sin acción):
--   docker exec -i CONTENEDOR psql -X -w -U USUARIO -d BASE -f - < unidades/unidad-6/maintenance.sql
-- Acción, solo tras revisar el diagnóstico (se requieren las tres variables):
--   docker exec -i CONTENEDOR psql -X -w -U USUARIO -d BASE -v tabla_mantenimiento=<tabla> -v confirmar_analyze=on -v justificacion='<texto registrado por el operador>' -f - < unidades/unidad-6/maintenance.sql
-- Sustituir <tabla> por categoria, usuario, producto, pedido o detalle_pedido.
-- tabla_mantenimiento selecciona una tabla; confirmar_analyze autoriza con un
-- booleano verdadero; justificacion registra la razón real, no vacía, del operador.
-- No utilizar -1: la acción debe quedar fuera de las transacciones READ ONLY.
--
-- READ ONLY es una protección complementaria a la revisión del SQL, no una
-- garantía absoluta: no bloquea escrituras temporales ni efectos de funciones
-- fuera de la transacción. Los bloques de diagnóstico terminan en ROLLBACK.
-- Prohibidos: VACUUM FULL, REINDEX general, archivado físico, ALTER SYSTEM,
-- programación de tareas y dependencias de pg_cron. No se crean objetos ni se
-- modifican datos de negocio o configuraciones persistentes.

-- Parte 1 — Diagnóstico previo, siempre antes de evaluar la selección.
START TRANSACTION READ ONLY;

-- Las filas y el porcentaje de filas muertas son estimaciones, no conteos exactos.
-- Una fecha NULL indica que no se registró la operación desde el reinicio de
-- estadísticas. Los contadores son acumulados, no valores de esta ejecución.
SELECT
  t.schemaname                                   AS esquema,
  t.relname                                      AS tabla,
  t.n_live_tup                                   AS filas_vivas_estimadas,
  t.n_dead_tup                                   AS filas_muertas_estimadas,
  round(100.0 * t.n_dead_tup / nullif(t.n_live_tup + t.n_dead_tup, 0), 2)
                                                 AS pct_muertas_estimado,
  t.n_mod_since_analyze,
  t.n_ins_since_vacuum,
  t.last_vacuum,
  t.last_autovacuum,
  t.vacuum_count,
  t.autovacuum_count,
  t.last_analyze,
  t.last_autoanalyze,
  t.analyze_count,
  t.autoanalyze_count,
  c.reloptions                                  AS opciones_por_tabla
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = t.relid
WHERE t.schemaname = 'public'
ORDER BY t.relname;

-- Lectura de configuración global y opciones particulares (reloptions arriba).
-- No se definen umbrales operativos ni se toma una decisión automática.
SELECT
  current_setting('autovacuum')                      AS autovacuum,
  current_setting('track_counts')                    AS track_counts,
  current_setting('autovacuum_analyze_threshold')     AS autovacuum_analyze_threshold,
  current_setting('autovacuum_analyze_scale_factor')  AS autovacuum_analyze_scale_factor,
  current_setting('autovacuum_vacuum_threshold')      AS autovacuum_vacuum_threshold,
  current_setting('autovacuum_vacuum_scale_factor')   AS autovacuum_vacuum_scale_factor;

ROLLBACK;

-- Parte 2 — Selección y autorización explícitas; ninguna acción por defecto.
-- Las pruebas de existencia no interpolan el contenido de variables ausentes.
SELECT
  NOT (:{?tabla_mantenimiento}::boolean
       OR :{?confirmar_analyze}::boolean
       OR :{?justificacion}::boolean) AS mantenimiento_solo_diagnostico,
  (:{?tabla_mantenimiento}::boolean
   AND :{?confirmar_analyze}::boolean
   AND :{?justificacion}::boolean) AS mantenimiento_seleccion_completa
\gset

\if :mantenimiento_solo_diagnostico
  \echo 'solo diagnóstico; no se ejecutó ninguna acción'
  \quit
\endif

\if :mantenimiento_seleccion_completa
  -- Un booleano inválido produce error antes de cualquier acción; uno falso
  -- se rechaza abajo. Los valores se interpolan como literales, no como SQL.
  SELECT :'confirmar_analyze'::boolean AS mantenimiento_autorizado,
         btrim(:'justificacion') <> '' AS mantenimiento_justificacion_valida
  \gset
  SELECT :'tabla_mantenimiento' IN
         ('categoria', 'usuario', 'producto', 'pedido', 'detalle_pedido')
         AS tabla_valida
  \gset
\else
  -- DO no crea objetos; ON_ERROR_STOP convierte el error en salida no cero.
  DO $$ BEGIN
    RAISE EXCEPTION 'maintenance.sql: selección incompleta; no se ejecutó ninguna acción';
  END $$;
\endif

\if :mantenimiento_autorizado
\else
  DO $$ BEGIN
    RAISE EXCEPTION 'maintenance.sql: falta autorización verdadera; no se ejecutó ninguna acción';
  END $$;
\endif

\if :mantenimiento_justificacion_valida
\else
  DO $$ BEGIN
    RAISE EXCEPTION 'maintenance.sql: justificación vacía; no se ejecutó ninguna acción';
  END $$;
\endif

\if :tabla_valida
\else
  DO $$ BEGIN
    RAISE EXCEPTION 'maintenance.sql: tabla fuera de la selección permitida; no se ejecutó ninguna acción';
  END $$;
\endif

-- Registro previo de la decisión y de la misma fila que se observará después.
START TRANSACTION READ ONLY;

SELECT :'tabla_mantenimiento' AS tabla_seleccionada,
       :'justificacion'       AS justificacion_registrada,
       now()                  AS observado_en,
       current_user           AS ejecutor,
       current_database()     AS base;

SELECT
  t.schemaname                                   AS esquema,
  t.relname                                      AS tabla,
  t.n_live_tup                                   AS filas_vivas_estimadas,
  t.n_dead_tup                                   AS filas_muertas_estimadas,
  round(100.0 * t.n_dead_tup / nullif(t.n_live_tup + t.n_dead_tup, 0), 2)
                                                 AS pct_muertas_estimado,
  t.n_mod_since_analyze,
  t.n_ins_since_vacuum,
  t.last_vacuum,
  t.last_autovacuum,
  t.vacuum_count,
  t.autovacuum_count,
  t.last_analyze,
  t.last_autoanalyze,
  t.analyze_count,
  t.autoanalyze_count,
  c.reloptions                                  AS opciones_por_tabla
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = t.relid
WHERE t.schemaname = 'public'
  AND t.relname = :'tabla_mantenimiento';

ROLLBACK;

-- Única acción: identificador delimitado y limitado por la lista validada.
ANALYZE VERBOSE public.:"tabla_mantenimiento";

-- Parte 3 — Comprobación posterior, sin inferir una mejora automáticamente.
-- Solo se limpia la instantánea estadística de esta sesión. Las estadísticas
-- acumuladas pueden actualizarse con un pequeño retraso: esta consulta es una
-- observación posterior, no una prueba de mejora ni una medición de rendimiento.
START TRANSACTION READ ONLY;

SELECT pg_stat_clear_snapshot();

SELECT
  t.schemaname                                   AS esquema,
  t.relname                                      AS tabla,
  t.n_live_tup                                   AS filas_vivas_estimadas,
  t.n_dead_tup                                   AS filas_muertas_estimadas,
  round(100.0 * t.n_dead_tup / nullif(t.n_live_tup + t.n_dead_tup, 0), 2)
                                                 AS pct_muertas_estimado,
  t.n_mod_since_analyze,
  t.n_ins_since_vacuum,
  t.last_vacuum,
  t.last_autovacuum,
  t.vacuum_count,
  t.autovacuum_count,
  t.last_analyze,
  t.last_autoanalyze,
  t.analyze_count,
  t.autoanalyze_count,
  c.reloptions                                  AS opciones_por_tabla
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = t.relid
WHERE t.schemaname = 'public'
  AND t.relname = :'tabla_mantenimiento';

ROLLBACK;
