-- Unidad 5, Parte A — instalación de roles y privilegios, PostgreSQL 17.
-- Escritura/revisión únicamente: este archivo todavía no fue ejecutado.
-- Orden: 00_precondiciones.sql -> roles.sql -> funciones_seguridad.sql -> pruebas/.
-- Repite el inventario previo para impedir omitir las guardas. Requiere u5_base_objetivo.
-- No usar -1: BEGIN/COMMIT propios. Una colisión aborta, no se reutilizan roles.
-- No modifica definiciones ni propietarios canónicos (D2, REQ-A12, SEC-15).
\set ON_ERROR_STOP on
\ir 00_precondiciones.sql

BEGIN;
SET LOCAL search_path = pg_catalog;

-- 1. REQ-A01/A02/A11; SEC-01/02/06/20; design.md §3.4, D6/D13.
-- Roles globales del clúster: una base nueva NO evita colisiones en instancia compartida.
-- Sin contraseñas literales ni verificadores. Asignación externa con \password (README).
CREATE ROLE rol_app_lectura NOLOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_app_escritura NOLOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_soporte NOLOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_reportes NOLOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_app_autenticacion NOLOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_propietario_ventas NOLOGIN NOINHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_propietario_credenciales NOLOGIN NOINHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE app_web LOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE admin_datos LOGIN INHERIT
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- 2. REQ-A01/A02/A06; SEC-07/10. Tres membresías explícitas (PG16+).
-- Hereda privilegios sin asumir grupos ni delegar membresía; SET ROLE app_web
-- desde el superusuario de pruebas no depende del SET de estas membresías.
GRANT rol_app_lectura TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_app_escritura TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_app_autenticacion TO app_web WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
-- Nadie es miembro de los propietarios ni de admin_datos. No crear tst_u5_* aquí (D12).

-- 3. REQ-A05/A08/A09; SEC-04/06/17; design.md §3.3/§4, D10.
-- El superusuario instalador conserva el esquema; los propietarios NOLOGIN no tienen CREATE.
CREATE SCHEMA IF NOT EXISTS reportes;
GRANT USAGE ON SCHEMA reportes TO rol_reportes;
GRANT USAGE, CREATE ON SCHEMA reportes TO admin_datos;
GRANT USAGE ON SCHEMA public TO rol_app_lectura, rol_app_escritura, rol_soporte,
    rol_app_autenticacion, rol_propietario_ventas, rol_propietario_credenciales, admin_datos;
-- No cambiar CREATE de PUBLIC: precondiciones falla si está concedido.
-- No cambiar CONNECT/TEMP de PUBLIC ni conceder CONNECT explícito: D9 pendiente.

-- 4. REQ-A02/A03/A09; SEC-04/05/08/09/14; design.md §3.1, D15.
GRANT SELECT ON public.v_productos_vigentes TO rol_app_lectura;
GRANT INSERT (usuario_id, forma_pago) ON public.pedido TO rol_app_escritura;
GRANT SELECT (id) ON public.pedido TO rol_app_escritura;
GRANT SELECT ON public.v_usuarios_publico, public.v_pedidos_resumen TO rol_soporte;
-- D4 pendiente: ningún UPDATE (estado). Sin DML directo del detalle ni stock para app.
-- Sin permisos sobre v_pedido_detalle, tablas base de catálogo ni usuario para app/soporte.

