# Corrección de la restauración — base administrativa (`-a`)

**Fecha:** 2026-11-05 (hora local -03:00; los registros del servidor están en UTC).
**Laboratorio:** contenedor `foodstore-u6-lab`, PostgreSQL 17.11.
**Evidencia externa:** `<DIR_PRIVADO>/correccion_20261105_143921/` (en adelante
`<RUN>`), fuera del repositorio. Hay un extracto revisado en
[../evidencias/correccion_restauracion_20261105.txt](../evidencias/correccion_restauracion_20261105.txt).

Esta corrida es independiente del [ensayo funcional](ensayo_funcional.md): sus
huellas, tiempos y bases son otros, y no reemplazan los de aquel ensayo. No es la
comprobación docente, no recupera la seguridad de U5 ni evalúa metas RPO/RTO.

## Problema corregido

La versión de `restore_test.sh` del commit `8c8f81f` (SHA-256 `fd7dde44…`) se
conectaba a la **base de origen** en dos momentos:

- para consultar `pg_database` y comprobar que el destino no existiera (`--dbname`);
- como `--maintenance-db` de `createdb`.

Esto impedía restaurar cuando el origen ya no existe, que es justamente un caso de
recuperación. El ensayo funcional anterior no lo detectó porque el origen seguía
disponible.

## Cambio realizado

Solo cambió `restore_test.sh`, de `fd7dde44…` a `68031b1f…`. Los demás scripts no se
modificaron.

- **Nuevo parámetro obligatorio** `-a BASE_ADMINISTRATIVA`, sin valor por defecto.
  Se valida con las mismas restricciones que los otros nombres
  (`^[A-Za-z0-9_]+$`) y se rechaza si es igual al origen o al destino (comparación
  sin distinguir mayúsculas).
- **Conexiones antes de crear el destino:** la consulta de ausencia en
  `pg_database` y `createdb --maintenance-db` usan ahora la base administrativa.
- **Usos que conserva `-s BASE_ORIGEN`:** comparación con `base=` del `.baseline`,
  rechazo de un destino igual al origen y trazabilidad en el log y el resumen. El
  script no exige que exista ni se conecta a él.
- **Trazabilidad:** el log y `resumen.txt`, tanto de éxito como de fallo, registran
  `BASE_ADMINISTRATIVA`.
- **Sin cambios:**
  - la comprobación del SHA-256 del respaldo;
  - el rechazo de destinos existentes o protegidos;
  - los dos modos de propietarios;
  - `--exit-on-error --single-transaction`;
  - la medición desde antes de `createdb` hasta el final de las validaciones;
  - la conservación del destino ante fallos y la ausencia de borrados.

Interfaz vigente:

```bash
bash unidades/unidad-6/restore_test.sh -c CONTENEDOR -U USUARIO -a BASE_ADMINISTRATIVA \
  -s BASE_ORIGEN -d BASE_DESTINO -f RESPALDO.dump -b RESPALDO.baseline \
  -m MODO -o DIR_RESULTADOS
```

**Revisión previa a la ejecución:**

- `bash -n` terminó con exit 0.
- Lectura del diff: después del cambio, las únicas conexiones del script son
  `--dbname=$admin_db` (consulta de ausencia), `--maintenance-db=$admin_db`
  (`createdb`) y `--dbname=$target_db` (`pg_restore` y validaciones).

## Huellas

| Archivo | Antes de la corrida | Al finalizar |
|---|---|---|
| `restore_test.sh` | `68031b1f0d5e07048d5547897b7fe81a4185921562524f74449ac76fd42f9938` (versión del commit `8c8f81f`: `fd7dde44…`) | igual |
| `backup_foodstore.sh` | `3b8e39c80b6bdfdd96da620a42f820230d79a6ace3ba3a076fa4be5123a44b52` | igual |
| `validaciones.sql` | `e4afea968f84dc721ecd7bf084630fe73de632d7c0b54e555c82548e28112eba` | igual |
| `health_check.sql` | `ed2644efc13b06b6dacddc9a7f784331a6877bd4fca3fe5ff84c9a63a26ec3c7` | igual |
| `maintenance.sql` | `f5e6bd2a07512bf318631401bc7bcc781da55381b49c1b2c4085f6595db0bbcd` | igual |
| `schema.sql`, `datos_iniciales.sql`, `objetos_programables.sql` | `d5cbb990…`, `ab983fbe…`, `9696a32e…` | iguales |

Fuentes: `<RUN>/00_previas/huellas_antes.txt` y `<RUN>/06_estado_final/estado.txt`.

