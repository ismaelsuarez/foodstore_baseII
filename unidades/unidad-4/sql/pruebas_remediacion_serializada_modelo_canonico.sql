-- U4 Fase 6E: pruebas de ruta cerrada, no simulación mediante SET ROLE.
-- Ejecutar con conexión LOGIN real -U u4_app y -v modo=funcional.
-- El administrador prepara pedidos 1200001..1200003, usuario1, EFECTIVO.
-- Los detalles 2200001..2200003 deben estar libres. Los pedidos son fixtures
-- externos: este archivo revierte sus detalles y cambios, no elimina pedidos.
-- Totales coherentes del setup: precio producto1 / 0 / precio producto3.
-- No se instala TPI: esta API no administra stock, subtotal ni pedido.total.
-- No incluye contraseñas. Provisión efímera fuera del repositorio y sin logs.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
\pset pager off
\if :{?modo}
\else
\echo STOP: debe indicar -v modo=funcional
SELECT 1/0;
\endif
SELECT :'modo'='funcional'
 AND current_database()='foodstore_u4_revalidacion'
 AND CURRENT_DATE=DATE '2026-09-23'
 AND current_setting('server_version')='17.11'
 AND session_user='u4_app' AND current_user='u4_app' AS guard_ok \gset
\if :guard_ok
\else
\echo STOP: modo_base_fecha_version_o_LOGIN_real
SELECT 1/0;
\endif

SELECT categoria_id AS categoria_original_1 FROM public.producto WHERE id=1 \gset
SELECT categoria_id AS categoria_original_3 FROM public.producto WHERE id=3 \gset
BEGIN ISOLATION LEVEL READ COMMITTED;
DO LANGUAGE plpgsql $pruebas$
DECLARE
    v_constraint text;
    v_column text;
    v_estado text;
    v_missing bigint;
    v_count integer;
    v_precio numeric(12,2);
    v_ctid_before text;
    v_ctid_after text;
