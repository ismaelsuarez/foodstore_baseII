-- ANTES de roles.sql/funciones_seguridad.sql; DESPUÉS de precondiciones y de
-- cualquier instalación de dependencias expresamente autorizada (VP-11).
-- Mantener esta conexión: no exportar/restaurar inventarios desde valores supuestos.
\ir 00_guardas.sql
\ir 00_helpers.sql
DO $g$
BEGIN
    IF to_regclass('pg_temp.u5_f0') IS NOT NULL THEN
        RAISE EXCEPTION 'F0 ya capturada; no sobrescribir el inventario';
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname IN
       ('rol_app_lectura','rol_app_escritura','rol_app_autenticacion','rol_soporte',
        'rol_reportes','rol_propietario_ventas','rol_propietario_credenciales','app_web','admin_datos')
       OR rolname LIKE 'tst\_u5\_%') THEN
        RAISE EXCEPTION 'VP-01: colisión de roles; no adoptar ni limpiar identidades previas';
    END IF;
END $g$;
\ir huella.sql
CREATE TEMP TABLE u5_f0 AS SELECT * FROM pg_temp.u5_huella;
CREATE TEMP TABLE u5_vp01_roles AS SELECT rolname::text AS rol FROM pg_roles;
CREATE TEMP TABLE u5_vp02 AS
SELECT p.oid::regprocedure::text AS firma, p.proowner, pg_get_userbyid(p.proowner) AS propietario
FROM pg_proc p JOIN pg_temp.u5_f0 f ON f.clase = 'rutina' AND f.clave = p.oid::regprocedure::text;
SELECT pg_temp.verificar('F0.VP02.rutinas', 'SELECT count(*)::text FROM pg_temp.u5_vp02', '7');
SELECT pg_temp.verificar('F0.tablas', $$SELECT count(*)::text FROM pg_temp.u5_f0 WHERE clase='tabla'$$, '5');
SELECT pg_temp.verificar('F0.triggers', $$SELECT count(*)::text FROM pg_temp.u5_f0 WHERE clase='trigger'$$, '5');
SELECT * FROM pg_temp.u5_vp02 ORDER BY firma;
SELECT * FROM pg_temp.u5_f0 ORDER BY clase, clave;
