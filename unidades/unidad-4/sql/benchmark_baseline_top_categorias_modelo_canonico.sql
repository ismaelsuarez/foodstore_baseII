-- Unidad 4, Fase 4: baseline WARM-CACHE; no instala optimizaciones.
-- Ejecutar desde la raíz con psql -X -w -v ON_ERROR_STOP=1
-- -d foodstore_u4_revalidacion -f <este archivo>.
-- Primera invocación: estadísticas, semántica, estimado, WARMUP y RUN_1..RUN_5.
-- Calcular externamente MIN/MAX/MEDIA/MEDIANA de Execution Time de RUN_1..5.
-- Elegir la corrida oficial más cercana a la mediana. Después invocar UNA VEZ:
-- psql ... -v text_only=true -f <este archivo>
-- Ese modo captura el textual adicional sin repetir ANALYZE ni corridas JSON.
-- No sumar buffers ni tiempos inclusivos entre padres/hijos: resumen nodo raíz.
-- SELECT semántico después de cada corrida, fuera de tiempos, calienta cachés.
-- El protocolo no vacía caché y no acredita un estado frío. ANALYZE muestrea:
-- reproducir el protocolo no garantiza planes ni tiempos numéricos idénticos.
-- Sin escritores concurrentes durante el ensayo. No modifica filas/estructura
-- ni configuración del servidor; solamente ANALYZE sobre cuatro tablas.
-- Las guardas usan SELECT y variables psql. SELECT 1/0 bajo ON_ERROR_STOP
-- produce una salida fallida si una guarda es falsa; no modifica objetos.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
\pset format unaligned
\pset tuples_only on
\pset pager off
\if :{?text_only}
\else
\set text_only false
\endif

SELECT current_database()='foodstore_u4_revalidacion' AND CURRENT_DATE=DATE '2026-09-23' AND current_setting('server_version')='17.11' AS guard_ok \gset
\if :guard_ok
\echo PASS: base_fecha_version
\else
\echo STOP: base_fecha_version
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f'))=5
 AND NOT EXISTS (SELECT 1 FROM (VALUES ('categoria'),('usuario'),('producto'),('pedido'),('detalle_pedido')) x(nombre)
   WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname=x.nombre AND c.relkind='r'))
 AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema')
 AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal)
 AND NOT EXISTS (SELECT 1 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='detalle_pedido' AND column_name='categoria_id') AS guard_ok \gset
\if :guard_ok
\echo PASS: catalogo_sin_U4_TPI_FNBC
\else
\echo STOP: catalogo_sin_U4_TPI_FNBC
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_indexes WHERE schemaname='public')=14
 AND NOT EXISTS (
 SELECT 1 FROM (VALUES
 ('idx_producto_categoria','CREATE INDEX idx_producto_categoria ON public.producto USING btree (categoria_id)'),
 ('idx_pedido_usuario','CREATE INDEX idx_pedido_usuario ON public.pedido USING btree (usuario_id)'),
 ('idx_producto_nombre_vig','CREATE INDEX idx_producto_nombre_vig ON public.producto USING btree (nombre) WHERE (eliminado = false)'),
 ('idx_producto_stock_bajo','CREATE INDEX idx_producto_stock_bajo ON public.producto USING btree (stock, nombre) INCLUDE (id, precio) WHERE (eliminado = false)'),
 ('idx_pedido_fecha_reciente','CREATE INDEX idx_pedido_fecha_reciente ON public.pedido USING btree (fecha DESC) INCLUDE (id, usuario_id, estado, forma_pago, total) WHERE (eliminado = false)'),
 ('idx_usuario_mail_lower','CREATE INDEX idx_usuario_mail_lower ON public.usuario USING btree (lower((mail)::text)) WHERE (eliminado = false)')
 ) x(nombre,definicion)
 LEFT JOIN pg_indexes i ON i.schemaname='public' AND i.indexname=x.nombre
 LEFT JOIN pg_index ix ON ix.indexrelid=to_regclass('public.'||x.nombre)
 WHERE i.indexname IS NULL OR i.indexdef<>x.definicion OR NOT ix.indisvalid OR NOT ix.indisready) AS guard_ok \gset
