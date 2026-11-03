#!/usr/bin/env bash
# Unidad 5, Parte C — orquesta el simulacro de incidente en un contenedor PostgreSQL 17 descartable.
# Uso, desde la raíz del repositorio: bash unidades/unidad-5/sql/simulacro_incidente.sh
# Crea el contenedor foodstore_u5_simulacro_c (sin red ni puertos), instala Food Store y la Parte A,
# ejecuta simulacro_incidente.sql, escribe el log anonimizado en
# unidades/unidad-5/docs/log_simulacro_anonimizado.txt y destruye el contenedor.
# Todas las credenciales son sintéticas y existen solo en variables de entorno de este proceso.
# El log crudo nunca se escribe fuera del contenedor.
# log_statement no se fija al arrancar: una opción de línea de comandos tiene prioridad sobre
# ALTER SYSTEM, y así falló el primer intento (docs/log_simulacro_intento1_sin_select.txt).
set -euo pipefail

C=foodstore_u5_simulacro_c
DB=foodstore_simulacro_c
OUT=unidades/unidad-5/docs/log_simulacro_anonimizado.txt
LOG=/var/lib/postgresql/data/log/postgresql.log

[ -f schema.sql ] && [ -d unidades/unidad-5/sql ] || { echo "Ejecutar desde la raíz del repositorio" >&2; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx "$C" && { echo "BLOCKED: $C ya existe" >&2; exit 2; }
[ -e "$OUT" ] && { echo "BLOCKED: $OUT ya existe; no se sobrescribe" >&2; exit 2; }

PS_ANTES="$(docker ps -a --format '{{.Names}}' | sort)"
U5C_SUPER="$(openssl rand -hex 16)"
U5C_MAIL="cliente.simulacro@ejemplo.test"
U5C_PWD_OK="sim-$(openssl rand -hex 12)"
U5C_PWD_MAL_1="sim-$(openssl rand -hex 12)"
U5C_PWD_MAL_2="sim-$(openssl rand -hex 12)"
U5C_PWD_MAL_3="sim-$(openssl rand -hex 12)"
export U5C_SUPER U5C_MAIL U5C_PWD_OK U5C_PWD_MAL_1 U5C_PWD_MAL_2 U5C_PWD_MAL_3
trap 'unset U5C_SUPER U5C_MAIL U5C_PWD_OK U5C_PWD_MAL_1 U5C_PWD_MAL_2 U5C_PWD_MAL_3' EXIT

echo "== 1. Contenedor"
docker run -d --name "$C" --network none \
  -e POSTGRES_PASSWORD="$U5C_SUPER" -e POSTGRES_DB="$DB" -v "$PWD:/repo:ro" postgres:17 \
  -c logging_collector=on -c log_filename=postgresql.log -c log_file_mode=0600 \
  -c log_connections=on -c log_disconnections=on \
  -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 \
  -c "log_line_prefix=%m [%p] %q%u@%d %r " >/dev/null
until docker logs "$C" 2>&1 | grep -q 'PostgreSQL init process complete'; do sleep 1; done
until docker exec "$C" pg_isready -q -d "$DB"; do sleep 1; done
docker inspect "$C" -f 'red={{.HostConfig.NetworkMode}} puertos={{json .NetworkSettings.Ports}} imagen={{.Image}}'

su_psql() { docker exec -i "$C" psql -X -q -v ON_ERROR_STOP=1 -v u5_base_objetivo="$DB" -U postgres -d "$DB" "$@"; }

echo "== 2. Food Store, U3, pgcrypto y Parte A"
su_psql -1 -f /repo/schema.sql
su_psql -f /repo/datos_iniciales.sql >/dev/null
su_psql -1 -f /repo/tpi/sql/objetos_programables.sql
su_psql -f /repo/unidades/unidad-3/sql/views.sql >/dev/null
su_psql -f /repo/unidades/unidad-3/sql/materializadas.sql >/dev/null
su_psql -c 'CREATE EXTENSION pgcrypto WITH SCHEMA public' >/dev/null
su_psql -f /repo/unidades/unidad-5/sql/roles.sql >/dev/null
su_psql -f /repo/unidades/unidad-5/sql/funciones_seguridad.sql >/dev/null
su_psql -At -c "SELECT version()"

echo "== 3. Preparación del laboratorio (fuera de la secuencia registrada)"
docker exec -i -e U5C_MAIL -e U5C_PWD_OK "$C" \
  psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "$DB" <<'SQL'
\getenv u5c_mail U5C_MAIL
\getenv u5c_ok U5C_PWD_OK
INSERT INTO public.usuario (nombre, apellido, mail, contrasena)
VALUES ('Cliente', 'Simulacro', $1, public.crypt($2, public.gen_salt('bf')))
\bind :'u5c_mail' :'u5c_ok' \g
CREATE ROLE tst_u5_lector LOGIN;
GRANT SELECT ON public.usuario TO tst_u5_lector;
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
SQL
sleep 1
su_psql -At -c "SELECT name || '=' || setting || ' (' || source || ')' FROM pg_settings WHERE name IN ('log_statement','log_parameter_max_length','log_parameter_max_length_on_error','log_connections','log_disconnections','log_line_prefix') ORDER BY name"
[ "$(su_psql -At -c "SELECT current_setting('log_statement')")" = all ] || {
  echo "BLOCKED: log_statement no quedó en 'all'; no se ejecuta el simulacro" >&2; docker rm -f -v "$C" >/dev/null; exit 3; }

echo "== 4. Simulacro (como app_web por TCP 127.0.0.1)"
T0="$(docker exec "$C" date -u '+%F %T.%3N')"
set +e
docker exec -i -e U5C_MAIL -e U5C_PWD_OK -e U5C_PWD_MAL_1 -e U5C_PWD_MAL_2 -e U5C_PWD_MAL_3 "$C" \
  psql -X -v u5_base_objetivo="$DB" "host=127.0.0.1 dbname=$DB user=app_web" \
  -f /repo/unidades/unidad-5/sql/simulacro_incidente.sql
RC=$?
set -e
sleep 1
T1="$(docker exec "$C" date -u '+%F %T.%3N')"
echo "exit_simulacro=$RC inicio=$T0 fin=$T1"

echo "== 5. Fin del registro temporal y limpieza del rol temporal"
su_psql <<'SQL'
ALTER SYSTEM SET log_statement = 'mod';
SELECT pg_reload_conf();
REVOKE SELECT ON public.usuario FROM tst_u5_lector;
DROP ROLE tst_u5_lector;
SQL
su_psql -At -c "SELECT 'rol_temporal_existe=' || EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tst_u5_lector')"
su_psql -At -c "SELECT 'membresias_admin_datos=' || count(*) FROM pg_auth_members WHERE roleid = 'admin_datos'::regrole"
su_psql -At -c "SELECT 'log_statement=' || current_setting('log_statement')"

echo "== 6. Validación sobre el log crudo (dentro del contenedor)"
docker exec -i -e T0="$T0" -e T1="$T1" "$C" sh -c '
  awk -v t0="$T0" -v t1="$T1" '"'"'
    /^[0-9]{4}-[0-9]{2}-[0-9]{2} / { ts = $1 " " $2; dentro = (ts >= t0 && ts <= t1) }
    dentro { print }
  '"'"' '"$LOG"' > /tmp/fragmento.log
  echo "lineas_fragmento=$(wc -l < /tmp/fragmento.log)"
  echo "llamadas_fn_autenticar=$(grep -c "app_web@.*fn_autenticar" /tmp/fragmento.log)"
  echo "lecturas_usuario=$(grep -c "tst_u5_lector@.*SELECT \* FROM public.usuario" /tmp/fragmento.log)"
  echo "rechazos_grant=$(grep -c "ERROR:  permission denied to grant role \"admin_datos\"" /tmp/fragmento.log)"
  echo "lineas_parameters=$(grep -c "parameters:" /tmp/fragmento.log)"
  ls -l '"$LOG"' | cut -c1-10