## Comprobaciones previas

- Rama `feat/u6-mantenimiento`, HEAD `8c8f81f`, índice vacío.
- Contenedor en ejecución, con el mismo id e imagen:
  - `--network none`, sin puertos publicados y montaje de autenticación en solo
    lectura;
  - 0 de 7 reglas HBA `trust`;
  - PostgreSQL 17.11.
- `u6_fix_origen`, `u6_fix_reserva` y `u6_fix_destino` estaban ausentes.
- Antes de empezar se registró una huella de `u6_ensayo_origen` y
  `u6_ensayo_restauracion`.

## Procedimiento y resultados

| Paso | Comando (sin secretos) | Resultado esperado | Observado | Código | Evidencia |
|---|---|---|---|---|---|
| A. Crear origen | `docker exec foodstore-u6-lab createdb -w -U postgres --template=template0 u6_fix_origen` | Base nueva | Creada, OID 16632 | 0 | `<RUN>/01_origen/1_createdb.txt`, `6_oid_origen.txt` |
| A. Núcleo canónico | `psql … -v ON_ERROR_STOP=1 -1 -f - < schema.sql`; seed sin `-1`; objetos con `-1` | Sin errores | Sin errores | 0, 0, 0 | `01_origen/2_schema.txt`, `3_seed.txt`, `4_objetos.txt` |
| A. Validaciones del origen | `validaciones.sql` | 12 claves, controles en 0 | categoria 2, usuario 3, producto 3, pedido 5, detalle_pedido 7; `eliminados.*` 0; controles 0 | 0 | `01_origen/5_validaciones_origen.txt` |
| B. Respaldo | `bash unidades/unidad-6/backup_foodstore.sh -c foodstore-u6-lab -d u6_fix_origen -U postgres -o <RUN>/02_respaldo/backups -l <RUN>/02_respaldo/logs` | `.dump` y `.baseline` | `RESULTADO=OK`; `u6_fix_origen_20261105_143949.dump` (26537 B, SHA-256 `88ac0f05…9b46`) y `.baseline` (753 B, `base=u6_fix_origen`, `pg_dump_inicio=2026-11-05T14:39:50-03:00`); 0 sesiones previas | 0 | `02_respaldo/1_backup_consola.txt`, `02_respaldo/logs/` |
| C. Sesiones antes del renombre | consulta a `pg_stat_activity` desde `postgres` | 0 | 0 | 0 | `03_renombre/1_sesiones_previas.txt` |
| C. Renombre | `psql -d postgres -c "ALTER DATABASE u6_fix_origen RENAME TO u6_fix_reserva"` | Solo cambia el nombre | `ALTER DATABASE` | 0 | `03_renombre/2_renombre.txt` |
| C. Estado posterior | consulta de OID por nombre | origen ausente; reserva con el mismo OID | `u6_fix_origen` ausente; `u6_fix_reserva` OID 16632; validaciones y huella iguales a las del origen creado | 0 | `03_renombre/3_estado_tras_renombre.txt`, `4_validaciones_reserva.txt`, `5_huella_reserva.txt` |
| C. Respaldo intacto | `sha256sum` antes y después | Sin cambios | Iguales | — | `03_renombre/0_sha_respaldo_antes.txt`, `6_sha_respaldo_despues.txt` |
| D. Restauración | `bash unidades/unidad-6/restore_test.sh -c foodstore-u6-lab -U postgres -a postgres -s u6_fix_origen -d u6_fix_destino -f <dump> -b <baseline> -m sin-propietarios -o <RUN>/04_restauracion/resultados` | Restauración validada | `RESULTADO=RESTAURACION_VALIDADA`; destino creado por el script (OID 16754); `pg_restore --exit-on-error --single-transaction --no-owner --no-privileges`; stderr vacío | 0 | `04_restauracion/1_restore_consola.txt`, `resultados/restore_u6_fix_destino_20261105_144014/` |
| E. Validaciones | `validaciones.sql` en el destino, ejecutado por el script | Igual a la línea base | 12 líneas idénticas; `comparacion.diff` de 0 bytes; ambos controles en 0 | — | `resumen.txt`, `validaciones_destino.txt`, `04_restauracion/5_comprobaciones.txt` |
| E. Conexiones de la restauración | log del servidor en la ventana de la ejecución | Solo a `postgres` y al destino | `postgres` (`psql`, `createdb`) y `u6_fix_destino` (`pg_restore`, `psql`); 0 conexiones a `u6_fix_origen` | — | `04_restauracion/2_log_servidor_conexiones.txt` |
| E. Reserva y origen | OID y huella | Reserva sin cambios; origen ausente | `u6_fix_reserva` 16632 con la misma huella; `u6_fix_origen` ausente; huella del destino igual a la del origen creado | — | `04_restauracion/3_huella_reserva_despues.txt`, `4_huella_destino.txt`, `5_comprobaciones.txt` |
| E. Mediciones | registradas por el script | — | Tiempo desde antes de `createdb` hasta el fin de las validaciones: **0,264 s**; antigüedad del respaldo: **24 s** | — | `resumen.txt` |

