# Design — Unidad 6: Mantenimiento, respaldo y recuperación

**Trabajo Práctico — Unidad 6 / Semana 10**
Base de Datos II — UTN
**Integrantes:** Avalos Pablo, Blangetti Sofia, Suarez Ismael
**Motor objetivo:** PostgreSQL 16+

> Scripts implementados. Primer ensayo funcional del núcleo canónico satisfactorio,
> según las evidencias de la corrida; pendiente la comprobación docente. La versión
> y las herramientas del laboratorio se comprobaron en la etapa anterior; esa
> prueba de infraestructura sobre `postgres` usó una versión anterior de
> `backup_foodstore.sh`. No es validación del TP6 ni demuestra la restauración de
> Food Store. Procedimiento y evidencia previa: [laboratorio](../docs/laboratorio.md).
> Ensayo técnico posterior con el núcleo canónico, que no es la comprobación
> docente: [ensayo funcional](../docs/ensayo_funcional.md).

---

## 1. Flujo de trabajo

```
línea base → respaldo → restauración → validaciones → evidencias
```

### 1.1 Línea base

Antes de iniciar `pg_dump`, `backup_foodstore.sh` ejecuta `validaciones.sql`:
conteos exactos por tabla (incluidas las bajas lógicas), bajas lógicas por tabla
y controles de productos y detalles inválidos. Si la captura falla o un control no
es cero, no genera respaldo. La línea base no incluye suma de totales: el
requisito vigente son conteos y controles.

El laboratorio requiere una ventana sin escrituras durante la captura de la línea
base y el respaldo, porque ambos usan instantáneas distintas. El script no
garantiza ni impone esa ventana; la organiza el operador. Es una recomendación del
equipo, no una exigencia literal del TP.

### 1.2 Respaldo

`pg_dump -Fc` con fecha y hora en el nombre del archivo. El script registra la marca
de inicio de `pg_dump` en un log. Si `pg_dump` falla, registra el error y finaliza
con código distinto de cero. Sin contraseñas en el script; autenticación
desatendida con un archivo de formato pgpass (permiso 0600), seleccionado dentro
del contenedor mediante `PGPASSFILE=/run/foodstore-u6-auth/pgpass`, no desde el
`~/.pgpass` del host. `PGHOST=127.0.0.1`
fija TCP al puerto 5432 también para el script sin opción `-h`. Los clientes se
ejecutan por `docker exec` como usuario SO `root`, con el rol PostgreSQL
`postgres`, solo para la prueba de infraestructura (véase §2.2).

### 1.3 Restauración

Restaurar el último respaldo en una base descartable. Si la base de restauración ya
existe, detenerse; no borrarla ni sobrescribirla automáticamente. RTO: cronómetro
desde inmediatamente antes de `createdb` del destino hasta terminar las validaciones.

### 1.4 Validaciones

- Conteos de filas por tabla coincidentes con la línea base.
- Productos con `precio < 0 OR stock < 0` = 0.
- Detalles con `cantidad <= 0 OR precio_unitario < 0` = 0.
- Los controles fallidos no se presentan como éxito.

### 1.5 Evidencias

El informe registra fecha y hora del respaldo utilizado, tiempo total de
restauración y validación, RPO y RTO observados (separados del cumplimiento de
metas), resultado de las validaciones, problema real encontrado si lo hubo, y una
mejora concreta para la siguiente ejecución.

---

## 2. Entorno

### 2.1 Inventario reportado por Claude

Información reportada por Claude en sesión de análisis, no una inspección nueva:

- Sistema operativo: Ubuntu 26.04.1 LTS.
- Shell: Bash disponible.
- Clientes PostgreSQL (`psql`, `pg_dump`, `pg_restore`, `createdb`, `dropdb`): no
  encontrados en el PATH del host.
- Docker: disponible. Imagen local `postgres:17` presente.
- Contenedores identificados como Food Store: ninguno.
- Contenedores y volúmenes existentes: ajenos a U6; no se reutilizan.

### 2.2 Infraestructura creada y primera prueba

