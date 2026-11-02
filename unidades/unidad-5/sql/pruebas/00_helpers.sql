-- Adaptación de poc_permisos/sql/00_helpers.sql: auxiliares de sesión INVOKER.
-- Las etiquetas de resultado solo se emitirán condicionalmente en una ejecución futura.
-- No se imprimen sentencias, parámetros, hashes ni MESSAGE_TEXT (podría contener datos).
CREATE OR REPLACE FUNCTION pg_temp.verificar(p_caso text, p_consulta text, p_esperado text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_obs text;
BEGIN
    EXECUTE p_consulta INTO v_obs;
    IF v_obs IS DISTINCT FROM p_esperado THEN
        RAISE NOTICE 'RESULT|%|FAIL|esperado=% observado=%|aserción',
            p_caso, p_esperado, coalesce(v_obs, 'NULL');
        RAISE EXCEPTION 'Aserción fallida: %; detener y preservar diagnóstico', p_caso;
    END IF;
    RAISE NOTICE 'RESULT|%|%|esperado=% observado=%|aserción',
        p_caso, 'PASS', p_esperado, v_obs;
END $f$;

CREATE OR REPLACE FUNCTION pg_temp.esperar_error(p_caso text, p_sentencia text, p_estado text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_estado text;
BEGIN
    BEGIN
        EXECUTE p_sentencia;
        -- También revierte un éxito inesperado: no contamina los siguientes casos.
        RAISE EXCEPTION USING ERRCODE = 'ZX001', MESSAGE = 'control interno del arnés';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN v_estado := 'sin_error';
              WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE;
    END;
    PERFORM pg_temp.verificar(p_caso, format('SELECT %L::text', v_estado), p_estado);
END $f$;

CREATE OR REPLACE FUNCTION pg_temp.esperar_ok(p_caso text, p_sentencia text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_estado text := 'sin_error';
BEGIN
    BEGIN
        EXECUTE p_sentencia;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE;
    END;
    PERFORM pg_temp.verificar(p_caso, format('SELECT %L::text', v_estado), 'sin_error');
END $f$;

CREATE OR REPLACE FUNCTION pg_temp.id(p_ref text)
RETURNS bigint LANGUAGE sql STABLE AS $f$
    SELECT current_setting('u5.' || p_ref)::bigint
$f$;

CREATE OR REPLACE FUNCTION pg_temp.sin_fixtures(p_caso text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    PERFORM pg_temp.verificar(p_caso, $q$
        SELECT (NOT EXISTS (SELECT FROM public.categoria WHERE nombre = '__U5_VERIFICACION__')
            AND NOT EXISTS (SELECT FROM public.usuario WHERE mail LIKE 'u5.verificacion.%@ejemplo.test')
            AND NOT EXISTS (SELECT FROM public.producto
                WHERE left(nombre,length('__U5_VERIFICACION_'))='__U5_VERIFICACION_')
            AND NOT EXISTS (SELECT FROM public.pedido
                WHERE id IN (pg_temp.id('o1'),pg_temp.id('o2'),pg_temp.id('o3'))
                   OR usuario_id IN (pg_temp.id('u1'),pg_temp.id('u2'),pg_temp.id('ua')))
            AND NOT EXISTS (SELECT FROM public.detalle_pedido
                WHERE pedido_id IN (pg_temp.id('o1'),pg_temp.id('o2'),pg_temp.id('o3'))))::text
    $q$, 'true');
END $f$;
