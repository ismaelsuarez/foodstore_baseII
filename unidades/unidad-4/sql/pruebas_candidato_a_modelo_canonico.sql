-- Unidad 4, Fase 6: pruebas reversibles y costo WRITE del candidato A.
-- Uso obligatorio: psql -X -w -v ON_ERROR_STOP=1 -v modo=write|functional|fanout|stress -f <archivo>
-- Una invocación write/fanout/stress produce exactamente un plan JSON de DML.
-- El coordinador ejecuta un warmup y cinco corridas, sin descartar observaciones.
-- write permite estado canónico BEFORE o candidato AFTER: mismo INSERT sin categoria_id.
-- No contiene benchmark READ AFTER. Las secuencias no se consumen: IDs explícitos.
-- La concurrencia necesita dos conexiones y monitor; no se simula aquí.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
\pset pager off
\pset format unaligned
\pset tuples_only on
\timing off
\if :{?modo}
\else
\echo STOP: indicar -v modo=write|functional|fanout|stress
SELECT 1/0;
\endif
SELECT :'modo' IN ('write','functional','fanout','stress') AS mode_ok,
 :'modo'='write' AS mode_write, :'modo'='functional' AS mode_functional,
 :'modo'='fanout' AS mode_fanout, :'modo'='stress' AS mode_stress \gset
\if :mode_ok
\else
SELECT 1/0;
\endif
SELECT current_database()='foodstore_u4_revalidacion'
 AND CURRENT_DATE=DATE '2026-09-23'
 AND current_setting('server_version')='17.11' AS guard_ok \gset
\if :guard_ok
\else
\echo STOP: base_fecha_version
SELECT 1/0;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
 AND table_name='detalle_pedido' AND column_name='categoria_id') AS has_candidate \gset
SELECT (SELECT count(*) FROM public.categoria)=8
 AND (SELECT count(*) FROM public.usuario)=20000
 AND (SELECT count(*) FROM public.producto)=50000
 AND (SELECT count(*) FROM public.pedido)=200000
 AND (SELECT count(*) FROM public.detalle_pedido)=500000
 AND NOT EXISTS (SELECT 1 FROM public.pedido WHERE id BETWEEN 1000001 AND 1001000)
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id BETWEEN 2000001 AND 2001000)
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE subtotal IS DISTINCT FROM cantidad*precio_unitario)
 AND NOT EXISTS (SELECT 1 FROM public.pedido p LEFT JOIN public.detalle_pedido d ON d.pedido_id=p.id
   GROUP BY p.id,p.total HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0))
 AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f'))=5
 AND (SELECT count(*) FROM pg_indexes WHERE schemaname='public')=14
 AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgisinternal AND tgenabled<>'O') AS guard_ok \gset
\if :guard_ok
\else
\echo STOP: checkpoint_o_rangos_fixture
SELECT 1/0;
\endif
\if :has_candidate
SELECT (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)=2
 AND (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled='O'
      AND tgname IN ('trg_detalle_pedido_set_categoria','trg_producto_sync_categoria_detalle'))=2
 AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema')=2
 AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('fn_detalle_pedido_set_categoria','fn_producto_sync_categoria_detalle')
     AND p.prorettype='trigger'::regtype AND p.provolatile='v')=2
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
   WHERE d.categoria_id IS DISTINCT FROM p.categoria_id)
 AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.detalle_pedido'::regclass
   AND conname='fk_detalle_pedido_categoria' AND contype='f' AND confdeltype='r' AND convalidated) AS guard_ok \gset
\else
SELECT :'modo'='write'
 AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal)
 AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema') AS guard_ok \gset
\endif
\if :guard_ok
\echo PASS: checkpoint_canonico_o_candidato_valido
\else
\echo STOP: objetos_inesperados_o_candidato_ausente
SELECT 1/0;
\endif

-- Todas las huellas se comparan después del ROLLBACK, fuera del tiempo medido.
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snap_categoria FROM public.categoria t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snap_usuario FROM public.usuario t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snap_producto FROM public.producto t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snap_pedido FROM public.pedido t \gset
SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) AS snap_detalle FROM public.detalle_pedido t \gset
SELECT md5(string_agg(indexname||indexdef,'' ORDER BY indexname)) AS snap_indexes FROM pg_indexes WHERE schemaname='public' \gset
SELECT md5(string_agg(sequencename||COALESCE(last_value::text,'NULL'),'' ORDER BY sequencename)) AS snap_sequences FROM pg_sequences WHERE schemaname='public' \gset

