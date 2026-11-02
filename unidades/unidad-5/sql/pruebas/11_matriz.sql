-- REQ-A03..A08; SEC-05.R/08.R/09.P/11.R/12.R/13.R/14.R/17.P.
-- Comparación de GRANT explícitos y privilegios efectivos. Misma sesión que 10_catalogo.
\ir 00_guardas.sql
\ir 00_helpers.sql
DO $g$
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE c.relname='mv_facturacion_categoria_mes' AND c.relkind='m'
       AND n.nspname IN ('public','reportes')) <> 1 THEN
  RAISE EXCEPTION 'VP-11: debe existir exactamente una materializada; no crear/mover desde pruebas';
 END IF;
END $g$;
CREATE TEMP TABLE u5_mv AS
SELECT c.oid, n.nspname::text AS esquema, c.relname::text AS nombre
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE c.relname='mv_facturacion_categoria_mes' AND c.relkind='m'
AND n.nspname IN ('public','reportes');
SELECT set_config('u5.mv', format('%I.%I',esquema,nombre), false) AS mv FROM pg_temp.u5_mv
\gset
CREATE TEMP TABLE u5_esperado(
 clase text, rol text, objeto text, columna text, privilegio text, delegable boolean DEFAULT false);
-- §3.1: permisos de relación, sin convertirlos en falsos GRANT por columna.
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio) VALUES
 ('tabla','admin_datos','public.categoria','','SELECT'),
 ('tabla','admin_datos','public.producto','','SELECT'),
 ('tabla','admin_datos','public.pedido','','SELECT'),
 ('tabla','admin_datos','public.detalle_pedido','','SELECT'),
 ('tabla','rol_app_lectura','public.v_productos_vigentes','','SELECT'),
 ('tabla','rol_soporte','public.v_usuarios_publico','','SELECT'),
 ('tabla','rol_soporte','public.v_pedidos_resumen','','SELECT');
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio)
SELECT 'tabla',r.rol, m.esquema||'.'||m.nombre,'','SELECT'
FROM pg_temp.u5_mv m CROSS JOIN (VALUES ('rol_reportes'),('admin_datos')) r(rol);
-- Parte A no admite otros objetos analíticos preinstalados sin autorización.
SELECT c.oid::regclass AS objeto_inesperado FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='reportes' AND c.relkind IN ('r','p','v','m','S','f')
AND c.oid NOT IN (SELECT oid FROM pg_temp.u5_mv);
SELECT pg_temp.verificar('MATRIZ.reportes.sin_objetos_inesperados', $q$
 SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='reportes' AND c.relkind IN ('r','p','v','m','S','f')
 AND c.oid NOT IN (SELECT oid FROM pg_temp.u5_mv)$q$,'0');
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio)
SELECT 'columna',rol,'public.'||tabla,columna,privilegio FROM (VALUES
 ('rol_app_escritura','pedido','INSERT',ARRAY['usuario_id','forma_pago']),
 ('rol_app_escritura','pedido','SELECT',ARRAY['id']),
 ('rol_propietario_ventas','pedido','SELECT',ARRAY['id','usuario_id','eliminado']),
 ('rol_propietario_ventas','pedido','UPDATE',ARRAY['total']),
 ('rol_propietario_ventas','usuario','SELECT',ARRAY['id','eliminado']),
 ('rol_propietario_ventas','usuario','UPDATE',ARRAY['celular']),
 ('rol_propietario_ventas','producto','SELECT',ARRAY['id','precio','stock','disponible','eliminado']),
 ('rol_propietario_ventas','producto','UPDATE',ARRAY['stock']),
 ('rol_propietario_ventas','detalle_pedido','SELECT',ARRAY['pedido_id','producto_id','subtotal','eliminado']),
 ('rol_propietario_ventas','detalle_pedido','INSERT',ARRAY['pedido_id','producto_id','cantidad','precio_unitario']),
 ('rol_propietario_credenciales','usuario','SELECT',ARRAY['id','mail','contrasena','rol','eliminado']),
 ('rol_propietario_credenciales','usuario','UPDATE',ARRAY['contrasena']),
 ('admin_datos','usuario','SELECT',ARRAY['id','rol','eliminado','created_at'])
) e(rol,tabla,privilegio,columnas) CROSS JOIN LATERAL unnest(columnas) c(columna);
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio)
SELECT 'esquema',rol,'public','','USAGE' FROM pg_temp.u5_roles
WHERE rol NOT IN ('app_web','rol_reportes');
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio)
SELECT 'esquema','rol_reportes','public','','USAGE' FROM pg_temp.u5_mv WHERE esquema='public';
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio) VALUES
 ('esquema','rol_reportes','reportes','','USAGE'),
 ('esquema','admin_datos','reportes','','USAGE'),
 ('esquema','admin_datos','reportes','','CREATE');
