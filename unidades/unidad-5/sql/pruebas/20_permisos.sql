-- Comportamiento positivo/negativo; todos los efectos quedan en BEGIN ... ROLLBACK.
-- Ejecutar en la conexión que conserva F0, 10_catalogo, 11_matriz y IDs reservados.
\ir 00_guardas.sql
\ir 00_helpers.sql
\ir 00_guardas_credenciales.sql
BEGIN;
\ir 13_fixtures.sql
\ir 14_identidades.sql
SET ROLE app_web;
SELECT pg_temp.esperar_ok('LECTURA.P.catalogo', 'SELECT * FROM public.v_productos_vigentes LIMIT 1');
SELECT pg_temp.esperar_ok('SEC08.P.SEC14.P.insert_returning',
 $$INSERT INTO public.pedido(usuario_id,forma_pago) VALUES (pg_temp.id('u1'),'TARJETA') RETURNING id$$);
SELECT pg_temp.esperar_error('SEC08.N.pedido_completo','SELECT * FROM public.pedido','42501');
SELECT pg_temp.esperar_error('SEC08.N.total','SELECT total FROM public.pedido','42501');
-- D4 pendiente: se verifica la matriz actual SIN UPDATE(estado), no una política de transición.
SELECT pg_temp.esperar_error('SEC08.N.estado',
 $$UPDATE public.pedido SET estado='CANCELADO' WHERE id=pg_temp.id('o1')$$,'42501');
SELECT pg_temp.esperar_error('SEC14.N.fecha',
 $$INSERT INTO public.pedido(usuario_id,forma_pago,fecha) VALUES (pg_temp.id('u1'),'EFECTIVO',CURRENT_DATE)$$,'42501');
SELECT pg_temp.esperar_error('SEC14.N.total',
 $$INSERT INTO public.pedido(usuario_id,forma_pago,total) VALUES (pg_temp.id('u1'),'EFECTIVO',0)$$,'42501');
SELECT pg_temp.esperar_error('SEC14.N.estado',
 $$INSERT INTO public.pedido(usuario_id,forma_pago,estado) VALUES (pg_temp.id('u1'),'EFECTIVO','PENDIENTE')$$,'42501');
SELECT pg_temp.esperar_error('SEC14.N.eliminado',
 $$INSERT INTO public.pedido(usuario_id,forma_pago,eliminado) VALUES (pg_temp.id('u1'),'EFECTIVO',false)$$,'42501');
SELECT pg_temp.esperar_error('SEC05.N.insert_detalle',
 $$INSERT INTO public.detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario)
 VALUES (pg_temp.id('o1'),pg_temp.id('p1'),1,1250.50)$$,'42501');
SELECT pg_temp.esperar_error('SEC05.N.update_detalle',
 'UPDATE public.detalle_pedido SET cantidad=1 WHERE id=-1','42501');
SELECT pg_temp.esperar_error('SEC05.N.delete_detalle','DELETE FROM public.detalle_pedido WHERE id=-1','42501');
SELECT pg_temp.esperar_error('SEC05.N.select_detalle','SELECT * FROM public.detalle_pedido','42501');
SELECT pg_temp.esperar_error('SEC03.N.SEC13.N.call',
 $$CALL public.registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),1)$$,'42501');
SELECT pg_temp.esperar_error('SEC13.N.total',
 $$SELECT public.calcular_total_pedido(pg_temp.id('o1'))$$,'42501');
SELECT pg_temp.esperar_error('MINIMO.N.stock','UPDATE public.producto SET stock=0 WHERE id=-1','42501');
SELECT pg_temp.esperar_error('MINIMO.N.total','UPDATE public.pedido SET total=0 WHERE id=-1','42501');
SELECT pg_temp.esperar_error('MINIMO.N.usuario','SELECT * FROM public.usuario','42501');
SELECT pg_temp.esperar_error('SEC17.N.contrasena','SELECT contrasena FROM public.usuario LIMIT 1','42501');
SELECT pg_temp.esperar_error('SEC09.N.delete','DELETE FROM public.pedido WHERE id=-1','42501');
SELECT pg_temp.esperar_error('SEC09.N.truncate','TRUNCATE public.detalle_pedido','42501');
-- SEC-03.N: errores de negocio deben atravesar la API con SQLSTATE intacto.
SELECT pg_temp.esperar_error('SEC03.N.cantidad0',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),0)$$,'22023');
SELECT pg_temp.esperar_error('SEC03.N.cantidad_null',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),NULL)$$,'22023');
SELECT pg_temp.esperar_error('SEC03.N.pedido_ausente',
 $$SELECT public.api_registrar_detalle_pedido(-1,pg_temp.id('p1'),1)$$,'23503');
