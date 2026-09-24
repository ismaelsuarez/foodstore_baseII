# U4 — Fase 6E: remediación serializada con ruta de acceso cerrada

**HARD GATES = PASS en los escenarios ejecutados. Candidato instalado, EXPERIMENTAL / NOT_ADOPTED.**
No se ejecutó benchmark READ AFTER del Top 5. La aprobación funcional no decide adopción ni borra el fallo anterior.
Se registró una incidencia del arnés concurrente, conservada y separada del resultado PostgreSQL.

## 1. Identidad y antecedentes preservados

| Dato | Valor |
|---|---|
| Fecha / CURRENT_DATE | 2026-09-23 |
| Repo | C:/Users/facu/Documents/UTN/Base_datos_II/foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD base de esta ejecución | 15ef165c4bf5803dfd123706fd92cb821f96bfb7 |
| PostgreSQL | 17.11, x86_64-windows, msvc-19.44.35228, 64-bit |
| Base exclusiva de datos | foodstore_u4_revalidacion |
| Fuente estructural y seed | schema.sql + datos_iniciales.sql canónicos de e5282f6 |
| Dataset | Phase3 restaurado y validado por Fase6R |
| TPI / FNBC / MV | Ausentes; TPI excluido del baseline primario |
| Estado Git inicial | CLEAN |

El candidato original sigue **FAIL_CONCURRENCY_40P01**. Su S4, código y pruebas quedan preservados en
7eea571c915101bbda7edf0264da41a1a30b5155 y en la [evidencia original](evidencia_implementacion_candidato_a_modelo_canonico.md).
No se modificaron ese documento ni [sus pruebas](../sql/pruebas_candidato_a_modelo_canonico.sql).
Se mantienen: INSERT +67.09 %, backfill 6001.146 ms, fan-out 12/1012 y sus costos.

Dump Phase3 verificado, no restaurado en esta fase:
`backups/foodstore_u4_revalidacion_phase3.dump`, SHA-256
`75DE3D6B072AF714B44944C862767B1CA6E619716A425F8194C7B248F93F24CE`.
El dump forense previo no se sobrescribió ni utilizó como bootstrap.

Fuentes entregables: [UP/DOWN](../sql/tp_desnormalizacion_top_categorias.sql),
[pruebas nuevas](../sql/pruebas_remediacion_serializada_modelo_canonico.sql) y
[análisis previo](analisis_remediacion_candidato_a.md). El cambio de contrato de acceso fue autorizado expresamente
después de ese análisis; no se atribuye retrospectivamente a la spec histórica.

## 2. Frontera de acceso implementada

Roles nuevos de clúster, sin membresías, con permisos de objetos únicamente en el laboratorio:

- `u4_app`: LOGIN, no superusuario, sin CREATEDB/CREATEROLE/BYPASSRLS/REPLICATION, NOINHERIT.
- `u4_owner`: NOLOGIN y mismas restricciones administrativas; propietario del esquema `u4_api` y sus funciones,
  no de tablas canónicas.
- `u4_app` puede leer categoria/producto/pedido/detalle y ejecutar cuatro API. No puede leer usuario.
- No tiene DML directo, UPDATE de ninguna columna, CREATE en public/u4_api ni acceso directo a helpers.
- `u4_owner` solo recibe SELECT de id/categoria de producto y UPDATE de categoría; SELECT de id/producto/categoría
  de detalle, UPDATE de producto/categoría e INSERT de las columnas explícitas del fixture.
- No se concedieron privilegios de secuencias. Los fixtures usan IDs explícitos y OVERRIDING SYSTEM VALUE.

API SECURITY DEFINER, VOLATILE, propietario u4_owner, `search_path=pg_catalog, pg_temp`, tablas calificadas,
sin SQL dinámico, sin STRICT y sin control interno de COMMIT:

| API | Firma / retorno |
|---|---|
| insertar_detalles | (jsonb) RETURNS SETOF bigint |
| cambiar_producto_detalle | (bigint,bigint) RETURNS void |
| normalizar_categoria_detalle | (bigint,bigint) RETURNS void |
| recategorizar_producto | (bigint,bigint) RETURNS void |

EXECUTE se revocó de PUBLIC para las siete funciones. Solo las cuatro API se concedieron a u4_app.
Los tres helpers son SECURITY INVOKER y se ejecutan por los triggers en el contexto de la API.
Las cuatro API adquieren como primera instrucción `pg_catalog.pg_advisory_xact_lock(21812,1)`.
21812 codifica U4 (85*256+52); 1 identifica el protocolo experimental. No se afirma unicidad universal.

### Autenticación real, no impersonación de superusuario

Las sesiones operativas conectaron por psql como u4_app: session_user=current_user=u4_app y rolsuper=false.
El administrador solo instaló, preparó/limpió fixtures y monitoreó. No se utilizó SET ROLE como sustituto de LOGIN real.
Se usó la autenticación SCRAM-SHA-256 ya configurada para localhost. La credencial fue efímera en memoria,
sin archivo, argumento de proceso, SQL versionado ni log permanente. Su provisión usó entrada estándar y un
verificador SCRAM calculado en memoria; se suprimió el registro de sentencias sensibles solo en esa conexión administrativa.
No se cambió configuración global ni pg_hba.conf. Al finalizar cada grupo se retiró la contraseña del rol.

La huella de reglas HBA y la configuración global registrada coinciden antes/después. Otros nombres/OID de bases
no cambiaron; las dependencias de estos roles en otras bases son cero. Los roles son cluster-wide: no se presentan
como roles físicamente locales ni como prohibición universal de CONNECT heredado de PUBLIC en otras bases.

## 3. Orden de locks y objetos

Contrato operativo: **permisos cerrados -> API -> gate transaccional -> locks de datos -> sincronización -> COMMIT/ROLLBACK**.
READ COMMITTED fue el aislamiento de concurrencia. La lectura en la función VOLATILE ocurre después de adquirir/esperar el gate.
El gate global permanece hasta el final de la transacción y también serializa productos distintos.

Helpers: `u4_api.fn_gate_categoria`, `u4_api.fn_detalle_pedido_set_categoria`,
`u4_api.fn_producto_sync_categoria_detalle`.

| Trigger | Nivel / evento |
|---|---|
| trg_detalle_pedido_gate_categoria | BEFORE STATEMENT INSERT / UPDATE OF producto_id,categoria_id |
| trg_producto_gate_categoria | BEFORE STATEMENT UPDATE OF categoria_id |
| trg_detalle_pedido_set_categoria | BEFORE ROW, deriva categoría desde producto bajo FOR SHARE |
| trg_producto_sync_categoria_detalle | AFTER ROW, propaga cambio de categoría a todos los detalles |

Los statement triggers son defensa adicional: NO interceptan SELECT FOR UPDATE previo. La garantía frente a ese
bypass viene de permisos y API. Se conserva FOR SHARE como protección de la lectura, no como cura aislada del deadlock.
La propagación incluye bajas y utiliza IS DISTINCT FROM. No toca stock, subtotal ni total.
La extensión es `detalle_pedido.categoria_id BIGINT NOT NULL`, FK `fk_detalle_pedido_categoria`
contra categoria(id), ON DELETE RESTRICT. No se agregó ningún índice.

La API es un acceso DML del laboratorio, no una API completa de ventas. El coordinador prepara importes/totales
coherentes y elimina o revierte fixtures; la integración con TPI sigue sin probarse.

## 4. Instalación y backfill reales

UP ejecutado una sola vez, ON_ERROR_STOP, exit 0 y COMMIT. Backfill de 500000 filas; NULL/desync/FK de categoría=0.
Se verificó el backfill antes de NOT NULL/FK. La migración retuvo locks de tablas hasta instalar el conjunto completo.
Los siguientes tiempos son de instrucciones psql, no Execution Time de un benchmark READ:

