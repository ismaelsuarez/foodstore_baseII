-- Complemento de 11_matriz: detecta privilegios indirectos por PUBLIC/herencia.
-- No basta comparar solo ACL que nombren roles U5. REQ-A02/A05/A06 transversal.
\ir 00_guardas.sql
CREATE TEMP VIEW u5_esperado_efectivo AS
SELECT clase,rol,objeto,columna,privilegio FROM pg_temp.u5_esperado
UNION
SELECT clase,'app_web',objeto,columna,privilegio FROM pg_temp.u5_esperado
WHERE rol IN ('rol_app_lectura','rol_app_escritura','rol_app_autenticacion');
SELECT pg_temp.verificar('MATRIZ.efectiva.columnas_exactas', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r
 CROSS JOIN pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
 CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('REFERENCES')) p(priv)
 WHERE n.nspname IN ('public','reportes') AND c.relkind IN ('r','v','m')
 AND has_column_privilege(r.rol,c.oid,a.attnum,p.priv) IS DISTINCT FROM EXISTS (
  SELECT FROM pg_temp.u5_esperado_efectivo e WHERE e.rol=r.rol
  AND e.objeto=n.nspname||'.'||c.relname AND e.privilegio=p.priv
  AND (e.clase='tabla' OR (e.clase='columna' AND e.columna=a.attname)))$q$,'0');
SELECT pg_temp.verificar('MATRIZ.efectiva.tabla_sin_extras', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r CROSS JOIN pg_class c
 JOIN pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN (VALUES ('DELETE'),('TRUNCATE'),('TRIGGER'),('MAINTAIN')) p(priv)
 WHERE n.nspname IN ('public','reportes') AND c.relkind IN ('r','v','m')
 AND has_table_privilege(r.rol,c.oid,p.priv)$q$,'0');
SELECT pg_temp.verificar('MATRIZ.efectiva.rutinas', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r CROSS JOIN pg_temp.u5_rutinas f
 JOIN pg_proc p ON p.oid=to_regprocedure(f.firma)
 WHERE has_function_privilege(r.rol,p.oid,'EXECUTE') IS DISTINCT FROM EXISTS (
  SELECT FROM pg_temp.u5_esperado_efectivo e WHERE e.clase='rutina' AND e.rol=r.rol
  AND e.objeto=f.firma AND e.privilegio='EXECUTE')$q$,'0');
SELECT pg_temp.verificar('MATRIZ.efectiva.esquemas', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r
 CROSS JOIN (VALUES ('public'),('reportes')) n(esquema)
 CROSS JOIN (VALUES ('USAGE'),('CREATE')) p(priv)
 WHERE has_schema_privilege(r.rol,n.esquema,p.priv) IS DISTINCT FROM
  ((n.esquema='public' AND p.priv='USAGE') OR EXISTS (
   SELECT FROM pg_temp.u5_esperado_efectivo e WHERE e.clase='esquema' AND e.rol=r.rol
   AND e.objeto=n.esquema AND e.privilegio=p.priv))$q$,'0');
SELECT pg_temp.verificar('MATRIZ.efectiva.sin_secuencias', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r CROSS JOIN pg_class c
 JOIN pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN (VALUES ('USAGE'),('SELECT'),('UPDATE')) p(priv)
 WHERE n.nspname='public' AND c.relkind='S' AND has_sequence_privilege(r.rol,c.oid,p.priv)$q$,'0');
SELECT pg_temp.verificar('CREDENCIALES.pgcrypto_acl', $q$
 SELECT (has_function_privilege('rol_propietario_credenciales','public.crypt(text,text)','EXECUTE')
 AND has_function_privilege('rol_propietario_credenciales','public.gen_salt(text)','EXECUTE'))::text$q$,'true');
