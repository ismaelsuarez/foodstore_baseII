# Guía de evaluación — Unidad 6

Guía operativa para preparar, conectar y evaluar U6 usando solo este repositorio
y la consigna. No reemplaza la [SPEC](SPEC_U6.md) ni la bitácora: indica qué
ejecutar y qué comparar. Los resultados previos del equipo son antecedentes y no
hace falta aceptarlos como aprobación.

## A. Alcance y fuentes

- **Consigna:** `TPUnidad_6_Mantenimiento_FoodStore.pdf` — «Trabajo Práctico —
  Unidad 6: Mantenimiento, respaldo y recuperación». Es material de la cátedra,
  actividad de laboratorio de la Semana 10, y no está incorporado al repositorio.
- **Esquema real:** [schema.sql](../../schema.sql) (cinco tablas: `categoria`,
  `usuario`, `producto`, `pedido`, `detalle_pedido`),
  [datos_iniciales.sql](../../datos_iniciales.sql) y
  [tpi/sql/objetos_programables.sql](../../tpi/sql/objetos_programables.sql)
  (7 rutinas y 5 triggers).
- **Entregables U6:** [backup_foodstore.sh](backup_foodstore.sh),
  [health_check.sql](health_check.sql), [maintenance.sql](maintenance.sql),
  [restore_test.sh](restore_test.sh) y [validaciones.sql](validaciones.sql),
  usado por los dos scripts Bash. El informe es `informe_u6.pdf`.

### Decisiones del equipo (2026-11-05)

Las adoptó el equipo antes de la corrida de evaluación. **No son confirmaciones
del profesor** y no se aplican retroactivamente a los ensayos anteriores.

| Tema | Decisión |
|---|---|
| Base de origen | `foodstore` |
| Base de restauración | `foodstore_restore_test` |
| Base administrativa de la restauración | `postgres` |
| Modelo | `schema.sql` vigente, con `usuario`; no se crean `cliente` ni aliases |
| Alcance | Núcleo canónico: esquema, datos y objetos programables del TPI |
| Modo de restauración | `sin-propietarios` (`--no-owner --no-privileges`) |
| Rol de ejecución | `postgres`, solo en el laboratorio académico aislado |
| Metas | RPO 24 h; RTO 20 min |

### Diferencias que siguen sujetas a evaluación docente

| Tema | PDF | ZIP del docente | Implementación |
|---|---|---|---|
| Nombres de bases | `foodstore`, `foodstore_restore_test` | `food_store`, `food_store_prueba_restauracion` | Los del PDF |
| Tabla de usuarios en la validación | `cliente` | `usuario` | `usuario`, la que existe en el schema |
| Opciones de restauración | `--no-owner --no-privileges` | `--exit-on-error -j 4` con TOC filtrado | `--exit-on-error --single-transaction --no-owner --no-privileges` |
| Base de restauración existente | — | `dropdb --if-exists` automático | Se detiene sin borrarla |
| Roles, `pg_cron`, archivado, `ALTER SYSTEM` | — | `00_roles…`, `06_…`, `03_…` y `07_…` | No instalados ni ejecutados |

Estas diferencias no son erratas confirmadas, el docente no las aceptó y no se
afirma compatibilidad literal con el paquete del ZIP. El análisis completo está en
[compatibilidad docente](docs/compatibilidad_docente.md).

### Qué es U6 y qué no

- **Núcleo U6:** respaldo con línea base, salud, mantenimiento puntual y
  restauración validada del núcleo canónico.
- **Trabajos históricos:** U1–U5 están cerrados. Su SQL no forma parte de esta
  instalación y no debe ejecutarse en cadena.
- **Sin probar:** recuperación de propietarios, permisos y seguridad de U5; modo
  `conservar-propietarios`; scripts del docente; `pg_cron`; volumen real de datos;
  escrituras concurrentes.

## B. Preparación reproducible

**Requisitos:**

- Bash, Docker y `openssl`, y una imagen local de PostgreSQL 17 (`postgres:17`).
  `psql`, `pg_dump`, `pg_restore` y `createdb` se usan desde dentro del
  contenedor; no hace falta instalarlos en el host.
