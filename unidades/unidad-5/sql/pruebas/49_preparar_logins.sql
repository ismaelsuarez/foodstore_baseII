-- OPCIONAL/MANUAL, autorización separada: identidades visibles por otras sesiones.
-- Ejecutar en la conexión de control después de 40; conservarla hasta 52.
-- No crea contraseñas, ni modifica pg_hba, CONNECT o TEMP (D9 sigue pendiente).
\ir 00_guardas.sql
BEGIN;
\ir 14_identidades.sql
ALTER ROLE tst_u5_soporte LOGIN;
ALTER ROLE tst_u5_reportes LOGIN;
CREATE TEMP TABLE u5_logins_creados AS
SELECT oid,rolname FROM pg_roles WHERE rolname IN
 ('tst_u5_soporte','tst_u5_reportes','tst_u5_sin_privilegios');
COMMIT;
-- Si se requiere contraseña de login: asignarla fuera del repositorio mediante
-- \password, tras verificar password_encryption=scram-sha-256. No capturar esa salida.
-- No usar ALTER ROLE ... PASSWORD ni variables con contraseñas en línea de comandos.