| Instrucción | ms |
|---|---:|
| ADD COLUMN | 0.468 |
| Backfill | 4853.635 |
| NOT NULL | 57.129 |
| FK | 71.113 |
| Función gate | 0.795 |
| Función de derivación | 0.341 |
| Función de propagación | 0.221 |
| Trigger statement detalle | 0.234 |
| Trigger statement producto | 0.209 |
| Trigger row detalle | 0.194 |
| Trigger row producto | 0.150 |
| API insertar / cambiar / normalizar / recategorizar | 0.225 / 0.185 / 0.173 / 0.234 |

Los ALTER OWNER, REVOKE y GRANT también quedaron en installation.stdout; no se incorporan a una métrica de lectura.

## 5. Permisos y pruebas negativas

SELECT normal sobre producto/detalle y API reversible: permitidos. Revisión de permisos efectivos incluyendo columnas,
PUBLIC y membresías: app sin UPDATE/INSERT, sin propiedad ni membresía privilegiada.
Las siguientes quince pruebas independientes devolvieron realmente **42501 — insufficient_privilege**:

| Intento | Casos | SQLSTATE observado |
|---|---:|---|
| INSERT directo detalle | 1 | 42501 |
| UPDATE categoría / otra columna de detalle | 2 | 42501 |
| UPDATE directo producto | 1 | 42501 |
| FOR UPDATE, NO KEY UPDATE, SHARE, KEY SHARE en ambas tablas | 8 | 42501 |
| SET ROLE u4_owner | 1 | 42501 |
| ALTER / CREATE OR REPLACE función API | 2 | 42501 |

La prueba versionada agregó rechazo de lectura de usuario y comprobación de helpers no ejecutables.
Se corrige expresamente la expectativa equivocada 23501 de la revisión inicial: el código real fue 42501.
Los rechazos se capturan como resultados esperados, no se ocultan como ejecución exitosa del DML.

