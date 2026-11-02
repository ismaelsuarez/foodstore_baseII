-- U5 Parte A: NO EJECUTADO. Setup exclusivamente por superusuario.
-- No sustituye autorización explícita de base e instancia aisladas.
\ir 00_destino.sql
DO $guarda$
BEGIN
 IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user)
 OR current_user<>session_user THEN
  RAISE EXCEPTION 'GUARDA: setup requiere sesión de superusuario sin SET ROLE activo';
 END IF;
END $guarda$;
SET search_path = public, pg_temp;