-- 5. REQ-A02/A03/A10; SEC-03/05/17; cadena INVOKER validada en POC 04/06 (§13.7).
GRANT SELECT (id, usuario_id, eliminado) ON public.pedido TO rol_propietario_ventas;
GRANT UPDATE (total) ON public.pedido TO rol_propietario_ventas;
GRANT SELECT (id, eliminado) ON public.usuario TO rol_propietario_ventas;
-- D11 aprobada 2026-11-02. Nunca UPDATE de la tabla completa.
-- RR-01 (§5.4): habilita FOR SHARE, pero SQL arbitrario con esta identidad podría
-- escribir celular de cualquier usuario. NOLOGIN, NOINHERIT, sin miembros;
-- la cadena canónica nunca escribe celular. No eliminar ni ampliar este permiso.
GRANT UPDATE (celular) ON public.usuario TO rol_propietario_ventas;
GRANT SELECT (id, precio, stock, disponible, eliminado) ON public.producto TO rol_propietario_ventas;
GRANT UPDATE (stock) ON public.producto TO rol_propietario_ventas;
GRANT SELECT (pedido_id, producto_id, subtotal, eliminado) ON public.detalle_pedido
    TO rol_propietario_ventas;
GRANT INSERT (pedido_id, producto_id, cantidad, precio_unitario) ON public.detalle_pedido
    TO rol_propietario_ventas;
-- Sin privilegios de secuencias, REFERENCES ni EXECUTE de funciones trigger (POC T08/T09).

-- 6. REQ-A02/A03/A10; SEC-17/18; design.md §2.1/§3.1.
GRANT SELECT (id, mail, contrasena, rol, eliminado) ON public.usuario
    TO rol_propietario_credenciales;
GRANT UPDATE (contrasena) ON public.usuario TO rol_propietario_credenciales;
-- crypt(text,text) y gen_salt(text): EXECUTE heredado de PUBLIC, verificado por VP-07.
-- No se cambia el ACL de pgcrypto ni se amplían sus permisos.

-- 7. REQ-A01/A02/A09; SEC-06; D13/D18, sin DML ni propietarios canónicos nuevos.
GRANT SELECT ON public.categoria, public.producto, public.pedido, public.detalle_pedido
    TO admin_datos;
GRANT SELECT (id, rol, eliminado, created_at) ON public.usuario TO admin_datos;

-- 8. REQ-A08/A09; SEC-04/06; §4.2: conservar ubicación sin mover ni duplicar.
-- REVISAR: §4.2 contempla ubicación arbitraria; §3.3 no autoriza USAGE en otros
-- esquemas. Solo public/reportes: la guarda aborta ante cualquier otra ubicación.
DO $$
DECLARE
    v_esquema text;
BEGIN
    SELECT n.nspname INTO STRICT v_esquema
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'mv_facturacion_categoria_mes' AND c.relkind = 'm';
    IF v_esquema NOT IN ('public', 'reportes') THEN
        RAISE EXCEPTION 'Ubicación de materializada fuera de matriz: %; revisar §3.3/§4.2', v_esquema;
    END IF;
    IF v_esquema = 'public' THEN
        GRANT USAGE ON SCHEMA public TO rol_reportes;
    END IF;
    EXECUTE format('GRANT SELECT ON %I.mv_facturacion_categoria_mes TO rol_reportes, admin_datos', v_esquema);
END $$;

-- 9. REQ-A07/A12; SEC-03/13/15; D3, §3.2. Solo ACL: sin redefinir ni reasignar.
REVOKE EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_propietario_ventas;
GRANT EXECUTE ON FUNCTION public.calcular_total_pedido(BIGINT) TO rol_propietario_ventas;
REVOKE EXECUTE ON FUNCTION public.fn_set_subtotal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_detalle_vigente() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_update() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_total_delete() FROM PUBLIC;

-- 10. REQ-A04/A08; SEC-11/12; exactamente los dos contextos de §6.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA reportes
    GRANT SELECT ON TABLES TO rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Ningún ADP sobre public. La verificación usa pg_default_acl, no una vista inexistente.

COMMIT;
-- RR-07: tras reinstalar el TPI, seguir el procedimiento MANUAL de recuperación
-- de ACL en README.md, con autorización separada. No reejecutar esta instalación
-- ni borrar/reutilizar roles para aparentar idempotencia.
-- EXECUTE de las tres interfaces nuevas se concede en funciones_seguridad.sql,
-- dentro de su transacción de creación. No hay GRANT anticipado a un objeto inexistente.
