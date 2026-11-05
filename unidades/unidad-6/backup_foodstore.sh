#!/usr/bin/env bash
# Unidad 6 — respaldo lógico de Food Store con pg_dump en formato custom (-Fc)
# y archivo .baseline asociado con conteos, controles, marcas de tiempo y SHA-256.
#
# Uso:
#   bash unidades/unidad-6/backup_foodstore.sh \
#     -c CONTENEDOR -d BASE -U USUARIO -o DIR_RESPALDOS -l DIR_LOGS
#
#   -c  contenedor Docker existente y en ejecución, elegido por el operador.
#       Las herramientas psql, pg_dump y pg_restore se usan desde dentro de él.
#   -d  base a respaldar. No hay valor por defecto: el nombre está pendiente (CD-1).
#   -U  rol de conexión. No hay valor por defecto.
#   -o  directorio de respaldos y líneas base en el host.
#   -l  directorio de logs en el host; debe ser distinto del de respaldos.
#
# Códigos de salida: 0 respaldo verificado y línea base generada; 1 fallo de captura,
# validación o respaldo; 2 error de uso o de entorno detectado antes de ejecutar pg_dump.
#
# El laboratorio requiere una ventana sin escrituras durante la captura de la línea
# base y pg_dump. El script no garantiza ni impone esa ventana: la línea base y
# pg_dump usan instantáneas distintas.
# Esta versión (con línea base) todavía no fue probada funcionalmente; la prueba de
# infraestructura registrada en docs/laboratorio.md corresponde a la versión anterior.
#
# Alcance y límites:
# - No crea, inicia ni detiene contenedores.
# - No contiene contraseñas ni configura autenticación. pg_dump se ejecuta con
#   --no-password: si el entorno exige una contraseña no disponible, falla en lugar
#   de pedirla. La autenticación queda a cargo de la preparación del laboratorio.
# - No borra respaldos anteriores ni sobrescribe un archivo existente.
# - pg_restore --list solo comprueba que el archivo es legible; no reemplaza una
#   restauración de prueba.
set -euo pipefail

readonly EXIT_FAIL=1
readonly EXIT_USAGE=2

usage() {
  cat >&2 <<'EOF'
Uso: backup_foodstore.sh -c CONTENEDOR -d BASE -U USUARIO -o DIR_RESPALDOS -l DIR_LOGS
  -c  contenedor Docker existente y en ejecución
  -d  base a respaldar (sin valor por defecto)
  -U  rol de conexión (sin valor por defecto)
  -o  directorio de respaldos y líneas base (.baseline)
  -l  directorio de logs, distinto del de respaldos
EOF
  exit "$EXIT_USAGE"
}

die_usage() {
  echo "ERROR: $*" >&2
  exit "$EXIT_USAGE"
}

# --- 1. Parámetros obligatorios -------------------------------------------------
container="" db="" db_user="" backup_dir="" log_dir=""
while getopts ":c:d:U:o:l:h" opt; do
  case "$opt" in
    c) container="$OPTARG" ;;
    d) db="$OPTARG" ;;
    U) db_user="$OPTARG" ;;
    o) backup_dir="$OPTARG" ;;
    l) log_dir="$OPTARG" ;;
    h) usage ;;
    :) die_usage "la opción -$OPTARG requiere un valor" ;;
    *) die_usage "opción desconocida -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || die_usage "argumentos inesperados: $*"

[[ -n "$container" && -n "$db" && -n "$db_user" && -n "$backup_dir" && -n "$log_dir" ]] \
  || { echo "ERROR: faltan parámetros obligatorios." >&2; usage; }

