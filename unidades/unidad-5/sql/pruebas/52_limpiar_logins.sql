-- MANUAL: volver a la conexión de control original de 49; cerrar antes los logins.
-- No adoptar identidades de otra corrida ni eliminar roles ajenos.
\ir 00_guardas.sql
DO $g$
BEGIN
 IF to_regclass('pg_temp.u5_logins_creados') IS NULL THEN
  RAISE EXCEPTION 'Falta procedencia de 49 en esta sesión; detenerse';
 END IF;
 IF (SELECT count(*) FROM pg_temp.u5_logins_creados)<>3
 OR EXISTS (SELECT FROM pg_temp.u5_logins_creados e LEFT JOIN pg_roles r ON r.oid=e.oid
            WHERE r.rolname IS DISTINCT FROM e.rolname)
 OR EXISTS (SELECT FROM pg_stat_activity WHERE usename IN
           ('tst_u5_soporte','tst_u5_reportes','tst_u5_sin_privilegios')) THEN
  RAISE EXCEPTION 'Identidades distintas o conexiones aún activas; no limpiar';
 END IF;
END $g$;
BEGIN;
\ir 15_limpieza.sql
COMMIT;
-- REPETICIÓN preparada después del COMMIT, no solo en el snapshot de la limpieza.
SELECT pg_temp.verificar('P8.membresias.post_commit', $q$
 SELECT count(*)::text FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid
 JOIN pg_roles u ON u.oid=m.member
 WHERE r.rolname IN (SELECT rol FROM pg_temp.u5_roles)
 OR u.rolname IN (SELECT rol FROM pg_temp.u5_roles)
 OR r.rolname LIKE 'tst\_u5\_%' OR u.rolname LIKE 'tst\_u5\_%'$q$,'3');
SELECT pg_temp.verificar('D12.post_commit.sin_roles',
 $$SELECT count(*)::text FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'$$,'0');
