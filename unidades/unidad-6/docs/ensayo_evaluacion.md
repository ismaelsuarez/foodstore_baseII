# Ensayo de evaluación — corrida desde EVALUACION.md

**Fecha:** 2026-11-05. Los scripts registran hora local -03:00; el servidor, UTC.
**Instancia:** `foodstore-u6-evaluacion` (id `e46713bd8004…`), volumen
`foodstore_u6_evaluacion_data`, imagen local `postgres:17`
`sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`,
PostgreSQL 17.11. Es una instancia nueva: no se reutilizó `foodstore-u6-lab` ni
sus bases.

**Evidencia completa, fuera del repositorio:**

- Directorio privado de la guía (`U6_PRIV`), con las credenciales en `auth/` y los
  resultados en `resultados/`.
- Directorio de consola con la salida de cada bloque. En adelante `<CONSOLA>`.

Hay un extracto revisado en
[../evidencias/ensayo_evaluacion_20261105.txt](../evidencias/ensayo_evaluacion_20261105.txt).

**Alcance:** corrida técnica con las
[decisiones del equipo](../EVALUACION.md#decisiones-del-equipo-2026-11-05), que se
adoptaron antes de ejecutarla. No es la comprobación docente ni recupera
propietarios, permisos o seguridad de U5.

## Cómo se ejecutó

Los bloques `# [P0]` a `# [P13]` se extrajeron de `EVALUACION.md` tal como
estaban escritos y se ejecutaron en orden, cada uno precedido por P0.

- **Versión de la guía usada:** SHA-256 `1ecce5a2…`.
- **Modo estricto:** cada bloque corrió con `set -euo pipefail`. Esa versión de la
  guía no lo indicaba, y sin él un `DETENERSE` de P1 o P5 no cortaba el bloque.
  Ahora la guía lo prescribe (versión `858957f3…`); el cambio es solo de texto
  fuera de los bloques, que son idénticos a los de `93a29a4c…`.
- **Única sustitución:** en P12 se reemplazaron los marcadores previstos (`TABLA`
  y el texto de la justificación). El cambio está en `<CONSOLA>/P12_sustitucion.diff`.
- **Variable del operador:** se definió `U6_PRIV`, que es la que P0 exige.
- **Comprobaciones adicionales,** que no forman parte del procedimiento de la guía
  y no cambian datos:
  - `validaciones.sql` sobre la copia después de P12
    (`<CONSOLA>/P12b_validaciones_post.txt`);
  - consultas del OID de `foodstore_restore_test` antes y después de cada negativa
    (`<CONSOLA>/N*_oid_*.txt`);
  - la captura de la salida de cada bloque en `<CONSOLA>`.

## Resultados

| Bloque | Comprobación | Observado | Exit |
|---|---|---|---|
| P1 | Nombres libres e imagen local | Contenedor, volumen y directorio inexistentes; imagen `2d2b8998…` | 0 |
| P2 | Credenciales propias | Dos archivos `-rw-------`; valores no impresos | 0 |
| P3 | Instancia aislada | `red=none puertos={} privilegiado=false`; `accepting connections` | 0 |
| P4 | Conexión | `PostgreSQL 17.11`; `postgres\|postgres\|127.0.0.1/32`; `0 reglas trust de 7`; rechazo sin contraseña | 0 |
| P5 | Núcleo canónico en `foodstore` (OID 16384) | Tres archivos sin errores. El seed imprime sus dos consultas de control con 0 filas. Validaciones: categoria 2, usuario 3, producto 3, pedido 5, detalle_pedido 7; `eliminados.*` 0; controles 0 | 0 |
| P6 / P13 | Huellas antes y después | `huellas sin cambios`. Scripts `3b8e39c8` (backup), `68031b1f` (restore), `ed2644ef` (salud), `f5e6bd2a` (mantenimiento), `e4afea96` (validaciones); canónicos `d5cbb990`, `ab983fbe`, `9696a32e` | 0 |
| P7 | Línea base y respaldo | 0 sesiones en el origen; `RESULTADO=OK`; `foodstore_20261105_155836.dump`, 26518 B; `PG_DUMP_INICIO 2026-11-05T15:58:36-03:00` | 0 |
| P8 | Respaldo y `.baseline` asociados | `archivo_respaldo` y `sha256_respaldo` (`ca491275…4f89`) coinciden con el dump | 0 |
| P9 | Restauración (`-a postgres`, `sin-propietarios`) | `RESTAURACION_VALIDADA`; `foodstore_restore_test` creada por el script (OID 16506); `comparacion.diff` y stderr de `pg_restore` vacíos | 0 |
| P10 | Salud en origen y copia | Ambas 7942 kB, 1 sesión (la propia), 5 tablas, control 4 con 0 filas. Origen: `pedido` con 5 filas muertas estimadas (50 %) | 0 |
| P11 | Diagnóstico en la copia | Las 5 tablas sin `last_analyze` ni `last_autoanalyze`, `n_mod_since_analyze` igual a sus filas; umbral de autoanalyze 50 + 0,1·n; `solo diagnóstico` | 0 |
| P12 | `ANALYZE` puntual en la copia | `detalle_pedido`: justificación registrada; 1 de 1 página, 7 filas vivas; `n_mod_since_analyze` de 7 a 0. Conteos posteriores iguales a la línea base | 0 |

## Mediciones y metas del equipo

| Medida | Observado (esta corrida) | Meta del equipo | Comparación |
|---|---|---|---|
| Recuperación: desde antes de `createdb` hasta el fin de las validaciones | **0,264 s** | RTO 20 min (1200 s) | Dentro de la meta |
| Antigüedad del respaldo al iniciar la restauración, desde `pg_dump_inicio` | **1 s** | RPO 24 h (86400 s) | Dentro de la meta |

**Límites de estas mediciones:**

- Son de esta corrida, con el seed mínimo, y no se trasladan de los ensayos
  anteriores.
- La antigüedad es mínima porque la restauración se hizo enseguida del respaldo. No
  demuestra que exista una frecuencia diaria de respaldos: no hay programación de
  tareas.
- La antigüedad no representa una pérdida efectiva de datos.
- `restore_test.sh` sigue registrando «metas RPO/RTO pendientes de aprobación; no se
  evalúa cumplimiento», porque es anterior a la decisión y no se modificó. La
  comparación con las metas se hace en este documento y en el informe.

## Incidencia de la guía y corrección

Al probar la negativa sugerida en la sección F (repetir P9 contra el destino ya
existente), el script rechazó con `exit=2` y el OID 16506 no cambió. El bloque P9
de la versión `1ecce5a2…`, sin embargo, terminó con exit 0. La causa: su `cat
…/restore_*/resumen.txt` final con comodín encontró dos directorios de resultados
y su éxito ocultó el código del script.

- **Corrección:** P7 y P9 de `EVALUACION.md` ahora capturan el código (`rc`),
  imprimen `… exit=$rc`, leen solo el resumen más reciente y terminan con
  `[ "$rc" = 0 ]`. Es la versión `93a29a4c…`; los diffs están en
  `<CONSOLA>/P7_v1_v3.diff` y `P9_v1_v3.diff`.
- **Reejecución de la negativa con P9 corregido:** `restore_test.sh exit=2`, el
  bloque termina con exit 1 y el OID 16506 no cambió.
- **Intento intermedio descartado:** un segundo extracto de bloques se tomó antes de
  que la edición estuviera en disco, así que era idéntico al primero. Su negativa
  también rechazó (exit 2, OID sin cambios); se conserva como `N2_…` y está
  marcado en `bloques_v2/LEEME.txt`.
- **Directorios de resultados:** quedaron cuatro. `…155837` es el de la
  restauración exitosa; `…155919`, `…155943` y `…155956` son los de los rechazos,
  todos `RESULTADO=FALLO` en la etapa `ausencia_destino`.
- **No reejecutado en esta corrida:** el camino exitoso de P7 y P9 con la versión
  corregida, porque no estaba autorizado un segundo origen ni un segundo destino.
  Se comprobó después, en la verificación posterior de los bloques finales
  (sección siguiente).

## Verificación posterior de los bloques finales (P7 y P9)

Complementa la corrida de entrega y no reemplaza sus mediciones. No se
reejecutaron los trece pasos.

**Problemas que se corrigieron en la guía antes de probar:**

- P7 y P9 terminaban con `[ "$rc" = 0 ]`, así que ante un fallo el bloque devolvía
  1 y no el código del script. Ahora terminan con `(exit "$rc")`.
- P9 leía el resumen más reciente por nombre, que podía ser el de otra
  ejecución. Ahora muestra solo el directorio creado por esa ejecución, o avisa
  que no lo hay.
- La guía no explicaba que los bloques son de Bash ni cómo leer el código del
  bloque. Ahora lo hace.
- Origen, destino y carpeta de resultados pasaron a ser variables de P0
  (`U6_ORIGEN`, `U6_DESTINO`, `U6_RES`). Sus valores por defecto son los de la
  entrega.

**Versiones probadas:**

- Guía `490f1be1…`.
- `restore_test.sh` `973223df…`: solo se reemplazó la frase sobre las metas
  pendientes por «El script registra las mediciones; su comparación con los
  objetivos se documenta en el informe y en SPEC_U6.md.».

Las huellas de la guía, de los scripts y de los bloques fueron las mismas antes y
después de las comprobaciones.

**Cómo se ejecutó:**

- Contenedor existente `foodstore-u6-evaluacion`.
- Bloques extraídos sin cambios y ejecutados con
  `bash -c 'set -euo pipefail; source P0.sh; source P7.sh'`, o el bloque
  correspondiente.
- Nombres de la prueba pasados solo por las variables documentadas: destino
  `u6_guia_restore_test` y una carpeta de resultados nueva.
- No se crearon credenciales ni recursos de infraestructura.

| Caso | Código del script | Código del bloque | Resultado observado |
|---|---|---|---|
| A. P7 con `foodstore` | 0 | 0 | `RESULTADO=OK`; `foodstore_20261105_170450.dump`, 26518 B. P8 confirmó `archivo_respaldo` y SHA-256 `324848d2…` (bloque 0) |
| B. P7 con `u6_guia_inexistente` | 1 | 1 | Falló la captura de la línea base; se eliminó el temporal; `RESULTADO=FALLO`; sin `.dump` ni `.baseline`; la base sigue sin existir |
| C. P9 hacia `u6_guia_restore_test` | 0 | 0 | El script creó el destino (OID 16632); `RESTAURACION_VALIDADA`; diff vacío; controles en 0; se mostró el resumen de esa ejecución |
| D. P9 repetido en el mismo segundo que C | 2 | 2 | Rechazo en la etapa `directorio_resultados`: el directorio con la misma marca de tiempo ya era el de C. El bloque informó «sin resumen propio». No llegó a comprobar el destino |
| D3. P9 de la guía `93b4b9fb…`, destino existente | 2 | 2 | Igual que D2, con la versión final de P9; OID 16632 y contenido sin cambios |
| D2. P9 repetido 2 s después | 2 | 2 | `el destino ya existe; no se borra ni se sobrescribe`, etapa `ausencia_destino`; se mostró su propio resumen (`RESULTADO=FALLO`); OID 16632 y contenido sin cambios |

**Versión final de la guía (`93b4b9fb…`):** después de A–D2, el verificador
independiente señaló un riesgo en P9, aunque no se había manifestado en ningún
caso. Con `set -e`, si fallaran el `comm` o el `cat` informativos, el bloque
terminaría antes de `(exit "$rc")`. Se les agregó `|| true`, sin cambiar ningún
otro bloque. Con esa versión se repitió solo el caso de destino existente (D3).
El camino exitoso de P9 no se volvió a ejecutar, porque habría requerido otro
destino nuevo no autorizado.

**Qué se lee en cada columna:** el código del bloque es el que recibió el proceso
que lo invocó. El texto en pantalla, como `restore_test.sh exit=N` o el resumen,
es informativo.

**Otras comprobaciones:**

- `foodstore` y `foodstore_restore_test` mantuvieron la misma huella antes y
  después de las comprobaciones.
- Tiempos de C: 0,262 s y 1 s de antigüedad. Son de esta verificación y no
  reemplazan los de la corrida de entrega.

**Limitación detectada:** el directorio de resultados de `restore_test.sh` tiene
resolución de un segundo. Dos ejecuciones hacia el mismo destino en el mismo
segundo hacen que la segunda se rechace sin sobrescribir nada (caso D). Es un
comportamiento seguro, pero hay que esperar al menos un segundo entre ejecuciones.

**Evidencia:**

- Completa, fuera del repositorio: `<VERIFICACION>/consola` y
  `<VERIFICACION>/resultados`, separadas de `auth/` y de las corridas anteriores.
- Extracto:
  [../evidencias/verificacion_bloques_20261105.txt](../evidencias/verificacion_bloques_20261105.txt).

## Qué se comprobó y qué no

**Comprobado en esta corrida:**

- Preparación desde la guía: instancia aislada con SCRAM, sin `trust`.
- Instalación del núcleo canónico y línea base previa al respaldo.
- Asociación del respaldo con su línea base por nombre, SHA-256 y marca de inicio.
- Restauración con el origen registrado y la base administrativa `postgres`.
- Conteos iguales a la línea base y controles en 0.
- Salud en ambas bases y mantenimiento justificado en la copia.
- Rechazo de un destino existente.
- Huellas estables durante la corrida.

**No comprobado:**

- Seguridad de U5 y modo `conservar-propietarios`.
- Scripts del docente, `pg_cron`, programación diaria y volumen real de datos.
- Escrituras concurrentes y fallos a mitad de la restauración.
- Ejecución en otra computadora: la guía se siguió en esta misma máquina.

## Recursos al finalizar

- Contenedor `foodstore-u6-evaluacion` en ejecución.
- Bases `foodstore` (16384) y `foodstore_restore_test` (16506).
- No se borró nada, y `foodstore-u6-lab` no se tocó.