# Nombres acotados: la base forma parte del nombre del archivo y no debe
# interpretarse como cadena de conexión (un valor con '=' o 'postgresql://' lo haría).
[[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die_usage "nombre de contenedor no válido"
[[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || die_usage "nombre de base no válido (solo letras, dígitos y _)"
[[ "$db_user" =~ ^[A-Za-z0-9_]+$ ]] || die_usage "nombre de usuario no válido (solo letras, dígitos y _)"

# --- 2. Entorno -------------------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" \
  || die_usage "no se pudo resolver el directorio del script"
validaciones_sql="$script_dir/validaciones.sql"
[[ -r "$validaciones_sql" ]] || die_usage "no se puede leer $validaciones_sql"
command -v docker >/dev/null || die_usage "docker no está disponible en el PATH"
command -v sha256sum >/dev/null || die_usage "sha256sum no está disponible en el PATH"

# Solo se consulta si el contenedor está en ejecución; no se leen su configuración
# ni sus variables de entorno.
running="$(docker container inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" \
  || die_usage "el contenedor '$container' no existe o Docker no es accesible"
[[ "$running" == "true" ]] || die_usage "el contenedor '$container' no está en ejecución"

mkdir -p -- "$backup_dir" "$log_dir" || die_usage "no se pudieron crear los directorios"
backup_dir="$(cd -- "$backup_dir" && pwd -P)" || die_usage "directorio de respaldos no accesible"
log_dir="$(cd -- "$log_dir" && pwd -P)" || die_usage "directorio de logs no accesible"
[[ "$backup_dir" != "$log_dir" ]] || die_usage "respaldos y logs deben estar en directorios distintos"

# Los respaldos contienen datos de la base: se crean legibles solo por su dueño.
umask 077

# --- 3. Nombres de archivo ----------------------------------------------------------
# La marca de tiempo identifica la ejecución; el nombre definitivo nunca se reutiliza.
run_ts="$(date +%Y%m%d_%H%M%S)"
final_file="$backup_dir/${db}_${run_ts}.dump"
tmp_file="$final_file.partial"
baseline_file="$backup_dir/${db}_${run_ts}.baseline"
baseline_tmp="$baseline_file.partial"
log_file="$log_dir/backup_foodstore.log"
tmp_created=0
baseline_tmp_created=0
baseline_final_created=0
completed=0

log() {
  local level="$1"
  shift
  printf '%s [%s] run=%s %s\n' "$(date --iso-8601=seconds)" "$level" "$run_ts" "$*" \
    | tee -a "$log_file" >&2
}

# Al salir sin completar el respaldo (error o interrupción) se registra el fallo y se
# eliminan los temporales y la línea base final creados por esta ejecución, para que
# no se confundan con un respaldo válido. Nunca se borra un archivo ajeno.
on_exit() {
  local status=$?
  if [[ "$completed" -ne 1 ]]; then
    if [[ "$tmp_created" -eq 1 && -e "$tmp_file" ]]; then
      rm -f -- "$tmp_file"
      log ERROR "archivo temporal eliminado: $tmp_file"
    fi
    if [[ "$baseline_tmp_created" -eq 1 && -e "$baseline_tmp" ]]; then
      rm -f -- "$baseline_tmp"
      log ERROR "archivo temporal eliminado: $baseline_tmp"
    fi
    if [[ "$baseline_final_created" -eq 1 && -e "$baseline_file" ]]; then
      rm -f -- "$baseline_file"
      log ERROR "línea base sin respaldo completado eliminada: $baseline_file"
    fi
    log ERROR "RESULTADO=FALLO exit=$status"
  fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  log ERROR "$*"
  exit "$EXIT_FAIL"
}

# Error de entorno ya registrable en el log, detectado antes de ejecutar pg_dump.
abort_env() {
  log ERROR "$*"
  exit "$EXIT_USAGE"
}

[[ ! -e "$final_file" ]] || abort_env "ya existe $final_file; no se sobrescribe"
[[ ! -e "$baseline_file" ]] || abort_env "ya existe $baseline_file; no se sobrescribe"
log INFO "inicio de ejecución: contenedor=$container base=$db usuario=$db_user"
log INFO "destino: $final_file"
log INFO "herramienta: $(docker exec "$container" pg_dump --version 2>&1 || echo 'pg_dump no disponible')"

# --- 4. pg_dump hacia un archivo temporal -------------------------------------------
# Con noclobber, bash crea el temporal de forma exclusiva: falla si ya existe, así
# que nunca se escribe sobre un archivo ajeno.
set -o noclobber
: >"$tmp_file" || abort_env "ya existe o no se puede crear $tmp_file"
set +o noclobber
tmp_created=1

# La línea base se captura y valida antes de iniciar el volcado.
linea_base_inicio="$(date --iso-8601=seconds)"
log INFO "LINEA_BASE_INICIO $linea_base_inicio"
baseline_status=0
baseline_output="$(docker exec -i "$container" psql -X -w -v ON_ERROR_STOP=1 \
  --username="$db_user" --dbname="$db" -f - < "$validaciones_sql" 2>>"$log_file")" \
  || baseline_status=$?
linea_base_fin="$(date --iso-8601=seconds)"
log INFO "LINEA_BASE_FIN $linea_base_fin exit=$baseline_status"
[[ "$baseline_status" -eq 0 ]] || fail "falló la captura de la línea base (detalle en el log)"
printf '%s\n' "$baseline_output" >>"$log_file"

# Se exige cada clave una sola vez, en el orden emitido por validaciones.sql.
expected_keys=(
  conteo.categoria conteo.detalle_pedido conteo.pedido conteo.producto conteo.usuario
  control.detalle_pedido_invalido control.producto_invalido
  eliminados.categoria eliminados.detalle_pedido eliminados.pedido
  eliminados.producto eliminados.usuario
)
line_count=0
while IFS= read -r line; do
  [[ "$line" =~ ^(conteo|eliminados|control)\.[a-z_]+\|[0-9]+$ ]] \
    || fail "formato de línea base no válido"
  [[ "${line%%|*}" == "${expected_keys[line_count]-}" ]] \
    || fail "claves de línea base inesperadas, repetidas o fuera de orden"
  if [[ "$line" == control.* ]]; then
    [[ "${line#*|}" == 0 ]] || fail "control inicial no válido: $line"
  fi
  ((line_count += 1))
done <<<"$baseline_output"
[[ "$line_count" -eq 12 ]] || fail "la línea base debe contener exactamente 12 líneas"

# docker exec sin -t para no alterar la salida binaria. Los mensajes de pg_dump
# (stderr) van al log; el volcado (stdout) va al archivo temporal.
# Esta marca de inicio es la que aproxima la antigüedad del respaldo para el RPO.
pg_dump_inicio="$(date --iso-8601=seconds)"
log INFO "PG_DUMP_INICIO $pg_dump_inicio"
if docker exec "$container" pg_dump --format=custom --no-password \
     --username="$db_user" --dbname="$db" \
     >"$tmp_file" 2>>"$log_file"; then
  pg_dump_fin="$(date --iso-8601=seconds)"
  log INFO "PG_DUMP_FIN $pg_dump_fin exit=0"
else
  dump_status=$?
  fail "PG_DUMP_FIN $(date --iso-8601=seconds) exit=$dump_status (detalle en las líneas previas del log)"
fi

# --- 5. Verificación mínima del archivo ---------------------------------------------
[[ -s "$tmp_file" ]] || fail "el archivo generado está vacío"
log INFO "tamaño: $(stat -c %s -- "$tmp_file") bytes"

# pg_restore --list lee el índice del archivo desde stdin dentro del contenedor.
# Comprueba la legibilidad del formato custom; no restaura ni valida datos.
if docker exec -i "$container" pg_restore --list <"$tmp_file" >/dev/null 2>>"$log_file"; then
  log INFO "pg_restore --list: archivo legible"
else
  fail "pg_restore --list no pudo leer el archivo (detalle en las líneas previas del log)"
fi

# --- 6. Línea base asociada y nombres definitivos ---------------------------------
dump_sha256="$(sha256sum <"$tmp_file")" || fail "no se pudo calcular SHA-256 del respaldo"
dump_sha256="${dump_sha256%% *}"
[[ "$dump_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "SHA-256 del respaldo no válido"
set -o noclobber
: >"$baseline_tmp" || fail "ya existe o no se puede crear $baseline_tmp"
set +o noclobber
baseline_tmp_created=1
printf '%s\n' \
  '# Línea base de backup_foodstore.sh: conteos y controles capturados antes de pg_dump.' \
  "run=$run_ts" \
  "contenedor=$container" \
  "base=$db" \
  "usuario=$db_user" \
  "archivo_respaldo=${final_file##*/}" \
  "sha256_respaldo=$dump_sha256" \
  "linea_base_inicio=$linea_base_inicio" \
  "linea_base_fin=$linea_base_fin" \
  "pg_dump_inicio=$pg_dump_inicio" \
  "pg_dump_fin=$pg_dump_fin" \
  '[validaciones]' \
  "$baseline_output" >"$baseline_tmp" || fail "no se pudo escribir la línea base"

# ln falla si el destino ya existe, por lo que nunca reemplaza un respaldo anterior.
ln -- "$baseline_tmp" "$baseline_file" || fail "no se pudo crear $baseline_file"
baseline_final_created=1
if ! ln -- "$tmp_file" "$final_file"; then
  rm -f -- "$baseline_file"
  baseline_final_created=0
  fail "no se pudo crear $final_file"
fi
rm -f -- "$tmp_file" "$baseline_tmp"
completed=1
log INFO "RESULTADO=OK archivo=$final_file linea_base=$baseline_file"
log INFO "la legibilidad no reemplaza una restauración de prueba"
