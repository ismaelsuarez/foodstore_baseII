-- POC U5 — P0: guardas e inventario VP sobre la instancia vacía (design.md §14).
-- Solo lectura. VP-02, VP-03, VP-04, VP-11 y VP-12 se relevan tras P1 (02_vp_post_p1.sql).
\ir 00_guardas.sql
\ir 00_guarda_sin_roles.sql

\echo '== VP-00 servidor'
SHOW server_version;

\echo '== VP-01 bases y roles'
SELECT datname, pg_get_userbyid(datdba) AS propietario FROM pg_database ORDER BY datname;
SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication,
       rolbypassrls
FROM pg_roles ORDER BY rolname;

\echo '== VP-05 ACL del esquema public'
SELECT nspname, pg_get_userbyid(nspowner) AS propietario, nspacl FROM pg_namespace
WHERE nspname = 'public';
SELECT CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type
FROM pg_namespace n
CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
WHERE n.nspname = 'public' ORDER BY 1, 2;

\echo '== VP-06 ACL de la base'
SELECT datname, datacl FROM pg_database WHERE datname = current_database();
SELECT CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
       a.privilege_type
FROM pg_database d
CROSS JOIN LATERAL aclexplode(coalesce(d.datacl, acldefault('d', d.datdba))) a
WHERE d.datname = current_database() ORDER BY 1, 2;

\echo '== VP-07 pgcrypto (solo disponibilidad; la extensión no se instala en la POC)'
SELECT name, default_version, installed_version FROM pg_available_extensions
WHERE name = 'pgcrypto';
SELECT extname, extversion FROM pg_extension ORDER BY extname;

\echo '== VP-08 privilegios por defecto'
SELECT count(*) AS entradas_pg_default_acl FROM pg_default_acl;

\echo '== VP-09 logs y contraseñas'
SELECT name, setting FROM pg_settings
WHERE name IN ('log_statement', 'log_parameter_max_length',
               'log_parameter_max_length_on_error', 'log_min_error_statement',
               'log_min_duration_statement', 'log_file_mode', 'logging_collector',
               'password_encryption')
ORDER BY name;

\echo '== VP-10 membresías y createrole_self_grant'
SELECT pg_get_userbyid(roleid) AS rol, pg_get_userbyid(member) AS miembro, admin_option,
       inherit_option, set_option
FROM pg_auth_members ORDER BY 1, 2;
SHOW createrole_self_grant;
