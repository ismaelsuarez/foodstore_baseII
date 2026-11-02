-- Retira SOLO las tres identidades creadas por 14_identidades en esta corrida.
-- Solo incluir tras 14 en la transacción actual o desde 52, que valida procedencia.
-- No elimina roles U5 instalados ni objetos canónicos; no usa CASCADE.
RESET ROLE;
DROP OWNED BY tst_u5_soporte, tst_u5_reportes, tst_u5_sin_privilegios;
DROP ROLE tst_u5_soporte, tst_u5_reportes, tst_u5_sin_privilegios;
SELECT pg_temp.verificar('SEC19.R.SEC20.R.efimeros', $q$
 SELECT count(*)::text FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'$q$,'0');
-- Repetición PREPARADA de P8.membresias (A-3); no se retiran los nueve roles U5.
-- El subconjunto U5 debe conservar tres membresías; las efímeras deben ser cero.
-- Contar toda pg_auth_members incluiría las tres membresías predefinidas pg_monitor.
SELECT pg_temp.verificar('P8.membresias.efimeras', $q$
 SELECT count(*)::text FROM pg_auth_members m
 JOIN pg_roles r ON r.oid=m.roleid JOIN pg_roles u ON u.oid=m.member
 WHERE r.rolname LIKE 'tst\_u5\_%' OR u.rolname LIKE 'tst\_u5\_%'$q$,'0');
SELECT pg_temp.verificar('P8.membresias.U5_filtradas', $q$
 SELECT count(*)::text FROM pg_auth_members m
 JOIN pg_roles r ON r.oid=m.roleid JOIN pg_roles u ON u.oid=m.member
 WHERE r.rolname IN (SELECT rol FROM pg_temp.u5_roles)
 OR u.rolname IN (SELECT rol FROM pg_temp.u5_roles)
 OR r.rolname LIKE 'tst\_u5\_%' OR u.rolname LIKE 'tst\_u5\_%'$q$,'3');
SELECT pg_temp.verificar('P8.membresias.EXCEPT', $q$
 SELECT count(*)::text FROM (
 (SELECT * FROM pg_temp.u5_membresias EXCEPT SELECT * FROM pg_temp.u5_membresias_esperadas)
 UNION ALL
 (SELECT * FROM pg_temp.u5_membresias_esperadas EXCEPT SELECT * FROM pg_temp.u5_membresias)) d$q$,'0');
