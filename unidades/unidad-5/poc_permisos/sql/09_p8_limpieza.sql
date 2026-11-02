-- POC U5 — P8: retiro de los roles de la POC y verificación sin residuos.
-- La destrucción de la instancia se hace después, desde run_poc.sh.
\ir 00_guardas.sql

BEGIN;
DROP OWNED BY app_web, rol_app_escritura, rol_propietario_ventas, tst_u5_sin_privilegios;
DROP ROLE app_web, rol_app_escritura, rol_propietario_ventas, tst_u5_sin_privilegios;
COMMIT;

\ir 00_guarda_sin_roles.sql
\ir 00_helpers.sql

SELECT pg_temp.verificar('P8.roles',
    $q$SELECT count(*)::text FROM pg_roles
       WHERE rolname IN ('app_web', 'rol_app_escritura', 'rol_propietario_ventas',
                         'tst_u5_sin_privilegios')$q$, '0');
SELECT pg_temp.verificar('P8.api',
    $q$SELECT coalesce(to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)')::text, 'NULL')$q$,
    'NULL');
SELECT pg_temp.verificar('P8.membresias',
    $q$SELECT count(*)::text FROM pg_auth_members$q$, '0');