- Docker clásico, ni rootless ni con userns-remap. Con root dentro del contenedor,
  los clientes leen archivos 0600 del operador del host; con otra configuración
  puede ser necesario ajustar el montaje.

**Cómo usar los bloques:** se ejecutan desde la raíz del repositorio y en orden.
Cada uno es independiente, salvo P0, que define las variables y debe repetirse en
cada terminal nueva. Ningún bloque borra recursos.

**Shell:** los bloques están escritos para Bash. Si la terminal usa fish u otro
shell, primero hay que abrir `bash`.

Hay que ejecutar cada bloque en una subshell con modo estricto, para que un
`DETENERSE` o cualquier error corte el bloque y no siga con los comandos
siguientes. Por ejemplo: `( set -euo pipefail; <pegar P0>; <pegar el bloque> )`,
y después `echo "bloque exit=$?"`. Si los bloques se guardan en archivos, la forma
equivalente es `bash -c 'set -euo pipefail; source P0.sh; source P7.sh'`.

P7 y P9 terminan con el mismo código de salida que el script que ejecutan; mostrar
el log o el resumen no lo cambia. Si un bloque termina con un código distinto de
cero, no hay que continuar.

**Variables de P0:**

- `U6_ORIGEN` y `U6_DESTINO` valen por defecto `foodstore` y
  `foodstore_restore_test`, los nombres de la entrega.
- `U6_RES` vale por defecto `$U6_PRIV/resultados` y es la carpeta de resultados.
- Solo P7, P8 y P9 usan estas variables. Se cambian únicamente para una prueba
  autorizada; por ejemplo, otro destino nuevo y otra carpeta de resultados.
- Los demás bloques usan los nombres de la entrega.

```bash
# [P0] Variables. U6_PRIV: directorio privado NUEVO, fuera del repositorio.
export U6_PRIV="${U6_PRIV:?definir U6_PRIV con un directorio privado nuevo fuera del repositorio}"
export U6_C=foodstore-u6-evaluacion U6_V=foodstore_u6_evaluacion_data U6_IMG=postgres:17
export U6_ORIGEN="${U6_ORIGEN:-foodstore}" U6_DESTINO="${U6_DESTINO:-foodstore_restore_test}" U6_RES="${U6_RES:-$U6_PRIV/resultados}"
if [ ! -f schema.sql ] || [ ! -d unidades/unidad-6 ]; then echo "DETENERSE: ejecutar desde la raíz del repositorio"; false; fi
```

```bash
# [P1] Nombres libres e imagen local (no descarga nada).
if docker container inspect "$U6_C" >/dev/null 2>&1; then echo "DETENERSE: el contenedor ya existe"; false; fi
if docker volume inspect "$U6_V" >/dev/null 2>&1; then echo "DETENERSE: el volumen ya existe"; false; fi
if [ -e "$U6_PRIV" ]; then echo "DETENERSE: U6_PRIV ya existe; usar uno nuevo"; false; fi
docker image inspect --format 'imagen={{.Id}}' "$U6_IMG"
```

```bash
# [P2] Credenciales propias de esta instancia; nunca se imprimen ni van a Git.
umask 077
mkdir -m 0700 "$U6_PRIV" "$U6_PRIV/auth" "$U6_PRIV/resultados"
openssl rand -hex 24 > "$U6_PRIV/auth/postgres_password"
{ printf '127.0.0.1:5432:*:postgres:'; cat "$U6_PRIV/auth/postgres_password"; } > "$U6_PRIV/auth/pgpass"
stat -c '%A %s bytes %n' "$U6_PRIV/auth/postgres_password" "$U6_PRIV/auth/pgpass"
```

