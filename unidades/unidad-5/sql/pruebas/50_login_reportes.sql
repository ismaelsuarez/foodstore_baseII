-- MANUAL: conexión REAL como tst_u5_reportes, no SET ROLE desde superusuario.
\ir 00_destino.sql
BEGIN;
DO $g$
DECLARE v_objeto text; v_estado text := 'sin_error';
BEGIN
 IF session_user<>'tst_u5_reportes' OR current_user<>session_user THEN
  RAISE EXCEPTION 'SEC04: se requiere login real de la identidad efímera de reportes';
 END IF;
 SELECT format('%I.%I',n.nspname,c.relname) INTO STRICT v_objeto
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relname='mv_facturacion_categoria_mes' AND c.relkind='m'
 AND n.nspname IN ('public','reportes');
 EXECUTE 'SELECT * FROM '||v_objeto||' LIMIT 1';
 RAISE NOTICE 'RESULT|SEC04.P.login_real|%|esperado=sin_error observado=sin_error|','PASS';
 BEGIN
  PERFORM * FROM public.usuario;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 IF v_estado<>'42501' THEN RAISE EXCEPTION 'SEC04.N.login_usuario: esperado 42501 observado %',v_estado; END IF;
 RAISE NOTICE 'RESULT|SEC04.N.login_usuario|%|esperado=42501 observado=42501|','PASS';
 v_estado:='sin_error';
 BEGIN
  PERFORM * FROM public.pedido;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE;
 END;
 IF v_estado<>'42501' THEN RAISE EXCEPTION 'SEC04.N.login_pedido: esperado 42501 observado %',v_estado; END IF;
 RAISE NOTICE 'RESULT|SEC04.N.login_pedido|%|esperado=42501 observado=42501|','PASS';
END $g$;
ROLLBACK;
