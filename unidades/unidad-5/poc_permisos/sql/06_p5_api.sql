-- POC U5 — P5: creación atómica de la API, literal de design.md §5.1.
\ir 00_guardas.sql

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
    -- Referencia calificada; el procedimiento canónico hereda este search_path
    CALL public.registrar_detalle_pedido(p_pedido_id, p_producto_id, p_cantidad);
END;
$$;

ALTER FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    OWNER TO rol_propietario_ventas;

REVOKE ALL ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.api_registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_app_escritura;

COMMIT;