En PostgreSQL17 las cláusulas de row-lock requieren UPDATE sobre al menos una columna, además de SELECT;
por eso se negó UPDATE completo, no solo de las columnas de sincronización.
Referencia: [SELECT](https://www.postgresql.org/docs/17/sql-select.html).

## 6. Funcionales y errores canónicos

Prueba versionada ejecutada con LOGIN real, exit 0, BEGIN/ROLLBACK. Pedidos1200001..1200003 preparados por
administrador; detalles2200001..2200003 creados por API y revertidos. Pedidos administrativos limpiados después.

| Caso | Resultado real |
|---|---|
| A | INSERT sin categoría útil deriva la actual; observado también en S1/S2 y lote de escritura |
| B | INSERT con categoría incorrecta se normaliza |
| C | Cambio de producto recalcula categoría, conserva precio/subtotal históricos |
| D | Categoría incorrecta por API no persiste; escritura directa rechazada |
| E | Producto inexistente: 23503, fk_detalle_pedido_producto |
| F | Producto NULL: 23502, columna producto_id |
| G/H | Recategorización propaga incluyendo detalle eliminado |
| I | Mismo valor no reescribe detalles: ctid anterior/posterior idéntico |

Subtransacciones de errores conservan la transacción exterior y su gate; el ROLLBACK exterior los libera.
No se probaron reglas nuevas de cancelación o reposición.

## 7. S4 histórico y nueva concurrencia

S4 original permanece como **DIRECT SQL BYPASS / NEGATIVE TEST**. El SQL exacto de prebloqueo
`SELECT id FROM detalle_pedido WHERE id=2100001 FOR UPDATE` se ejecutó como u4_app sobre fixture existente:
**S4_ORIGINAL_DIRECT_SQL = BYPASS_BLOCKED, SQLSTATE 42501**. No se continuó a construir el ciclo.
No se llama PASS funcional al S4 original ni se cambia el resultado histórico 40P01.

S4_AUTHORIZED_ROUTE es otro ensayo: A llama normalizar_categoria_detalle; B recategorizar_producto.
S1/S2 usan pedidos precreados por administrador porque app no crea pedidos. Es una adaptación explícita del fixture,
no un ensayo de creación de pedidos ni una reproducción idéntica del antiguo DML administrativo.

Dos procesos psql de aplicación independientes más monitor administrativo. SET LOCAL lock_timeout=15s en las
transacciones, sin modificar configuración global. Tras confirmar el primer DML con pg_stat_activity se lanzó el segundo.
Cada espera se acreditó por Lock/advisory, pg_blocking_pids y pg_locks, no solo por tiempo.

| Escenario | PID A / B | Resultado | Espera observada aproximada s |
|---|---|---|---:|
| S1 | 18216 / 17972 | PASS, Lock/advisory, desync=0 | 0.163647 |
| S2 | 10220 / 11956 | PASS, Lock/advisory, desync=0 | 0.281098 |
| S3 | 13876 / 10936 | PASS, Lock/advisory, desync=0 | 0.175487 |
| S4_AUTHORIZED_ROUTE | 15188 / 12532 | PASS, Lock/advisory, desync=0 | 0.185563 |
| S5 | 1552 / 8212 | PASS, Lock/advisory, desync=0 | 1.395788 |
| S6 | 6692 / 16700 | PASS, Lock/advisory, desync=0 | 0.190964 |

S1: INSERT primero; S2: recategorización primero; S3: cambio al producto destino mientras se recategoriza;
S4: normalización autorizada frente a recategorización. S1–S5 confirmaron ambas operaciones y luego se limpiaron
fixtures/restauraron categorías originales. S6 revirtió ambas operaciones. No se consumieron secuencias.

En S4 A15188 retuvo advisory ExclusiveLock concedido; B12532 esperó el mismo lock, classid21812/objid1/objsubid2.
El monitor no mostró locks de relación de B sobre las tablas protegidas ni espera de transactionid/tupla antes del gate.
No se formó el ciclo antiguo. Los PIDs son circunstanciales de esta ejecución.

### S5–S8 y costo de contención

- S5: productos1 y3 distintos quedaron serializados. Espera observada1.395788s, incluyendo una retención deliberada
  de1.2s después de observar el bloqueo. Es GLOBAL_SERIALIZATION_COST, no una estimación de throughput de producción.
- S6: ROLLBACK del titular liberó gate y permitió continuar al segundo actor.
- S7: error deliberado de división por cero, SQLSTATE real22012. El monitor comprobó que el backend abortado
  no retenía advisory; el segundo actor continuó. Ambos finalizaron con ROLLBACK.
- S8: una llamada API, un INSERT SELECT y1000 filas verificadas. Catálogo FOR EACH STATEMENT (no FOR EACH ROW)
  en el trigger gate. Se observó una entrada advisory retenida. Esa entrada NO mide cantidad de adquisiciones:
  API y trigger adquieren reentrantemente la misma clave. La multiplicidad por sentencia deriva del catálogo y
  la semántica PostgreSQL, no de un contador de llamadas instrumentado. No hubo adquisición por fila en el código.

**Deadlocks40P01 observados en la nueva ruta:0.** No garantiza ausencia universal de deadlocks.
La garantía no aplica a un superusuario/owner que deliberadamente evite la API. No se repitió el deadlock como administrador.

## 8. Incidencia del arnés, preservada

Primer intento de S1: A16372 insertó y retuvo gate; B11512 esperó correctamente Lock/advisory. El comparador Python
falló porque pg_locks.classid/objid llegaron como cadenas JSON y se compararon con enteros. No hubo error SQL.
El intento se interrumpió antes de COMMIT; ambas transacciones se revirtieron y se limpió el fixture.

Clasificación: **NON_PRODUCT_TEST_HARNESS_INCIDENT**. El registro original concurrency.json contiene FAIL del
orquestador; no significa40P01 ni PASS del escenario. Se conservan failure_s1.json, stdout/stderr y harness_incident.json.
Se informó la causa antes de continuar. Se corrigió únicamente el normalizador temporal y la ejecución completa de
S1–S7 quedó separada en concurrency_validated/. No se alteró el SQL instalado ni se repitió S4_DIRECT negativo.
Un helper de edición del delegado también falló antes de escribir por coincidencia de texto Unicode;
no ejecutó SQL ni produjo archivo parcial. No se confunde ninguna incidencia con el fallo productivo Phase6.

## 9. Escritura: protocolo y comparabilidad

Tres series: INSERT1000, recategorización real y estrés. Cada una tiene1WARMUP+5oficiales, ninguna descartada.
EXPLAIN(ANALYZE,BUFFERS,FORMAT JSON) sobre la API de escritura, no sobre el Top5.
La cifra principal es Execution Time; planes y Planning Time se conservaron por corrida.
Buffers del nodo raíz, sin sumar padres/hijos; no se presenta como idéntica instrumentación a un INSERT directo.

INSERT usa mismos IDs, productos, cantidades e importes del fixture anterior. El payload JSON se prepara fuera
del tiempo medido; su procesamiento dentro de la API sí está incluido. Los pedidos se confirman como fixture administrativo,
las líneas medidas se revierten en cada corrida y luego se limpian los pedidos. Esto difiere del setup anterior en una única TX.
El benchmark mide costo integral API/JSON/privilegios/gate/columna/FK/triggers, no costo aislado del gate.

Fan-out real: producto1,12detalles. Estrés: se agregaron1000detalles exclusivos por API, total1012, antes de medir;
se limpiaron después. Cada recategorización medida terminó en ROLLBACK. Actual Rows=1 en el plan es el resultado
de la llamada, no un contador de filas internas del trigger. El fan-out corresponde al conteo del fixture; la propagación
completa y el invariante se validan en funcionales y auditorías. No se capturó un plan interno independiente del UPDATE.

### INSERT1000 por API

| Corrida | Planning ms | Execution ms | Filas del plan | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.114 | 42.151 | 1000 | 26629 | 0 | 0 | 0 |
| RUN_1 | 0.106 | 34.962 | 1000 | 27732 | 0 | 0 | 0 |
| RUN_2 | 0.108 | 38.640 | 1000 | 27646 | 0 | 0 | 0 |
| RUN_3 | 0.116 | 42.754 | 1000 | 27699 | 0 | 0 | 0 |
| RUN_4 | 0.103 | 35.607 | 1000 | 27709 | 0 | 0 | 0 |
| RUN_5 | 0.150 | 41.443 | 1000 | 27695 | 0 | 9 | 0 |

MIN=34.962; MAX=42.754; MEDIA=38.6812; MEDIANA=38.640ms. Temp read/write=0.

### Recategorización real12

| Corrida | Planning ms | Execution ms | Filas del plan | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.137 | 85.460 | 1 | 11752 | 715 | 0 | 0 |
| RUN_1 | 0.097 | 72.241 | 1 | 11850 | 619 | 1 | 0 |
| RUN_2 | 0.099 | 73.818 | 1 | 11922 | 547 | 1 | 0 |
| RUN_3 | 0.098 | 65.493 | 1 | 12002 | 467 | 0 | 0 |
| RUN_4 | 0.134 | 67.860 | 1 | 12082 | 387 | 0 | 0 |
| RUN_5 | 0.094 | 62.695 | 1 | 12155 | 315 | 0 | 0 |

MIN=62.695; MAX=73.818; MEDIA=68.4214; MEDIANA=67.860ms. Temp read/write=0.

### Recategorización estrés1012

| Corrida | Planning ms | Execution ms | Filas del plan | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.099 | 94.110 | 1 | 32586 | 218 | 16 | 8 |
| RUN_1 | 0.098 | 118.740 | 1 | 34493 | 154 | 10 | 0 |
| RUN_2 | 0.098 | 91.241 | 1 | 34261 | 90 | 7 | 0 |
| RUN_3 | 0.100 | 88.541 | 1 | 34610 | 26 | 6 | 0 |
| RUN_4 | 0.101 | 91.079 | 1 | 34536 | 0 | 6 | 1 |
| RUN_5 | 0.102 | 93.023 | 1 | 34910 | 0 | 0 | 0 |

MIN=88.541; MAX=118.740; MEDIA=96.5248; MEDIANA=91.241ms. Temp read/write=0.

### Comparación aritmética, no causalidad aislada

| Referencia | Mediana INSERT ms |
|---|---:|
| CANONICAL BEFORE, Phase6 preservado | 24.278 |
| FAILED CANDIDATE, Phase6 preservado | 40.567 |
| REMEDIATED CANDIDATE, esta ejecución | 38.640 |

Diferencia respecto del BEFORE: **+59.16 %**; respecto del candidato fallido: **-4.75 %**.
No se reemplaza el +67.09 % original. Estas referencias no aíslan una mejora del gate: cambiaron API,
frontera de medición y estado físico tras restore/backfill. No hay un nuevo BEFORE emparejado de esta API.
Fan-out original32.051/76.184ms y actual67.860/91.241ms se conservan como observaciones de ensayos distintos,
no como una conclusión causal ni umbral de adopción. Las lecturas de bloques en recategorización muestran que
un warmup no implica shared-read=0; se conservaron todas las corridas.

## 10. Auditoría final y equivalencia

Antes y después de pruebas/DOWN: 8categorías,20000usuarios,50000productos,200000pedidos,500000detalles.
Del día:20000pedidos/19800vigentes;50000detalles/48900utilizables;8categorías.
NULL de categoría, desync, FK huérfanas, subtotal, total, pares duplicados y CHECK: **0**.
EXCEPT de los agregados completos: **0/0**. Top5 idéntico:

| Categoría | total_vendido |
|---|---:|
| __U4_LAB_CATEGORIA_07__ | 194538488.00 |
| __U4_LAB_CATEGORIA_03__ | 90236048.00 |
| __U4_LAB_CATEGORIA_06__ | 88912722.00 |
| __U4_LAB_CATEGORIA_05__ | 74717570.00 |
| __U4_LAB_CATEGORIA_08__ | 40242037.00 |

Huellas de todas las columnas canónicas de las cinco tablas y estado de las secuencias idénticos al preflight.
En detalle se excluye solo la columna añadida. Permanecen14índices, incluidos los seis explícitos raíz+TP5;
las18restricciones y40columnas originales están intactas. Sin TPI, FNBC ni vistas/materializadas.
Fixtures pendientes=0; sesiones app/owner=0; advisory gate pendiente=0; contraseña efímera retirada.

## 11. Estado físico y mantenimiento

VACUUM(ANALYZE) de detalle_pedido,producto,pedido,categoria ejecutados, exit0. Sin FULL/CLUSTER/REINDEX.
La siguiente observación es posterior al mantenimiento; live/dead son estadísticas, no conteos exactos ni garantía
de ausencia física de todas las versiones muertas. Una lectura posterior confirmó los mismos valores.

| Tabla | Heap bytes | Total bytes | n_live_tup | n_dead_tup |
|---|---:|---:|---:|---:|
| categoria | 8192 | 73728 | 8 | 0 |
| detalle_pedido | 97116160 | 151298048 | 500000 | 13871 |
| pedido | 17145856 | 37076992 | 200000 | 3009 |
| producto | 7536640 | 15007744 | 50000 | 31 |
| usuario | 2760704 | 5283840 | 20000 | 0 |

| Tabla | Heap preflight restaurado | Total preflight restaurado | Heap Phase3 original | Total Phase3 original |
|---|---:|---:|---:|---:|
| detalle_pedido | 46923776 | 73998336 | 46546944 | 73637888 |
| pedido | 16908288 | 36601856 | 16891904 | 36552704 |
| producto | 7536640 | 15007744 | 7454720 | 15220736 |

El crecimiento incorpora backfill, escrituras revertidas y evolución física del ensayo; no equivale únicamente
a8bytes por fila. VACUUM no se usó para ocultar el costo mediante compactación. Los dead estimados no se sustituyeron
por cero: no se investigó su causa física en esta fase. La preparación/comparabilidad del futuro READ requiere autorización.

## 12. DOWN realmente ejecutado

Se ejecutó el bloque DOWN versionado dentro de BEGIN, tras cerrar conexiones de aplicación. Retiró cuatro triggers,
siete funciones, FK/columna, grants por columna y tabla, esquema, CONNECT/USAGE y los dos roles.
Antes de DROP ROLE se verificaron sesiones, membresías y dependencias compartidas residuales. Sin CASCADE ni DROP OWNED.

Dentro de la transacción: candidato, esquema y roles ausentes; cinco tablas,40columnas,18constraints y14índices presentes;
conteos, huellas de datos y reconciliaciones canónicas intactos. **DOWN=PASS**.
ROLLBACK restauró candidato, roles y permisos; auditoría posterior y EXCEPT0/0 pasaron.
El laboratorio queda con candidato instalado para una revisión futura, no adoptado.

## 13. Backup nuevo y alcance final

- Archivo: `backups/foodstore_u4_revalidacion_phase6e_candidate.dump`.
- Formato custom; bytes: **11305063**.
- Fecha UTC: 2026-09-23T23:50:24.940204+00:00.
- pg_dump exit0; pg_restore --list exit0. No se restauró.
- SHA-256: `7BA7A261AB0923969A304A59BF6C6BF8532AE9D9BC14E036470E278E37D4628F`.

Un dump de base no incluye CREATE ROLE del clúster: cualquier restauración futura deberá planificar los roles/grants
desde el entregable y requerirá autorización nueva. No se incluyeron secretos ni se sobrescribieron backups previos.

Archivos de este cambio exclusivamente:

1. Modificado: ../sql/tp_desnormalizacion_top_categorias.sql.
2. Nuevo: ../sql/pruebas_remediacion_serializada_modelo_canonico.sql.
3. Nuevo: este documento.

El checkpoint local agrupa esos tres archivos; su identificador se obtiene con git log sobre este documento.
No se modifica main, schema raíz, seed, Unidad3, FNBC, spec ni evidencias históricas. No push.

## 14. Trazabilidad operativa y límites

Logs locales: `C:/Users/facu/AppData/Local/Temp/foodstore-u4-phase6e-b754f751`.
Fuentes: preflight/post_install/final/after_down_rollback.json, initial/final/down_equivalence.json,
installation.stdout/stderr, effective_permissions.json, permission_tests.json, s4_original_direct_result.json,
functional.stdout/stderr, concurrency_validated/concurrency.json y capturas s1..s7, s8_result.json,
measurements.json y18planes JSON, final_physical.json, down_test.sql/stdout/stderr, dump.json/list,
cluster_before/final.json y security_final.json. Los orquestadores temporales quedan fuera del repo.
La persistencia de esa ruta no se supone indefinida; las cifras y límites relevantes se preservan aquí.

HARD GATES: privilegios y bypass cerrado, funcionales, S1-S3 y S4autorizado, auditoría/equivalencia y DOWN acreditados.
SOFT COSTS: redundancia, backfill, escritura, propagación y serialización global medidos; sin SLO de producción inventado.
Solo se acredita la ruta operativa autorizada y los cronogramas ejecutados bajo READ COMMITTED. No se acredita DML
administrativo arbitrario, SERIALIZABLE, ausencia universal de deadlocks, integraciónTPI, rendimiento bajo carga ni ADOPT.
No se ejecutó el benchmark READ AFTER oficial. **Siguiente acción: revisión humana de esta evidencia antes de autorizar Fase7.**