**Lectura de las mediciones:** 0,264 s y 24 s son de esta corrida, con el seed
mínimo. No evalúan las metas RPO 24 h y RTO 20 min, que siguen pendientes de
aprobación (EA-1). La antigüedad no representa una pérdida efectiva de datos.

**Qué se renombró:** solo la base nueva de esta prueba. No se borró ni se alteraron
los datos de ningún origen; la base sigue disponible como `u6_fix_reserva`, con su
contenido intacto. El `.baseline` conserva `base=u6_fix_origen`, sin modificar.

## Pruebas negativas

| Prueba | Resultado esperado | Observado | Código | Evidencia |
|---|---|---|---|---|
| N1. Sin `-a` | Rechazo antes de escribir en PostgreSQL | Muestra el uso con `-a BASE_ADMINISTRATIVA`, etapa `parametros`; 0 conexiones; sin directorio de resultados | 2 | `<RUN>/05_negativas/N1_sin_a.txt` |
| N2a. `-a` igual al origen | Rechazo | `la base administrativa no puede ser igual al origen`, etapa `parametros`; 0 conexiones | 2 | `05_negativas/N2a_admin_igual_origen.txt` |
| N2b. `-a` igual al destino | Rechazo | `la base administrativa no puede ser igual al destino`, etapa `parametros`; 0 conexiones | 2 | `05_negativas/N2b_admin_igual_destino.txt` |
| N3. Repetir hacia `u6_fix_destino` | Rechazo sin modificar el destino | `el destino ya existe; no se borra ni se sobrescribe`, etapa `ausencia_destino`; OID 16754 y huella iguales antes y después; la única conexión del script fue a `postgres` | 2 | `05_negativas/N3_destino_existente.txt`, `N3_comparacion.txt`, `N3_conexiones_autorizadas.txt` |

En N3, la atribución de las conexiones a cada consulta de comprobación está anotada
(y marcada como anotación) en `N3_conexiones_autorizadas.txt`.

## Qué demuestra y qué no

**Demuestra, para el núcleo canónico en este laboratorio:**

- `restore_test.sh` restaura y valida un respaldo cuyo origen registrado ya no
  existe con ese nombre, sin conectarse a él.
- La validación compara el destino con la línea base conservada.
- El parámetro `-a` es obligatorio y se rechaza si coincide con el origen o con el
  destino.
- Un destino existente se sigue rechazando sin modificarlo.

**No comprueba:**

- La recuperación tras una pérdida física del clúster ni con el servidor
  inaccesible. El renombre simula la ausencia del nombre de origen, no un desastre.
- El modo `conservar-propietarios`, los roles de U5, U3, `pgcrypto` ni los scripts
  del docente.
- Otra base administrativa que no sea `postgres`, ni un rol distinto de
  `postgres`. Ninguno queda aprobado como identidad definitiva (EP-4).
- Datos de mayor volumen, escrituras concurrentes, interrupciones o fallos de
  `pg_restore` a mitad de la restauración.
- Las decisiones docentes pendientes: nombres (CD-1), `cliente`/`usuario` (CD-2),
  propietarios y permisos (CD-3, EA-4) y metas RPO/RTO (EA-1). Identificar la
  consigna `TPUnidad_6_Mantenimiento_FoodStore.pdf` no las resuelve.

## Recursos al finalizar

- Contenedor `foodstore-u6-lab` en ejecución, sin reinicios.
- Bases presentes: `postgres`, `template0`, `template1`, `u6_ensayo_origen`,
  `u6_ensayo_restauracion`, `u6_fix_reserva` (16632) y `u6_fix_destino` (16754).
  `u6_fix_origen` no existe.
- `u6_ensayo_origen` y `u6_ensayo_restauracion` mantienen la misma huella que antes
  de la corrida.
- No se eliminaron bases, respaldos ni recursos. La búsqueda de la contraseña de
  inicialización en `<RUN>`, como cadena fija, no encontró coincidencias.
