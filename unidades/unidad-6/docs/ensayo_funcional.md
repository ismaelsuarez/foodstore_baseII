# Ensayo funcional U6 — núcleo canónico de Food Store

**Fecha:** 2026-11-05 (hora local -03:00). **Laboratorio:** contenedor
`foodstore-u6-lab`, PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2).

**Este ensayo es técnico y cubre solo el núcleo canónico** (schema, seed y objetos
TPI). No es la comprobación definitiva del docente ni la recuperación integral de
U5. Los nombres `u6_ensayo_origen`, `u6_ensayo_restauracion` y `u6_ensayo_rechazo`
son exclusivos del ensayo y no resuelven CD-1. Se usó el rol `postgres` y el modo
`sin-propietarios` solo para esta corrida. Ninguno queda aprobado como definitivo y
el modo `conservar-propietarios` no se validó.

Las evidencias completas (logs, dump, línea base, copia alterada y salidas)
permanecen fuera del repositorio, en `<DIR_PRIVADO>/ensayo_20261105_130238/`
(en adelante `<RUN>`). Las evidencias de la prueba de infraestructura anterior no
se modificaron.

El repositorio versiona un extracto sin secretos ni filas personales, en
[../evidencias/ensayo_canonico_20261105.txt](../evidencias/ensayo_canonico_20261105.txt).
Copia líneas literales de la evidencia e indica el archivo de procedencia de cada
bloque.

## Versiones de los archivos ejecutados

| Archivo | SHA-256 |
|---|---|
| `schema.sql` | `d5cbb990c76ecc085c44736e877d3fc9d993a734ecc137120679ff3706e8a108` |
| `datos_iniciales.sql` | `ab983fbe7547793bc9fa5483c6254cee0d7c4b1363ba12f8b67ad3577327565f` |
| `tpi/sql/objetos_programables.sql` | `9696a32e8edf56a5bdf23a30eda3bd589cedb0a1b00a382e63969bf3386aa6c4` |
| `unidades/unidad-6/validaciones.sql` | `e4afea968f84dc721ecd7bf084630fe73de632d7c0b54e555c82548e28112eba` |
| `unidades/unidad-6/backup_foodstore.sh` | `3b8e39c80b6bdfdd96da620a42f820230d79a6ace3ba3a076fa4be5123a44b52` |
| `unidades/unidad-6/restore_test.sh` | `fd7dde44a0980b9f9c442735e55907ce7ab5034f58d2df8d3c1d5f226d58a426` |
| `unidades/unidad-6/health_check.sql` | `ed2644efc13b06b6dacddc9a7f784331a6877bd4fca3fe5ff84c9a63a26ec3c7` |
| `unidades/unidad-6/maintenance.sql` | `f5e6bd2a07512bf318631401bc7bcc781da55381b49c1b2c4085f6595db0bbcd` |

**Registro de las huellas:**

- Al terminar la corrida se guardaron en `<RUN>/06_estado_final/estado.txt`, y
  coinciden con los archivos versionados de este hito.
- Al inicio solo quedó guardada en archivo la de `validaciones.sql`
  (`<RUN>/01_origen/sha256_archivos.txt`). Las de los demás scripts se observaron
  en la consola de la sesión, sin archivo propio.

Los comentarios iniciales de `backup_foodstore.sh`, `restore_test.sh` y
`maintenance.sql` todavía dicen que no se probaron funcionalmente. Se conservaron
sin cambios para no alterar las huellas ensayadas; el estado vigente es el que
consta en este documento.

## Comprobaciones previas

- Rama `feat/u6-mantenimiento`, HEAD `f4207d7`; cambios de U6 sin versionar.
- **Contenedor detenido al comenzar:** `exited`, código 0, con un apagado
  ordenado registrado por PostgreSQL (`fast shutdown`) a las 00:35 locales. El host
  se reinició a las 08:11 y la política de reinicio es `no`. Con autorización
  explícita del equipo se ejecutó solo `docker start foodstore-u6-lab`: no se
  recreó el contenedor ni se tocaron el volumen o la autenticación.
- Tras iniciarlo se comprobó lo siguiente:
  - mismo id `2625b25f320c…` e imagen `sha256:2d2b8998…f9e3`;
  - `--network none`, sin puertos, no privilegiado y montaje de autenticación en
    solo lectura;
  - servidor y clientes 17.11;
  - 0 de 7 reglas HBA `trust`, y conexiones `method=scram-sha-256` en el log.
