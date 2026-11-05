#!/usr/bin/env bash
# Unidad 6 — restauración de prueba con línea base asociada al respaldo.
#
# Uso (todos los parámetros son obligatorios y no tienen valores por defecto):
#   bash unidades/unidad-6/restore_test.sh \
#     -c CONTENEDOR -U USUARIO -a BASE_ADMINISTRATIVA -s BASE_ORIGEN -d BASE_DESTINO \
#     -f RESPALDO.dump -b RESPALDO.baseline -m MODO -o DIR_RESULTADOS
#
# -a  base administrativa existente. Se usa solo para consultar pg_database y como
#     --maintenance-db de createdb. Debe ser distinta del origen y del destino.
# -s  base de origen registrada en el .baseline. Solo se usa para comprobar la
#     procedencia, rechazar un destino igual y registrar la trazabilidad. No necesita
#     existir y el script nunca se conecta a ella.
#
# Requiere la ventana sin escrituras documentada para capturar la línea base y
# pg_dump. Las pruebas de cada versión constan en docs/ensayo_funcional.md (versión
# sin -a) y docs/correccion_restauracion.md (versión con -a). La autenticación
# debe estar preparada en el entorno; no solicita ni configura contraseñas.
# No restaura roles globales ni ajusta privilegios por fuera del respaldo.
#
# Modos (decisión explícita del operador, no una aprobación de CD-3/EA-4):
# - sin-propietarios: --no-owner --no-privileges; solo validación de datos. No
#   recupera propietarios, ACL ni seguridad de U5. Los objetos pertenecen al rol
#   restaurador; esto cambia los privilegios efectivos de funciones SECURITY DEFINER.
# - conservar-propietarios: sin esas opciones; aplica ALTER OWNER y GRANT/REVOKE
#   del respaldo. Los roles referenciados deben existir previamente y el rol que
#   restaura debe poder asignarles la propiedad (superusuario o miembro de esos
#   roles): un rol ausente o un permiso insuficiente hace fallar la restauración
#   con --exit-on-error. No valida equivalencia con U5.
#
# El destino debe ser nuevo y distinto del origen y de las bases protegidas.
# Nunca se elimina automáticamente, ni siquiera ante un fallo o interrupción.
# No se ejecutan dropdb, DROP, ALTER SYSTEM, CREATE ROLE, pg_dumpall ni --globals.
# El script registra las mediciones; su comparación con los objetivos se documenta en el informe y en SPEC_U6.md.
# Códigos: 0 restauración validada; 1 fallo desde el intento de creación o durante
# restauración/validación; 2 error de uso/entorno antes de escribir en PostgreSQL.
# Antes de disponer de un directorio de ejecución propio, el diagnóstico se emite
# solo por stderr; no se escriben logs ni resúmenes sobre directorios ajenos.
set -euo pipefail
umask 077
export LC_ALL=C

readonly EXIT_FAIL=1 EXIT_USAGE=2
container="" db_user="" admin_db="" source_db="" target_db="" dump_file="" baseline_file=""
mode="" results_dir="" run_dir="" log_file="" scope_text="" run_ts=""
stage="parametros" failure_exit="$EXIT_USAGE"
run_dir_created=0 dest_created=0 completed=0
measurement_start="" backup_age="" dump_start="" rto=""

log() {
  local level="$1"
  shift
  if [[ -n "$log_file" ]]; then
    printf '%s [%s] run=%s %s\n' "$(date --iso-8601=seconds)" "$level" "$run_ts" "$*" \
      | tee -a "$log_file" >&2
  else
    printf '[%s] %s\n' "$level" "$*" >&2
  fi
}

elapsed_seconds() {
  local end
  end="$(date +%s.%N)" || return 1
  awk -v inicio="$measurement_start" -v fin="$end" 'BEGIN { printf "%.3f", fin - inicio }'
}

