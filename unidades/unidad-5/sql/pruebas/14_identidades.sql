-- D12: incluir dentro de una transacción de pruebas; guardas contra adopción.
DO $g$
BEGIN
 IF EXISTS (SELECT FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%') THEN
  RAISE EXCEPTION 'Hay identidades efímeras previas; no adoptarlas ni eliminarlas';
 END IF;
END $g$;
CREATE ROLE tst_u5_soporte NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE tst_u5_reportes NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE tst_u5_sin_privilegios NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
-- Igual que app_web: herencia sin SET al grupo ni delegación. El superusuario
-- asume la identidad efímera directamente; las conexiones reales heredan su grupo.
GRANT rol_soporte TO tst_u5_soporte WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_reportes TO tst_u5_reportes WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
SELECT pg_temp.verificar('D12.membresias.opciones', $q$
 WITH esperado(rol,miembro,administra,hereda,asume) AS (VALUES
  ('rol_soporte','tst_u5_soporte',false,true,false),
  ('rol_reportes','tst_u5_reportes',false,true,false)), observado AS (
  SELECT pg_get_userbyid(roleid)::text,pg_get_userbyid(member)::text,
         admin_option,inherit_option,set_option
  FROM pg_auth_members WHERE member IN
   ('tst_u5_soporte'::regrole,'tst_u5_reportes'::regrole))
 SELECT count(*)::text FROM (
  (SELECT * FROM esperado EXCEPT SELECT * FROM observado) UNION ALL
  (SELECT * FROM observado EXCEPT SELECT * FROM esperado)) d$q$,'0');
SELECT pg_temp.verificar('SEC19.P.aislamiento', $q$
 SELECT (EXISTS (SELECT FROM pg_roles WHERE rolname='tst_u5_sin_privilegios'
  AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)
 AND NOT EXISTS (SELECT FROM pg_auth_members WHERE member='tst_u5_sin_privilegios'::regrole))::text$q$,'true');