CREATE TEMP TABLE u5_rutinas(firma text PRIMARY KEY, beneficiario text);
INSERT INTO pg_temp.u5_rutinas VALUES
 ('public.registrar_detalle_pedido(bigint,bigint,integer)','rol_propietario_ventas'),
 ('public.calcular_total_pedido(bigint)','rol_propietario_ventas'),
 ('public.fn_set_subtotal()',NULL), ('public.fn_validar_detalle_vigente()',NULL),
 ('public.fn_recalcular_total_insert()',NULL), ('public.fn_recalcular_total_update()',NULL),
 ('public.fn_recalcular_total_delete()',NULL),
 ('public.api_registrar_detalle_pedido(bigint,bigint,integer)','rol_app_escritura'),
 ('public.fn_autenticar(text,text)','rol_app_autenticacion'),
 ('public.fn_resetear_password(bigint,text)','rol_soporte');
SELECT pg_temp.verificar('SEC13.R.diez_rutinas', $q$
 SELECT count(*)::text FROM pg_temp.u5_rutinas WHERE to_regprocedure(firma) IS NOT NULL$q$, '10');
INSERT INTO pg_temp.u5_esperado(clase,rol,objeto,columna,privilegio)
SELECT 'rutina',r.beneficiario,r.firma,'','EXECUTE' FROM pg_temp.u5_rutinas r WHERE beneficiario IS NOT NULL
UNION
SELECT 'rutina', pg_get_userbyid(p.proowner), r.firma,'','EXECUTE'
FROM pg_temp.u5_rutinas r JOIN pg_proc p ON p.oid=to_regprocedure(r.firma);
CREATE TEMP VIEW u5_observado AS
SELECT 'tabla'::text AS clase, pg_get_userbyid(x.grantee)::text AS rol,
       n.nspname||'.'||c.relname AS objeto, ''::text AS columna,
       x.privilege_type AS privilegio, x.is_grantable AS delegable
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
WHERE n.nspname IN ('public','reportes') AND c.relkind IN ('r','v','m','S')
AND pg_get_userbyid(x.grantee) IN (SELECT rol FROM pg_temp.u5_roles)
UNION ALL
SELECT 'columna',pg_get_userbyid(x.grantee), n.nspname||'.'||c.relname,a.attname,
       x.privilege_type,x.is_grantable
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
CROSS JOIN LATERAL aclexplode(a.attacl) x
WHERE n.nspname IN ('public','reportes')
AND pg_get_userbyid(x.grantee) IN (SELECT rol FROM pg_temp.u5_roles)
UNION ALL
SELECT 'esquema',pg_get_userbyid(x.grantee),n.nspname,'',x.privilege_type,x.is_grantable
FROM pg_namespace n
CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x
WHERE n.nspname IN ('public','reportes')
AND pg_get_userbyid(x.grantee) IN (SELECT rol FROM pg_temp.u5_roles)
UNION ALL
SELECT 'rutina',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,
       r.firma,'',x.privilege_type,x.is_grantable
