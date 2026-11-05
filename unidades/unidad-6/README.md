# Food Store — Base de Datos II

## TP Unidad 6 — Semana 10

## Mantenimiento, respaldo y recuperación

**Estado:** scripts del procedimiento implementados. Primer ensayo funcional del
núcleo canónico satisfactorio, según las evidencias de la corrida. Pendientes la
comprobación docente, la seguridad de U5 y la entrega. La versión y las
herramientas del laboratorio (PostgreSQL 17.11) se comprobaron en la etapa de
[infraestructura](docs/laboratorio.md), que usó una versión anterior de
`backup_foodstore.sh`.

El 2026-11-05 se realizó un [ensayo funcional](docs/ensayo_funcional.md) con el
núcleo canónico (schema, seed y objetos TPI) en bases exclusivas del ensayo.
Incluyó respaldo con línea base, restauración `sin-propietarios` validada, tres
pruebas negativas rechazadas, salud en ambas bases y un `ANALYZE` puntual en la
copia restaurada. Es un ensayo técnico: no es la comprobación docente, no
recupera la seguridad de U5 ni evalúa las metas RPO/RTO. U6 no está terminada;
quedan pendientes las decisiones de la comprobación docente y `informe_u6.pdf`.
Hay un extracto sin secretos en
[evidencias/ensayo_canonico_20261105.txt](evidencias/ensayo_canonico_20261105.txt).

## Integrantes

- Avalos Pablo
- Blangetti Sofia
- Suarez Ismael

## Propósito y alcance

Construir un procedimiento de mantenimiento para Food Store que genere respaldos
lógicos, monitoree la salud de la base, ejecute mantenimiento preventivo y pruebe
la restauración en un entorno descartable. El trabajo se basa en la
[consigna oficial](../../tpi/) y en los scripts de mantenimiento proporcionados por
el docente. Las unidades 1 a 5 están cerradas; este repositorio conserva las seis
unidades. Las unidades 7 y 8 se desarrollarán después en un segundo repositorio.

## Ruta de lectura

1. [SPEC_U6.md](SPEC_U6.md): especificación de requisitos (una página).
2. [Compatibilidad docente](docs/compatibilidad_docente.md): análisis de
   compatibilidad entre la consigna, los scripts del docente y el esquema vigente.
3. [Diseño](specs/design.md): diseño de scripts y flujo de respaldo/restauración.
4. [Tareas](specs/tasks.md): lista ordenada para la implementación con Claude.
5. [Laboratorio](docs/laboratorio.md): procedimiento, comprobaciones de
   infraestructura y límites de la evidencia.
6. [Ensayo funcional](docs/ensayo_funcional.md): ensayo técnico con el núcleo
   canónico, pruebas negativas, mantenimiento y aspectos no probados.

## Entregables que exige la consigna

| Entregable | Estado |
|---|---|
| `SPEC_U6.md` | Escrito |
| [`backup_foodstore.sh`](backup_foodstore.sh) | Implementado; ensayado con el núcleo canónico (exit 0 y fallo controlado previo); pendiente la comprobación docente |
| [`health_check.sql`](health_check.sql) | Implementado; ensayado en el origen y la restauración (exit 0) |
| [`maintenance.sql`](maintenance.sql) | Implementado; diagnóstico y un `ANALYZE` puntual ensayados en la copia restaurada |
| `informe_u6.pdf` | Pendiente |
| [`restore_test.sh`](restore_test.sh) (opcional) | Implementado; modo `sin-propietarios` y tres rechazos ensayados; `conservar-propietarios` sin probar |

Apoyo: [`validaciones.sql`](validaciones.sql), consultas de conteos y controles que
usan el respaldo y la restauración. Implementado y ensayado con el núcleo canónico.

En la etapa anterior se obtuvo un respaldo legible de la base auxiliar `postgres`,
se ejecutó el chequeo de salud y se comprobó el fallo ante una base inexistente;
véase [laboratorio](docs/laboratorio.md). Esa prueba es de infraestructura y
corresponde a la versión anterior del respaldo. **No constituye la validación del
TP6 ni demuestra que Food Store pueda restaurarse.** Los scripts nuevos o
modificados solo pasaron revisión estática y `bash -n`, que no es una prueba
funcional.