on_exit() {
  local status=$? elapsed="no_iniciada"
  trap - EXIT INT TERM
  if [[ "$completed" -eq 1 && "$status" -eq 0 ]]; then
    return
  fi
  # El diagnóstico debe sobrevivir incluso a un fallo de escritura del propio log.
  set +e
  status="$failure_exit"
  [[ -z "$measurement_start" ]] || elapsed="$(elapsed_seconds)"
  log ERROR "RESULTADO=FALLO etapa=$stage exit=$status"
  log ERROR "DESTINO_CREADO_POR_ESTA_EJECUCION=$dest_created; no se elimina ninguna base"
  if [[ "$run_dir_created" -eq 1 ]]; then
    {
      printf 'RESULTADO=FALLO\nETAPA=%s\nCODIGO_SALIDA=%s\n' "$stage" "$status"
      printf 'BASE_ADMINISTRATIVA=%s\nORIGEN=%s\n' "$admin_db" "$source_db"
      printf 'DESTINO=%s\nDESTINO_CREADO_POR_ESTA_EJECUCION=%s\n' "$target_db" "$dest_created"
      printf 'CONSERVACION=No se elimina ninguna base; si se creó el destino, se conserva.\n'
      printf 'TIEMPO_HASTA_FALLO_SEGUNDOS_NO_ES_RTO=%s\n' "$elapsed"
      printf 'MODO=%s\nALCANCE=%s\n' "$mode" "$scope_text"
      printf 'ANTIGUEDAD_RESPALDO_SEGUNDOS=%s\nPG_DUMP_INICIO=%s\n' "$backup_age" "$dump_start"
      printf 'RESPALDO=%s\nLINEA_BASE=%s\nLOG=%s\n' "$dump_file" "$baseline_file" "$log_file"
      printf 'METAS=El script registra las mediciones; su comparación con los objetivos se documenta en el informe y en SPEC_U6.md.\n'
    } >"$run_dir/resumen.txt"
  fi
  exit "$status"
}
trap on_exit EXIT
trap 'log ERROR "ejecución interrumpida por INT"; exit "$failure_exit"' INT
trap 'log ERROR "ejecución interrumpida por TERM"; exit "$failure_exit"' TERM

usage() {
  printf '%s\n' \
    'Uso: restore_test.sh -c CONTENEDOR -U USUARIO -a BASE_ADMINISTRATIVA -s BASE_ORIGEN -d BASE_DESTINO' \
    '       -f RESPALDO.dump -b RESPALDO.baseline -m MODO -o DIR_RESULTADOS' \
    'MODO: sin-propietarios | conservar-propietarios (todos los parámetros obligatorios).' >&2
  exit "$EXIT_USAGE"
}

fail() {
  log ERROR "$*"
  exit "$failure_exit"
}

# --- 1. Parámetros y entorno; todavía no se escribe en PostgreSQL ---------------
while getopts ':c:U:a:s:d:f:b:m:o:h' opt; do
  case "$opt" in
    c) container="$OPTARG" ;;
    U) db_user="$OPTARG" ;;
    a) admin_db="$OPTARG" ;;
    s) source_db="$OPTARG" ;;
    d) target_db="$OPTARG" ;;
    f) dump_file="$OPTARG" ;;
    b) baseline_file="$OPTARG" ;;
    m) mode="$OPTARG" ;;
    o) results_dir="$OPTARG" ;;
    h) usage ;;
    :) fail "la opción -$OPTARG requiere un valor" ;;
    *) fail "opción desconocida -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || fail "se recibieron argumentos inesperados"
[[ -n "$container" && -n "$db_user" && -n "$admin_db" && -n "$source_db" && -n "$target_db" &&
   -n "$dump_file" && -n "$baseline_file" && -n "$mode" && -n "$results_dir" ]] || usage
