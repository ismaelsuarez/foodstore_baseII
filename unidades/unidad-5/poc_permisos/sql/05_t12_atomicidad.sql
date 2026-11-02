-- POC U5 — T12 (design.md §13.5). Se ejecuta antes de P5: después de P5 la función
-- ya existiría y CREATE FUNCTION fallaría por duplicado (42723).
\ir 00_guardas.sql
\ir 00_helpers.sql

SELECT pg_temp.verificar('T12.previo',
    $q$SELECT coalesce(to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)')::text, 'NULL')$q$,
    'NULL');

BEGIN;

CREATE FUNCTION public.api_registrar_detalle_pedido(
    p_pedido_id   BIGINT,
    p_producto_id BIGINT,
    p_cantidad    INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    CALL public.registrar_detalle_pedido(p_pedido_id, p_producto_id, p_cantidad);
END;
$$;

ALTER FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    OWNER TO rol_propietario_ventas;

ROLLBACK;

SELECT pg_temp.verificar('T12',
    $q$SELECT coalesce(to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)')::text, 'NULL')$q$,
    'NULL');