## Uso previsto de los scripts implementados

Todos usan las herramientas cliente de un contenedor existente, elegido por el
operador. No fijan nombres de base ni de usuario (CD-1) y no contienen contraseñas.
En el laboratorio, los clientes se ejecutan mediante `docker exec` como usuario
SO `root` (uid 0); el servidor corre como usuario SO `postgres` (uid 999). El
operador ejecuta Docker/Bash en el host. El rol PostgreSQL `postgres` es una
identidad distinta de esos usuarios SO y se usa solo para preparación y prueba
de infraestructura; no queda aprobado como rol definitivo de respaldo de Food Store.

`PGHOST=127.0.0.1` y `PGPASSFILE=/run/foodstore-u6-auth/pgpass` hacen que los
clientes, incluido el respaldo sin opción `-h`, usen TCP al puerto 5432 y un
archivo de formato pgpass, no el `~/.pgpass` del host. La SPEC menciona
`~/.pgpass`; el laboratorio selecciona el mismo formato mediante `PGPASSFILE`.
El directorio privado externo al repositorio se monta en solo lectura; véanse
[autenticación y comprobaciones SCRAM](docs/laboratorio.md#autenticación).

```bash
bash unidades/unidad-6/backup_foodstore.sh \
  -c CONTENEDOR -d BASE -U USUARIO -o DIR_RESPALDOS -l DIR_LOGS

docker exec -i CONTENEDOR psql -X -v ON_ERROR_STOP=1 -U USUARIO -d BASE \
  -f - < unidades/unidad-6/health_check.sql

# Solo diagnóstico; la acción requiere tabla_mantenimiento, confirmar_analyze=on
# y justificacion (véase el encabezado del archivo).
docker exec -i CONTENEDOR psql -X -w -U USUARIO -d BASE \
  -f - < unidades/unidad-6/maintenance.sql

# MODO: sin-propietarios o conservar-propietarios (sin valor por defecto).
bash unidades/unidad-6/restore_test.sh \
  -c CONTENEDOR -U USUARIO -s BASE_ORIGEN -d BASE_DESTINO \
  -f RESPALDO.dump -b RESPALDO.baseline \
  -m MODO -o DIR_RESULTADOS
```

- `backup_foodstore.sh`: antes de `pg_dump` ejecuta `validaciones.sql` y exige
  sus 12 líneas con los controles en cero; si la captura o los controles fallan,
  sale con 1 sin generar respaldo. Luego hace `pg_dump -Fc` hacia un temporal. Los
  nombres definitivos `BASE_AAAAMMDD_HHMMSS.dump` y `BASE_AAAAMMDD_HHMMSS.baseline`
  se asignan solo si `pg_dump` termina bien, el archivo no está vacío y
  `pg_restore --list` puede leerlo. El `.baseline` comparte nombre base y
  ejecución con el respaldo. Registra `archivo_respaldo`, `sha256_respaldo`, las
  marcas de la línea base y de `pg_dump` (`pg_dump_inicio`) y, tras
  `[validaciones]`, los conteos y controles. Nunca sobrescribe ni borra respaldos
  anteriores. El log `backup_foodstore.log` queda en un directorio distinto. Sale
  con 0 si completa, 1 si falla la captura, el respaldo o su verificación, y 2
  ante errores de uso o de entorno.
- **Ventana sin escrituras:** el laboratorio la requiere durante la captura de la
  línea base y el respaldo, porque ambos usan instantáneas distintas. El script no
  garantiza ni impone esa ventana.
- `validaciones.sql`: conteos exactos de `categoria`, `usuario`, `producto`,
  `pedido` y `detalle_pedido`, incluidas las bajas lógicas, que además se informan
  aparte (`eliminados.*`). Agrega los controles `control.producto_invalido` y
  `control.detalle_pedido_invalido`. Salida `clave|valor` ordenada por clave. Usa
  `usuario`, no `cliente` (CD-2 sigue pendiente).
- `restore_test.sh`: antes de escribir en PostgreSQL verifica parámetros, archivos,
  correspondencia del `.baseline` (base, nombre y SHA-256 del respaldo), que el
  destino no sea el origen ni `postgres`, `template0` o `template1`, que el destino
  no exista y que el respaldo pueda listarse. Si el destino existe, se detiene sin
  borrarlo. Mide desde inmediatamente antes de `createdb` hasta que terminan las
  validaciones. Restaura con `--exit-on-error --single-transaction`, compara con la
  línea base y exige controles en cero. Registra la antigüedad desde
  `pg_dump_inicio`, no desde el `mtime`. Ante un fallo sale con código distinto de
  cero, conserva el diagnóstico y no borra el destino. No evalúa metas RPO/RTO.
- **Propietarios y permisos de la restauración (`-m`):** `sin-propietarios` usa
  `--no-owner --no-privileges`; valida datos y **no** recupera propietarios, ACL ni
  la seguridad de U5. `conservar-propietarios` aplica los propietarios y permisos
  del respaldo y requiere que los roles ya existan. En ningún modo se restauran
  roles globales, y la elección no resuelve CD-3 ni EA-4.
- `maintenance.sql`: siempre muestra el diagnóstico de autovacuum, autoanalyze y
  estado de tablas. Solo ejecuta `ANALYZE VERBOSE` sobre una de las cinco tablas
  canónicas cuando se pasan las tres variables de selección, autorización y
  justificación. Una selección incompleta termina con error sin actuar. La
  justificación real se registra al ejecutar. No incluye `VACUUM FULL`, `REINDEX`,
  archivado, `ALTER SYSTEM` ni `pg_cron`.
- `health_check.sql`: consultas de observación dentro de una transacción
  `START TRANSACTION READ ONLY` que termina en `ROLLBACK`: es una protección,
  no una garantía absoluta. No bloquea escrituras en tablas temporales ni efectos
  de funciones fuera de la transacción; la garantía real depende de revisar el
  contenido del archivo. No selecciona el texto SQL de otras sesiones.
  No implementa semáforo VERDE/AMARILLO/ROJO ni umbrales: registra métricas y la
  interpretación se hace aparte. Los colores que menciona la SPEC no son un
  requisito bloqueante del chequeo; sus umbrales quedan como mejora pendiente.
  `age(backend_xmin)` del control 4 es un indicador de diagnóstico, no prueba por
  sí solo de bloqueo de VACUUM; véanse sus límites en el
  [diseño](specs/design.md#32-health_checksql).

El directorio `backups/` está ignorado por Git en cualquier nivel. En este ensayo,
los respaldos y evidencias permanecen fuera del repositorio, en
`<DIR_PRIVADO>/evidence`, con respaldos y logs en subdirectorios distintos.

## Próxima etapa de trabajo

La implementación corresponde a Claude, partiendo de la especificación y el diseño
guardados en este directorio. Las tareas están listadas en
[specs/tasks.md](specs/tasks.md). Cada tarea indica su resultado esperado y sus
dependencias. La ejecución de pruebas requiere autorización explícita del equipo.

## Decisiones pendientes que condicionan implementación o ejecución

| Decisión | Referencia |
|---|---|
| Nombre de la base principal y de restauración | CD-1 en [compatibilidad](docs/compatibilidad_docente.md) |
| Tabla de validación: `cliente` (PDF) o `usuario` (schema) | CD-2 en [compatibilidad](docs/compatibilidad_docente.md) |
| `00_roles_unidad5_base.sql` del ZIP vs roles reales de U5 | CD-3 en [compatibilidad](docs/compatibilidad_docente.md) |
| RPO 24 h y RTO 20 min como metas de laboratorio | EA-1 en [compatibilidad](docs/compatibilidad_docente.md) |
| Procedimiento de comprobación docente (nombres CD-1, scripts del ZIP) | CD-1/CD-4 en [compatibilidad](docs/compatibilidad_docente.md) |
| Entorno para Food Store e identidades definitivas de cada tarea (infraestructura ya creada y probada) | EP-2/EP-4 en [diseño](specs/design.md); antecedente VE-5/VE-6 en [compatibilidad](docs/compatibilidad_docente.md) |
| Disponibilidad de `pg_cron` | VE-2 en [compatibilidad](docs/compatibilidad_docente.md) |