[[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "nombre de contenedor no válido"
for name in "$db_user" "$admin_db" "$source_db" "$target_db"; do
  [[ "$name" =~ ^[A-Za-z0-9_]+$ ]] || fail "usuario o base no válido: solo letras, dígitos y _"
done
[[ "${target_db,,}" != "${source_db,,}" ]] || fail "el destino no puede ser igual al origen"
[[ "${admin_db,,}" != "${source_db,,}" ]] || fail "la base administrativa no puede ser igual al origen"
[[ "${admin_db,,}" != "${target_db,,}" ]] || fail "la base administrativa no puede ser igual al destino"
case "${target_db,,}" in
  postgres|template0|template1) fail "la base de destino está protegida" ;;
esac

restore_args=(-w "--username=$db_user" "--dbname=$target_db" --exit-on-error --single-transaction)
case "$mode" in
  sin-propietarios)
    restore_args+=(--no-owner --no-privileges)
    scope_text='Solo validación de datos: propietarios, ACL y seguridad de U5 NO recuperados. Con --no-owner los objetos pertenecen al rol restaurador, lo que cambia los privilegios efectivos de funciones SECURITY DEFINER. No se restauran roles globales.'
    ;;
  conservar-propietarios)
    scope_text='Se aplican propietarios y permisos del respaldo; los roles referenciados deben existir previamente y el rol restaurador debe poder asignarles la propiedad. Un rol ausente o un permiso insuficiente causa fallo con --exit-on-error. No se crean ni restauran roles globales. No se validó equivalencia con la seguridad de U5.'
    ;;
  *) fail "modo no válido: use sin-propietarios o conservar-propietarios" ;;
esac

stage="entorno_y_archivos"
for tool in docker date dirname basename mkdir tee awk diff sha256sum grep; do
  command -v "$tool" >/dev/null || fail "herramienta no disponible en PATH: $tool"
done
[[ -f "$dump_file" && -r "$dump_file" && -s "$dump_file" ]] || fail "respaldo no legible, vacío o no regular"
[[ -f "$baseline_file" && -r "$baseline_file" && -s "$baseline_file" ]] || fail "línea base no legible, vacía o no regular"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
validation_sql="$script_dir/validaciones.sql"
[[ -f "$validation_sql" && -r "$validation_sql" && -s "$validation_sql" ]] || fail "validaciones.sql no es legible o está vacío"

# No se interpreta la línea base como código de shell. Se rechazan duplicados,
# claves desconocidas, secciones repetidas y salidas incompletas o no ordenadas.
stage="linea_base"
declare -A metadata=() expected_metadata=() expected_values=() baseline_values=()
for key in run contenedor base usuario archivo_respaldo sha256_respaldo \
           linea_base_inicio linea_base_fin pg_dump_inicio pg_dump_fin; do
  expected_metadata["$key"]=1
done
for table in categoria detalle_pedido pedido producto usuario; do
  expected_values["conteo.$table"]=1
  expected_values["eliminados.$table"]=1