- Bases existentes: solo `postgres`, `template0` y `template1`. Las tres bases del
  ensayo estaban ausentes.

## 1. Instalación y ensayo canónico

| Prueba | Resultado esperado | Observado | Código | Evidencia |
|---|---|---|---|---|
| Crear origen | `createdb -w -U postgres u6_ensayo_origen` | Base creada | 0 | `<RUN>/01_origen/1_createdb.txt` |
| `schema.sql` | Instalación con `-1`, `ON_ERROR_STOP=1` | Sin errores | 0 | `01_origen/2_schema.txt` |
| `datos_iniciales.sql` | Sin `-1`; el seed administra su transacción | Sin errores | 0 | `01_origen/3_seed.txt` |
| `objetos_programables.sql` | Instalación con `-1` | Sin errores | 0 | `01_origen/4_objetos.txt` |
| Inventario del origen | Núcleo canónico | 5 tablas, 7 rutinas, 5 triggers, 3 ENUM, 11 índices, 18 restricciones; solo `plpgsql`; ninguna rutina SECURITY DEFINER | 0 | `01_origen/6_inventario_origen.txt` |
| `validaciones.sql` en el origen | 12 claves; controles en 0 | categoria 2, usuario 3, producto 3, pedido 5, detalle_pedido 7; `eliminados.*` 0; ambos controles 0 | 0 | `01_origen/5_validaciones_origen.txt` |
| Sesiones previas al respaldo | Sin escritores | 0 sesiones cliente en el origen (contenedor sin red) | 0 | `02_respaldo/0_sesiones_previas.txt` |
| `backup_foodstore.sh` sobre el origen | `.dump` y `.baseline` definitivos | `RESULTADO=OK`, `u6_ensayo_origen_20261105_131427.{dump,baseline}` | 0 | `02_respaldo/1_backup_consola.txt`, `02_respaldo/logs/backup_foodstore.log` |
| Correspondencia dump/línea base | Mismo nombre y SHA-256 | `archivo_respaldo` y `sha256_respaldo` (`13211d6b…5b4b`) coinciden con el dump | — | `02_respaldo/2_comprobaciones.txt` |
| Línea base | 12 claves, controles 0, captura antes de `pg_dump` | 12 líneas iguales a la validación del origen; `linea_base_fin` = `pg_dump_inicio` = 13:14:28 | — | `.baseline`, `2_comprobaciones.txt` |
| Archivos de la corrida | Modo 0600, sin temporales residuales | dump 26546 B y baseline 759 B, ambos `-rw-------`, cabecera `PGDMP`, 0 `.partial`, sin stderr de herramientas en el log | — | `2_comprobaciones.txt` |
| `pg_restore --list` independiente | Archivo legible | 54 entradas TOC: 5 tablas, 7 rutinas, 5 triggers, generado desde y por 17.11 | 0 | `02_respaldo/3_pg_restore_list.txt` |
| `restore_test.sh` (sin-propietarios) | Restauración validada | `RESULTADO=RESTAURACION_VALIDADA`; destino creado por el script | 0 | `03_restauracion/1_restore_consola.txt`, `resultados/restore_u6_ensayo_restauracion_20261105_131454/` |
| Opciones de `pg_restore` | Registradas con su alcance | `-w --username=postgres --dbname=u6_ensayo_restauracion --exit-on-error --single-transaction --no-owner --no-privileges` | — | `resumen.txt`, `restore_test.log` |
| Comparación con la línea base | `diff` vacío | `comparacion.diff` de 0 bytes; ambos controles en 0 en el destino | — | `validaciones_destino.txt`, `comparacion.diff` |
| Tiempo observado | Desde antes de `createdb` hasta el fin de las validaciones | 0,312 s (13:14:54 → 13:14:54) | — | `resumen.txt` |
| Antigüedad del respaldo | Desde `pg_dump_inicio` | 26 s al iniciar la restauración | — | `resumen.txt` |
| Origen sin cambios tras la restauración | Igual a la línea base | `validaciones.sql` del origen idéntica a la línea base | 0 | `03_restauracion/2_validaciones_origen_post.txt` |
| Huella por tabla | Origen igual a destino | md5 de las filas ordenadas por `id`, por tabla, idéntico en las cinco tablas | 0 | `03_restauracion/3_huella_{origen,destino}.txt` |
| Inventario del destino | Mismos objetos | Mismo conjunto de tablas, rutinas, triggers y resumen; propietario `postgres` | 0 | `03_restauracion/4_inventario_destino.txt`, `4b_inventario_diff_ordenado.txt` |