\if :mode_write
-- Fixture idéntico BEFORE/AFTER. Preparación fuera de EXPLAIN y del tiempo INSERT.
INSERT INTO public.pedido(id,fecha,estado,total,forma_pago,usuario_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT 1000000+s,DATE '2026-09-23','TERMINADO',p.precio,'EFECTIVO',1,FALSE,
       TIMESTAMPTZ '2026-09-23 00:00:00-03'
FROM generate_series(1,1000) s JOIN public.producto p ON p.id=4+(s%49997);
\echo PLAN_JSON_BEGIN
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT 2000000+s,1,p.precio,p.precio,1000000+s,p.id,FALSE,
       TIMESTAMPTZ '2026-09-23 00:00:00-03'
FROM generate_series(1,1000) s JOIN public.producto p ON p.id=4+(s%49997)
RETURNING id;
\echo PLAN_JSON_END
SELECT (SELECT count(*) FROM public.pedido WHERE id BETWEEN 1000001 AND 1001000)=1000
 AND (SELECT count(*) FROM public.detalle_pedido WHERE id BETWEEN 2000001 AND 2001000)=1000
 AND NOT EXISTS (SELECT 1 FROM public.pedido p LEFT JOIN public.detalle_pedido d ON d.pedido_id=p.id
   WHERE p.id BETWEEN 1000001 AND 1001000 GROUP BY p.id,p.total
   HAVING p.total IS DISTINCT FROM COALESCE(SUM(d.subtotal) FILTER(WHERE NOT d.eliminado),0)) AS guard_ok \gset
\if :guard_ok
\echo PASS: WRITE_1000_detalles_y_totales
\else
SELECT 1/0;
\endif
\endif

\if :mode_functional
DO LANGUAGE plpgsql $tests$
DECLARE
    v_a BIGINT;
    v_b BIGINT;
    v_g BIGINT;
    v_h BIGINT;
    v_cat_a BIGINT;
    v_cat_b BIGINT;
    v_alt BIGINT;
    v_missing BIGINT;
    v_price NUMERIC(12,2);
    v_count BIGINT;
    v_restriccion TEXT;
    v_columna TEXT;
    v_before TEXT;
    v_stocks TEXT;
    v_monetarios TEXT;
    v_totales TEXT;
BEGIN
    SELECT id,categoria_id,precio INTO v_a,v_cat_a,v_price FROM public.producto ORDER BY id LIMIT 1;
    SELECT id,categoria_id INTO v_b,v_cat_b FROM public.producto WHERE categoria_id<>v_cat_a ORDER BY id LIMIT 1;
    SELECT producto_id INTO v_g FROM public.detalle_pedido GROUP BY producto_id ORDER BY count(*) DESC,producto_id LIMIT 1;
    SELECT producto_id INTO v_h FROM public.detalle_pedido WHERE eliminado ORDER BY id LIMIT 1;
    SELECT max(id)+1 INTO v_missing FROM public.producto;
    IF v_a IS NULL OR v_b IS NULL OR v_g IS NULL OR v_h IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: referencias suficientes';
    END IF;
    INSERT INTO public.pedido(id,fecha,total,forma_pago,usuario_id)
    OVERRIDING SYSTEM VALUE
    VALUES(1000001,CURRENT_DATE,v_price,'EFECTIVO',1),
          (1000002,CURRENT_DATE,v_price,'EFECTIVO',1);

    -- A: no enviar la categoría; el BEFORE la completa sin otros efectos.
    INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id)
    OVERRIDING SYSTEM VALUE VALUES(2000001,1,v_price,v_price,1000001,v_a);
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id=2000001 AND categoria_id=v_cat_a
                   AND cantidad=1 AND precio_unitario=v_price AND subtotal=v_price)
    THEN RAISE EXCEPTION 'TEST FAILED A'; END IF;
    RAISE NOTICE 'PASS A: INSERT deriva categoria';

    -- B: una categoría válida pero incorrecta se sobrescribe.
    INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,categoria_id)
    OVERRIDING SYSTEM VALUE VALUES(2000002,1,v_price,v_price,1000002,v_a,v_cat_b);
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id=2000002 AND categoria_id=v_cat_a)
    THEN RAISE EXCEPTION 'TEST FAILED B'; END IF;
    RAISE NOTICE 'PASS B: INSERT con categoria incorrecta corregido';
    SELECT md5(string_agg(id::text||':'||stock::text,',' ORDER BY id)) INTO v_stocks FROM public.producto;
    SELECT md5(string_agg(id::text||':'||cantidad||':'||precio_unitario||':'||subtotal,',' ORDER BY id))
      INTO v_monetarios FROM public.detalle_pedido;
    SELECT md5(string_agg(id::text||':'||total,',' ORDER BY id)) INTO v_totales FROM public.pedido;

    UPDATE public.detalle_pedido SET producto_id=v_b WHERE id=2000001;
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id=2000001 AND producto_id=v_b AND categoria_id=v_cat_b
                   AND precio_unitario=v_price AND subtotal=v_price)
    THEN RAISE EXCEPTION 'TEST FAILED C'; END IF;
    RAISE NOTICE 'PASS C: cambio de producto deriva categoria y conserva importes';

    UPDATE public.detalle_pedido SET categoria_id=v_cat_a WHERE id=2000001;
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id=2000001 AND categoria_id=v_cat_b)
    THEN RAISE EXCEPTION 'TEST FAILED D: categoria incorrecta'; END IF;
    UPDATE public.detalle_pedido SET categoria_id=NULL WHERE id=2000001;
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id=2000001 AND categoria_id=v_cat_b)
    THEN RAISE EXCEPTION 'TEST FAILED D: categoria NULL'; END IF;
    RAISE NOTICE 'PASS D: manipulacion directa y NULL corregidos';

    BEGIN
        UPDATE public.detalle_pedido SET producto_id=v_missing WHERE id=2000001;
        RAISE EXCEPTION 'TEST FAILED E: producto inexistente aceptado';
    EXCEPTION WHEN SQLSTATE '23503' THEN
        GET STACKED DIAGNOSTICS v_restriccion=CONSTRAINT_NAME;
        IF v_restriccion IS DISTINCT FROM 'fk_detalle_pedido_producto' THEN
            RAISE EXCEPTION 'TEST FAILED E: restriccion inesperada %',v_restriccion;
        END IF;
        RAISE NOTICE 'PASS E: producto inexistente SQLSTATE 23503, constraint % (error explicito del trigger)',v_restriccion;
    END;

    BEGIN
        -- Categoría válida explícita aísla NOT NULL de producto_id.
        INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,categoria_id)
        OVERRIDING SYSTEM VALUE VALUES(2000099,1,v_price,v_price,1000001,NULL,v_cat_a);
        RAISE EXCEPTION 'TEST FAILED F: producto NULL aceptado';
    EXCEPTION WHEN SQLSTATE '23502' THEN
        GET STACKED DIAGNOSTICS v_columna=COLUMN_NAME;
        IF v_columna IS DISTINCT FROM 'producto_id' THEN
            RAISE EXCEPTION 'TEST FAILED F: columna inesperada %',v_columna;
        END IF;
        RAISE NOTICE 'PASS F: producto NULL SQLSTATE 23502, columna %',v_columna;
    END;

    SELECT count(*) INTO v_count FROM public.detalle_pedido WHERE producto_id=v_g;
    SELECT min(id) INTO v_alt FROM public.categoria
      WHERE id<>(SELECT categoria_id FROM public.producto WHERE id=v_g);
    UPDATE public.producto SET categoria_id=v_alt WHERE id=v_g;
    IF (SELECT count(*) FROM public.detalle_pedido WHERE producto_id=v_g AND categoria_id=v_alt)<>v_count
    THEN RAISE EXCEPTION 'TEST FAILED G'; END IF;
    RAISE NOTICE 'PASS G: propagacion completa, producto %, detalles %',v_g,v_count;

    -- H: bajas no excluyen la sincronización. No se ensaya inventario ni TPI.
    UPDATE public.producto SET eliminado=TRUE,disponible=FALSE WHERE id=v_h;
    UPDATE public.pedido SET eliminado=TRUE
      WHERE id=(SELECT pedido_id FROM public.detalle_pedido WHERE producto_id=v_h AND eliminado ORDER BY id LIMIT 1);
    SELECT min(id) INTO v_alt FROM public.categoria
      WHERE id<>(SELECT categoria_id FROM public.producto WHERE id=v_h);
    UPDATE public.categoria SET eliminado=TRUE WHERE id=v_alt;
    UPDATE public.producto SET categoria_id=v_alt WHERE id=v_h;
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE producto_id=v_h AND eliminado)
       OR EXISTS (SELECT 1 FROM public.detalle_pedido WHERE producto_id=v_h AND categoria_id IS DISTINCT FROM v_alt)
    THEN RAISE EXCEPTION 'TEST FAILED H'; END IF;
    RAISE NOTICE 'PASS H: detalles y padres eliminados sincronizados';

    -- I: ctid detecta nuevas versiones físicas incluso dentro de la misma TX.
    SELECT md5(string_agg(id::text||':'||ctid::text,',' ORDER BY id)) INTO v_before
      FROM public.detalle_pedido WHERE producto_id=v_g;
    UPDATE public.producto SET categoria_id=categoria_id WHERE id=v_g;
    IF v_before IS DISTINCT FROM (SELECT md5(string_agg(id::text||':'||ctid::text,',' ORDER BY id))
                                  FROM public.detalle_pedido WHERE producto_id=v_g)
    THEN RAISE EXCEPTION 'TEST FAILED I: reescritura innecesaria'; END IF;
    RAISE NOTICE 'PASS I: categoria sin cambio no reescribe detalles';

    IF v_stocks IS DISTINCT FROM (SELECT md5(string_agg(id::text||':'||stock::text,',' ORDER BY id)) FROM public.producto)
       OR v_monetarios IS DISTINCT FROM (SELECT md5(string_agg(id::text||':'||cantidad||':'||precio_unitario||':'||subtotal,',' ORDER BY id)) FROM public.detalle_pedido)
       OR v_totales IS DISTINCT FROM (SELECT md5(string_agg(id::text||':'||total,',' ORDER BY id)) FROM public.pedido)
       OR EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
                  WHERE d.categoria_id IS DISTINCT FROM p.categoria_id)
    THEN RAISE EXCEPTION 'TEST FAILED: auditoria o efectos laterales'; END IF;
    RAISE NOTICE 'PASS: bateria funcional A-I, stock/subtotal/total intactos';
