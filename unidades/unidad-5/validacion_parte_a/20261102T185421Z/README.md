# Unidad 5 — Parte A: corrida abortada antes de instalar SQL

**Estado global: BLOCKED (arnés), no aceptación de la Parte A.**
Corrida única del 2026-11-02 UTC. No se ejecutaron instaladores ni pruebas SQL.
No se modificó ningún archivo preexistente ni se repitió una prueba para sustituir
un fallo. El contenedor y su volumen fueron destruidos después de capturar la evidencia.

## 1. Identificación de instancia

| Campo | Observado |
|---|---|
| Rama | `feat/u5-seguridad` |
| Contenedor creado | `foodstore_u5_validacion_a` |
| ID | `6480b47944fcfe5260fe32789841b5a89ff7461e1b8450fa26eddbd16ba3cc98` |
| Imagen local | `postgres:17` |
| Digest verificado | `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| Motor observado | PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2), según `servidor.txt` |
| `SHOW server_version` / versión psql | BLOCKED: no se llegó a ejecutar |
| Base creada por entrypoint | `foodstore_tpi_oficial`, según sentencia del log |
| Aislamiento | `network=none`, `bindings={}`, `/repo` con `RW=false` |
| Volumen anónimo propio | `2aa5f12c394af0c4c749843ca1406413f3ae26041eb7167218f426e066bf00ca` |
| Creación | 18:57:52 UTC, exit 0 |
| Destrucción | 18:59:40 UTC, exit 0 |

Fuentes: `01_container_create.txt`, `01_container_isolation.txt`,
`comandos_y_salidas_final.json`, `servidor.txt`.

Se solicitó al servidor, exclusivamente mediante opciones de `docker run`:
`logging_collector=on`, `log_statement=mod`, ambos límites de parámetros en `0`,
`log_file_mode=0600`, `password_encryption=scram-sha-256`, conexiones/desconexiones
activas, rotación desactivada para este intervalo. **No se verificaron mediante
`pg_settings`: son opciones solicitadas, no una comprobación SQL acreditada.**
El SO sí informó `600 postgres postgres` para el log.

## 2. Preflight y precondiciones

| Control | Estado | Evidencia / límite |
|---|---|---|
| Raíz/rama/estado Git | PASS | `00_root.txt`, `00_branch.txt`, `00_git_status_before.txt` |
| Docker disponible | PASS | `00_docker_version.txt`: 29.9.2 |
| Nombre exclusivo libre | PASS | `00_container_names.txt`, `00_docker_ps_before.txt` |
| Imagen local/digest, sin pull | PASS | `00_image_id.txt`, comando con `--pull=never` |
| PostgreSQL 17.11 | PASS de versión por log | No versión del cliente ni consulta SQL |
| Fuentes y dependencias SQL presentes | PASS de presencia | `00_source_sha256_before.txt`; no acredita instalación |
| OpenSSL disponible | PASS | `00_openssl_version.txt` |
| Destino y variable | PASS del plan | Todas las invocaciones U5 previstas llevan `u5_base_objetivo=foodstore_tpi_oficial`; guardas leídas, no ejecutadas |
| Red/puertos/mount | PASS | Inspección del único contenedor creado |
| Autenticación | Parcial | Log: socket local `trust`; se solicitaron reglas host SCRAM; sin prueba de logins U5 |
| Plan de logging | PASS del plan | Opciones en JSON; configuración efectiva SQL BLOCKED |
| Secret scan rastreado | PASS | `git grep -nE -I` para literales PASSWORD, bcrypt y claves privadas: exit 1, sin coincidencias |
| Arranque confirmado por arnés | **BLOCKED (arnés)** | `BLOCKED_o_fallo_runner.txt`: `RuntimeError: BLOCKED: servidor no listo` |
| VP-00..VP-12 | **BLOCKED** | No se ejecutó `00_precondiciones.sql` |

Los marcadores académicos no se trataron como contraseñas. La comprobación
rastreada no cubre por sí sola todos los archivos no rastreados; las evidencias
se revisaron además contra los tres valores sintéticos exactos.

## 3. Instalación y códigos de salida

El registro de comandos realmente ejecutados, argumentos no sensibles, tiempos y
exits está en `comandos_y_salidas_final.json`. Los `.txt` correspondientes
conservan stdout y stderr combinados, sin normalizar espacios.

| Paso | Resultado / exit |
|---|---|
| Crear laboratorio | Ejecutado, 0 |
| Espera de arranque | Abortó; excepción del arnés, no exit de psql |
| `schema.sql` con `-1` | BLOCKED: no ejecutado, sin exit |
| `datos_iniciales.sql` sin `-1` | BLOCKED: no ejecutado, sin exit |
| `tpi/sql/objetos_programables.sql` con `-1` | BLOCKED: no ejecutado, sin exit |
| Baseline TPI y HAVING | BLOCKED: no ejecutados, sin exit |
| Vistas U3 y después materializada/índice propio | BLOCKED: no ejecutados, sin exit |
| `CREATE EXTENSION pgcrypto WITH SCHEMA public` | BLOCKED: no ejecutado, sin exit |
| Precondiciones → F0 → roles → funciones → F1 | BLOCKED: no ejecutados, sin exit |
| 10 → 11 → 16 → 12 → 20 → 30 → 40 | BLOCKED: no ejecutados, sin exit |
| 49 → conexiones 50/51 → 52 → 99 | BLOCKED: no ejecutados, sin exit |

La base se creó por el entrypoint de la imagen, pero no se cargó el seed ni ningún
objeto canónico, U3 o U5. Nunca se abrió la sesión de control que debía conservar F0.

## 4. SEC-01..SEC-20: resultados por criterio

**Ningún criterio tiene PASS.** `RESULT_resumen.txt` no contiene líneas RESULT;
`RESULT_conteos.json` informa 0 PASS / 0 FAIL. Cero FAIL no significa éxito: no hubo
casos SQL ejecutados. Los SQLSTATE esperados tampoco se observaron.

| Criterio | Veredicto | Archivo/caso pendiente |
|---|---|---|
| SEC-01 | BLOCKED (arnés) | 10:`SEC01.P.grupos`; M06 NOLOGIN; M05 limpia |
| SEC-02 | BLOCKED (arnés) | 10:`SEC02.P.SEC06.P.SEC20.P.atributos` |
| SEC-03 | BLOCKED (arnés) | 20:`SEC03.N.*`; 30:`SEC03.P.*` |
| SEC-04 | BLOCKED (arnés) | 20:`SEC04.*`; 50 login real; M03 |
| SEC-05 | BLOCKED (arnés) | 20:`SEC05.*`; 11 matriz |
| SEC-06 | BLOCKED (arnés) | 10 atributos; 20:`SEC06.*` |
| SEC-07 | BLOCKED (arnés) | 10:`SEC07.*` |
| SEC-08 | BLOCKED (arnés) | 20:`SEC08.*`; 11 columnas |
| SEC-09 | BLOCKED (arnés) | 11:`SEC09.P.*`; 20:`SEC09.N.*` |
| SEC-10 | BLOCKED (arnés) | 10 membresías; 20:`SEC10.N.*` |
| SEC-11 | BLOCKED (arnés) | 11 ADP; 20:`SEC11.*` |
| SEC-12 | BLOCKED (arnés) | 11 ADP; 20:`SEC12.*` |
| SEC-13 | BLOCKED (arnés) | 11 diez rutinas; 20:`SEC13.*`; 30 |
| SEC-14 | BLOCKED (arnés) | 20:`SEC14.*`; 11/16 matriz |
| SEC-15 | BLOCKED (arnés) | M01 antes/después; 02 huella; 99 |
| SEC-16 | BLOCKED (cobertura incompleta) | M02 sin coincidencias en arranque; 40 y guardas preventivas no ejecutados |
| SEC-17 | BLOCKED (arnés) | 10 endurecimiento; 20 suplantación; M04 interrupción |
| SEC-18 | BLOCKED (arnés) | 40:`SEC18.*` |
| SEC-19 | BLOCKED (arnés) | 14 aislamiento; 20 negativos; 15 limpieza |
| SEC-20 | BLOCKED (arnés) | 10 atributos; 15/52 limpieza; 99 inventario |

M03 no puede acreditarse sin analítica instalada. M04 se leyó estáticamente:
el instalador contiene BEGIN/COMMIT alrededor de CREATE/OWNER/REVOKE/GRANT;
no se ensayó interrupción desde otra conexión. M05 requiere otra instalación
limpia, que no se improvisó. M06 tampoco se ejecutó.

## 5. Regresión TPI, HAVING y F0/F1

| Medición | Antes U5 | Después U5 | Referencia acreditada, no observada aquí |
|---|---|---|---|
| Grupos / variantes | No ejecutado | No ejecutado | 29 / 37 |
| NOTICE PASS | 0 observados por no ejecución | 0 observados por no ejecución | 30 |
| Exit psql | No existe | No existe | 0 |
| Limpieza e inventario de 12 objetos | No ejecutado | No ejecutado | Requeridos |
| HAVING / ventana | No ejecutado | No ejecutado | No se extrapolan resultados históricos |
| Huella | F0 no capturada | F1 no capturada | No hay diff acreditado |

Las diferencias autorizadas se leyeron en el procedimiento (ACL de las siete
rutinas, interfaces nuevas y USAGE explícito; matriz exacta en 11), pero no se
observaron. No se reconstruyó F0 a posteriori. P0099 no se utilizó.

## 6. P8.membresias y limpieza SQL

`15_limpieza.sql`, `52_limpiar_logins.sql` y `99_cierre.sql`: **BLOCKED, no ejecutados**.
No se crearon roles U5 ni efímeros con estos scripts. No se ejecutó ni acreditó
la aserción corregida de P8: tres membresías U5, cero efímeras y EXCEPT en ambos
sentidos siguen pendientes. La destrucción del clúster no sustituye esa prueba.

## 7. Seguridad, auditoría y revisión M02

Los tres valores sintéticos se generaron con OpenSSL en memoria y viajaron solo
por entorno. No se mostraron, guardaron ni pasaron con `-v`. Se limpiaron al
terminar el proceso. Las contraseñas de negocio **nunca se usaron** en SQL.

| Comprobación | Observado |
|---|---|
| Permisos SO log | `600 postgres postgres`, exit 0 (`40_log_permissions.txt`) |
| Copia restringida dentro del laboratorio | Exit 0 (`41_log_snapshot.txt`) |
| grep -F valores exactos + bcrypt + cláusula PASSWORD | Exit 1, sin coincidencias (`42_m02_container_scan.txt`) |
| `docker cp` posterior al scan preventivo | Exit 0, `servidor.txt` |
| Mismo grep sobre copia host | Exit 1 (`44_m02_host_scan.txt`) |
| Cobertura de log | 382 líneas; 1 statement, 91 autorizaciones y 91 desconexiones |
| Scan exacto de evidencia antes de destruir | Sin coincidencias (`46_evidence_secret_scan.txt`) |
| Scan exacto final del arnés | Sin coincidencias (`94_final_secret_scan.txt`) |

El statement corresponde a CREATE DATABASE del entrypoint; la actividad restante
es arranque y sondeos. El log demuestra auditoría de ese intervalo, **no** ausencia
de fugas durante autenticación/reset U5, que no se ejecutaron. No acredita SEC-16
completo. Tampoco contiene el apagado posterior causado por `docker rm -f`.

## 8. Fallos, causa y limitaciones

### A-V01: fallo del nuevo arnés de esta corrida, no del producto

El sondeo exigió simultáneamente `pg_isready` exitoso y esta igualdad adicional:

```sh
test "$(readlink /proc/1/exe)" = /usr/lib/postgresql/17/bin/postgres
```

La condición no se confirmó en el bucle y terminó en la excepción literal:
`RuntimeError: BLOCKED: servidor no listo`. Sin embargo, el log registra al PID 1
listo desde **18:57:53.379 UTC**, con conexiones posteriores a la base objetivo.
Por lo tanto, no corresponde atribuir el bloqueo a una caída de PostgreSQL ni
al SQL de U5, que no llegó a ejecutarse.

**Límite de diagnóstico:** el arnés no guardó stdout/stderr ni el exit individual
del `readlink`/`test`; también perdió su buffer de sondeos al elevar la excepción
antes de crear `01_ready.txt`. No puede afirmarse si la causa concreta fue un
permiso de `/proc`, una ruta diferente o un estado inesperado. La igualdad fue
una suposición no requerida por el procedimiento y resultó un control inadecuado.

### A-V02: salida global y plantilla de confirmación inadecuadas

El proceso Python terminó con exit 0 después de capturar la excepción y limpiar.
Ese exit **NO** significa validación exitosa. Asimismo,
`47_confirmacion_captura.txt` contiene una plantilla que menciona evidencia SQL
como si estuviera disponible. Se conserva sin editar, pero **esa frase es
incorrecta para esta corrida**: solo existía evidencia de preflight/arranque,
fallo y limpieza. Las ausencias se delimitan en este informe. No existe archivo
`control_session_exit.txt` porque la sesión nunca se abrió.

No se corrigió ni reejecutó el arnés después del fallo. Propuestas para decisión
humana, no aplicadas: capturar cada sondeo inmediatamente, usar un control de
servidor final independiente de una ruta de binario y con diagnóstico, devolver
exit no cero en un aborto y confirmar solo los artefactos realmente disponibles.
Una nueva corrida debe tener directorio UTC nuevo y conservar íntegra esta.

No se probaron permisos, negocio, credenciales, concurrencia, tiempos bcrypt,
reidentificación, atomicidad de instalación ni limpieza SQL. No se modificaron
D4/D8/D9 ni configuraciones globales fuera del contenedor.

## 9. Evidencias y destrucción

Antes de eliminar se habían guardado los resultados disponibles, log revisado,
permisos, inventario, metadatos y resumen vacío de RESULT. La comparación de los
inventarios Docker anterior/posterior es **idéntica byte a byte**:
`tpi_ssd-db-1` siguió activo/healthy; `taller-db-1` y `libreria-pg` siguieron detenidos,
con los mismos IDs. Solo se los enumeró mediante `docker ps -a`.

`docker rm -f -v foodstore_u5_validacion_a`: **exit 0**.
Nombre ausente en `51_container_names_after.txt`; volumen propio ausente en
`52_volumes_after.txt` y `53_volume_absence.txt`. No se eliminaron otros recursos.
No hubo conexiones, arranques, paradas ni inspección individual de contenedores
preexistentes.

## 10. Estado Git y alcance

Únicamente se crearon archivos en este directorio nuevo. El manifiesto SHA-256
anterior/posterior acredita que las fuentes SQL leídas permanecen idénticas.
`git diff --check`: exit 0 (no valida por sí solo archivos no rastreados).
No se realizó staging, commit, push ni merge. Cambios previos preservados:

```text
 M unidades/unidad-5/specs/design.md
 M unidades/unidad-5/specs/requirements.md
?? odd/
?? unidades/unidad-5/sql/
?? unidades/unidad-5/validacion_parte_a/
```

TDD OFF por autorización explícita para validación de integración:
RED no activo; GREEN no activo. No se declara aceptación ni finalización de la
validación integral. **Detenido a la espera de revisión/autorización humana.**