```bash
# [P3] Instancia aislada: sin red, sin puertos publicados, no privilegiada, SCRAM.
docker volume create "$U6_V"
docker create --pull never --name "$U6_C" --network none \
  -v "$U6_V:/var/lib/postgresql/data" \
  -v "$U6_PRIV/auth:/run/foodstore-u6-auth:ro" \
  -e POSTGRES_PASSWORD_FILE=/run/foodstore-u6-auth/postgres_password \
  -e POSTGRES_INITDB_ARGS="--auth-local=scram-sha-256 --auth-host=scram-sha-256" \
  -e PGHOST=127.0.0.1 -e PGPASSFILE=/run/foodstore-u6-auth/pgpass \
  "$U6_IMG" -c log_connections=on
docker start "$U6_C"
for i in $(seq 1 90); do docker exec "$U6_C" pg_isready -q -h 127.0.0.1 && break; sleep 1; done
docker exec "$U6_C" pg_isready -h 127.0.0.1
docker container inspect "$U6_C" --format 'red={{.HostConfig.NetworkMode}} puertos={{json .HostConfig.PortBindings}} privilegiado={{.HostConfig.Privileged}}'
```

## C. Conexión

Los clientes corren dentro del contenedor mediante `docker exec`. `PGHOST`
(127.0.0.1) y `PGPASSFILE` del contenedor llevan las conexiones por TCP con SCRAM
usando el archivo pgpass del paso P2.

**No hay ningún puerto publicado:** la instancia no es accesible desde el host ni
desde la red. Para evaluar en otra computadora hay que reproducir allí los pasos
P0–P3; no existe una conexión remota disponible.

```bash
# [P4] Versión, base y usuario efectivos; reglas HBA; rechazo sin contraseña.
docker exec "$U6_C" psql -X -w -U postgres -d postgres -At \
  -c "SELECT version()" \
  -c "SELECT current_database() || '|' || current_user || '|' || inet_server_addr()" \
  -c "SELECT count(*) FILTER (WHERE auth_method = 'trust') || ' reglas trust de ' || count(*) FROM pg_hba_file_rules"
if docker exec -e PGPASSFILE=/nonexistent "$U6_C" psql -X -w -U postgres -d postgres -c 'SELECT 1' >/dev/null 2>&1; then
  echo "DETENERSE: el servidor aceptó una conexión sin contraseña"; false
else echo "OK: conexión sin contraseña rechazada"; fi
```

## D. Procedimiento completo

```bash
# [P5] Origen foodstore con el núcleo canónico. ON_ERROR_STOP en todos los archivos;
# -1 solo en schema y objetos, porque el seed administra su propia transacción.
existe="$(docker exec "$U6_C" psql -X -w -U postgres -d postgres -At -c "SELECT count(*) FROM pg_database WHERE datname IN ('foodstore','foodstore_restore_test')")"
if [ "$existe" != 0 ]; then echo "DETENERSE: foodstore o foodstore_restore_test ya existen; no se borran"; false; fi
docker exec "$U6_C" createdb -w -U postgres --template=template0 foodstore
docker exec -i "$U6_C" psql -X -w -q -U postgres -d foodstore -v ON_ERROR_STOP=1 -1 -f - < schema.sql
docker exec -i "$U6_C" psql -X -w -q -U postgres -d foodstore -v ON_ERROR_STOP=1 -f - < datos_iniciales.sql
docker exec -i "$U6_C" psql -X -w -q -U postgres -d foodstore -v ON_ERROR_STOP=1 -1 -f - < tpi/sql/objetos_programables.sql
docker exec -i "$U6_C" psql -X -w -U postgres -d foodstore -f - < unidades/unidad-6/validaciones.sql
```

```bash
# [P6] Huellas de los archivos que se van a ejecutar.
sha256sum unidades/unidad-6/*.sh unidades/unidad-6/*.sql schema.sql datos_iniciales.sql \
  tpi/sql/objetos_programables.sql | tee "$U6_PRIV/resultados/huellas_antes.txt"
```

```bash
# [P7] Línea base y respaldo. Requiere que nadie escriba en el origen durante la
# captura y el pg_dump: el script no garantiza esa ventana.
docker exec "$U6_C" psql -X -w -U postgres -d postgres -At -c "SELECT 'sesiones_en_origen=' || count(*) FROM pg_stat_activity WHERE datname = '$U6_ORIGEN'"
rc=0; bash unidades/unidad-6/backup_foodstore.sh -c "$U6_C" -d "$U6_ORIGEN" -U postgres \
  -o "$U6_RES/respaldos" -l "$U6_RES/logs" || rc=$?
echo "backup_foodstore.sh exit=$rc"
(exit "$rc")
```

