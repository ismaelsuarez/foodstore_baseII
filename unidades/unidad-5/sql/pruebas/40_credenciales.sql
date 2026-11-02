-- SEC-16.P, SEC-18.P/N/R, REQ-A10/A11. Preparado; NO ejecutado.
-- Nunca usar -a/-e, ECHO all, \set sin argumentos ni imprimir variables sintéticas.
\ir 00_guardas.sql
\ir 00_helpers.sql
-- Fallar ANTES de importar o utilizar valores de credenciales.
\ir 00_guardas_credenciales.sql
SELECT name,setting FROM pg_settings WHERE name IN
 ('log_parameter_max_length','log_parameter_max_length_on_error','log_file_mode',
  'password_encryption','log_statement','log_min_duration_statement') ORDER BY name;
-- No se construye SQL dinámico con contraseñas. Los auxiliares son INVOKER.
CREATE FUNCTION pg_temp.probar_auth(p_caso text,p_mail text,p_valor text,p_filas bigint,p_estado text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_filas bigint; v_identidad boolean; v_estado text := 'sin_error';
BEGIN
 BEGIN
  SELECT count(*),bool_and(a.usuario_id=pg_temp.id('u1') AND a.rol='USUARIO')
  INTO v_filas,v_identidad FROM public.fn_autenticar(p_mail,p_valor) a;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 PERFORM pg_temp.verificar(p_caso||'.estado',format('SELECT %L::text',v_estado),p_estado);
 IF v_estado='sin_error' THEN
  PERFORM pg_temp.verificar(p_caso||'.filas',format('SELECT %L::text',v_filas::text),p_filas::text);
  IF p_filas=1 THEN
   PERFORM pg_temp.verificar(p_caso||'.identidad',format('SELECT %L::text',v_identidad::text),'true');
  END IF;
 END IF;
END $f$;
CREATE FUNCTION pg_temp.probar_reset(p_caso text,p_id bigint,p_valor text,p_estado text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_estado text := 'sin_error';
BEGIN
 BEGIN
  PERFORM public.fn_resetear_password(p_id,p_valor);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 PERFORM pg_temp.verificar(p_caso,format('SELECT %L::text',v_estado),p_estado);
END $f$;
-- SEC-16.N: generación FUERA del SQL, en el shell (README M02).
-- Solo entorno del cliente; no archivos, argumentos -v ni texto SQL con valores.
\getenv u5_pwd U5_SYN_PWD
\getenv u5_nueva U5_SYN_NUEVA
SELECT length($1::text)>0 AND length($2::text)>0 AND $1::text<>$2::text AS u5_sinteticos_validos
\bind :'u5_pwd' :'u5_nueva'
\gset
\if :u5_sinteticos_validos
\else
DO $g$ BEGIN
 RAISE EXCEPTION 'SEC16: se requieren dos valores sintéticos no vacíos y distintos en el entorno';
END $g$;
\endif
BEGIN;
\ir 13_fixtures.sql
\ir 14_identidades.sql
UPDATE public.usuario SET contrasena=public.crypt($1,public.gen_salt('bf')) WHERE id=pg_temp.id('u1')
\bind :'u5_pwd'
\g
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.P.valida','u5.verificacion.uno@ejemplo.test',$1,1,'sin_error')
\bind :'u5_pwd'
\g
SELECT pg_temp.probar_auth('AUTH.N.incorrecta','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_nueva'
\g
SELECT pg_temp.probar_auth('AUTH.N.ausente','u5.verificacion.ausente@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
SELECT pg_temp.probar_auth('AUTH.N.baja','u5.verificacion.baja@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
SELECT pg_temp.probar_auth('AUTH.N.mail_null',NULL,$1,0,'28P01')
\bind :'u5_pwd'
\g
SELECT pg_temp.probar_auth('AUTH.N.mail_vacio','',$1,0,'28P01')
\bind :'u5_pwd'
\g
SELECT pg_temp.probar_auth('AUTH.N.valor_null','u5.verificacion.uno@ejemplo.test',NULL,0,'28P01');
SELECT pg_temp.probar_auth('AUTH.N.valor_vacio','u5.verificacion.uno@ejemplo.test','',0,'28P01');
SELECT pg_temp.probar_auth('AUTH.N.valor_blanco','u5.verificacion.uno@ejemplo.test',' ',0,'28P01');
RESET ROLE;
-- D16: se muta un hash generado, nunca se incluye un hash literal en el archivo.
UPDATE public.usuario SET contrasena=overlay(contrasena placing 'b' from 3 for 1) WHERE id=pg_temp.id('u1');
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.N.prefijo_2b','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
RESET ROLE;
UPDATE public.usuario SET contrasena=overlay(contrasena placing 'y' from 3 for 1) WHERE id=pg_temp.id('u1');
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.N.prefijo_2y','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
RESET ROLE;
UPDATE public.usuario SET contrasena='SEED_NO_AUTH' WHERE id=pg_temp.id('u1');
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.N.seed','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
RESET ROLE;
UPDATE public.usuario SET contrasena='hash_no_valido' WHERE id=pg_temp.id('u1');
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.N.marcador','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
RESET ROLE;
UPDATE public.usuario SET contrasena=left(public.crypt($1,public.gen_salt('bf')),59) WHERE id=pg_temp.id('u1')
\bind :'u5_pwd'
\g
SET ROLE app_web;
SELECT pg_temp.probar_auth('AUTH.N.longitud_hash','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
RESET ROLE;
UPDATE public.usuario SET contrasena=public.crypt($1,public.gen_salt('bf')) WHERE id=pg_temp.id('u1')
\bind :'u5_pwd'
\g
SET ROLE tst_u5_soporte;
SELECT pg_temp.probar_reset('SEC18.N.admin',pg_temp.id('ua'),$1,'42501')
\bind :'u5_nueva'
\g
SELECT pg_temp.probar_reset('SEC18.N.eliminado',pg_temp.id('u2'),$1,'23503')
\bind :'u5_nueva'
\g
SELECT pg_temp.probar_reset('SEC18.N.ausente',-1,$1,'23503')
\bind :'u5_nueva'
\g
SELECT pg_temp.probar_reset('SEC18.N.null',pg_temp.id('u1'),NULL,'22023');
SELECT pg_temp.probar_reset('SEC18.N.vacia',pg_temp.id('u1'),'','22023');
SELECT pg_temp.probar_reset('SEC18.N.blanco',pg_temp.id('u1'),' ','22023');
SELECT pg_temp.esperar_error('SEC18.N.update_directo',
 $$UPDATE public.usuario SET contrasena=contrasena WHERE id=pg_temp.id('u1')$$,'42501');
SELECT pg_temp.esperar_error('SEC18.N.total',
 $$SELECT public.calcular_total_pedido(pg_temp.id('o1'))$$,'42501');
SELECT pg_temp.probar_reset('SEC18.P.reset',pg_temp.id('u1'),$1,'sin_error')
\bind :'u5_nueva'
\g
RESET ROLE;
SELECT pg_temp.verificar('SEC18.P.formato_bcrypt', $q$
 SELECT (contrasena ~ ('^'||chr(92)||chr(36)||'2a'||chr(92)||chr(36)||
 '(0[4-9]|[12][0-9]|3[01])'||chr(92)||chr(36)||'[./A-Za-z0-9]{53}$'))::text
 FROM public.usuario WHERE id=pg_temp.id('u1')$q$,'true');
-- Delimitadores escapados; se verifica el formato sin imprimir la columna ni su hash.
SELECT pg_temp.verificar('SEC18.N.admin_sin_cambios',
 $$SELECT (contrasena='SEED_NO_AUTH')::text FROM public.usuario WHERE id=pg_temp.id('ua')$$,'true');
SET ROLE app_web;
SELECT pg_temp.probar_auth('SEC18.P.autentica_nueva','u5.verificacion.uno@ejemplo.test',$1,1,'sin_error')
\bind :'u5_nueva'
\g
SELECT pg_temp.probar_auth('SEC18.P.rechaza_anterior','u5.verificacion.uno@ejemplo.test',$1,0,'sin_error')
\bind :'u5_pwd'
\g
-- La función devuelve solo identidad de negocio, no contraseña ni hash.
RESET ROLE;
\ir 15_limpieza.sql
ROLLBACK;
\unset u5_pwd
\unset u5_nueva
\unset u5_sinteticos_validos
-- El shell conserva los valores solo hasta la inspección exacta del log (M02);
-- luego debe ejecutar unset U5_SYN_PWD U5_SYN_NUEVA, también ante un fallo.
SELECT pg_temp.sin_fixtures('CREDENCIALES.R.sin_fixtures');
SELECT pg_temp.verificar('CREDENCIALES.R.sin_roles',
 $$SELECT count(*)::text FROM pg_roles WHERE rolname LIKE 'tst\_u5\_%'$$,'0');
