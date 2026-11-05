# Laboratorio U6 — Primera prueba técnica de infraestructura

## Propósito y límites

El 2026-11-04 (hora local -03:00) se realizó una primera prueba técnica de
`backup_foodstore.sh` y `health_check.sql` sobre la base auxiliar `postgres` de un
laboratorio aislado. Este documento registra el procedimiento y los resultados
comunicados de ese ensayo; la actualización documental no repite las ejecuciones.

**Esta prueba es de infraestructura. No constituye la validación del TP6 ni
demuestra que Food Store pueda restaurarse.** No se cargaron datos de Food Store,
no se restauró el respaldo y no se midieron RPO/RTO. El rol `postgres` se utiliza
aquí para preparación y prueba de infraestructura; **no queda aprobado como rol
definitivo de respaldo de Food Store**.

## Recursos

| Recurso | Estado observado |
|---|---|
| Contenedor | `foodstore-u6-lab`, id `2625b25f320c…`, creado el 2026-11-04 (-03:00) |
| Volumen | `foodstore_u6_lab_data`, etiqueta `org.foodstore.lab=u6` |
| Imagen local | `postgres:17`, id `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| Servidor y clientes | PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) |
| Aislamiento | `--network none`, sin puertos publicados, no privilegiado, sin socket Docker montado |
| Autenticación | Montaje de solo lectura en `/run/foodstore-u6-auth`; SCRAM local y TCP |
| Registro | Argumento del servidor `-c log_connections=on` |
| Conservación | Contenedor en ejecución para la siguiente etapa; evidencias y dumps fuera del repositorio, en `<DIR_PRIVADO>/evidence` |

No se crearon las bases Food Store ni se cargaron schema/seed, objetos TPI,
roles U5, vistas U3 o `pgcrypto`: no estaban autorizados. Los nombres principal y
de restauración siguen pendientes (CD-1). EP-1 está resuelto; EP-2 es parcial
(contenedor y volumen creados, bases y roles pendientes). EP-6/VE-2 (`pg_cron`)
no se comprobó.

## Autenticación

### Identidades y transporte

- El operador SO del host ejecuta Docker y Bash.
- Los clientes `psql`, `pg_dump` y `pg_restore` se ejecutan mediante `docker exec`
  como usuario SO `root` (uid 0) dentro del contenedor.
- El servidor se ejecuta como usuario SO `postgres` (uid 999).
- `postgres`, pasado con `-U` o `--username`, es el rol de PostgreSQL, distinto
  de los usuarios del sistema operativo. Es superusuario y solo se usa aquí para
  preparación y prueba de infraestructura; las identidades por tarea siguen
  pendientes (EP-4).

El entorno del contenedor establece `PGHOST=127.0.0.1` y
`PGPASSFILE=/run/foodstore-u6-auth/pgpass`. Así, incluso
`backup_foodstore.sh`, que no tiene opción `-h` y no fue modificado, conecta por
TCP a 127.0.0.1:5432. No utiliza el `~/.pgpass` del host. La SPEC menciona
`~/.pgpass`: el laboratorio usa el mismo formato pgpass, seleccionado por
`PGPASSFILE`.

### Archivos privados e inicialización

El directorio externo al repositorio se identifica únicamente como
`<DIR_PRIVADO>`. Su directorio `auth` tiene modo 0700; los archivos tienen modo
0600 y pertenecen al operador del host (uid/gid observados: 1000:1000). Se monta
en solo lectura en `/run/foodstore-u6-auth`.

Docker no es rootless ni utiliza userns-remap. `root` dentro del contenedor puede
leer los archivos por su capacidad; el usuario SO `postgres` no puede leerlos.
Esto permite a los clientes ejecutados como root usar pgpass sin dar acceso a los
archivos al usuario SO del servidor.

La contraseña inicial se entrega mediante `POSTGRES_PASSWORD_FILE`. Se revisó el
entrypoint: lee el archivo como root antes de pasar al usuario SO postgres,
limpia `PGHOST` durante la inicialización y elimina `PGPASSWORD` después de ella.
Las contraseñas son aleatorias, de 48 caracteres hexadecimales, generadas con
OpenSSL directamente en archivos: no se imprimieron ni se pasaron como argumentos.

La entrada pgpass tiene alcance `127.0.0.1:5432:*:postgres:` seguido de la
contraseña. `*` permite autenticar también el intento F contra la base inexistente:
el fallo debe ser por base ausente, no por falta de contraseña. Los archivos son
texto plano en el disco del host, aceptable solo como condición de este laboratorio,
no como aprobación de una solución definitiva.

`POSTGRES_INITDB_ARGS="--auth-local=scram-sha-256 --auth-host=scram-sha-256"`
configura SCRAM. Una conexión exitosa por sí sola no prueba la autenticación:
se comprobaron reglas HBA, formato del verificador mediante un booleano, logs del
servidor y rechazo al retirar pgpass, como se detalla más adelante.

## Procedimiento reproducible

Los bloques siguientes son documentación para una futura ejecución autorizada,
no comandos ejecutados en esta actualización. Sustituir `<DIR_PRIVADO>` por un
directorio privado nuevo, externo al repositorio, sin publicar su ubicación ni su
contenido. La variable permite citar las rutas sin interpretar los signos `<` y
`>` como redirecciones. No reutilizar recursos existentes ni eliminarlos.

### 1. Comprobar nombres y preparar archivos

Antes de crear recursos, comprobar si existen los nombres; **si cualquiera
existe, detenerse**. Un fallo de acceso a Docker tampoco acredita su ausencia.

```bash
docker container ls -a --format '{{.Names}}'
docker volume ls --format '{{.Name}}'
```

Confirmar que no figuran `foodstore-u6-lab` ni `foodstore_u6_lab_data`, y que la
imagen local requerida está disponible, sin descargar otra imagen:

```bash
docker image inspect --format '{{.Id}}' sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3
```

Crear un directorio nuevo, no uno con credenciales previas. No mostrar los
archivos de autenticación. El uso de `cat` siguiente los escribe directamente en
otro archivo, no en la consola.

```bash
umask 077
DIR_PRIVADO='<DIR_PRIVADO>'
mkdir -m 0700 "$DIR_PRIVADO"
mkdir -m 0700 "$DIR_PRIVADO/auth" "$DIR_PRIVADO/evidence"
openssl rand -hex 24 > "$DIR_PRIVADO/auth/postgres_password"
{ printf '127.0.0.1:5432:*:postgres:'; cat "$DIR_PRIVADO/auth/postgres_password"; } > "$DIR_PRIVADO/auth/pgpass"
```

Los archivos se crean con modo 0600 por `umask 077`; los directorios, con 0700.
Detenerse ante cualquier error, sin continuar con archivos parciales.

### 2. Crear el laboratorio e inspeccionar el entrypoint

```bash
docker volume create --label org.foodstore.lab=u6 foodstore_u6_lab_data
docker create --pull never --name foodstore-u6-lab --network none \
  --label org.foodstore.lab=u6 \
  -v foodstore_u6_lab_data:/var/lib/postgresql/data \
  -v "$DIR_PRIVADO/auth:/run/foodstore-u6-auth:ro" \
  -e POSTGRES_PASSWORD_FILE=/run/foodstore-u6-auth/postgres_password \
  -e POSTGRES_INITDB_ARGS="--auth-local=scram-sha-256 --auth-host=scram-sha-256" \
  -e PGHOST=127.0.0.1 \
  -e PGPASSFILE=/run/foodstore-u6-auth/pgpass \
  sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3 -c log_connections=on