done
expected_values[control.detalle_pedido_invalido]=1
expected_values[control.producto_invalido]=1
in_values=0 value_count=0 previous_key="" baseline_section=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$in_values" -eq 0 ]]; then
    [[ "$line" != \#* ]] || continue
    if [[ "$line" == '[validaciones]' ]]; then
      in_values=1
      continue
    fi
    [[ "$line" == *=* ]] || fail "metadato de línea base mal formado"
    key="${line%%=*}" value="${line#*=}"
    [[ -n "$key" ]] || fail "metadato de línea base sin clave"
    [[ -n "${expected_metadata[$key]:-}" && -z "${metadata[$key]:-}" && -n "$value" ]] \
      || fail "metadato de línea base desconocido, vacío o duplicado"
    metadata["$key"]="$value"
  else
    [[ "$line" =~ ^(conteo|eliminados|control)\.[a-z_]+\|[0-9]+$ ]] \
      || fail "fila de validación de línea base mal formada"
    key="${line%%|*}" value="${line#*|}"
    [[ -n "${expected_values[$key]:-}" && -z "${baseline_values[$key]:-}" ]] \
      || fail "clave de validación desconocida o duplicada"
    [[ -z "$previous_key" || "$key" > "$previous_key" ]] || fail "línea base sin orden C por clave"
    baseline_values["$key"]="$value"
    previous_key="$key"
    baseline_section+="$line"$'\n'
    value_count=$((value_count + 1))
  fi
done <"$baseline_file"
[[ "$in_values" -eq 1 && "$value_count" -eq 12 ]] || fail "se requieren sección [validaciones] y sus 12 filas"
for key in "${!expected_metadata[@]}"; do
  [[ -n "${metadata[$key]:-}" ]] || fail "falta el metadato $key"
done
for key in "${!expected_values[@]}"; do
  [[ -n "${baseline_values[$key]:-}" ]] || fail "falta la validación $key"
done
[[ "${metadata[base]}" == "$source_db" ]] || fail "la línea base no corresponde al origen"
[[ "${metadata[archivo_respaldo]}" == "$(basename -- "$dump_file")" ]] || fail "la línea base no corresponde al archivo de respaldo"
[[ "${metadata[sha256_respaldo]}" =~ ^[[:xdigit:]]{64}$ ]] || fail "SHA256 de línea base no válido"
checksum="$(sha256sum <"$dump_file")" || fail "no se pudo calcular SHA256 del respaldo"
[[ "${checksum%% *}" == "${metadata[sha256_respaldo],,}" ]] || fail "SHA256 del respaldo distinto de la línea base"
dump_start="${metadata[pg_dump_inicio]}"
[[ "$dump_start" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]] \
  || fail "pg_dump_inicio debe incluir fecha, segundos y desplazamiento horario ISO-8601"
dump_start_epoch="$(date -d "$dump_start" +%s)" || fail "pg_dump_inicio no es una fecha válida"

# --- 2. Directorio exclusivo, antigüedad y comprobaciones de solo lectura --------
stage="directorio_resultados"
mkdir -p -- "$results_dir" || fail "no se pudo crear el directorio de resultados"
results_dir="$(cd -- "$results_dir" && pwd -P)" || fail "directorio de resultados no accesible"
run_ts="$(date +%Y%m%d_%H%M%S)"
candidate_dir="$results_dir/restore_${target_db}_${run_ts}"
mkdir -- "$candidate_dir" || fail "el directorio de ejecución existe o no puede crearse; no se sobrescribe"
run_dir="$candidate_dir"
run_dir_created=1
log_file="$run_dir/restore_test.log"
: >"$log_file"
printf '%s' "$baseline_section" >"$run_dir/validaciones_linea_base.txt"
log INFO "inicio: contenedor=$container usuario=$db_user base_administrativa=$admin_db origen=$source_db destino=$target_db"
log INFO "el origen solo se usa para trazabilidad y para comprobar la línea base; no se abre conexión a él"
log INFO "MODO=$mode; ALCANCE=$scope_text"
printf -v restore_command '%q ' docker exec -i "$container" pg_restore "${restore_args[@]}"
log INFO "argumentos exactos de restauración: $restore_command; entrada=$dump_file"
test_start_epoch="$(date +%s)"
backup_age=$((test_start_epoch - dump_start_epoch))
log INFO "ANTIGUEDAD_RESPALDO_SEGUNDOS=$backup_age PG_DUMP_INICIO=$dump_start"
log INFO "El script registra las mediciones; su comparación con los objetivos se documenta en el informe y en SPEC_U6.md."

stage="contenedor"
# Se consulta solo State.Running, nunca variables de entorno del contenedor.
running="$(docker container inspect --format '{{.State.Running}}' "$container" 2>>"$log_file")" \
  || fail "el contenedor no existe o Docker no es accesible"
[[ "$running" == true ]] || fail "el contenedor no está en ejecución"
stage="ausencia_destino"
# Conexión a la base administrativa, no al origen, que puede no existir.
# -f - permite interpolar :'destino' como literal SQL; -c no lo haría.
if ! destination_count="$(docker exec -i "$container" psql -X -w -v ON_ERROR_STOP=1 \
    --username="$db_user" --dbname="$admin_db" -At -v "destino=$target_db" -f - \
    2>>"$log_file" <<'SQL'
SELECT count(*) FROM pg_database WHERE datname = :'destino';
SQL
)"; then
  fail "no se pudo comprobar la ausencia del destino"
fi
[[ "$destination_count" =~ ^[0-9]+$ ]] || fail "respuesta no válida al comprobar el destino"
[[ "$destination_count" == 0 ]] || fail "el destino ya existe; no se borra ni se sobrescribe"
stage="listado_respaldo"
docker exec -i "$container" pg_restore --list <"$dump_file" \
  >"$run_dir/pg_restore_list.txt" 2>>"$log_file" || fail "pg_restore --list no pudo leer el respaldo"

# --- 3. Medición desde creación hasta validaciones completas ---------------------
failure_exit="$EXIT_FAIL"
stage="creacion_destino"
rto_start_iso="$(date --iso-8601=seconds)"
log INFO "RTO_INICIO=$rto_start_iso (medición inmediatamente antes de createdb)"
measurement_start="$(date +%s.%N)"
docker exec "$container" createdb -w --username="$db_user" \
  --maintenance-db="$admin_db" --template=template0 "$target_db" \
  >>"$log_file" 2>&1 || fail "createdb falló; no se atribuye a esta ejecución una base ajena"
dest_created=1

stage="restauracion"
# --single-transaction + --exit-on-error revierte los objetos restaurados ante un
# fallo: el destino nuevo queda vacío pero existente. Se conserva, no se elimina.
# La tubería espera también a tee; pipefail conserva el fallo de pg_restore.
if docker exec -i "$container" pg_restore "${restore_args[@]}" <"$dump_file" \
    2>&1 >"$run_dir/pg_restore_stdout.txt" \
    | tee "$run_dir/pg_restore_stderr.txt" >>"$log_file"; then
  log INFO "pg_restore terminó sin errores"
else
  fail "la restauración falló; consultar pg_restore_stderr.txt y el log"
fi

stage="validaciones_destino"
docker exec -i "$container" psql -X -w -v ON_ERROR_STOP=1 \
  --username="$db_user" --dbname="$target_db" -f - <"$validation_sql" \
  >"$run_dir/validaciones_destino.txt" 2>>"$log_file" || fail "fallaron las consultas de validación"
stage="comparacion_linea_base"
diff -u "$run_dir/validaciones_linea_base.txt" "$run_dir/validaciones_destino.txt" \
  >"$run_dir/comparacion.diff" 2>>"$log_file" || fail "la salida restaurada no coincide con la línea base o falló diff"
stage="controles_cero"
grep -Fxq 'control.producto_invalido|0' "$run_dir/validaciones_destino.txt" \
  || fail "el control de productos inválidos no está en cero"
grep -Fxq 'control.detalle_pedido_invalido|0' "$run_dir/validaciones_destino.txt" \
  || fail "el control de detalles inválidos no está en cero"
rto="$(elapsed_seconds)"
rto_end_iso="$(date --iso-8601=seconds)"

# --- 4. Resultado: nunca se presenta la medida de un fallo como RTO válido -------
stage="registro_resultado"
log INFO "RTO_FIN=$rto_end_iso RTO_OBSERVADO_SEGUNDOS=$rto"
{
  printf 'RESULTADO=RESTAURACION_VALIDADA\nMODO=%s\nALCANCE=%s\n' "$mode" "$scope_text"
  printf 'CONTENEDOR=%s\nUSUARIO=%s\nBASE_ADMINISTRATIVA=%s\nORIGEN=%s\nDESTINO=%s\n' "$container" "$db_user" "$admin_db" "$source_db" "$target_db"
  printf 'ANTIGUEDAD_RESPALDO_SEGUNDOS=%s\nPG_DUMP_INICIO=%s\n' "$backup_age" "$dump_start"
  printf 'RTO_INICIO=%s\nRTO_FIN=%s\nRTO_OBSERVADO_SEGUNDOS=%s\n' "$rto_start_iso" "$rto_end_iso" "$rto"
  printf 'RESPALDO=%s\nLINEA_BASE=%s\nSHA256_RESPALDO=%s\n' "$dump_file" "$baseline_file" "${checksum%% *}"
  printf 'COMANDO_RESTAURACION=%s\n' "$restore_command"
  printf 'ARCHIVOS=restore_test.log, pg_restore_list.txt, pg_restore_stdout.txt, pg_restore_stderr.txt, validaciones_linea_base.txt, validaciones_destino.txt, comparacion.diff, resumen.txt\n'
  printf 'DESTINO_CREADO_POR_ESTA_EJECUCION=1\nCONSERVACION=Se conserva el destino.\n'
  printf 'METAS=El script registra las mediciones; su comparación con los objetivos se documenta en el informe y en SPEC_U6.md.\n'
} >"$run_dir/resumen.txt"
log INFO "RESULTADO=RESTAURACION_VALIDADA resumen=$run_dir/resumen.txt"
completed=1
exit 0
