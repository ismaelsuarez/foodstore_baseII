-- SEC-01/02/06/07/10/17/20 y REQ-A01/02/05/06/10. No ejecutado.
\ir 00_guardas.sql
\ir 00_helpers.sql
CREATE TEMP TABLE u5_roles(rol text PRIMARY KEY, login boolean, hereda boolean);
INSERT INTO pg_temp.u5_roles VALUES
 ('rol_app_lectura',false,true), ('rol_app_escritura',false,true),
 ('rol_app_autenticacion',false,true), ('rol_soporte',false,true), ('rol_reportes',false,true),
 ('rol_propietario_ventas',false,false), ('rol_propietario_credenciales',false,false),
 ('app_web',true,true), ('admin_datos',true,true);
\du
SELECT pg_temp.verificar('SEC01.P.grupos', $q$
 SELECT count(*)::text FROM pg_roles p JOIN pg_temp.u5_roles e ON e.rol=p.rolname
 WHERE NOT e.login AND NOT p.rolcanlogin$q$, '7');
SELECT pg_temp.verificar('SEC02.P.SEC06.P.SEC20.P.atributos', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles e LEFT JOIN pg_roles p ON p.rolname=e.rol
 WHERE p.oid IS NULL OR p.rolcanlogin IS DISTINCT FROM e.login
 OR p.rolinherit IS DISTINCT FROM e.hereda OR p.rolsuper OR p.rolcreatedb
 OR p.rolcreaterole OR p.rolreplication OR p.rolbypassrls$q$, '0');
CREATE TEMP TABLE u5_membresias_esperadas(rol text, miembro text, administra boolean, hereda boolean, asume boolean);
INSERT INTO pg_temp.u5_membresias_esperadas VALUES
 ('rol_app_lectura','app_web',false,true,false), ('rol_app_escritura','app_web',false,true,false),
 ('rol_app_autenticacion','app_web',false,true,false);
CREATE TEMP VIEW u5_membresias AS
SELECT pg_get_userbyid(m.roleid)::text AS rol, pg_get_userbyid(m.member)::text AS miembro,
       m.admin_option AS administra, m.inherit_option AS hereda, m.set_option AS asume
FROM pg_auth_members m
WHERE m.roleid IN (SELECT p.oid FROM pg_roles p JOIN pg_temp.u5_roles u ON u.rol=p.rolname)
   OR m.member IN (SELECT p.oid FROM pg_roles p JOIN pg_temp.u5_roles u ON u.rol=p.rolname);
SELECT pg_temp.verificar('SEC07.P.N.SEC10.P.membresias', $q$
 SELECT count(*)::text FROM (
  (SELECT * FROM pg_temp.u5_membresias EXCEPT SELECT * FROM pg_temp.u5_membresias_esperadas)
  UNION ALL
  (SELECT * FROM pg_temp.u5_membresias_esperadas EXCEPT SELECT * FROM pg_temp.u5_membresias)) d$q$, '0');
-- §3.4/SEC-07: EXCEPT contrasta admin=false, inherit=true y set=false exactamente.
SELECT roleid::regrole, member::regrole, admin_option, inherit_option, set_option
FROM pg_auth_members WHERE member='app_web'::regrole ORDER BY roleid::regrole::text;
SELECT pg_temp.verificar('SEC07.N.propietarios.SEC10.P.admin_datos', $q$
 SELECT (NOT pg_has_role('app_web','rol_propietario_ventas','MEMBER')
     AND NOT EXISTS (SELECT FROM pg_auth_members WHERE roleid='admin_datos'::regrole)
     AND NOT EXISTS (SELECT FROM pg_auth_members
       WHERE roleid IN ('rol_propietario_ventas'::regrole,'rol_propietario_credenciales'::regrole)
          OR member IN ('rol_propietario_ventas'::regrole,'rol_propietario_credenciales'::regrole)))::text$q$, 'true');
SELECT pg_temp.verificar('SEC17.P.definer', $q$
 WITH e(firma,dueno) AS (VALUES
  ('public.api_registrar_detalle_pedido(bigint,bigint,integer)','rol_propietario_ventas'),
  ('public.fn_autenticar(text,text)','rol_propietario_credenciales'),
  ('public.fn_resetear_password(bigint,text)','rol_propietario_credenciales'))
 SELECT count(*)::text FROM e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.firma)
 WHERE p.oid IS NULL OR NOT p.prosecdef OR pg_get_userbyid(p.proowner)<>e.dueno
 OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]$q$, '0');
SELECT pg_temp.verificar('SEC17.P.create_public', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles
 WHERE has_schema_privilege(rol,'public','CREATE')$q$, '0');
SELECT pg_temp.verificar('SEC17.P.create_public_PUBLIC', $q$
 SELECT count(*)::text FROM pg_namespace n
 CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
 WHERE n.nspname='public' AND a.grantee=0 AND a.privilege_type='CREATE'$q$, '0');
SELECT pg_temp.verificar('SEC17.P.propietarios_sin_create', $q$
 SELECT count(*)::text FROM pg_namespace n CROSS JOIN
 (VALUES ('rol_propietario_ventas'),('rol_propietario_credenciales')) r(rol)
 WHERE n.oid <> pg_my_temp_schema() AND has_schema_privilege(r.rol,n.oid,'CREATE')$q$, '0');
-- Excluye solo el esquema temporal de esta sesión: PG17 concede todo sobre él a quien tenga TEMP
-- en la base (aclchk.c, pg_namespace_aclmask); con D9 pendiente, PUBLIC conserva TEMP.
-- REQ-A09: barrera estructural, no sustituye revisión humana de reidentificación.
SELECT pg_temp.verificar('SEC04.R.analitica_sin_columnas_personales', $q$
 SELECT count(*)::text FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='reportes' AND c.relkind IN ('r','v','m')
 AND a.attnum>0 AND NOT a.attisdropped
 AND a.attname IN ('nombre','apellido','mail','celular','contrasena','usuario_id')$q$, '0');
SELECT c.oid::regclass AS analitico, a.attname AS columna,
       CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) END AS definicion
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
WHERE n.nspname='reportes' AND c.relkind IN ('r','v','m') ORDER BY 1, a.attnum;
-- SEC-02.N y SEC-20.N: N/A según §8. No se inventa prueba negativa.
-- D9 pendiente: no se afirma REVOKE CONNECT/TEMP. Solo inventario de catálogo.
SELECT datname, datacl FROM pg_database WHERE datname=current_database();