docker cp foodstore-u6-lab:/usr/local/bin/docker-entrypoint.sh - | tar -xO
```

Revisar el entrypoint antes de iniciar: lectura como root, cambio a postgres,
limpieza de `PGHOST` para init y eliminación de `PGPASSWORD` tras init.

```bash
docker start foodstore-u6-lab
docker logs foodstore-u6-lab
docker exec foodstore-u6-lab pg_isready -h 127.0.0.1
```

Esperar el mensaje `PostgreSQL init process complete` y la disponibilidad indicada
por `pg_isready`; esta última no sustituye las pruebas de autenticación.

### 3. Comprobar versión y autenticación (A, B y C)

Todos los accesos SQL de este ensayo usan la base auxiliar y el rol `postgres`.
No registrar contraseñas ni verificadores completos.

```bash
# A1 y A2
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -At -c "SELECT version()"
docker exec foodstore-u6-lab psql --version
docker exec foodstore-u6-lab pg_dump --version
docker exec foodstore-u6-lab pg_restore --version
docker exec foodstore-u6-lab createdb --version

# B1: identidad y extremos TCP
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT current_user, inet_client_addr(), inet_server_addr(), inet_server_port()"
# B2: reglas sin secretos
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT line_number, type, database, user_name, address, netmask, auth_method, error FROM pg_hba_file_rules ORDER BY line_number"
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT count(*) FILTER (WHERE auth_method = 'trust') AS trust_rules, count(*) AS total_rules FROM pg_hba_file_rules"
# B3: solo configuración y booleano, nunca el verificador
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SHOW password_encryption"
docker exec foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT rolname, rolpassword LIKE 'SCRAM-SHA-256\$%' AS scram_verifier FROM pg_authid WHERE rolcanlogin ORDER BY rolname"
# B4: contrastar las conexiones en el log del servidor
docker logs foodstore-u6-lab