SELECT pg_temp.esperar_error('SEC03.N.producto_ausente',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),-1,1)$$,'23503');
SELECT pg_temp.esperar_error('SEC03.N.pedido_baja',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o3'),pg_temp.id('p1'),1)$$,'23514');
SELECT pg_temp.esperar_error('SEC03.N.usuario_baja',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o2'),pg_temp.id('p1'),1)$$,'23514');
SELECT pg_temp.esperar_error('SEC03.N.no_disponible',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p3'),1)$$,'23514');
SELECT pg_temp.esperar_error('SEC03.N.producto_baja',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p4'),1)$$,'23514');
SELECT pg_temp.esperar_error('SEC03.N.stock',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p2'),3)$$,'23514');
RESET ROLE;
SELECT pg_temp.verificar('SEC03.N.sin_efectos', $q$
 SELECT ((SELECT count(*) FROM public.detalle_pedido WHERE pedido_id IN (pg_temp.id('o1'),pg_temp.id('o2'),pg_temp.id('o3')))=0
 AND (SELECT stock FROM public.producto WHERE id=pg_temp.id('p1'))=10
 AND (SELECT stock FROM public.producto WHERE id=pg_temp.id('p2'))=2
 AND (SELECT total FROM public.pedido WHERE id=pg_temp.id('o1'))=0)::text$q$,'true');
SELECT pg_temp.verificar('SEC08.P.defaults', $q$
 SELECT (count(*)=1 AND bool_and(fecha=CURRENT_DATE AND estado='PENDIENTE' AND total=0 AND NOT eliminado))::text
 FROM public.pedido WHERE usuario_id=pg_temp.id('u1') AND forma_pago='TARJETA'$q$,'true');
SET ROLE app_web;
SELECT pg_temp.esperar_ok('SEC05.P.SEC13.P.api',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),3)$$);
SELECT pg_temp.esperar_error('SEC03.N.duplicado',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p1'),1)$$,'23505');
RESET ROLE;
SELECT pg_temp.verificar('SEC05.P.estado', $q$
 SELECT ((SELECT count(*) FROM public.detalle_pedido WHERE pedido_id=pg_temp.id('o1'))=1
 AND EXISTS (SELECT FROM public.detalle_pedido WHERE pedido_id=pg_temp.id('o1')
 AND producto_id=pg_temp.id('p1') AND cantidad=3 AND precio_unitario=1250.50 AND subtotal=3751.50)
 AND (SELECT stock FROM public.producto WHERE id=pg_temp.id('p1'))=7
 AND (SELECT total FROM public.pedido WHERE id=pg_temp.id('o1'))=3751.50)::text$q$,'true');
-- SEC-17.N: D9 no aplicada; observar TEMP efectivo, sin exigir REVOKE alguno.
SELECT has_database_privilege('app_web',current_database(),'TEMP') AS u5_tiene_temp
\gset
\if :u5_tiene_temp
 SET ROLE app_web;
 SELECT pg_temp.esperar_ok('SEC17.N.temp_explicita',
 $$CREATE TEMP TABLE producto(id bigint,nombre varchar(120),precio numeric(12,2),stock integer,
 disponible boolean,categoria_id bigint,eliminado boolean)$$);
 SELECT pg_temp.esperar_ok('SEC17.N.temp_fila',
 $$INSERT INTO pg_temp.producto VALUES (pg_temp.id('p2'),'U5 temporal',300,999,true,pg_temp.id('c1'),false)$$);
 SELECT pg_temp.esperar_ok('SEC17.N.api_no_suplanta',
 $$SELECT public.api_registrar_detalle_pedido(pg_temp.id('o1'),pg_temp.id('p2'),1)$$);
 RESET ROLE;
 SELECT pg_temp.verificar('SEC17.N.public_stock',
 $$SELECT stock::text FROM public.producto WHERE id=pg_temp.id('p2')$$,'1');
 SELECT pg_temp.verificar('SEC17.N.temp_intacta',
 $$SELECT stock::text FROM pg_temp.producto WHERE id=pg_temp.id('p2')$$,'999');
\else
 SET ROLE app_web;
 SELECT pg_temp.esperar_error('SEC17.N.temp_denegada',
 'CREATE TEMP TABLE producto(id bigint)','42501');
 RESET ROLE;
\endif
SET ROLE admin_datos;
SELECT pg_temp.esperar_ok('SEC06.P.lectura','SELECT count(*) FROM public.categoria');
SELECT pg_temp.esperar_ok('SEC06.P.create_reportes','CREATE TABLE reportes.tst_u5_tmp(x int)');
SELECT pg_temp.esperar_error('SEC06.N.create_role','CREATE ROLE tst_u5_x','42501');
SELECT pg_temp.esperar_error('SEC06.N.insert',
 $$INSERT INTO public.categoria(nombre) VALUES ('__U5_NO_DEBE_INSERTARSE__')$$,'42501');
SELECT pg_temp.esperar_error('SEC06.N.contrasena','SELECT contrasena FROM public.usuario','42501');
SELECT pg_temp.esperar_error('SEC06.N.public','CREATE TABLE public.tst_u5_tmp(x int)','42501');
SELECT pg_temp.esperar_ok('SEC11.P.adp_tabla','CREATE TABLE reportes.tst_u5_adp(x int)');
SELECT pg_temp.esperar_ok('SEC12.P.adp_funcion',
 $$CREATE FUNCTION reportes.tst_u5_fn() RETURNS int LANGUAGE sql AS 'SELECT 1'$$);
RESET ROLE;
SELECT pg_temp.verificar('SEC11.P.select_automatico',
 $$SELECT has_table_privilege('rol_reportes','reportes.tst_u5_adp','SELECT')::text$$,'true');
SELECT pg_temp.verificar('SEC12.P.sin_execute', $q$
 SELECT (NOT has_function_privilege('tst_u5_sin_privilegios','reportes.tst_u5_fn()','EXECUTE')
 AND NOT EXISTS (SELECT FROM pg_proc p
 CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.oid='reportes.tst_u5_fn()'::regprocedure AND a.grantee=0))::text$q$,'true');
-- Controles creados por el superusuario SIN ADP propios (verificar precondición).
SELECT pg_temp.verificar('SEC12.N.control_precondicion', $q$
 SELECT count(*)::text FROM pg_default_acl WHERE defaclrole=current_user::regrole$q$,'0');
CREATE TABLE public.tst_u5_adp(x int);
CREATE FUNCTION reportes.tst_u5_control() RETURNS int LANGUAGE sql AS 'SELECT 1';
SELECT pg_temp.verificar('SEC11.N.public_sin_automaticos', $q$
 SELECT count(*)::text FROM (VALUES ('rol_app_lectura'),('rol_app_escritura'),('rol_soporte'),
 ('rol_reportes'),('rol_app_autenticacion')) r(rol)
 CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) p(priv)
 WHERE has_table_privilege(r.rol,'public.tst_u5_adp',p.priv)$q$,'0');
SELECT pg_temp.verificar('SEC12.N.control_execute',
 $$SELECT has_function_privilege('tst_u5_sin_privilegios','reportes.tst_u5_control()','EXECUTE')::text$$,'true');
SET ROLE rol_reportes;
SELECT pg_temp.esperar_ok('SEC04.P.grupo',
 format('SELECT * FROM %s LIMIT 1',current_setting('u5.mv')));
RESET ROLE;
SET ROLE tst_u5_reportes;
SELECT pg_temp.esperar_ok('SEC04.P.efimero',
 format('SELECT * FROM %s LIMIT 1',current_setting('u5.mv')));
SELECT pg_temp.esperar_error('SEC04.N.usuario','SELECT * FROM public.usuario','42501');
SELECT pg_temp.esperar_error('SEC04.N.pedido','SELECT * FROM public.pedido','42501');
SELECT pg_temp.esperar_error('SEC04.N.escritura','INSERT INTO reportes.tst_u5_adp VALUES (1)','42501');
RESET ROLE;
SET ROLE tst_u5_soporte;
SELECT pg_temp.esperar_ok('REG04.soporte_usuarios','SELECT * FROM public.v_usuarios_publico LIMIT 1');
SELECT pg_temp.esperar_ok('REG04.soporte_pedidos','SELECT * FROM public.v_pedidos_resumen LIMIT 1');
SELECT pg_temp.esperar_error('SEC10.N.efimero','GRANT admin_datos TO tst_u5_soporte','42501');
SELECT pg_temp.esperar_error('SOPORTE.N.usuario','SELECT * FROM public.usuario','42501');
RESET ROLE;
SET ROLE rol_soporte;
SELECT pg_temp.esperar_error('SEC10.N.grupo','GRANT admin_datos TO tst_u5_soporte','42501');
RESET ROLE;
SET ROLE app_web;
SELECT pg_temp.esperar_error('SEC10.N.app_admin','GRANT admin_datos TO tst_u5_soporte','42501');
SELECT pg_temp.esperar_error('SEC10.N.app_escritura','GRANT rol_app_escritura TO tst_u5_soporte','42501');
RESET ROLE;
SET ROLE admin_datos;
SELECT pg_temp.esperar_error('SEC10.N.admin','GRANT admin_datos TO tst_u5_soporte','42501');
RESET ROLE;
-- SEC19.N: recorre las diez firmas, tablas y cuatro vistas; no basta has_*.
SET ROLE tst_u5_sin_privilegios;
DO $casos$
DECLARE r record;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('api','SELECT public.api_registrar_detalle_pedido(-1,-1,1)'),
 ('call','CALL public.registrar_detalle_pedido(-1,-1,1)'),
 ('total','SELECT public.calcular_total_pedido(-1)'),
 ('subtotal','SELECT public.fn_set_subtotal()'),
 ('vigente','SELECT public.fn_validar_detalle_vigente()'),
 ('insert','SELECT public.fn_recalcular_total_insert()'),
 ('update','SELECT public.fn_recalcular_total_update()'),
 ('delete','SELECT public.fn_recalcular_total_delete()'),
 ('auth','SELECT * FROM public.fn_autenticar(NULL,NULL)'),
 ('reset','SELECT public.fn_resetear_password(-1,NULL)'),
 ('categoria','SELECT * FROM public.categoria'), ('usuario','SELECT * FROM public.usuario'),
 ('producto','SELECT * FROM public.producto'), ('pedido','SELECT * FROM public.pedido'),
 ('detalle','SELECT * FROM public.detalle_pedido'),
 ('catalogo','SELECT * FROM public.v_productos_vigentes'),
 ('usuarios_publicos','SELECT * FROM public.v_usuarios_publico'),
 ('resumen','SELECT * FROM public.v_pedidos_resumen'),
 ('pedido_detalle','SELECT * FROM public.v_pedido_detalle')) v(caso,sentencia)
 LOOP
  PERFORM pg_temp.esperar_error('SEC19.N.'||r.caso,r.sentencia,'42501');
 END LOOP;
 PERFORM pg_temp.esperar_error('SEC19.N.materializada',
  format('SELECT * FROM %s',current_setting('u5.mv')),'42501');
END $casos$;
RESET ROLE;
-- REG04: las cuatro vistas siguen accesibles al superusuario; v_pedido_detalle
-- no tiene beneficiarios U5 según matriz (no inventar GRANT a soporte).
SELECT pg_temp.esperar_ok('REG04.super_catalogo','SELECT * FROM public.v_productos_vigentes LIMIT 1');
SELECT pg_temp.esperar_ok('REG04.super_usuarios','SELECT * FROM public.v_usuarios_publico LIMIT 1');
SELECT pg_temp.esperar_ok('REG04.super_resumen','SELECT * FROM public.v_pedidos_resumen LIMIT 1');
SELECT pg_temp.esperar_ok('REG04.super_detalle','SELECT * FROM public.v_pedido_detalle LIMIT 1');
\ir 15_limpieza.sql
ROLLBACK;
SELECT pg_temp.sin_fixtures('PERMISOS.R.sin_fixtures');
SELECT pg_temp.verificar('PERMISOS.R.sin_roles',
 $$SELECT count(*)::text FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'$$,'0');
SELECT pg_temp.verificar('PERMISOS.R.sin_objetos', $q$
 SELECT (to_regclass('public.tst_u5_adp') IS NULL AND to_regclass('reportes.tst_u5_adp') IS NULL
 AND to_regclass('reportes.tst_u5_tmp') IS NULL AND to_regclass('pg_temp.producto') IS NULL
 AND to_regprocedure('reportes.tst_u5_fn()') IS NULL
 AND to_regprocedure('reportes.tst_u5_control()') IS NULL)::text$q$,'true');