FROM pg_temp.u5_rutinas r JOIN pg_proc p ON p.oid=to_regprocedure(r.firma)
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x;
CREATE TEMP VIEW u5_diff_matriz AS
SELECT 'sobrante'::text AS sentido, d.* FROM
 (SELECT * FROM pg_temp.u5_observado EXCEPT SELECT * FROM pg_temp.u5_esperado) d
UNION ALL
SELECT 'faltante',d.* FROM
 (SELECT * FROM pg_temp.u5_esperado EXCEPT SELECT * FROM pg_temp.u5_observado) d;
SELECT * FROM pg_temp.u5_diff_matriz ORDER BY sentido,clase,rol,objeto,columna,privilegio;
SELECT pg_temp.verificar('MATRIZ.EXCEPT.bidireccional',
 'SELECT count(*)::text FROM pg_temp.u5_diff_matriz','0');
-- Las vistas de information_schema son evidencia complementaria, no matriz completa.
SELECT * FROM information_schema.role_table_grants
WHERE grantee IN (SELECT rol FROM pg_temp.u5_roles) ORDER BY grantee,table_schema,table_name,privilege_type;
SELECT * FROM information_schema.role_column_grants
WHERE grantee IN (SELECT rol FROM pg_temp.u5_roles) ORDER BY grantee,table_name,column_name,privilege_type;
SELECT * FROM information_schema.role_routine_grants
WHERE grantee IN (SELECT rol FROM pg_temp.u5_roles) ORDER BY grantee,routine_name;
SELECT pg_temp.verificar('MATRIZ.efectiva.columnas', $q$
 SELECT count(*)::text FROM pg_temp.u5_esperado
 WHERE clase='columna' AND NOT has_column_privilege(rol,objeto,columna,privilegio)$q$,'0');
SELECT pg_temp.verificar('REQ05.usage_efectivo', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles
 WHERE rol<>'rol_reportes' AND NOT has_schema_privilege(rol,'public','USAGE')$q$,'0');
SELECT pg_temp.verificar('SEC09.P.sin_delete_truncate', $q$
 SELECT count(*)::text FROM pg_temp.u5_roles r CROSS JOIN
 (VALUES ('public.categoria'),('public.usuario'),('public.producto'),('public.pedido'),('public.detalle_pedido')) t(tabla)
 WHERE has_table_privilege(r.rol,t.tabla,'DELETE') OR has_table_privilege(r.rol,t.tabla,'TRUNCATE')$q$,'0');
-- §6: consulta oficial; se inspeccionan TODAS las entradas, no una vista inexistente.
SELECT pg_get_userbyid(d.defaclrole) AS rol_creador,
       coalesce(n.nspname,'(global)') AS esquema, d.defaclobjtype AS tipo, d.defaclacl AS acl
FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace ORDER BY 1,2,3;
SELECT pg_temp.verificar('SEC11.R.SEC12.R.dos_entradas',
 'SELECT count(*)::text FROM pg_default_acl','2');
SELECT pg_temp.verificar('SEC11.R.SEC12.R.EXCEPT', $q$
 WITH esperado(creador,esquema,tipo,beneficiario,privilegio,delegable) AS (VALUES
 ('admin_datos','reportes','r','rol_reportes','SELECT',false),
 ('admin_datos','(global)','f','admin_datos','EXECUTE',false)),
 observado AS (
 SELECT pg_get_userbyid(d.defaclrole)::text,coalesce(n.nspname::text,'(global)'),
 d.defaclobjtype::text,CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END,
 a.privilege_type,a.is_grantable FROM pg_default_acl d
 LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace CROSS JOIN LATERAL aclexplode(d.defaclacl) a)
 SELECT count(*)::text FROM (
 (SELECT * FROM esperado EXCEPT SELECT * FROM observado) UNION ALL
 (SELECT * FROM observado EXCEPT SELECT * FROM esperado)) d$q$,'0');