BEGIN
    IF (SELECT count(*) FROM public.pedido WHERE id IN (1200001,1200002,1200003))<>3
       OR EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id BETWEEN 2200001 AND 2200003)
       OR (SELECT count(*) FROM public.detalle_pedido)<>500000
       OR (SELECT count(*) FROM public.producto WHERE id IN (1,3))<>2
    THEN RAISE EXCEPTION 'STOP: fixtures administrativos incompatibles'; END IF;

    -- Cada excepción tiene subtransacción propia; no se usa WHEN OTHERS.
    BEGIN
        INSERT INTO public.detalle_pedido(id,cantidad,precio_unitario,subtotal,pedido_id,producto_id)
        OVERRIDING SYSTEM VALUE VALUES(2200001,1,1,1,1200001,1);
        RAISE EXCEPTION 'FAIL: INSERT directo permitido';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_INSERT: SQLSTATE %',v_estado;
    END;
    BEGIN
        UPDATE public.detalle_pedido SET categoria_id=7 WHERE id=1;
        RAISE EXCEPTION 'FAIL: UPDATE detalle directo permitido';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_UPDATE_DETALLE: SQLSTATE %',v_estado;
    END;
    BEGIN
        UPDATE public.producto SET categoria_id=8 WHERE id=1;
        RAISE EXCEPTION 'FAIL: UPDATE producto directo permitido';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_UPDATE_PRODUCTO: SQLSTATE %',v_estado;
    END;
    BEGIN
        PERFORM id FROM public.detalle_pedido WHERE id=1 FOR UPDATE;
        RAISE EXCEPTION 'FAIL: prelock directo del detalle permitido';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_PRELOCK_DETALLE: SQLSTATE %',v_estado;
    END;
    BEGIN
        PERFORM id FROM public.producto WHERE id=1 FOR UPDATE;
        RAISE EXCEPTION 'FAIL: prelock directo del producto permitido';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_PRELOCK_PRODUCTO: SQLSTATE %',v_estado;
    END;
    BEGIN
        PERFORM id FROM public.usuario WHERE id=1;
        RAISE EXCEPTION 'FAIL: lectura de usuario permitida';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
        RAISE NOTICE 'PASS PERM_USUARIO: SQLSTATE %',v_estado;
    END;
    IF pg_catalog.pg_has_role(current_user,'u4_owner','MEMBER')
       OR pg_catalog.has_function_privilege(current_user,'u4_api.fn_gate_categoria()','EXECUTE')
       OR pg_catalog.has_function_privilege(current_user,'u4_api.fn_detalle_pedido_set_categoria()','EXECUTE')
       OR pg_catalog.has_function_privilege(current_user,'u4_api.fn_producto_sync_categoria_detalle()','EXECUTE')
    THEN RAISE EXCEPTION 'FAIL: bypass de rol o helpers'; END IF;

    -- Una llamada, un INSERT multirregistro; categoria_id incorrecta se deriva.
    SELECT count(*) INTO v_count FROM u4_api.insertar_detalles((
        SELECT jsonb_agg(jsonb_build_object(
            'id',x.detalle_id,'cantidad',1,'precio_unitario',p.precio,
            'subtotal',p.precio,'pedido_id',x.pedido_id,'producto_id',p.id,
            'eliminado',x.eliminado,'categoria_id',7))
        FROM (VALUES (2200001::bigint,1200001::bigint,1::bigint,FALSE),
                     (2200002::bigint,1200002::bigint,1::bigint,TRUE),
                     (2200003::bigint,1200003::bigint,3::bigint,FALSE))
              x(detalle_id,pedido_id,producto_id,eliminado)
        JOIN public.producto p ON p.id=x.producto_id));
    IF v_count<>3 OR EXISTS (
        SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
        WHERE d.id BETWEEN 2200001 AND 2200003
          AND (d.categoria_id IS DISTINCT FROM p.categoria_id OR d.subtotal<>d.precio_unitario))
    THEN RAISE EXCEPTION 'FAIL: INSERT multirregistro o derivación'; END IF;
    RAISE NOTICE 'PASS A_B: API INSERT multirregistro y categoría incorrecta normalizada';

    SELECT precio_unitario INTO v_precio FROM public.detalle_pedido WHERE id=2200001;
    PERFORM u4_api.cambiar_producto_detalle(2200001,3);
    IF NOT EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
        WHERE d.id=2200001 AND d.producto_id=3 AND d.categoria_id=p.categoria_id
          AND d.precio_unitario=v_precio AND d.subtotal=v_precio)
    THEN RAISE EXCEPTION 'FAIL: cambio de producto'; END IF;
    RAISE NOTICE 'PASS C: cambio de producto sin alterar importes históricos';

    PERFORM u4_api.normalizar_categoria_detalle(2200001,7);
    IF EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
        WHERE d.id=2200001 AND d.categoria_id IS DISTINCT FROM p.categoria_id)
    THEN RAISE EXCEPTION 'FAIL: manipulación por API no corregida'; END IF;
    RAISE NOTICE 'PASS D: normalización sobrescribe categoría proporcionada';

    SELECT max(id)+1 INTO v_missing FROM public.producto;
    BEGIN
        PERFORM u4_api.cambiar_producto_detalle(2200001,v_missing);
        RAISE EXCEPTION 'FAIL: producto inexistente aceptado';
    EXCEPTION WHEN SQLSTATE '23503' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE,v_constraint=CONSTRAINT_NAME;
        IF v_constraint<>'fk_detalle_pedido_producto' THEN
            RAISE EXCEPTION 'FAIL: constraint inesperada %',v_constraint;
        END IF;
        RAISE NOTICE 'PASS E: SQLSTATE %, constraint %',v_estado,v_constraint;
    END;
    BEGIN
        PERFORM u4_api.cambiar_producto_detalle(2200001,NULL);
        RAISE EXCEPTION 'FAIL: producto NULL aceptado';
    EXCEPTION WHEN SQLSTATE '23502' THEN
        GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE,v_column=COLUMN_NAME;
        IF v_column<>'producto_id' THEN
            RAISE EXCEPTION 'FAIL: columna inesperada %',v_column;
        END IF;
        RAISE NOTICE 'PASS F: SQLSTATE %, columna %',v_estado,v_column;
    END;

    PERFORM u4_api.recategorizar_producto(1,8);
    IF EXISTS (SELECT 1 FROM public.detalle_pedido WHERE producto_id=1 AND categoria_id<>8)
       OR NOT EXISTS (SELECT 1 FROM public.detalle_pedido
                      WHERE id=2200002 AND eliminado AND categoria_id=8)
    THEN RAISE EXCEPTION 'FAIL: propagación incluidas bajas'; END IF;
    RAISE NOTICE 'PASS G_H: propagación completa incluidas bajas';

    SELECT string_agg(id::text||ctid::text,',' ORDER BY id) INTO v_ctid_before
    FROM public.detalle_pedido WHERE producto_id=1;
    PERFORM u4_api.recategorizar_producto(1,8);
    SELECT string_agg(id::text||ctid::text,',' ORDER BY id) INTO v_ctid_after
    FROM public.detalle_pedido WHERE producto_id=1;
    IF v_ctid_before IS DISTINCT FROM v_ctid_after THEN
        RAISE EXCEPTION 'FAIL: categoría sin cambio reescribió detalles';
    END IF;
    RAISE NOTICE 'PASS I: misma categoría no produce fan-out';

    -- Una entrada del lock NO acredita cantidad de invocaciones; sí su retención
    -- en esta transacción, después de varias llamadas y subtransacciones fallidas.
    IF (SELECT count(*) FROM pg_catalog.pg_locks
        WHERE pid=pg_catalog.pg_backend_pid() AND locktype='advisory'
          AND classid=21812 AND objid=1 AND objsubid=2 AND granted)<>1
       OR EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
                  WHERE d.categoria_id IS DISTINCT FROM p.categoria_id)
    THEN RAISE EXCEPTION 'FAIL: gate retenido o auditoría global'; END IF;
    RAISE NOTICE 'PASS: funcional por LOGIN real u4_app, múltiples API en una transacción';