\if :guard_ok
\echo PASS: indices_raiz_TP5
\else
\echo STOP: indices_raiz_TP5
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM categoria)=8
 AND (SELECT count(*) FROM usuario)=20000
 AND (SELECT count(*) FROM producto)=50000
 AND (SELECT count(*) FROM pedido)=200000
 AND (SELECT count(*) FROM detalle_pedido)=500000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE)=20000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND NOT eliminado)=19800
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND eliminado)=200
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE)=50000
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado)=49500
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=48900
 AND (SELECT count(DISTINCT pr.categoria_id) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id
      JOIN producto pr ON pr.id=d.producto_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=8 AS guard_ok \gset
\if :guard_ok
\echo PASS: conteos_y_poblacion_del_dia
\else
\echo STOP: conteos_y_poblacion_del_dia
SELECT 1/0;
\endif

SELECT NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id
   GROUP BY p.id,p.total HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0))
 AND NOT EXISTS (SELECT 1 FROM producto p LEFT JOIN categoria c ON c.id=p.categoria_id WHERE c.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN usuario u ON u.id=p.usuario_id WHERE u.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido d LEFT JOIN pedido p ON p.id=d.pedido_id
   LEFT JOIN producto pr ON pr.id=d.producto_id WHERE p.id IS NULL OR pr.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido GROUP BY pedido_id,producto_id HAVING count(*)>1)
 AND NOT EXISTS (SELECT 1 FROM producto WHERE precio<0 OR stock<0)
 AND NOT EXISTS (SELECT 1 FROM pedido WHERE total<0)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE cantidad<=0 OR precio_unitario<0 OR subtotal<0) AS guard_ok \gset
\if :guard_ok
\echo PASS: integridad
\else
\echo STOP: integridad
SELECT 1/0;
\endif

-- Huellas de todas las filas e índices; solo variables del cliente psql.
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snapshot_categoria FROM public.categoria t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snapshot_usuario FROM public.usuario t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snapshot_producto FROM public.producto t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snapshot_pedido FROM public.pedido t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snapshot_detalle_pedido FROM public.detalle_pedido t \gset
SELECT md5(string_agg(indexname||indexdef||i.indisvalid::text||i.indisready::text,'' ORDER BY indexname)) AS snapshot_indexes FROM pg_indexes x JOIN pg_index i ON i.indexrelid=to_regclass('public.'||x.indexname) WHERE schemaname='public' \gset

\echo BEGIN_ENVIRONMENT
SELECT current_database(),CURRENT_DATE,now(),version();
\echo CONFIG_server_version
SHOW server_version;
\echo CONFIG_TimeZone
SHOW TimeZone;
\echo CONFIG_shared_buffers
SHOW shared_buffers;
\echo CONFIG_effective_cache_size
SHOW effective_cache_size;
\echo CONFIG_work_mem
SHOW work_mem;
\echo CONFIG_maintenance_work_mem
SHOW maintenance_work_mem;
\echo CONFIG_random_page_cost
SHOW random_page_cost;
\echo CONFIG_seq_page_cost
SHOW seq_page_cost;
\echo CONFIG_effective_io_concurrency
SHOW effective_io_concurrency;
\echo CONFIG_max_parallel_workers
SHOW max_parallel_workers;
\echo CONFIG_max_parallel_workers_per_gather
SHOW max_parallel_workers_per_gather;
\echo CONFIG_jit
SHOW jit;
\echo CONFIG_track_io_timing
SHOW track_io_timing;
\echo END_ENVIRONMENT

\if :text_only
-- No repetir mantenimiento en la invocación textual.
\else
ANALYZE categoria;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;
\echo PASS: estadisticas_actualizadas
\endif