El 2026-11-04 (-03:00) se creó el contenedor aislado `foodstore-u6-lab` con volumen
`foodstore_u6_lab_data`, red `none` y sin puertos publicados. Se utilizó la imagen
local `postgres:17`, id
`sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`.
Servidor y clientes: 17.11 (Debian 17.11-1.pgdg13+2). Quedó en ejecución para la
siguiente etapa. El inventario de §2.1 es el antecedente, no el estado actual.

El operador SO del host ejecuta Docker/Bash; `psql`, `pg_dump` y `pg_restore`
corren por `docker exec` como usuario SO `root` (uid 0). El servidor corre como
usuario SO `postgres` (uid 999). El rol PostgreSQL `postgres` es distinto de los
usuarios SO: se usa aquí para preparación y prueba de infraestructura y no queda
aprobado como rol definitivo de respaldo de Food Store (EP-4 pendiente).

`PGHOST=127.0.0.1` y `PGPASSFILE=/run/foodstore-u6-auth/pgpass` seleccionan TCP
127.0.0.1:5432 y el archivo de formato pgpass. `<DIR_PRIVADO>/auth`, externo al
repositorio, tiene modo 0700 y archivos 0600 del operador, montados en solo
lectura. Docker no es rootless ni usa userns-remap: `root` del contenedor puede
leerlos por su capacidad; el usuario SO `postgres` no puede. La contraseña de
inicialización se suministró mediante `POSTGRES_PASSWORD_FILE`: el entrypoint
la lee como root antes de pasar a postgres, limpia `PGHOST` para inicializar y
elimina `PGPASSWORD` después de la inicialización. Todas las reglas HBA son
SCRAM, sin `trust`; una conexión exitosa por sí sola no demuestra esto.
Las comprobaciones y límites constan en [laboratorio](../docs/laboratorio.md).

No se cargaron base Food Store, schema/seed, objetos TPI, roles U5, vistas U3 ni
`pgcrypto`: no estaban autorizados.

### 2.3 Pendientes del entorno

| # | Pendiente |
|---|---|
| EP-1 | Resuelto: imagen local identificada en §2.2; servidor, psql, pg_dump, pg_restore y createdb 17.11 (Debian 17.11-1.pgdg13+2) |
| EP-2 | Parcial: contenedor y volumen creados; bases Food Store y roles pendientes de autorización y preparación |
| EP-3 | Nombres de bases: decisión del equipo del 2026-11-05, `foodstore` / `foodstore_restore_test` / administrativa `postgres`; sin confirmación docente (CD-1) |
| EP-4 | Identidades ejecutoras: el equipo usa `postgres` solo en el laboratorio académico aislado; no hay roles operativos definitivos de respaldo, monitoreo ni restauración |
| EP-5 | Configuración necesaria para reproducir la comprobación docente (roles de U5, vistas de U3, pgcrypto, objetos TPI) |
| EP-6 | Disponibilidad de `pg_cron` en el contenedor (VE-2): no comprobada |

---

## 3. Diseño y estado de los scripts

`validaciones.sql`, `backup_foodstore.sh`, `health_check.sql`,
`maintenance.sql` y `restore_test.sh` están implementados y se ensayaron con el
núcleo canónico en el [ensayo funcional](../docs/ensayo_funcional.md), con las
huellas SHA-256 que allí constan.

- **`restore_test.sh`:** después del ensayo se le agregó `-a` (de `fd7dde44…` a
  `68031b1f…`) y esa versión se probó aparte, en la
  [corrección de la restauración](../docs/correccion_restauracion.md). Solo se
  ensayó en el modo `sin-propietarios`, y su comentario inicial ahora remite a
  ambos documentos. Después se cambió solo la frase sobre las metas (`973223df…`):
  ahora indica que la comparación con los objetivos está en el informe y en la
  SPEC. Esa versión se usó en la verificación posterior de los bloques finales,
  descrita en el [ensayo de evaluación](../docs/ensayo_evaluacion.md).
- **`backup_foodstore.sh` y `maintenance.sql`:** sus comentarios iniciales todavía
  dicen que no se probaron. Se conservan sin cambios para no alterar las huellas
  ensayadas; el estado vigente es el de esta documentación.

