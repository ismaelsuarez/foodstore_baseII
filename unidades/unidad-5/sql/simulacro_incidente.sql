-- Unidad 5, Parte C — simulacro de incidente de acceso indebido.
-- Solo para un laboratorio descartable. Lo ejecuta simulacro_incidente.sh, que prepara la base,
-- crea el rol temporal tst_u5_lector, activa log_statement = 'all' durante la secuencia y limpia
-- al final. Se conecta como app_web por TCP (127.0.0.1).
--
-- Autenticación funcional: fn_autenticar valida mail y contraseña de la tabla usuario (bcrypt).
-- No es la autenticación de conexión a PostgreSQL, que en este laboratorio la resuelve pg_hba.conf.
--
-- Requiere la variable psql u5_base_objetivo y estas variables de entorno, generadas por el shell
-- con valores sintéticos: U5C_MAIL, U5C_PWD_OK, U5C_PWD_MAL_1, U5C_PWD_MAL_2, U5C_PWD_MAL_3.
-- Las contraseñas se envían como parámetros enlazados (\bind): el texto de la sentencia solo
-- contiene $1 y $2, y log_parameter_max_length = 0 evita que el log registre sus valores.
\set ON_ERROR_STOP on

\getenv u5c_mail U5C_MAIL
\getenv u5c_ok U5C_PWD_OK
\getenv u5c_mal_1 U5C_PWD_MAL_1
\getenv u5c_mal_2 U5C_PWD_MAL_2
\getenv u5c_mal_3 U5C_PWD_MAL_3

SELECT current_database() = :'u5_base_objetivo' AND current_user = 'app_web' AS u5c_destino_ok
\gset
\if :u5c_destino_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'Destino o usuario inesperado'; END $$;
\endif

-- 1. Tres intentos fallidos de inicio de sesión funcional: misma cuenta, contraseña incorrecta.
SELECT * FROM public.fn_autenticar($1, $2) \bind :'u5c_mail' :'u5c_mal_1' \g
SELECT * FROM public.fn_autenticar($1, $2) \bind :'u5c_mail' :'u5c_mal_2' \g
SELECT * FROM public.fn_autenticar($1, $2) \bind :'u5c_mail' :'u5c_mal_3' \g

-- 2. Inicio de sesión funcional exitoso.
SELECT * FROM public.fn_autenticar($1, $2) \bind :'u5c_mail' :'u5c_ok' \g

-- 3. Lectura masiva de usuario. app_web no tiene SELECT sobre usuario (Parte A): la lectura la hace
-- el rol temporal tst_u5_lector, que recibió ese permiso a propósito solo para este simulacro.
-- Las filas no se muestran; solo se informa cuántas se leyeron.
\connect :u5_base_objetivo tst_u5_lector 127.0.0.1
\o /dev/null
SELECT * FROM public.usuario;
\o
\echo filas_leidas: :ROW_COUNT

-- 4. Intento de escalamiento: el rol de bajo privilegio se otorga a sí mismo admin_datos.
-- Debe fallar. Si no falla, la Parte A tiene un defecto.
\set ON_ERROR_STOP off
GRANT admin_datos TO tst_u5_lector;
\echo sqlstate_escalamiento: :LAST_ERROR_SQLSTATE
\set ON_ERROR_STOP on