END;
$tests$;
\endif

-- fanout y stress usan el mismo producto de máximo fan-out previo al fixture.
\if :mode_fanout
\set mode_update true
\elif :mode_stress
\set mode_update true
\else
\set mode_update false
\endif
\if :mode_update
SELECT d.producto_id AS target_product, count(*) AS original_fanout,
 (SELECT min(id) FROM public.categoria WHERE id<>p.categoria_id) AS target_category
FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
GROUP BY d.producto_id,p.categoria_id ORDER BY count(*) DESC,d.producto_id LIMIT 1 \gset
\echo UPDATE_TARGET product=:target_product original_fanout=:original_fanout category=:target_category
\if :mode_stress
INSERT INTO public.pedido(id,fecha,estado,total,forma_pago,usuario_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT 1000000+s,DATE '2026-09-23','TERMINADO',p.precio,'EFECTIVO',1,FALSE,
       TIMESTAMPTZ '2026-09-23 00:00:00-03'
FROM generate_series(1,1000) s CROSS JOIN public.producto p WHERE p.id=:target_product;
INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id,eliminado,created_at)
OVERRIDING SYSTEM VALUE
SELECT 2000000+s,1,p.precio,p.precio,1000000+s,p.id,FALSE,
       TIMESTAMPTZ '2026-09-23 00:00:00-03'