'
docker exec -i -e U5C_PWD_OK -e U5C_PWD_MAL_1 -e U5C_PWD_MAL_2 -e U5C_PWD_MAL_3 -e U5C_SUPER "$C" sh -c '
  n=0; for v in "$U5C_PWD_OK" "$U5C_PWD_MAL_1" "$U5C_PWD_MAL_2" "$U5C_PWD_MAL_3" "$U5C_SUPER"; do
    grep -qF -- "$v" '"$LOG"' && n=$((n+1)); done
  echo "contrasenas_en_log_completo=$n"'

echo "== 7. Anonimización y escritura del fragmento"
# Mails -> usuarioN@anon.test (mismo mail, mismo reemplazo); nombres personales del seed y del
# usuario sintético -> "Usuario N". Fechas, PID, roles técnicos, sentencias y errores se conservan.
docker exec "$C" cat /tmp/fragmento.log | python3 -I -c '
import re, sys
texto = sys.stdin.read()
mails = {}
def mail(m):
    mails.setdefault(m.group(0), "usuario%d@anon.test" % (len(mails) + 1))
    return mails[m.group(0)]
texto = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+", mail, texto)
nombres = ["Ana", "Gómez", "Luis", "Paz", "Marta", "Ruiz", "Cliente", "Simulacro"]
n = 0
for i, nombre in enumerate(nombres, 1):
    texto, k = re.subn(r"\b%s\b" % re.escape(nombre), "Usuario %d" % i, texto)
    n += k
sys.stdout.write(texto)
print("mails_reemplazados=%d nombres_reemplazados=%d" % (len(mails), n), file=sys.stderr)
' > "$OUT"
echo "archivo=$OUT lineas=$(wc -l < "$OUT")"

echo "== 8. Verificación del archivo anonimizado"
echo "mails=$(grep -cE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[a-z]' "$OUT" | tr -d ' ' ; true)"
echo "nombres_seed=$(grep -cwE 'Ana|Gómez|Luis|Paz|Marta|Ruiz|Cliente|Simulacro' "$OUT"; true)"
echo "celulares=$(grep -cE '26100000[0-9]' "$OUT"; true)"
echo "hashes_bcrypt=$(grep -cF '$2a$' "$OUT"; true)"
n=0; for v in "$U5C_PWD_OK" "$U5C_PWD_MAL_1" "$U5C_PWD_MAL_2" "$U5C_PWD_MAL_3" "$U5C_SUPER"; do
  grep -qF -- "$v" "$OUT" && n=$((n+1)); done
echo "contrasenas_en_fragmento=$n"

echo "== 9. Destrucción del contenedor"
docker rm -f -v "$C" >/dev/null
docker ps -a --format '{{.Names}}' | grep -qx "$C" && { echo "el contenedor sigue existiendo" >&2; exit 1; }
[ "$(docker ps -a --format '{{.Names}}' | sort)" = "$PS_ANTES" ] && echo "contenedores_ajenos_sin_cambios=si"
exit "$RC"