`informe_u6.pdf` está generado, en una página, con los datos del ensayo de
evaluación; su revisión docente está pendiente. El contrato y las tareas constan en
[SPEC_U6.md](../SPEC_U6.md) y [tasks.md](tasks.md).

### 3.1 `backup_foodstore.sh`

- `pg_dump -Fc` con fecha y hora en el nombre del archivo.
- Log con marca de inicio y fin.
- Si `pg_dump` falla: registrar error, exit code distinto de cero.
- Autenticación con archivo de formato pgpass; sin contraseñas en el script.
  En el laboratorio, `PGPASSFILE` y `PGHOST` del contenedor permiten a `pg_dump`
  (sin opción `-h`) usar TCP 127.0.0.1:5432 y SCRAM como rol PostgreSQL `postgres`;
  el cliente corre como usuario SO `root`, no como el usuario SO del servidor.
- Línea base previa a `pg_dump` (§1.1). El archivo `BASE_AAAAMMDD_HHMMSS.baseline`
  comparte nombre base con `BASE_AAAAMMDD_HHMMSS.dump` y registra `run`, contenedor,
  base, usuario, `archivo_respaldo`, `sha256_respaldo`, `linea_base_inicio` y
  `linea_base_fin`, `pg_dump_inicio` y `pg_dump_fin`. Después de `[validaciones]`
  incluye las 12 líneas `clave|valor`. Ambos se publican con `ln` desde temporales
  exclusivos, sin sobrescribir. Si falla el enlace del respaldo, se retira el
  `.baseline` creado por esa ejecución.
- Prueba de infraestructura de la versión anterior (sin línea base): respaldo de
  `postgres` y lectura con `pg_restore --list` exitosos; fallo ante base
  inexistente sin dejar `.dump` ni `.partial`. La versión actual se ejecutó en el
  ensayo funcional del núcleo canónico, con exit 0 y una línea base
  correspondiente al respaldo.
- SHA-256 se usa para asociar el respaldo con su línea base. La retención sigue
  fuera del alcance; no hay borrado automático.

### 3.2 `health_check.sql`

Consulta, no instala objetos. Cuatro controles: tamaño, conexiones, estado de
tablas, consultas activas (`state <> 'idle'`, que incluye `active` e
`idle in transaction`). El control 2b incluye la sesión del propio chequeo; el
control 4 la excluye. Cero filas en el control 4 es un resultado válido. La primera
prueba sobre `postgres` terminó con exit 0; no había tablas de usuario.

No implementa semáforo VERDE/AMARILLO/ROJO ni umbrales: registra métricas y la
interpretación se hace aparte. La SPEC lo describe como registro de métricas sin
semáforo; una clasificación por colores no es requisito bloqueante y la definición
de sus umbrales queda como mejora pendiente.

`START TRANSACTION READ ONLY` … `ROLLBACK` es una protección, no una garantía
absoluta. PostgreSQL rechaza INSERT/UPDATE/DELETE/MERGE/COPY FROM sobre tablas no
temporales, CREATE/ALTER/DROP, COMMENT, GRANT, REVOKE, TRUNCATE y `nextval` sobre
secuencias permanentes. No impide escrituras en tablas temporales ni funciones
con efectos fuera de la transacción, como `pg_terminate_backend`,
`pg_cancel_backend` o `pg_stat_reset`. La garantía real depende de revisar el
contenido del archivo. El comentario inicial ya la describe como protección
complementaria a la revisión del SQL; ninguna consulta cambió.

`age(backend_xmin)` del control 4 es un indicador de diagnóstico: un valor alto
sugiere que la sesión mantiene una instantánea antigua que puede impedir a VACUUM
eliminar tuplas muertas; no lo prueba por sí solo. El chequeo no cubre otros
retenedores del horizonte, como slots de replicación, transacciones preparadas o
feedback de servidores standby.

### 3.3 `maintenance.sql`

Parte 1, siempre: diagnóstico de solo lectura sobre `pg_stat_user_tables` del
esquema `public` (estimaciones de filas vivas y muertas, `n_mod_since_analyze`,
fechas y contadores de vacuum y analyze, `reloptions`) y parámetros de
autovacuum. No hay umbrales ni decisión automática.