FROM generate_series(1,1000) s CROSS JOIN public.producto p WHERE p.id=:target_product;
\endif
SELECT count(*) AS measured_fanout FROM public.detalle_pedido WHERE producto_id=:target_product \gset
\echo MEASURED_FANOUT :measured_fanout
\echo PLAN_JSON_BEGIN
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
UPDATE public.producto SET categoria_id=:target_category WHERE id=:target_product RETURNING id;
\echo PLAN_JSON_END
SELECT (SELECT count(*) FROM public.detalle_pedido
        WHERE producto_id=:target_product AND categoria_id=:target_category)=:measured_fanout
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
                 WHERE d.categoria_id IS DISTINCT FROM p.categoria_id) AS guard_ok \gset
\if :guard_ok
\echo PASS: UPDATE_fanout_completo_auditoria_0
\else
SELECT 1/0;
\endif
\endif

\if :has_candidate
SELECT NOT EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
 WHERE d.categoria_id IS DISTINCT FROM p.categoria_id) AS guard_ok \gset
\if :guard_ok
\else
SELECT 1/0;
\endif
\endif
ROLLBACK;
SELECT :'snap_categoria'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.categoria t)
 AND :'snap_usuario'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.usuario t)
 AND :'snap_producto'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.producto t)
 AND :'snap_pedido'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.pedido t)
 AND :'snap_detalle'=(SELECT md5(string_agg(md5(to_jsonb(t)::text),'' ORDER BY id)) FROM public.detalle_pedido t)
 AND :'snap_indexes'=(SELECT md5(string_agg(indexname||indexdef,'' ORDER BY indexname)) FROM pg_indexes WHERE schemaname='public')
 AND :'snap_sequences'=(SELECT md5(string_agg(sequencename||COALESCE(last_value::text,'NULL'),'' ORDER BY sequencename)) FROM pg_sequences WHERE schemaname='public')
 AND NOT EXISTS (SELECT 1 FROM public.pedido WHERE id BETWEEN 1000001 AND 1001000)
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id BETWEEN 2000001 AND 2001000) AS guard_ok \gset
\if :guard_ok
\echo PASS: ROLLBACK_datos_indices_secuencias_intactos
\else
\echo STOP: estado_post_ROLLBACK
SELECT 1/0;
\endif