**Lectura de los resultados:**

- **Tiempo y antigüedad:** 0,312 s y 26 s son mediciones de este ensayo con el seed
  mínimo. No evalúan las metas RPO 24 h y RTO 20 min, que siguen pendientes de
  aprobación (EA-1). La antigüedad del respaldo no representa una pérdida efectiva
  de datos.
- **Huella por tabla:** compara la representación textual de cada fila sin
  mostrar valores. No verifica propietarios, privilegios, estadísticas, secuencias
  ni el estado de las identidades, y no reemplaza una comparación columna por
  columna de tipos o restricciones.
- **Seguridad:** el modo `sin-propietarios` no recupera propietarios, ACL ni la
  seguridad de U5. En este núcleo los objetos ya pertenecían a `postgres` y no
  había rutinas SECURITY DEFINER, así que esta prueba no ejerce ese efecto.

## 2. Pruebas negativas

| Prueba | Resultado esperado | Observado | Código | Evidencia |
|---|---|---|---|---|
| A. Destino existente (`u6_ensayo_restauracion`) | Rechazo sin borrar ni alterar | `el destino ya existe; no se borra ni se sobrescribe`, etapa `ausencia_destino`; huella del destino y OID de la base iguales antes y después | 2 | `<RUN>/04_negativas/A/` |
| B. Destino igual al origen | Rechazo sin tocar la fuente | `el destino no puede ser igual al origen`, etapa `parametros`; sin directorio de resultados; huella del origen sin cambios | 2 | `04_negativas/B/` |
| C. Dump alterado con la línea base original | Rechazo antes de crear `u6_ensayo_rechazo` | Copia con 1 byte cambiado (offset 2000, 0x3d → 0xff) y el mismo nombre de archivo: `SHA256 del respaldo distinto de la línea base`, etapa `linea_base`; `u6_ensayo_rechazo` ausente antes y después | 2 | `04_negativas/C/` |
| Archivos originales | Sin cambios | SHA-256 del dump y del `.baseline` originales iguales antes y después de las negativas | — | `04_negativas/0_sha_originales_{antes,despues}.txt` |

En C, el log del servidor no registra conexiones entre el inicio y el fin de la
ejecución del script: el rechazo ocurrió antes de contactar a PostgreSQL. Un
primer conteo de 8 conexiones usaba una ventana de un segundo que incluía A, B y
las consultas de comprobación; la atribución consta en
`04_negativas/C/atribucion_conexiones.txt`.

## 3. Salud y mantenimiento

| Prueba | Resultado esperado | Observado | Código | Evidencia |
|---|---|---|---|---|
| `health_check.sql` en el origen | Ejecución sin errores | 8014 kB, 1 conexión (la propia), `autovacuum` y `track_counts` en `on`, 5 tablas, control 4 con 0 filas | 0 | `05_salud_mantenimiento/1_health_origen.txt` |
| `health_check.sql` en la restauración | Ejecución sin errores | 7942 kB, 1 conexión, 5 tablas, control 4 con 0 filas | 0 | `2_health_restauracion.txt` |
| `maintenance.sql` sin variables (restauración) | Solo diagnóstico | `solo diagnóstico; no se ejecutó ninguna acción` | 0 | `3_maintenance_diagnostico_restauracion.txt` |
| `maintenance.sql` con selección (restauración, `detalle_pedido`) | `ANALYZE` puntual registrado | Justificación y estado previo registrados; `ANALYZE VERBOSE`: 1 de 1 página, 7 filas vivas y 0 muertas; después, `last_analyze` registrado y `n_mod_since_analyze` 0 | 0 | `5_maintenance_analyze_detalle_pedido.txt` |
| Conteos y contenido tras `ANALYZE` | Sin cambios | Validaciones iguales a la línea base; huella del destino idéntica | 0 | `6_huella_restauracion_despues.txt`, `7_validaciones_restauracion_post.txt` |
| Estadísticas del planificador | `detalle_pedido` con estadísticas | `pg_stats` con 8 columnas de `detalle_pedido`; el resto de las tablas sin estadísticas | 0 | `8_pg_stats_detalle_pedido.txt`, `9_pg_stats_por_tabla.txt` |

