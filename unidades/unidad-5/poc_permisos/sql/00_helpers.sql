-- POC U5 — funciones auxiliares temporales (pg_temp), visibles solo en esta sesión.
-- No crean objetos persistentes ni alteran la huella del esquema public.
-- Cada sentencia probada corre en un bloque con EXCEPTION, es decir, en una
-- subtransacción: un error no deja efectos parciales.
-- Formato de evidencia: NOTICE  RESULT|<caso>|PASS/FAIL|esperado=… observado=…|<mensaje>

CREATE FUNCTION pg_temp.id(p_ref text)
RETURNS bigint
LANGUAGE sql
STABLE
AS $f$ SELECT current_setting('poc.' || p_ref)::bigint $f$;

CREATE FUNCTION pg_temp.esperar_error(p_caso text, p_sentencia text, p_estado text)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_estado text;
    v_msg text;
    v_ctx text;
BEGIN
    BEGIN
        EXECUTE p_sentencia;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_msg = MESSAGE_TEXT,
                                v_ctx = PG_EXCEPTION_CONTEXT;
        RAISE NOTICE 'RESULT|%|%|esperado=% observado=%|%', p_caso,
            CASE WHEN v_estado = p_estado THEN 'PASS' ELSE 'FAIL' END,
            p_estado, v_estado, v_msg;
        RAISE NOTICE 'CONTEXT|%|%', p_caso, replace(v_ctx, E'\n', ' <- ');
        RETURN;
    END;
    RAISE NOTICE 'RESULT|%|FAIL|esperado=% observado=sin_error|la sentencia tuvo éxito',
        p_caso, p_estado;
END
$f$;

CREATE FUNCTION pg_temp.esperar_ok(p_caso text, p_sentencia text)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_estado text;
    v_msg text;
    v_ctx text;
BEGIN
    BEGIN
        EXECUTE p_sentencia;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_msg = MESSAGE_TEXT,
                                v_ctx = PG_EXCEPTION_CONTEXT;
        RAISE NOTICE 'RESULT|%|FAIL|esperado=sin_error observado=%|%', p_caso, v_estado, v_msg;
        RAISE NOTICE 'CONTEXT|%|%', p_caso, replace(v_ctx, E'\n', ' <- ');
        RETURN;
    END;
    RAISE NOTICE 'RESULT|%|PASS|esperado=sin_error observado=sin_error|', p_caso;
END
$f$;

-- Registra el resultado sin veredicto (para observaciones fuera del plan literal).
CREATE FUNCTION pg_temp.observar(p_caso text, p_sentencia text)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_estado text;
    v_msg text;
BEGIN
    BEGIN
        EXECUTE p_sentencia;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE NOTICE 'OBSERVADO|%|observado=%|%', p_caso, v_estado, v_msg;
        RETURN;
    END;
    RAISE NOTICE 'OBSERVADO|%|observado=sin_error|', p_caso;
END
$f$;

-- Compara el texto devuelto por una consulta con el valor esperado.
CREATE FUNCTION pg_temp.verificar(p_caso text, p_consulta text, p_esperado text)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_obs text;
BEGIN
    EXECUTE p_consulta INTO v_obs;
    RAISE NOTICE 'RESULT|%|%|esperado=% observado=%|', p_caso,
        CASE WHEN v_obs IS NOT DISTINCT FROM p_esperado THEN 'PASS' ELSE 'FAIL' END,
        p_esperado, coalesce(v_obs, 'NULL');
END
$f$;

-- Resumen del estado de venta: líneas (pedido/producto:cantidad:precio:subtotal),
-- stock de P1 y P2 y total de O1. Se consulta como superusuario.
CREATE FUNCTION pg_temp.estado()
RETURNS text
LANGUAGE sql
STABLE
AS $f$
    SELECT format('lineas=[%s] stock_p1=%s stock_p2=%s total_o1=%s',
        coalesce((
            SELECT string_agg(format('%s/%s:%s:%s:%s',
                       CASE d.pedido_id WHEN pg_temp.id('o1') THEN 'O1'
                                        WHEN pg_temp.id('o2') THEN 'O2'
                                        WHEN pg_temp.id('o3') THEN 'O3'
                                        ELSE d.pedido_id::text END,
                       CASE d.producto_id WHEN pg_temp.id('p1') THEN 'P1'
                                          WHEN pg_temp.id('p2') THEN 'P2'
                                          WHEN pg_temp.id('p3') THEN 'P3'
                                          WHEN pg_temp.id('p4') THEN 'P4'
                                          ELSE d.producto_id::text END,
                       d.cantidad, d.precio_unitario, d.subtotal), ',' ORDER BY d.id)
            FROM public.detalle_pedido d), ''),
        (SELECT stock FROM public.producto WHERE id = pg_temp.id('p1')),
        (SELECT stock FROM public.producto WHERE id = pg_temp.id('p2')),
        (SELECT total FROM public.pedido WHERE id = pg_temp.id('o1')));
$f$;
