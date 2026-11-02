-- POC U5 — VP-02, VP-03, VP-04, VP-11 y VP-12 tras P1 (solo lectura).
\ir 00_guardas.sql
\ir 00_guarda_sin_roles.sql

\echo '== VP-02 propietarios'
SELECT 'tabla' AS clase, relname AS objeto, pg_get_userbyid(relowner) AS propietario
FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'S')
UNION ALL
SELECT 'rutina', oid::regprocedure::text, pg_get_userbyid(proowner)
FROM pg_proc WHERE pronamespace = 'public'::regnamespace
UNION ALL
SELECT 'tipo', typname, pg_get_userbyid(typowner)
FROM pg_type WHERE typnamespace = 'public'::regnamespace AND typtype = 'e'
UNION ALL
SELECT 'esquema', nspname, pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'public'
UNION ALL
SELECT 'base', datname, pg_get_userbyid(datdba) FROM pg_database
WHERE datname = current_database()
ORDER BY 1, 2;

\echo '== VP-03 ACL y configuración de las rutinas (consulta de design.md §3.2)'
SELECT p.oid::regprocedure AS rutina,
       pg_get_userbyid(p.proowner) AS propietario,
       p.proacl IS NULL AS proacl_null,
       p.prosecdef,
       p.proconfig,
       CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
WHERE p.pronamespace = 'public'::regnamespace
ORDER BY 1, 6;

\echo '== VP-04 triggers'
SELECT tgrelid::regclass AS tabla, tgname, tgfoid::regprocedure AS funcion, tgenabled
FROM pg_trigger WHERE NOT tgisinternal ORDER BY 1, 2;

\echo '== VP-11 vistas y materializada de U3 (no forman parte de la instalación mínima)'
SELECT n AS objeto, to_regclass('public.' || n) IS NOT NULL AS presente
FROM unnest(ARRAY['v_productos_vigentes', 'v_pedidos_resumen', 'v_pedido_detalle',
                  'v_usuarios_publico', 'mv_facturacion_categoria_mes']) AS n
ORDER BY 1;

\echo '== VP-12 secuencias de identidad y ACL'
SELECT t AS tabla, pg_get_serial_sequence('public.' || t, 'id') AS secuencia,
       (SELECT relacl FROM pg_class
        WHERE oid = pg_get_serial_sequence('public.' || t, 'id')::regclass) AS acl
FROM unnest(ARRAY['categoria', 'usuario', 'producto', 'pedido', 'detalle_pedido']) AS t
ORDER BY 1;