\echo BEGIN_SEMANTIC_RESULT
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_SEMANTIC_RESULT
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: resultado_semantico_exacto
\else
\echo STOP: resultado_semantico_exacto
SELECT 1/0;
\endif

\if :text_only
\echo BEGIN_REPRESENTATIVE_TEXT_PLAN
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_REPRESENTATIVE_TEXT_PLAN
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_textual
\else
\echo STOP: semantica_despues_textual
SELECT 1/0;
\endif

\else
\echo BEGIN_ESTIMATED
EXPLAIN (COSTS, BUFFERS OFF, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_ESTIMATED

\echo BEGIN_WARMUP
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_WARMUP
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_WARMUP
\else
\echo STOP: semantica_despues_WARMUP
SELECT 1/0;
\endif


\echo BEGIN_RUN_1
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_RUN_1
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_RUN_1
\else
\echo STOP: semantica_despues_RUN_1
SELECT 1/0;
\endif


\echo BEGIN_RUN_2
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_RUN_2
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_RUN_2
\else
\echo STOP: semantica_despues_RUN_2
SELECT 1/0;
\endif


\echo BEGIN_RUN_3
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_RUN_3
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_RUN_3
\else
\echo STOP: semantica_despues_RUN_3
SELECT 1/0;
\endif


\echo BEGIN_RUN_4
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_RUN_4
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_RUN_4
\else
\echo STOP: semantica_despues_RUN_4
SELECT 1/0;
\endif


\echo BEGIN_RUN_5
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
\echo END_RUN_5
WITH actual AS (
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5
), esperado(categoria,total_vendido) AS (
 VALUES ('__U4_LAB_CATEGORIA_07__',194538488.00::numeric),
 ('__U4_LAB_CATEGORIA_03__',90236048.00::numeric),
 ('__U4_LAB_CATEGORIA_06__',88912722.00::numeric),
 ('__U4_LAB_CATEGORIA_05__',74717570.00::numeric),
 ('__U4_LAB_CATEGORIA_08__',40242037.00::numeric)
)
SELECT NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM esperado)
   AND NOT EXISTS (SELECT * FROM esperado EXCEPT SELECT * FROM actual) AS guard_ok \gset
\if :guard_ok
\echo PASS: semantica_despues_RUN_5
\else
\echo STOP: semantica_despues_RUN_5
SELECT 1/0;
\endif

\endif

-- Validaciones posteriores a las mediciones, fuera de Execution Time.
SELECT (SELECT count(*) FROM categoria)=8
 AND (SELECT count(*) FROM usuario)=20000
 AND (SELECT count(*) FROM producto)=50000
 AND (SELECT count(*) FROM pedido)=200000
 AND (SELECT count(*) FROM detalle_pedido)=500000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE)=20000
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND NOT eliminado)=19800
 AND (SELECT count(*) FROM pedido WHERE fecha=CURRENT_DATE AND eliminado)=200
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE)=50000
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado)=49500
 AND (SELECT count(*) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=48900
 AND (SELECT count(DISTINCT pr.categoria_id) FROM detalle_pedido d JOIN pedido p ON p.id=d.pedido_id
      JOIN producto pr ON pr.id=d.producto_id WHERE p.fecha=CURRENT_DATE AND NOT d.eliminado AND NOT p.eliminado)=8 AS guard_ok \gset
\if :guard_ok
\echo PASS: post_conteos
\else
\echo STOP: post_conteos
SELECT 1/0;
\endif

SELECT NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN detalle_pedido d ON d.pedido_id=p.id
   GROUP BY p.id,p.total HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0))
 AND NOT EXISTS (SELECT 1 FROM producto p LEFT JOIN categoria c ON c.id=p.categoria_id WHERE c.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM pedido p LEFT JOIN usuario u ON u.id=p.usuario_id WHERE u.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido d LEFT JOIN pedido p ON p.id=d.pedido_id
   LEFT JOIN producto pr ON pr.id=d.producto_id WHERE p.id IS NULL OR pr.id IS NULL)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido GROUP BY pedido_id,producto_id HAVING count(*)>1)
 AND NOT EXISTS (SELECT 1 FROM producto WHERE precio<0 OR stock<0)
 AND NOT EXISTS (SELECT 1 FROM pedido WHERE total<0)
 AND NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE cantidad<=0 OR precio_unitario<0 OR subtotal<0) AS guard_ok \gset