**Salida de `backup_foodstore.sh`:** 0 si hay respaldo y línea base; 1 si falló la
captura, un control inicial, `pg_dump` o su verificación; 2 ante un error de uso o
de entorno. Ante un fallo no quedan archivos definitivos de esa ejecución.

```bash
# [P8] Selección del respaldo y su línea base asociada (mismo nombre base y SHA-256).
DUMP="$(ls -1 "$U6_RES"/respaldos/"$U6_ORIGEN"_*.dump | tail -n 1)"; BASELINE="${DUMP%.dump}.baseline"
test -s "$DUMP" && test -s "$BASELINE"
grep -E '^(base|archivo_respaldo|sha256_respaldo|pg_dump_inicio)=' "$BASELINE"
sha256sum "$DUMP"
```

```bash
# [P9] Restauración: el script crea el destino ($U6_DESTINO). No crearlo antes.
DUMP="$(ls -1 "$U6_RES"/respaldos/"$U6_ORIGEN"_*.dump | tail -n 1)"; BASELINE="${DUMP%.dump}.baseline"
antes="$( { ls -1d "$U6_RES"/restauracion/restore_"$U6_DESTINO"_* 2>/dev/null || true; } | sort)"
rc=0; bash unidades/unidad-6/restore_test.sh -c "$U6_C" -U postgres -a postgres \
  -s "$U6_ORIGEN" -d "$U6_DESTINO" -f "$DUMP" -b "$BASELINE" \
  -m sin-propietarios -o "$U6_RES/restauracion" || rc=$?
echo "restore_test.sh exit=$rc"
nuevo="$(comm -13 <(printf '%s\n' "$antes") <( { ls -1d "$U6_RES"/restauracion/restore_"$U6_DESTINO"_* 2>/dev/null || true; } | sort) || true)"
if [ -n "$nuevo" ] && [ -f "$nuevo/resumen.txt" ]; then cat "$nuevo/resumen.txt" || true; else echo "sin resumen propio de esta ejecución (falló antes de crear su directorio)"; fi
(exit "$rc")
```

**Salida de `restore_test.sh`:** 0 solo con `RESULTADO=RESTAURACION_VALIDADA`; 1
ante un fallo desde la creación del destino; 2 ante un error de uso o de entorno
antes de escribir en PostgreSQL, por ejemplo un destino que ya existe.

- **Destino existente:** el script se detiene sin borrarlo ni sobrescribirlo. Para
  repetir la prueba hay que usar otro destino autorizado.
- **Ante un fallo:** el destino creado se conserva y el diagnóstico queda en
  `restore_<destino>_<fecha>/`: `restore_test.log`, `pg_restore_stderr.txt`,
  `comparacion.diff` y `resumen.txt`.

```bash
# [P10] Salud del origen y de la copia restaurada (solo lectura; registra métricas, sin semáforo).
docker exec -i "$U6_C" psql -X -w -U postgres -d foodstore -v ON_ERROR_STOP=1 -P pager=off -f - < unidades/unidad-6/health_check.sql
docker exec -i "$U6_C" psql -X -w -U postgres -d foodstore_restore_test -v ON_ERROR_STOP=1 -P pager=off -f - < unidades/unidad-6/health_check.sql
```

```bash
# [P11] Diagnóstico de mantenimiento en la copia restaurada (sin variables: no cambia nada).
docker exec -i "$U6_C" psql -X -w -U postgres -d foodstore_restore_test -P pager=off -f - < unidades/unidad-6/maintenance.sql
```

**`ANALYZE` puntual (P12):** solo se ejecuta si el diagnóstico lo justifica, sobre
una tabla canónica de la copia descartable y con la observación real escrita en la
justificación:

```bash
# [P12] Solo si la observación de P11 lo justifica. Reemplazar TABLA y el texto.
docker exec -i "$U6_C" psql -X -w -U postgres -d foodstore_restore_test -P pager=off \
  -v tabla_mantenimiento=TABLA -v confirmar_analyze=on \
  -v justificacion='OBSERVACION REAL DE P11' -f - < unidades/unidad-6/maintenance.sql
```