Parte 2, solo con `-v tabla_mantenimiento=<tabla> -v confirmar_analyze=on
-v justificacion='<texto>'`. Valida que la tabla sea una de las cinco canónicas,
que la autorización sea verdadera y que la justificación no esté vacía. Registra
selección, justificación, ejecutor y estado previo, y ejecuta solo
`ANALYZE VERBOSE public.<tabla>`. Sin variables, termina en el diagnóstico con
salida 0. Una selección incompleta o inválida termina con error, sin actuar.

Parte 3: comprobación posterior de la misma fila, que es una observación y no una
prueba de mejora. La justificación real la registra el operador al ejecutar. Se
eligió ANALYZE puntual sobre VACUUM; no hay `VACUUM FULL`, `REINDEX`, archivado,
`ALTER SYSTEM` ni `pg_cron`.

### 3.4 `restore_test.sh` (opcional)

Interfaz: `-c CONTENEDOR -U USUARIO -a BASE_ADMINISTRATIVA -s BASE_ORIGEN
-d BASE_DESTINO -f RESPALDO.dump -b RESPALDO.baseline -m MODO -o DIR_RESULTADOS`,
todos obligatorios y sin valores por defecto.

**Bases que participan:**

- `-a`: debe existir y ser distinta del origen y del destino. Es la única base a la
  que se conecta antes de crear el destino: consulta `pg_database` y la usa como
  `--maintenance-db` de `createdb`.
- `-s`: no necesita existir. Se usa solo para comparar con el `.baseline`, rechazar
  un destino igual y dejar trazabilidad.
- Destino: las validaciones posteriores consultan solo esta base y la comparan con
  la línea base conservada.

Hasta la [corrección de la restauración](../docs/correccion_restauracion.md), esas
dos conexiones usaban el origen.

Antes de escribir en PostgreSQL:

- Valida el `.baseline`: metadatos, 12 filas ordenadas, `base` igual al origen,
  `archivo_respaldo` igual al respaldo y SHA-256 coincidente.
- Rechaza un destino igual al origen o protegido (`postgres`, `template0`,
  `template1`).
- Comprueba que el destino no exista; si existe, se detiene sin borrarlo.
- Lista el respaldo con `pg_restore --list`.

Registra la antigüedad desde `pg_dump_inicio`, no desde el `mtime`. La medición
empieza inmediatamente antes de `createdb --template=template0`. La restauración
usa `pg_restore --exit-on-error --single-transaction`. Después ejecuta
`validaciones.sql` en el destino, aplica `diff -u` contra la línea base y exige los
controles en cero. La medición termina cuando las validaciones resultan correctas.

Modo `-m`:

- `sin-propietarios` (`--no-owner --no-privileges`): valida datos. **No** recupera
  propietarios, ACL ni la seguridad de U5, y cambia los privilegios efectivos de
  las funciones SECURITY DEFINER (EA-4).
- `conservar-propietarios`: aplica propietarios y permisos del respaldo; requiere
  roles existentes y permiso del rol restaurador para asignarlos. No valida
  equivalencia con U5.

Ninguno de los dos modos restaura roles globales, y la elección no resuelve CD-3.

Cada ejecución escribe en un directorio propio
`restore_<destino>_<AAAAMMDD_HHMMSS>`: log, listado, salida de `pg_restore`,
validaciones de origen y destino, `comparacion.diff` y `resumen.txt`. Ante un fallo
sale con código distinto de cero, conserva el diagnóstico, informa el tiempo hasta
el fallo como no-RTO y no borra el destino. No evalúa metas RPO/RTO.

---

## 4. RPO/RTO

| Objetivo | Meta (adoptada por el equipo el 2026-11-05) | Medición |
|---|---|---|
| RPO | 24 h | Antigüedad del respaldo: marca de inicio de `pg_dump` al momento del simulacro. No representa datos efectivamente perdidos. |
| RTO | 20 min | Cronómetro desde inmediatamente antes de `createdb` del destino hasta fin de validaciones |

Las metas son del equipo, no exigencias ni aprobaciones del docente. Los valores
medidos y su comparación con las metas se registran por corrida; la primera
comparación está en el [ensayo de evaluación](../docs/ensayo_evaluacion.md).
