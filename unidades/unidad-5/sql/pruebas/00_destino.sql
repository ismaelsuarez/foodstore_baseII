-- Guarda de destino compartida por setup y conexiones reales; no hace setup.
\set ON_ERROR_STOP on
\set ECHO none
\set ECHO_HIDDEN off
\set VERBOSITY terse
-- \quit no sirve como guarda: no acepta código de salida y, en un archivo incluido con \ir,
-- solo termina ese archivo (psql 17, \q). Se falla con un error SQL bajo ON_ERROR_STOP.
\if :{?u5_base_objetivo}
\else
DO $guarda$ BEGIN
 RAISE EXCEPTION 'GUARDA: falta la variable obligatoria u5_base_objetivo (-v u5_base_objetivo=...)';
END $guarda$;
\endif
SELECT current_database() = :'u5_base_objetivo' AND :'u5_base_objetivo' <> '' AS u5_base_correcta
\gset
\if :u5_base_correcta
\else
DO $guarda$ BEGIN
 RAISE EXCEPTION 'GUARDA: base distinta de u5_base_objetivo o destino vacío';
END $guarda$;
\endif
DO $guarda$
BEGIN
 IF current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
  RAISE EXCEPTION 'GUARDA: se requiere PostgreSQL 17.x';
 END IF;
 IF current_setting('session_replication_role') <> 'origin' THEN
  RAISE EXCEPTION 'GUARDA: se requiere origin';
 END IF;
END $guarda$;
SELECT current_database() AS base,current_setting('server_version') AS version,
       session_user AS conexion,current_user AS ejecutor;
