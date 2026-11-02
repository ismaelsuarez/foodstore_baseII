-- POC U5 — P3 y P4: roles de la POC y matriz de design.md §2.1, §3.1 y §3.2,
-- solo para rol_app_escritura y rol_propietario_ventas. Una sola transacción.
-- Sin contraseñas (§13.2): app_web se usa solo mediante SET ROLE.
\ir 00_guardas.sql
\ir 00_guarda_sin_roles.sql

BEGIN;

-- P3
CREATE ROLE rol_app_escritura NOLOGIN;
CREATE ROLE rol_propietario_ventas NOLOGIN NOINHERIT;
CREATE ROLE app_web LOGIN;
CREATE ROLE tst_u5_sin_privilegios NOLOGIN;

GRANT rol_app_escritura TO app_web;

-- P4: rol_app_escritura (la EXECUTE sobre la API se otorga en P5)
GRANT USAGE ON SCHEMA public TO rol_app_escritura;
GRANT INSERT (usuario_id, forma_pago) ON pedido TO rol_app_escritura;
GRANT SELECT (id) ON pedido TO rol_app_escritura;

-- P4: rol_propietario_ventas
GRANT USAGE ON SCHEMA public TO rol_propietario_ventas;
GRANT SELECT (id, usuario_id, eliminado) ON pedido TO rol_propietario_ventas;
GRANT UPDATE (total) ON pedido TO rol_propietario_ventas;
GRANT SELECT (id, eliminado) ON usuario TO rol_propietario_ventas;
GRANT UPDATE (celular) ON usuario TO rol_propietario_ventas;
GRANT SELECT (id, precio, stock, disponible, eliminado) ON producto TO rol_propietario_ventas;
GRANT UPDATE (stock) ON producto TO rol_propietario_ventas;
GRANT SELECT (pedido_id, producto_id, subtotal, eliminado) ON detalle_pedido
    TO rol_propietario_ventas;
GRANT INSERT (pedido_id, producto_id, cantidad, precio_unitario) ON detalle_pedido
    TO rol_propietario_ventas;

-- P4: D3 y funciones trigger
REVOKE EXECUTE ON PROCEDURE registrar_detalle_pedido(BIGINT, BIGINT, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION calcular_total_pedido(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE registrar_detalle_pedido(BIGINT, BIGINT, INTEGER)
    TO rol_propietario_ventas;
GRANT EXECUTE ON FUNCTION calcular_total_pedido(BIGINT) TO rol_propietario_ventas;

REVOKE EXECUTE ON FUNCTION fn_set_subtotal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_validar_detalle_vigente() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_recalcular_total_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_recalcular_total_update() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_recalcular_total_delete() FROM PUBLIC;

COMMIT;

SELECT rolname, rolcanlogin, rolinherit, rolsuper, rolcreaterole, rolcreatedb, rolreplication,
       rolbypassrls
FROM pg_roles
WHERE rolname IN ('rol_app_escritura', 'rol_propietario_ventas', 'app_web',
                  'tst_u5_sin_privilegios')
ORDER BY 1;

SELECT pg_get_userbyid(roleid) AS rol, pg_get_userbyid(member) AS miembro, admin_option,
       inherit_option, set_option
FROM pg_auth_members ORDER BY 1, 2;