END;
$pruebas$;
ROLLBACK;

SELECT (SELECT count(*) FROM public.detalle_pedido)=500000
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido WHERE id BETWEEN 2200001 AND 2200003)
 AND (SELECT categoria_id FROM public.producto WHERE id=1)=:categoria_original_1
 AND (SELECT categoria_id FROM public.producto WHERE id=3)=:categoria_original_3
 AND NOT EXISTS (SELECT 1 FROM public.detalle_pedido d JOIN public.producto p ON p.id=d.producto_id
                 WHERE d.categoria_id IS DISTINCT FROM p.categoria_id)
 AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_locks
      WHERE pid=pg_catalog.pg_backend_pid() AND locktype='advisory'
        AND classid=21812 AND objid=1 AND objsubid=2) AS rollback_ok \gset
\if :rollback_ok
\echo PASS: ROLLBACK funcional y liberacion del gate
\else
\echo STOP: ROLLBACK funcional
SELECT 1/0;
\endif

-- PROTOCOLO MULTISESIÓN: no se simula aquí con instrucciones secuenciales.
-- Administrador: preparar pedidos/fixtures exclusivos con IDs explícitos,
-- totales coherentes; registrar categorías originales. App no crea pedidos.
-- A y B: conexiones distintas -U u4_app, application_name distinto, BEGIN
-- ISOLATION LEVEL READ COMMITTED; SET LOCAL lock_timeout='15s'.
-- Monitor administrador: pg_stat_activity + pg_locks + pg_blocking_pids(pid).
-- Confirmar A ya retiene el gate mediante catálogo antes de iniciar B.
-- Conservar SQLSTATE, PIDs, aristas, wait_event_type/event, COMMIT/ROLLBACK.
--
-- S1: A SELECT * FROM u4_api.insertar_detalles('[...producto_id:1...]');
--     mantener A abierta. B SELECT u4_api.recategorizar_producto(1,8);
--     observar B Lock/advisory; COMMIT A; B finaliza; COMMIT B; auditoría=0.
-- S2: B recategorizar_producto(1,8) primero; A insertar_detalles(...) espera
--     gate. Confirmar B; A deriva categoría actual 8; confirmar A; auditoría=0.
-- S3: detalle confirmado con producto1. B recategorizar_producto(3,8);
--     A cambiar_producto_detalle(<detalle>,3) espera gate; COMMIT B, A; audit=0.
-- S4 original: u4_app intenta SELECT ...detalle... FOR UPDATE: exigir 42501,
--     ROLLBACK limpio. No llamarlo PASS de DML arbitrario ni ocultar la restricción.
-- S4 ruta admitida: A normalizar_categoria_detalle(<detalle>,7), mantiene TX;
--     B recategorizar_producto(1,8) espera gate antes de producto/detalle.
--     COMMIT A, B; comprobar no 40P01, sin desincronización.
-- Variante ROLLBACK: quien retiene gate revierte; bloqueado continúa con categoría
-- confirmada, nunca con estado revertido. Medir productos distintos: el gate GLOBAL
-- también los serializa. Varias API en una TX mantienen gate hasta cierre.
-- Multirregistro: insertar_detalles(jsonb_array_1000) es una llamada/INSERT;
-- verificar 1000 IDs y auditoría. Catálogo acredita FOR EACH STATEMENT; una sola
-- entrada advisory no acredita por sí sola el número de llamadas al trigger.
-- Cualquier 40P01, bypass, timeout inesperado o audit distinta de0: STOP sin retry.
--
-- WRITE (orquestador, misma carga controlada en ambas rutas):
-- EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON)
-- SELECT * FROM u4_api.insertar_detalles(<jsonb de1000 detalles>);
-- Una warmup + cinco oficiales, cada ensayo BEGIN/ROLLBACK; no consumir secuencias.
-- Informar costo integral API/JSON/gate/triggers, no aislarlo como "solo trigger".
-- UPDATE: EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON)
-- SELECT u4_api.recategorizar_producto(<id>,<categoria_distinta>);
-- Verificar fan-out real por conteos, no inferir filas internas del nodo Function.
-- Execution Time incluye trabajo de la función; buffers raíz, no suma padre/hijos.
--
-- DOWN está en tp_desnormalizacion_top_categorias.sql: cerrar conexiones app,
-- ejecutar sección marcada dentro de BEGIN, verificar roles/ACL/objetos retirados,
-- fuente canónica y seis índices intactos. ROLLBACK solo si el estado final
-- autorizado requiere conservar candidato; nunca retirar roles con sesiones vivas.
