# Food Store — Base de Datos II

## TP Unidad 6 — Semana 10

## Mantenimiento, respaldo y recuperación

**Estado:** entrega U6 preparada para evaluación, con ensayos manuales documentados
y limitaciones declaradas.

- **Para evaluar:** [EVALUACION.md](EVALUACION.md).
- **Corrida desde esa guía:** [ensayo de evaluación](docs/ensayo_evaluacion.md),
  con bases `foodstore` y `foodstore_restore_test`; restauración validada en
  0,264 s con 1 s de antigüedad, dentro de las metas del equipo.
- **Verificación posterior de P7 y P9:** con la guía corregida; el código de cada
  bloque coincide con el del script en los casos de éxito, fallo y destino
  existente. Ver la sección correspondiente del ensayo de evaluación.
- **Informe:** [informe_u6.pdf](informe_u6.pdf), con fuente editable en
  [informe_u6.html](informe_u6.html).
- **Sin aprobación docente:** la evaluación docente, la seguridad de U5, las
  diferencias PDF/ZIP y la programación diaria, que no se instaló ni se probó,
  siguen abiertas.

Primer ensayo funcional del núcleo canónico satisfactorio, según las evidencias de
la corrida. La versión y las
herramientas del laboratorio (PostgreSQL 17.11) se comprobaron en la etapa de
[infraestructura](docs/laboratorio.md), que usó una versión anterior de
`backup_foodstore.sh`.

El 2026-11-05 se realizó un [ensayo funcional](docs/ensayo_funcional.md) con el
núcleo canónico (schema, seed y objetos TPI) en bases exclusivas del ensayo.
Incluyó respaldo con línea base, restauración `sin-propietarios` validada, tres
pruebas negativas rechazadas, salud en ambas bases y un `ANALYZE` puntual en la
copia restaurada. Fue un ensayo técnico: no es la comprobación docente, no
recupera la seguridad de U5 y en ese momento no evaluaba metas, porque todavía no
estaban adoptadas. Después se agregó la
[corrección de la restauración](docs/correccion_restauracion.md) y se hizo el
[ensayo de evaluación](docs/ensayo_evaluacion.md).
Hay un extracto sin secretos en
[evidencias/ensayo_canonico_20261105.txt](evidencias/ensayo_canonico_20261105.txt).

## Integrantes

- Avalos Pablo
- Blangetti Sofia
- Suarez Ismael

## Propósito y alcance

Construir un procedimiento de mantenimiento para Food Store que genere respaldos
lógicos, monitoree la salud de la base, ejecute mantenimiento preventivo y pruebe
la restauración en un entorno descartable. El trabajo se basa en la consigna de la
unidad y en los scripts de mantenimiento proporcionados por el docente.

Consigna de referencia: `TPUnidad_6_Mantenimiento_FoodStore.pdf` —
«Trabajo Práctico — Unidad 6: Mantenimiento, respaldo y recuperación».
Material de la cátedra, actividad de laboratorio de la Semana 10,
no incorporado al repositorio.
 Las unidades 1 a 5 están cerradas; este repositorio conserva las seis
unidades. Las unidades 7 y 8 se desarrollarán después en un segundo repositorio.

## Ruta de lectura

0. [EVALUACION.md](EVALUACION.md): guía operativa para la evaluación independiente.
1. [SPEC_U6.md](SPEC_U6.md): especificación de requisitos (una página).
2. [Compatibilidad docente](docs/compatibilidad_docente.md): análisis de
   compatibilidad entre la consigna, los scripts del docente y el esquema vigente.
3. [Diseño](specs/design.md): diseño de scripts y flujo de respaldo/restauración.
4. [Tareas](specs/tasks.md): lista ordenada para la implementación con Claude.
5. [Laboratorio](docs/laboratorio.md): procedimiento, comprobaciones de
   infraestructura y límites de la evidencia.
6. [Ensayo funcional](docs/ensayo_funcional.md): ensayo técnico con el núcleo
   canónico, pruebas negativas, mantenimiento y aspectos no probados.
7. [Corrección de la restauración](docs/correccion_restauracion.md): `-a` y prueba
   con el nombre de origen ausente.
8. [Ensayo de evaluación](docs/ensayo_evaluacion.md): corrida desde
   `EVALUACION.md` con las decisiones del equipo, y comparación con las metas.

## Entregables que exige la consigna