\if :guard_ok
\echo PASS: post_integridad
\else
\echo STOP: post_integridad
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f'))=5
 AND NOT EXISTS (SELECT 1 FROM (VALUES ('categoria'),('usuario'),('producto'),('pedido'),('detalle_pedido')) x(nombre)
   WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname=x.nombre AND c.relkind='r'))
 AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema')
 AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal)
 AND NOT EXISTS (SELECT 1 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='detalle_pedido' AND column_name='categoria_id') AS guard_ok \gset
\if :guard_ok
\echo PASS: post_objetos
\else
\echo STOP: post_objetos
SELECT 1/0;
\endif

SELECT (SELECT count(*) FROM pg_indexes WHERE schemaname='public')=14
 AND NOT EXISTS (
 SELECT 1 FROM (VALUES
 ('idx_producto_categoria','CREATE INDEX idx_producto_categoria ON public.producto USING btree (categoria_id)'),
 ('idx_pedido_usuario','CREATE INDEX idx_pedido_usuario ON public.pedido USING btree (usuario_id)'),
 ('idx_producto_nombre_vig','CREATE INDEX idx_producto_nombre_vig ON public.producto USING btree (nombre) WHERE (eliminado = false)'),
 ('idx_producto_stock_bajo','CREATE INDEX idx_producto_stock_bajo ON public.producto USING btree (stock, nombre) INCLUDE (id, precio) WHERE (eliminado = false)'),
 ('idx_pedido_fecha_reciente','CREATE INDEX idx_pedido_fecha_reciente ON public.pedido USING btree (fecha DESC) INCLUDE (id, usuario_id, estado, forma_pago, total) WHERE (eliminado = false)'),
 ('idx_usuario_mail_lower','CREATE INDEX idx_usuario_mail_lower ON public.usuario USING btree (lower((mail)::text)) WHERE (eliminado = false)')
 ) x(nombre,definicion)
 LEFT JOIN pg_indexes i ON i.schemaname='public' AND i.indexname=x.nombre
 LEFT JOIN pg_index ix ON ix.indexrelid=to_regclass('public.'||x.nombre)
 WHERE i.indexname IS NULL OR i.indexdef<>x.definicion OR NOT ix.indisvalid OR NOT ix.indisready) AS guard_ok \gset
\if :guard_ok
\echo PASS: post_indices
\else
\echo STOP: post_indices
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.categoria t) = :'snapshot_categoria' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_categoria
\else
\echo STOP: snapshot_intacto_categoria
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.usuario t) = :'snapshot_usuario' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_usuario
\else
\echo STOP: snapshot_intacto_usuario
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.producto t) = :'snapshot_producto' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_producto
\else
\echo STOP: snapshot_intacto_producto
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.pedido t) = :'snapshot_pedido' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_pedido
\else
\echo STOP: snapshot_intacto_pedido
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.detalle_pedido t) = :'snapshot_detalle_pedido' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_detalle_pedido
\else
\echo STOP: snapshot_intacto_detalle_pedido
SELECT 1/0;
\endif

SELECT (SELECT md5(string_agg(indexname||indexdef||i.indisvalid::text||i.indisready::text,'' ORDER BY indexname)) FROM pg_indexes x JOIN pg_index i ON i.indexrelid=to_regclass('public.'||x.indexname) WHERE schemaname='public') = :'snapshot_indexes' AS guard_ok \gset
\if :guard_ok
\echo PASS: snapshot_intacto_indexes
\else
\echo STOP: snapshot_intacto_indexes
SELECT 1/0;
\endif

\echo PASS: baseline_sin_cambios_de_datos_ni_estructura