# C1: sin archivo de contraseña; sin stdin ni solicitud interactiva
docker exec -e PGPASSFILE=/nonexistent/pgpass foodstore-u6-lab psql -X -w -h 127.0.0.1 -U postgres -d postgres -c "SELECT 1"
```

### 4. Comprobar identidades, permisos y aislamiento (I)

Inspeccionar solo nombres de variables, nunca sus valores ni el contenido de
archivos privados. Para el entorno de PID 1, usar el usuario SO postgres: el
intento inicial como root no tuvo permiso.

```bash
# I1 e I2
docker exec foodstore-u6-lab id
docker exec foodstore-u6-lab stat -c '%A %u:%g %n' /run/foodstore-u6-auth /run/foodstore-u6-auth/postgres_password /run/foodstore-u6-auth/pgpass
# I3, I4 e I5: registrar cada código de salida por separado
docker exec foodstore-u6-lab test -r /run/foodstore-u6-auth/pgpass
docker exec -u postgres foodstore-u6-lab test -r /run/foodstore-u6-auth/pgpass
docker exec foodstore-u6-lab test -e /root/.pgpass
# I6: solo nombres del entorno del contenedor
docker container inspect foodstore-u6-lab --format '{{range .Config.Env}}{{println .}}{{end}}' | cut -d= -f1 | sort
# I7: solo nombres del entorno del servidor
docker exec -u postgres foodstore-u6-lab sh -c "tr '\0' '\n' < /proc/1/environ | cut -d= -f1 | sort"
# I8: red, privilegios, puertos y montajes
docker container inspect foodstore-u6-lab --format 'net={{.HostConfig.NetworkMode}} privileged={{.HostConfig.Privileged}} ports={{json .HostConfig.PortBindings}}{{range .Mounts}} | {{.Destination}} rw={{.RW}}{{end}}'
```

Los montajes pueden revelar la ubicación privada al operador; no publicar esa
salida sin sustituir su origen por `<DIR_PRIVADO>/auth`. Comprobar también que no
haya socket Docker montado. Ninguna de estas comprobaciones requiere mostrar las
credenciales.

### 5. Ejecutar salud, respaldo y fallo controlado (D, E y F)

**Alcance histórico:** E y F se ejecutaron con la versión anterior de
`backup_foodstore.sh`, sin línea base (SHA-256 que empieza en `c3d812c5`). La
versión actual captura `validaciones.sql` antes de `pg_dump`. Sobre la base
auxiliar `postgres`, que no tiene las tablas canónicas, fallaría al capturar la
línea base con salida 1 y sin respaldo. Por eso estos pasos no reproducen E con la
versión actual; su prueba funcional requiere una base Food Store autorizada.

Desde la raíz del repositorio, con la variable anterior definida:

```bash
# D
docker exec -i foodstore-u6-lab psql -X -w -v ON_ERROR_STOP=1 -U postgres -d postgres -P pager=off -f - < unidades/unidad-6/health_check.sql