| Entregable | Estado |
|---|---|
| `SPEC_U6.md` | Escrito |
| [`backup_foodstore.sh`](backup_foodstore.sh) | Implementado; ensayado con el núcleo canónico (exit 0 y fallo controlado previo); pendiente la comprobación docente |
| [`health_check.sql`](health_check.sql) | Implementado; ensayado en el origen y la restauración (exit 0) |
| [`maintenance.sql`](maintenance.sql) | Implementado; diagnóstico y un `ANALYZE` puntual ensayados en la copia restaurada |
| [`informe_u6.pdf`](informe_u6.pdf) | Una página con los datos del [ensayo de evaluación](docs/ensayo_evaluacion.md); fuente editable en [`informe_u6.html`](informe_u6.html) |
| [`restore_test.sh`](restore_test.sh) (opcional) | Implementado; modo `sin-propietarios` y tres rechazos ensayados; `conservar-propietarios` sin probar |

Apoyo: [`validaciones.sql`](validaciones.sql), consultas de conteos y controles que
usan el respaldo y la restauración. Implementado y ensayado con el núcleo canónico.

En la etapa anterior se obtuvo un respaldo legible de la base auxiliar `postgres`,
se ejecutó el chequeo de salud y se comprobó el fallo ante una base inexistente;
véase [laboratorio](docs/laboratorio.md). Esa prueba es de infraestructura y
corresponde a la versión anterior del respaldo. **No constituye la validación del
TP6 ni demuestra que Food Store pueda restaurarse.**

Etapas de comprobación, en orden:

1. Revisión estática y `bash -n` de los scripts nuevos.
2. [Ensayo funcional](docs/ensayo_funcional.md) con el núcleo canónico, sobre la
   versión de `restore_test.sh` sin `-a`.
3. [Corrección de la restauración](docs/correccion_restauracion.md): agrega `-a` y
   la prueba con el nombre de origen ausente.

Cada etapa registra sus propias huellas y mediciones.

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
archivo de formato pgpass, no el `~/.pgpass` del host. La autenticación vigente
usa ese archivo seleccionado por `PGPASSFILE` dentro del contenedor.
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
  -c CONTENEDOR -U USUARIO -a BASE_ADMINISTRATIVA \
  -s BASE_ORIGEN -d BASE_DESTINO \
  -f RESPALDO.dump -b RESPALDO.baseline \
  -m MODO -o DIR_RESULTADOS
```

`-a` es obligatorio y no tiene valor por defecto. Es una base existente, distinta
del origen y del destino, y se usa solo para consultar `pg_database` y como
`--maintenance-db` de `createdb`. El origen (`-s`) se compara con el `.baseline` y
queda registrado, pero no necesita existir: el script nunca se conecta a él.

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
  interpretación se hace aparte. Una clasificación por colores no es requisito
  bloqueante del chequeo; sus umbrales quedan como mejora pendiente.
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

## Decisiones del equipo y temas abiertos

El 2026-11-05, antes de la corrida de evaluación, el equipo adoptó:

- **Bases:** `foodstore` (origen), `foodstore_restore_test` (restauración) y
  `postgres` (administrativa).
- **Modelo:** `usuario`, sin `cliente` ni aliases.
- **Alcance:** núcleo canónico.
- **Restauración:** modo `sin-propietarios`.
- **Rol:** `postgres`, solo en el laboratorio aislado.
- **Metas:** RPO 24 h y RTO 20 min.

Ver [EVALUACION.md](EVALUACION.md#decisiones-del-equipo-2026-11-05). Son
decisiones del equipo, **no confirmaciones del profesor**.

| Tema que sigue abierto | Referencia |
|---|---|
| Comprobación docente: nombres del PDF frente al ZIP, y `cliente` frente a `usuario` | CD-1/CD-2/CD-4 en [compatibilidad](docs/compatibilidad_docente.md) |
| `00_roles_unidad5_base.sql` del ZIP frente a los roles reales de U5 | CD-3 en [compatibilidad](docs/compatibilidad_docente.md) |
| Propietarios y permisos de U5 en la restauración (`conservar-propietarios` sin probar) | EA-4 en [compatibilidad](docs/compatibilidad_docente.md) |
| Roles operativos definitivos fuera del laboratorio | EP-4 en [diseño](specs/design.md) |
| Disponibilidad de `pg_cron` y programación diaria | VE-2 en [compatibilidad](docs/compatibilidad_docente.md) |