```bash
# [P13] Huellas al terminar: deben coincidir con P6.
sha256sum unidades/unidad-6/*.sh unidades/unidad-6/*.sql schema.sql datos_iniciales.sql \
  tpi/sql/objetos_programables.sql | diff "$U6_PRIV/resultados/huellas_antes.txt" - && echo "huellas sin cambios"
```

## E. Matriz de evaluación

| Requisito (consigna / SPEC) | Archivo o comando | Comprobación | Evidencia |
|---|---|---|---|
| Respaldo con fecha y hora en el nombre | `backup_foodstore.sh` (P7) | `foodstore_AAAAMMDD_HHMMSS.dump` no vacío; exit 0 | `resultados/respaldos/` |
| Log con inicio y fin; código distinto de cero ante fallo | `backup_foodstore.sh` | `PG_DUMP_INICIO`, `PG_DUMP_FIN`, `RESULTADO=`; probar con una base inexistente | `resultados/logs/backup_foodstore.log` |
| Sin contraseñas en los scripts | Revisión de `*.sh` y `*.sql`; P2 | Credenciales solo en `U6_PRIV/auth`; `-w` y pgpass | Revisión de código; `stat` de P2 |
| Línea base antes de `pg_dump`, asociada al respaldo | P7–P8 | `.baseline` con `archivo_respaldo`, `sha256_respaldo` y `pg_dump_inicio` | `.baseline` |
| Salud: tamaño, conexiones, tablas, sesiones | `health_check.sql` (P10) | Exit 0; cuatro controles; cero sesiones es válido | Salida de P10 |
| Mantenimiento: diagnóstico previo y acción segura | `maintenance.sql` (P11–P12) | Sin variables, sin cambios; `ANALYZE` solo con selección y justificación; sin `VACUUM FULL` | Salida de P11–P12 |
| Restauración en una base de prueba que no existía | `restore_test.sh` (P9) | Crea `foodstore_restore_test`; se detiene si ya existe | `resumen.txt`, `restore_test.log` |
| Conteos iguales a la línea base | `validaciones.sql`, `comparacion.diff` | `diff` vacío entre destino y línea base | `validaciones_destino.txt`, `comparacion.diff` |
| Productos y detalles inválidos en cero | `validaciones.sql` | Ambos `control.*` en 0 | `validaciones_destino.txt` |
| RPO y RTO medidos | `resumen.txt` | `ANTIGUEDAD_RESPALDO_SEGUNDOS` contra 86400; `RTO_OBSERVADO_SEGUNDOS` contra 1200 | `resumen.txt` |
| Informe | `informe_u6.pdf` | Una página con los datos de la corrida | `informe_u6.pdf`, `informe_u6.html` |

## F. Pruebas independientes

- **Conteos:** los del seed (2, 3, 3, 5 y 7) son un ejemplo. La comparación válida
  es contra la línea base real de cada respaldo.
- **Pruebas que escriben:** usan una copia descartable autorizada y un destino
  nuevo para cada intento. No hay que borrar bases para reintentar.
- **Fallos:** no se modifican el código, los datos ni las expectativas para
  ocultarlos. El diagnóstico se conserva y se informa la parte afectada.
- **Logs del equipo:** los de [ensayo funcional](docs/ensayo_funcional.md),
  [corrección de la restauración](docs/correccion_restauracion.md) y
  [ensayo de evaluación](docs/ensayo_evaluacion.md) son antecedentes, no
  aprobación.
- **Scripts del docente:** varios crean objetos, cambian configuración
  (`ALTER SYSTEM`), programan tareas (`pg_cron`) o borran bases (`dropdb`). No hay
  que ejecutarlos automáticamente; antes hay que revisar su alcance y contar con
  autorización.
- **Prueba negativa sugerida:** repetir P9 contra el destino ya existente. Debe
  mostrar `restore_test.sh exit=2`, el bloque debe terminar también con 2 y el
  destino no debe cambiar. En este caso, el rechazo es el resultado esperado.
