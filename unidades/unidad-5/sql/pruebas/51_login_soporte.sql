-- MANUAL: conexión REAL como tst_u5_soporte; no prueba contraseñas de negocio.
\ir 00_destino.sql
\ir 00_guardas_credenciales.sql
BEGIN;
DO $g$
DECLARE v_estado text := 'sin_error';
BEGIN
 IF session_user<>'tst_u5_soporte' OR current_user<>session_user THEN
  RAISE EXCEPTION 'D12: se requiere login real de la identidad efímera de soporte';
 END IF;
 PERFORM * FROM public.v_usuarios_publico LIMIT 1;
 PERFORM * FROM public.v_pedidos_resumen LIMIT 1;
 RAISE NOTICE 'RESULT|D12.soporte.login_vistas|%|esperado=sin_error observado=sin_error|','PASS';
 BEGIN
  -- NULL no es una contraseña: prueba permiso EXECUTE y validación defensiva.
  PERFORM public.fn_resetear_password(-1,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 IF v_estado<>'22023' THEN RAISE EXCEPTION 'D12.soporte.execute: esperado 22023 observado %',v_estado; END IF;
 RAISE NOTICE 'RESULT|D12.soporte.login_execute|%|esperado=22023 observado=22023|','PASS';
 v_estado:='sin_error';
 BEGIN
  UPDATE public.usuario SET contrasena=contrasena WHERE id=-1;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 IF v_estado<>'42501' THEN RAISE EXCEPTION 'D12.soporte.update: esperado 42501 observado %',v_estado; END IF;
 RAISE NOTICE 'RESULT|D12.soporte.login_update|%|esperado=42501 observado=42501|','PASS';
END $g$;
ROLLBACK;