# Preparar los directorios ANTES de cualquier redirección de consola
mkdir -m 0700 "$DIR_PRIVADO/evidence/E_backup" "$DIR_PRIVADO/evidence/F_backup_fail"
# E
bash unidades/unidad-6/backup_foodstore.sh -c foodstore-u6-lab -d postgres -U postgres -o "$DIR_PRIVADO/evidence/E_backup/backups" -l "$DIR_PRIVADO/evidence/E_backup/logs"
```

Registrar el nombre producido en E; para el ensayo documentado fue
`postgres_20261104_231806.dump`. Sustituir `<ARCHIVO_DUMP_E>` por el archivo
producido en una nueva ejecución, sin asumir que conservará esa fecha.

```bash
DUMP_E='<ARCHIVO_DUMP_E>'
stat -c '%s %A' "$DUMP_E"
head -c 5 "$DUMP_E"
docker exec -i foodstore-u6-lab pg_restore --list < "$DUMP_E"

# F: confirmar primero que la base de fallo no existe (resultado requerido: 0)
docker exec foodstore-u6-lab psql -X -w -U postgres -d postgres -At -c "SELECT count(*) FROM pg_database WHERE datname='u6_lab_base_inexistente'"
# Si existe, detenerse; no borrarla
bash unidades/unidad-6/backup_foodstore.sh -c foodstore-u6-lab -d u6_lab_base_inexistente -U postgres -o "$DIR_PRIVADO/evidence/F_backup_fail/backups" -l "$DIR_PRIVADO/evidence/F_backup_fail/logs"
find "$DIR_PRIVADO/evidence/F_backup_fail/backups" -mindepth 1 -maxdepth 1 -print
```

Registrar por separado los códigos de salida de cada comando, los logs del
respaldo y las conexiones del servidor. F debe fallar: no presentarlo como error
del arnés ni como éxito de respaldo. No detener ni retirar recursos al finalizar
este procedimiento; se conservaron para la siguiente etapa.

## Comprobaciones y resultados

### Versiones y autenticación

| Prueba | Resultado observado | Salida |
|---|---|---|
| A1 | `SELECT version()`: PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) | 0 |
| A2 | `psql`, `pg_dump`, `pg_restore`, `createdb --version`: todos 17.11 (Debian 17.11-1.pgdg13+2) | 0 |
| B1 | `current_user=postgres`, cliente 127.0.0.1, servidor 127.0.0.1, puerto 5432 | 0 |
| B2 | 7 reglas HBA, todas `scram-sha-256`; `trust_rules=0` | 0 |
| B3 | `password_encryption=scram-sha-256`; verificador de postgres comienza con `SCRAM-SHA-256$` (solo booleano, sin mostrarlo) | 0 |
| B4 | Cada conexión de prueba autenticada registra `connection authenticated: identity="postgres" method=scram-sha-256 (pg_hba.conf:115)` | Evidencia de log |
| C1 | Sin pgpass: `fe_sendauth: no password supplied` | 2 |

Las siete reglas B2 son: local all, host 127.0.0.1/32, host ::1/128, tres reglas
local/host para replication y host all all all. Ninguna usa `trust`.

C1 no adjuntó stdin; `-w` impidió solicitar contraseña. No había `PGPASSWORD` en
el entorno del contenedor ni `/root/.pgpass`. El log mostró `connection received`
sin `authenticated`. Esto demuestra que el servidor exige contraseña por TCP
(`trust` habría aceptado); **no fue una prueba de contraseña incorrecta**.

### Identidades y aislamiento

| Prueba | Resultado observado |
|---|---|
| I1 | Usuario de exec: uid=0 (`root`) |
| I2 | Directorio `drwx------ 1000:1000`; archivos `-rw------- 1000:1000` |
| I3 | Root puede leer pgpass: exit 0 |
| I4 | Usuario SO postgres no puede leer pgpass: exit 1 |
| I5 | `/root/.pgpass` no existe: exit 1 |
| I6 | Solo nombres: sin `POSTGRES_PASSWORD` ni `PGPASSWORD`; presentes `POSTGRES_PASSWORD_FILE`, `PGHOST`, `PGPASSFILE`, `POSTGRES_INITDB_ARGS` |
| I7 | Entorno de PID 1, solo nombres: sin `POSTGRES_PASSWORD`, `POSTGRES_PASSWORD_FILE` ni `PGPASSWORD`; intento inicial como root con `Permission denied` sobre `/proc/1/environ`, repetido como usuario SO postgres |
| I8 | `net=none`, `privileged=false`, `ports={}`, montaje de auth `rw=false`; sin socket Docker |

### Salud (D)

El comando D terminó con **exit 0**. El log del servidor confirmó TCP + SCRAM.

| Control | Resultado observado |
|---|---|
| 1 | Tamaño 7689907 bytes (7510 kB) |
| 2a | `numbackends=1`, conexiones cliente del clúster=1, `max_connections=100`, cache hit=93.49 % |
| 2b | Una sesión `active`: el propio chequeo; este control no la excluye |
| 3a | `track_counts=on`, `autovacuum=on` |
| 3b | 0 filas: `postgres` no tiene tablas de usuario; no es un fallo |
| 4 | 0 filas, resultado válido; excluye la propia sesión |

Estos valores son una observación puntual de una base auxiliar sin datos de
Food Store. `health_check.sql` **no implementa semáforo VERDE/AMARILLO/ROJO ni
umbrales**; la SPEC menciona AMARILLO/ROJO pero ningún documento define sus
umbrales. La interpretación se registra aparte; su definición sigue pendiente.

`START TRANSACTION READ ONLY` … `ROLLBACK` es una protección, no una garantía
absoluta. PostgreSQL rechaza INSERT/UPDATE/DELETE/MERGE/COPY FROM sobre tablas no
temporales, CREATE/ALTER/DROP, COMMENT, GRANT, REVOKE, TRUNCATE y `nextval` sobre
secuencias permanentes. No bloquea escrituras en tablas temporales ni funciones
con efectos fuera de la transacción, como `pg_terminate_backend`,
`pg_cancel_backend` o `pg_stat_reset`. La garantía real depende de revisar el
contenido del archivo; no se probaron esos efectos en este ensayo.

`age(backend_xmin)` del control 4 es un indicador de diagnóstico: un valor alto
sugiere una sesión con instantánea antigua que puede impedir a VACUUM eliminar
tuplas muertas. No lo prueba por sí solo. Otros retenedores del horizonte
(slots de replicación, transacciones preparadas, feedback de standby) no están
cubiertos por `health_check.sql`.

### Respaldo legible (E) y base inexistente (F)

**E:** script con exit 0. Archivo `postgres_20261104_231806.dump`, 1109 bytes,
modo `-rw-------`, cabecera `PGDMP`. El log contiene `PG_DUMP_INICIO`,
`PG_DUMP_FIN exit=0`, tamaño, `pg_restore --list: archivo legible` y
`RESULTADO=OK`.

La lectura independiente mediante `docker exec -i … pg_restore --list` terminó
con exit 0: Format CUSTOM, TOC Entries 5, generado desde/por 17.11, sin objetos de
usuario seleccionables. Es esperable en esta base auxiliar vacía.
**Legibilidad no equivale a restauración.**

**F:** primero se confirmó que
`SELECT count(*) FROM pg_database WHERE datname='u6_lab_base_inexistente'`
devuelve 0. El mismo script, con esa base y directorios separados
`F_backup_fail/{backups,logs}`, terminó con exit 1. El log contiene:

- `FATAL: database "u6_lab_base_inexistente" does not exist`, después de
  autenticación SCRAM registrada por el servidor.
- `PG_DUMP_FIN exit=1`.
- `archivo temporal eliminado: ….dump.partial`.
- `RESULTADO=FALLO exit=1`.

El directorio de respaldos quedó vacío, sin `.dump` ni `.partial`. Este resultado
solo cubre el fallo ensayado, no interrupciones ni ejecuciones concurrentes.

## Incidencias del arnés

El primer intento de E y F **no ejecutó los comandos**: la redirección de consola
apuntaba a `E_backup/` y `F_backup_fail/`, todavía inexistentes. Bash no pudo abrir
el archivo y omitió los comandos. Se verificó que ninguno de los dos directorios
existía y que el servidor no recibió conexiones de respaldo. Se repitieron los
intentos tras crear los directorios, sin cambiar los scripts. Los resultados E/F
anteriores corresponden a esa repetición, no a los intentos omitidos.

Algunos archivos de evidencia (copia del entrypoint, `tests/`, las tres copias de
logs del servidor y `E_backup/independent_pg_restore_list.txt`) se crearon desde
shells sin `umask 077`: modos 664/775 dentro del directorio privado 0700. **No se
modificaron sus permisos.** Los respaldos, logs y consolas de D/E/F tienen 0600/0700. El procedimiento reproducible
anterior aplica `umask 077` desde el inicio como precaución para nuevas ejecuciones,
no como descripción de una corrección realizada sobre la evidencia existente.

### Evidencia complementaria

Tras la verificación independiente, que señaló observaciones de consola sin archivo
propio, se agregó `<DIR_PRIVADO>/evidence/supplement/` sin conectarse a la base:

- `S1`: modo `-rw-------`, 1109 bytes y cabecera `PGDMP` del dump de E;
  contenido de `F_backup_fail/` sin `.dump` ni `.partial`.
- `S2`: modos de los archivos de evidencia, excepto los de `supplement/`.
- `S3`: transcripción literal del diagnóstico de consola del intento omitido de
  E/F y de la comprobación posterior, con una anotación marcada como agregada
  después.
- `S4`: búsqueda de la contraseña de inicialización como cadena fija en la
  evidencia, en `unidades/unidad-6` y en `docker logs`. Solo imprime nombres de
  archivo o conteos: sin coincidencias.

## Cambios posteriores a la prueba

La evidencia anterior se conserva sin modificaciones y corresponde a la versión de
`backup_foodstore.sh` con SHA-256 que empieza en `c3d812c5`, todavía sin línea
base. Después de la prueba:

- `backup_foodstore.sh` captura la línea base con `validaciones.sql` antes de
  `pg_dump` y genera `BASE_AAAAMMDD_HHMMSS.baseline`. Después se ensayó con el
  núcleo canónico; véase el [ensayo funcional](ensayo_funcional.md). **En la fecha
  de este registro, esta versión todavía no había sido probada
  funcionalmente.**
- Se crearon `validaciones.sql`, `maintenance.sql` y `restore_test.sh`. En la fecha
  de este registro estaban pendientes de prueba funcional; después se ensayaron con
  el núcleo canónico (véase el [ensayo funcional](ensayo_funcional.md)).
- En `health_check.sql` solo cambió el comentario inicial: READ ONLY se describe
  como protección complementaria a la revisión del SQL. Ninguna consulta cambió,
  pero el archivo ya no es idéntico byte a byte al ejecutado en D.

Los scripts Bash nuevos o modificados pasaron `bash -n` y revisión estática, que
no son pruebas funcionales. La versión y las herramientas del laboratorio
(PostgreSQL 17.11) siguen comprobadas según las pruebas A anteriores.

## Límites y pendientes

- Validación del TP6 con datos Food Store, captura de línea base y restauración:
  pendientes. No se cargaron sus componentes ni se demostró su restaurabilidad.
- RPO y RTO no medidos. RPO 24 h y RTO 20 min siguen como propuestas pendientes de
  aprobación (EA-1), no requisitos docentes ni resultados alcanzados.
- Nombres Food Store pendientes (CD-1); decisiones CD-2/CD-3 no resueltas por este
  ensayo. El rol superusuario `postgres` no está aprobado como rol definitivo de
  respaldo; identidades por tarea pendientes (EP-4).
- `maintenance.sql` y `restore_test.sh`: implementado; pendiente de prueba
  funcional con Food Store. `informe_u6.pdf` pendiente; T6 no completada.
  `pg_cron` no comprobado (EP-6/VE-2).
- No se probaron contraseña incorrecta, interrupción con Ctrl-C ni ejecuciones
  concurrentes.
- Semáforo y umbrales de salud sin implementar. El chequeo registra métricas y
  los colores no son un requisito bloqueante; los umbrales quedan como mejora.
- El comentario inicial de `health_check.sql` decía «cualquier escritura
  accidental falla» y ya fue corregido en el bloque posterior (véase la sección
  anterior).
- La propiedad y los permisos de la restauración dependen del modo `-m` de
  `restore_test.sh`. La decisión sigue pendiente (CD-3, EA-4).
- Las credenciales permanecen en texto plano en archivos 0600 del disco del host,
  condición de laboratorio, sin aprobación como mecanismo definitivo.
- Los logs de Docker contienen registros de conexión, sin secretos. Evidencias y
  dumps permanecen fuera del repositorio, en `<DIR_PRIVADO>/evidence`; no se
  publica la ubicación real ni el contenido de credenciales.
