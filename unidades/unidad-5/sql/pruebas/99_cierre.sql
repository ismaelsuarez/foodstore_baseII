-- Cierre de la misma sesión de control: no reinstala, no elimina datos de dominio.
\ir 00_guardas.sql
SELECT pg_temp.verificar('SEC20.R.roles_VP01_mas_nueve', $q$
 WITH esperado AS (SELECT rol FROM pg_temp.u5_vp01_roles UNION SELECT rol FROM pg_temp.u5_roles),
 observado AS (SELECT rolname::text AS rol FROM pg_roles)
 SELECT count(*)::text FROM (
 (SELECT * FROM esperado EXCEPT SELECT * FROM observado) UNION ALL
 (SELECT * FROM observado EXCEPT SELECT * FROM esperado)) d$q$,'0');
SELECT pg_temp.verificar('SEC20.R.sin_efimeros',
 $$SELECT count(*)::text FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'$$,'0');
SELECT pg_temp.verificar('SEC20.R.membresias', $q$
 SELECT count(*)::text FROM (
 (SELECT * FROM pg_temp.u5_membresias EXCEPT SELECT * FROM pg_temp.u5_membresias_esperadas)
 UNION ALL
 (SELECT * FROM pg_temp.u5_membresias_esperadas EXCEPT SELECT * FROM pg_temp.u5_membresias)) d$q$,'0');
SELECT pg_temp.verificar('SEC15.R.huella_final',
 'SELECT count(*)::text FROM pg_temp.u5_diferencias_f0_f1','0');
SELECT pg_temp.verificar('MATRIZ.R.final',
 'SELECT count(*)::text FROM pg_temp.u5_diff_matriz','0');
SELECT pg_temp.sin_fixtures('CIERRE.sin_fixtures');
-- No anuncia éxito global: faltan registrar por separado TPI, conexiones, logs
-- y las revisiones humanas. Una futura salida correcta no cubre esos pasos.