/*
PROTOCOLO MULTISESIÓN MANUAL / COORDINADOR EXTERNO (NO AUTOEJECUTADO)

Requiere autorización y tres conexiones independientes a la misma base:
A, B y monitor. Usar ON_ERROR_STOP=1, VERBOSITY verbose, application_name
distintos por escenario y BEGIN ISOLATION LEVEL READ COMMITTED en A/B.
Las barreras se verifican con pg_stat_activity/pg_blocking_pids; no inferir
bloqueo por duración ni sustituir concurrencia por sentencias secuenciales.

Antes de cada escenario verificar que los IDs 1100001 y 2100001 están libres;
registrar las categorías originales de los productos 1 y 3 y huellas canónicas.
La categoría 8 debe existir y ser distinta de ambas categorías originales.
No consumir identidades: todos los INSERT del fixture usan IDs explícitos.

Preparación del pedido: S1/S2, A ejecuta este INSERT dentro de su transacción,
inmediatamente antes del INSERT del detalle. S3/S4, confirmar ambos fixtures
antes de abrir A/B. No confirmar el pedido por separado en S1/S2:
INSERT INTO pedido(id,fecha,total,forma_pago,usuario_id)
OVERRIDING SYSTEM VALUE
SELECT 1100001,CURRENT_DATE,precio,'EFECTIVO',1 FROM producto WHERE id=1;

INSERT del detalle usado por A en S1/S2:
INSERT INTO detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id)
OVERRIDING SYSTEM VALUE
SELECT 2100001,1,precio,precio,1100001,id FROM producto WHERE id=1;

S1 — INSERT primero / recategorización después:
A: SET application_name='u4_p6_s1_a'; BEGIN ISOLATION LEVEL READ COMMITTED;
A: insertar pedido y detalle; mantener la transacción abierta.
Monitor: comprobar A idle in transaction después del INSERT exitoso.
B: SET application_name='u4_p6_s1_b'; BEGIN ISOLATION LEVEL READ COMMITTED;
B: UPDATE producto SET categoria_id=8 WHERE id=1; debe esperar.
Monitor: capturar B con wait_event_type=Lock y pg_blocking_pids apuntando a A.
A: COMMIT; B debe finalizar UPDATE; B: COMMIT.
Verificar detalle.categoria_id=producto.categoria_id=8 y auditoría global=0.

S2 — Recategorización primero / INSERT después:
B: SET application_name='u4_p6_s2_b'; BEGIN ISOLATION LEVEL READ COMMITTED;
B: UPDATE producto SET categoria_id=8 WHERE id=1; mantener abierta.
Monitor: comprobar B idle in transaction después del UPDATE exitoso.
A: SET application_name='u4_p6_s2_a'; BEGIN ISOLATION LEVEL READ COMMITTED;
A: insertar pedido y luego detalle; el segundo INSERT debe esperar por producto.
Monitor: capturar A Lock y bloqueador B. B: COMMIT; A: COMMIT.
Verificar categoría 8 en el detalle, sin versión obsoleta; auditoría global=0.

S3/S4: además del pedido, crear y confirmar el detalle del fixture antes
de abrir A/B (mismo INSERT anterior). Conservar precio/subtotal históricos.

S3 — Cambio de producto del detalle frente a recategorización del destino:
B: SET application_name='u4_p6_s3_b'; BEGIN ISOLATION LEVEL READ COMMITTED;
B: UPDATE producto SET categoria_id=8 WHERE id=3; mantener abierta.
Monitor: confirmar UPDATE terminado y transacción B abierta.
A: SET application_name='u4_p6_s3_a'; BEGIN ISOLATION LEVEL READ COMMITTED;
A: UPDATE detalle_pedido SET producto_id=3 WHERE id=2100001; debe esperar.
Monitor: capturar A Lock y bloqueador B. B: COMMIT; A: COMMIT.
Verificar producto_id=3, categoría 8, importes históricos intactos y auditoría=0.

S4 — Manipulación directa frente a recategorización, orden inverso adversarial:
A: SET application_name='u4_p6_s4_a'; BEGIN ISOLATION LEVEL READ COMMITTED;
A: SELECT id FROM detalle_pedido WHERE id=2100001 FOR UPDATE;
B: SET application_name='u4_p6_s4_b'; BEGIN ISOLATION LEVEL READ COMMITTED;
B: UPDATE producto SET categoria_id=8 WHERE id=1;
Monitor: confirmar B esperando por el detalle bloqueado por A; conservar estado.
A: UPDATE detalle_pedido SET categoria_id=7 WHERE id=2100001;
El BEFORE de A solicita FOR SHARE de producto mientras B conserva su lock
y espera el detalle: este orden puede producir 40P01. No evitarlo cambiando
el cronograma ni agregar locks globales. Registrar SQLSTATE, DETAIL, CONTEXT
y grafo de bloqueos real. Cualquier deadlock/timeout/error inesperado es STOP,
no PASS, no reintento y no parche automático. Revertir solo transacciones propias.

Consulta de monitor durante las esperas:
SELECT pid,application_name,state,wait_event_type,wait_event,
       pg_blocking_pids(pid) AS bloqueadores,query
FROM pg_stat_activity
WHERE datname=current_database() AND application_name LIKE 'u4_p6_s%'
ORDER BY application_name;
SELECT pid,locktype,mode,granted,relation,transactionid
FROM pg_locks WHERE pid IN
  (SELECT pid FROM pg_stat_activity WHERE datname=current_database()
   AND application_name LIKE 'u4_p6_s%') ORDER BY pid,granted,locktype;

Entre escenarios, después de validar y cerrar ambas conexiones, cleanup
controlado en una transacción: DELETE solo el detalle id=2100001 y pedido
id=1100001; restaurar producto 1 y 3 a sus categorías originales REGISTRADAS
(no asumirlas ni usar valores nuevos), dejando al trigger propagar. COMMIT.
Verificar conteos, huellas lógicas de las cinco tablas, auditoría=0 e índices
intactos. No volver a empezar un escenario fallido para conseguir PASS.
Los logs y timestamps de cada conexión/monitor se conservan fuera del repo;
la evidencia Markdown resume únicamente lo efectivamente ejecutado.
*/