**Observación que justificó la acción.** En `u6_ensayo_restauracion`, las cinco
tablas tenían `last_analyze` y `last_autoanalyze` en NULL, `analyze_count` 0 y
`n_mod_since_analyze` igual a sus filas vivas estimadas. Con
`autovacuum_analyze_threshold` 50 y `autovacuum_analyze_scale_factor` 0,1, el
autoanalyze no alcanza su umbral en tablas de 2 a 7 filas. Se eligió una sola
tabla, `detalle_pedido`, según lo autorizado. No se desactivó autovacuum ni se
forzó la ausencia de estadísticas. No se ejecutó mantenimiento modificador sobre
el origen.

El chequeo del origen muestra 5 filas muertas estimadas en `pedido` (50 %),
consistentes con las actualizaciones de `total` que hacen los triggers durante la
carga del seed. Se registra como observación, no como problema, y no se actuó
sobre el origen. Las otras cuatro tablas restauradas siguen sin estadísticas del
planificador.

## 4. Incidencias del arnés

- **Contenedor detenido al inicio:** se resolvió con `docker start`, autorizado
  explícitamente (ver comprobaciones previas). No es un fallo de los scripts.
- **Orden del inventario:** la consulta auxiliar de inventario ordenaba las rutinas
  con `ORDER BY 2::text`, que PostgreSQL interpreta como una constante, no como la
  columna 2. Por eso la primera comparación textual mostró las mismas rutinas en
  distinto orden. Con las salidas ordenadas, la diferencia es nula. Las consultas
  auxiliares (`inventario.sql`, `huella.sql`) están en `<RUN>` y no forman parte
  de los entregables.
- **Búsqueda de secretos:** la contraseña de inicialización, buscada como cadena
  fija en `<RUN>`, no aparece en ningún archivo.

## 5. Aspectos no probados

- Modo `conservar-propietarios`, roles y funciones de seguridad de U5, vistas y
  materializada de U3, `pgcrypto` y scripts del docente.
- Restauración en un clúster distinto, con roles ausentes, o con datos de mayor
  volumen. La medición de 0,312 s corresponde solo al seed mínimo.
- Escrituras concurrentes durante la línea base o el respaldo. La ventana sin
  escrituras se cumplió por aislamiento del laboratorio, no porque el script la
  imponga.
- Fallos de `pg_restore` a mitad de la restauración, interrupción con Ctrl-C,
  contraseña incorrecta y espacio en disco insuficiente.
- Equivalencia de propietarios, privilegios, secuencias o identidades más allá de
  la huella por tabla y el inventario.
- `pg_cron` y la programación de tareas.

## 6. Pendientes de la comprobación docente

- Nombres de las bases y procedimiento de comprobación docente (CD-1, CD-4).
- Tabla de validación del PDF (`cliente`) frente al schema (`usuario`) (CD-2).
- Aislamiento de roles y decisión sobre propietarios y permisos de la restauración
  (CD-3, EA-4).
- Identidades definitivas de cada tarea (EP-4). `postgres` se usó solo en este
  ensayo.
- Aprobación de las metas RPO 24 h y RTO 20 min (EA-1).
- `informe_u6.pdf` sin generar. U6 no está terminada.

## Conclusiones

Primer ensayo funcional del núcleo canónico satisfactorio, según las evidencias de
la corrida.

**Qué comprendió:**

- PostgreSQL 17.11.
- Conteos observados de 2, 3, 3, 5 y 7 filas.
- Respaldo y línea base correspondientes.
- Restauración `sin-propietarios` validada en 0,312 s, con una antigüedad del
  respaldo de 26 s.
- Tres pruebas negativas rechazadas con exit 2.
- Diagnóstico y `ANALYZE` puntual sobre `detalle_pedido` en la copia restaurada.

**Qué no prueba este resultado:**

- La recuperación de la seguridad de U5.
- La comprobación docente.
- El cumplimiento de metas RPO/RTO, que siguen pendientes de aprobación.
- El comportamiento en todos los escenarios posibles (§5).

Tampoco declara U6 terminada.

## Recursos al finalizar

- Contenedor `foodstore-u6-lab` en ejecución, volumen `foodstore_u6_lab_data`.
- Bases del ensayo conservadas: `u6_ensayo_origen` y `u6_ensayo_restauracion`.
  `u6_ensayo_rechazo` no existe.
- No se eliminaron bases, respaldos ni recursos del laboratorio.
