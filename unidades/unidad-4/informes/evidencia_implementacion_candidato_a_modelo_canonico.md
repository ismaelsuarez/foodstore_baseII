# U4 — Implementación del candidato A: Fase 6 detenida por deadlock

**FASE 6 = FAIL / STOP.** El candidato se instaló y superó las pruebas
funcionales, pero el cuarto ensayo concurrente produjo **SQLSTATE 40P01**.
Se respetó la condición de detención: sin parche, repetición del escenario,
benchmark READ AFTER, mantenimiento manual final, DOWN, dump Phase6 ni commit.

El estado final es **INSTALLED_EXPERIMENTAL_FAILED**, no ADOPTED. Esta evidencia
registra el resultado negativo; no habilita a continuar ni modifica el rechazo
histórico de U4 o la decisión de selección experimental de Fase 5.

## 1. Identidad y fuentes

| Dato | Valor |
|---|---|
| Fecha / CURRENT_DATE | 2026-09-23 |
| Repositorio | C:/Users/facu/Documents/UTN/Base_datos_II/foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD de partida y al detenerse | dec15881f66b1c29baf95dbf422ff0a7774dc0b1 |
| Motor | PostgreSQL 17.11 |
| Base descartable | foodstore_u4_revalidacion |
| Fuente canónica | schema.sql + datos_iniciales.sql del checkpoint e5282f6 |
| Dataset | Phase3, sin restaurar dumps antiguos |
| Capa TPI | EXCLUDED_FROM_PRIMARY_U4_BASELINE |
| Parte 1 FNBC | Ausente, retirada en su fase |
| Commit Phase6 | NOT_CREATED |

Dump Phase3 verificado sin restaurar, SHA-256:
75DE3D6B072AF714B44944C862767B1CA6E619716A425F8194C7B248F93F24CE.

Fuentes versionadas: [decisión Fase5](decision_patron_parte2_modelo_canonico.md),
[spec del candidato](../specs/u4_desnormalizacion_top_categorias.md),
[dataset](evidencia_dataset_parte2_modelo_canonico.md),
[baseline READ previo](evidencia_baseline_parte2_modelo_canonico.md),
[UP/DOWN](../sql/tp_desnormalizacion_top_categorias.sql) y
[pruebas](../sql/pruebas_candidato_a_modelo_canonico.sql).

Evidencia operativa local: directorio temporal
C:/Users/facu/AppData/Local/Temp/foodstore-u4-phase6-vv6w4o92.
Se conservaron state.json, JSON de cada medición, stdout/stderr, installation.*,
functional.*, s1/s2/s3/s4 de sesiones y monitor, s4_cycle.json y s4_b.stderr.
La ruta temporal no se supone permanente; los resultados esenciales quedan aquí.

## 2. Precheck y alcance implementado

Precheck real PASS: Git limpio en el HEAD esperado; PostgreSQL y fecha correctos;
conteos 8 / 20.000 / 50.000 / 200.000 / 500.000; ausencia de objetos U4,
FNBC, TPI y de detalle_pedido.categoria_id antes del UP. Integridad sin errores.
Los 14 índices estructurales/UNIQUE/PK existentes permanecieron sin cambios:
incluyen los seis índices explícitos raíz + TP5.

- Raíz: idx_producto_categoria, idx_pedido_usuario, idx_producto_nombre_vig.
- TP5: idx_producto_stock_bajo, idx_pedido_fecha_reciente, idx_usuario_mail_lower.

El UP crea exclusivamente la redundancia experimental categoria_id BIGINT NOT NULL,
su FK fk_detalle_pedido_categoria con ON DELETE RESTRICT y estos cuatro objetos:

| Objeto | Responsabilidad |
|---|---|
| fn_detalle_pedido_set_categoria | Derivar desde producto bajo FOR SHARE |
| trg_detalle_pedido_set_categoria | BEFORE INSERT o UPDATE de producto_id/categoria_id |
| fn_producto_sync_categoria_detalle | Propagar categoría modificada a todos sus detalles |
| trg_producto_sync_categoria_detalle | AFTER UPDATE de producto.categoria_id |

Ambas funciones son VOLATILE. La fuente continúa siendo producto.categoria_id:
se representa la categoría actual, no una categoría histórica de venta.
No hay filtro de bajas en la propagación; no se alteran stock, subtotal ni total.
La asignación directa incorrecta del derivado se sobrescribe. La actualización
sin cambio de categoría no reescribe detalles, mediante IS DISTINCT FROM.
No se creó ningún índice adicional, vista ni materializada.

## 3. Instalación real y backfill

UP ejecutado **una sola vez**, con ON_ERROR_STOP, exit code 0 y COMMIT.
La carga mantuvo producto/detalle bloqueados durante la migración.
Backfill: **500.000 filas**. Auditoría posterior: NULL = 0,
referencias huérfanas = 0, desincronizaciones = 0.
NOT NULL se aplicó antes de la FK después de verificar el backfill;
ambas restricciones se confirmaron en la misma transacción.

Los tiempos siguientes son duración de instrucciones informada por psql,
no Execution Time de EXPLAIN y no benchmark READ:

| Etapa | Duración ms |
|---|---:|
| ADD COLUMN | 1.569 |
| Backfill | 6001.146 |
| NOT NULL | 69.236 |
| FK validada | 88.600 |
| Función de derivación | 4.992 |
| Trigger de derivación | 0.462 |
| Función de propagación | 0.171 |
| Trigger de propagación | 0.204 |
| Suma de cuatro instrucciones de funciones/triggers | 5.829 |

No se reinstaló el UP al corregir el parser de tiempos del helper.

## 4. Protocolo de costo de escritura

Cuatro series ejecutadas antes del ensayo concurrente: WRITE BEFORE,
WRITE AFTER, recategorización de fan-out real y recategorización de estrés.
Cada serie contiene **1 WARMUP + 5 corridas oficiales**, sin excluir outliers.
Métrica principal: Execution Time de EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
Cada invocación termina en ROLLBACK y comprueba huellas de datos, índices
y secuencias. No se consume nextval: IDs explícitos con OVERRIDING SYSTEM VALUE.

WRITE BEFORE/AFTER utiliza exactamente el mismo INSERT de 1.000 detalles
sin enviar categoria_id, con preparación de 1.000 pedidos fuera del plan medido.
RETURNING verifica Actual Rows = 1.000. La comparación evalúa el candidato
completo —columna, FK, lectura protegida y trigger—, no el trigger aislado.

Fan-out real: producto 1 con 12 detalles. Estrés: el mismo producto más 1.000
detalles temporales, total 1.012. La sentencia medida modifica un producto:
Actual Rows = 1; los 12/1.012 detalles propagados se verifican por conteo.
El fixture de estrés se prepara fuera de EXPLAIN y se revierte.

Las tablas siguientes muestran buffers **del nodo raíz**: hit/read/dirtied/written.
No se sumaron padres e hijos. Temp read/write = 0 en todas las corridas.
Estos buffers no se presentan como inventario completo del trabajo interno
del trigger AFTER; su UPDATE anidado no tiene un plan separado capturado.

Execution Time incluye los triggers ejecutados; el tiempo del nodo DML no incluye
el trabajo AFTER y los tiempos de triggers se reportan separadamente. No sumar
otra vez esos tiempos al Execution Time. Véase
[PostgreSQL 17 — Using EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html).

### WRITE BEFORE — 1.000 detalles
| Corrida | Planning ms | Execution ms | Actual Rows | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.17 | 26.621 | 1000 | 3987 | 0 | 24 | 18 |
| RUN_1 | 0.097 | 24.154 | 1000 | 6882 | 0 | 11 | 11 |
| RUN_2 | 0.104 | 22.575 | 1000 | 6880 | 0 | 11 | 11 |
| RUN_3 | 0.155 | 27.606 | 1000 | 6882 | 0 | 12 | 12 |
| RUN_4 | 0.108 | 24.88 | 1000 | 6882 | 0 | 11 | 11 |
| RUN_5 | 0.111 | 24.278 | 1000 | 6880 | 0 | 11 | 11 |

Oficiales: MIN **22.575**; MAX **27.606**; MEDIA **24.6986**; MEDIANA **24.278 ms**.

### WRITE AFTER — 1.000 detalles
| Corrida | Planning ms | Execution ms | Actual Rows | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.096 | 38.899 | 1000 | 10041 | 20 | 39 | 3 |
| RUN_1 | 0.131 | 42.032 | 1000 | 11847 | 18 | 13 | 0 |
| RUN_2 | 0.128 | 40.567 | 1000 | 11845 | 18 | 13 | 0 |
| RUN_3 | 0.119 | 41.588 | 1000 | 11845 | 18 | 13 | 0 |
| RUN_4 | 0.115 | 39.408 | 1000 | 11845 | 18 | 13 | 0 |
| RUN_5 | 0.137 | 39.203 | 1000 | 11845 | 18 | 13 | 0 |

Oficiales: MIN **39.203**; MAX **42.032**; MEDIA **40.5596**; MEDIANA **40.567 ms**.

### UPDATE — fan-out real 12
| Corrida | Planning ms | Execution ms | Actual Rows | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.089 | 40.571 | 1 | 20 | 9 | 6 | 0 |
| RUN_1 | 0.089 | 32.093 | 1 | 20 | 9 | 3 | 0 |
| RUN_2 | 0.087 | 30.913 | 1 | 19 | 10 | 3 | 0 |
| RUN_3 | 0.081 | 30.655 | 1 | 20 | 9 | 3 | 0 |
| RUN_4 | 0.083 | 32.38 | 1 | 19 | 10 | 3 | 0 |
| RUN_5 | 0.085 | 32.051 | 1 | 20 | 9 | 3 | 0 |

Oficiales: MIN **30.655**; MAX **32.38**; MEDIA **31.6184**; MEDIANA **32.051 ms**.

### UPDATE — fan-out de estrés 1.012
| Corrida | Planning ms | Execution ms | Actual Rows | Hit | Read | Dirtied | Written |
|---|---:|---:|---:|---:|---:|---:|---:|
| WARMUP | 0.104 | 63.165 | 1 | 15 | 9 | 3 | 0 |
| RUN_1 | 0.087 | 62.675 | 1 | 15 | 9 | 3 | 0 |
| RUN_2 | 0.1 | 76.46 | 1 | 15 | 9 | 3 | 0 |
| RUN_3 | 0.149 | 76.755 | 1 | 15 | 9 | 3 | 0 |
| RUN_4 | 0.117 | 76.184 | 1 | 15 | 9 | 3 | 0 |
| RUN_5 | 0.095 | 71.381 | 1 | 15 | 9 | 3 | 0 |

Oficiales: MIN **62.675**; MAX **76.755**; MEDIA **72.691**; MEDIANA **76.184 ms**.

La mediana INSERT pasó de **24.278 a 40.567 ms**, incremento observado
**67.09 %**: (40.567 / 24.278 - 1) × 100.
No se atribuye causalidad exclusiva al trigger ni se extrapola a otra carga.
La recategorización pasó de mediana 32.051 ms con 12 detalles a 76.184 ms
con 1.012; son dos cargas distintas, no una curva general de escalabilidad.

### Tiempos de triggers registrados

Derivación: trg_detalle_pedido_set_categoria, 1.000 llamadas por INSERT de la
serie WRITE AFTER; su disparo sigue siendo BEFORE, no AFTER.
Propagación: trg_producto_sync_categoria_detalle, una llamada por UPDATE.
FK nueva: fk_detalle_pedido_categoria, 1.000 llamadas por INSERT de WRITE AFTER.

| Corrida | Derivación INSERT ms | FK categoría INSERT ms | Propagación real ms | Propagación estrés ms |
|---|---:|---:|---:|---:|
| WARMUP | 8.13 | 5.875 | 39.577 | 62.672 |
| RUN_1 | 7.595 | 6.806 | 31.499 | 62.225 |
| RUN_2 | 7.429 | 6.623 | 30.379 | 75.927 |
| RUN_3 | 7.276 | 6.494 | 30.149 | 76.024 |
| RUN_4 | 7.194 | 6.441 | 31.789 | 75.602 |
| RUN_5 | 7.618 | 6.216 | 31.496 | 70.882 |

Las FK canónicas también se ejecutaron y sus tiempos están conservados en JSON.
No se midió el plan interno de la función ni se deduce un scan concreto solo
de su duración. El fan-out y la ausencia de un índice nuevo son hechos;
la atribución del costo interno es una interpretación limitada.

## 5. Pruebas funcionales A–I

Ejecución real exit code 0, con nueve NOTICE PASS y confirmación global.
ROLLBACK posterior: datos, índices y secuencias intactos.

| Caso | Resultado observado |
|---|---|
| A | INSERT sin categoría deriva la correcta |
| B | Categoría válida pero incorrecta enviada en INSERT se sobrescribe |
| C | Cambio de producto deriva categoría y conserva precio/subtotal históricos |
| D | Escritura directa incorrecta y NULL en categoria_id se corrigen |
| E | Producto inexistente: SQLSTATE 23503; constraint fk_detalle_pedido_producto |
| F | Producto NULL: SQLSTATE 23502; columna producto_id |
| G | Recategorización propagada a 13 detalles del producto 1 |
| H | Detalles y padres con bajas lógicas siguen sincronizados |
| I | Categoría sin cambio conserva ctid de detalles: sin reescritura |

G tiene 13 detalles porque el fixture funcional agrega uno neto al producto 1;
el fan-out medido fuera del fixture es 12. E es un error explícito del trigger
identificado con el nombre de la FK existente, no una ejecución de esa FK.
F suministra categoría válida para aislar NOT NULL de producto_id.
No se interpreta la sincronización de bajas como política de inventario.

## 6. Equivalencia semántica

Consulta normalizada y candidata ejecutadas sin EXPLAIN como comprobación,
no como benchmark READ AFTER. Agregado completo del día: **8 grupos**.
EXCEPT original menos candidato = **0**; inverso = **0**.
Se repitió la comprobación de solo lectura en la auditoría final.

| Categoría Top 5 | total_vendido |
|---|---:|
| __U4_LAB_CATEGORIA_07__ | 194538488.00 |
| __U4_LAB_CATEGORIA_03__ | 90236048.00 |
| __U4_LAB_CATEGORIA_06__ | 88912722.00 |
| __U4_LAB_CATEGORIA_05__ | 74717570.00 |
| __U4_LAB_CATEGORIA_08__ | 40242037.00 |

Resultado idéntico al checkpoint canónico. Esto acredita equivalencia del
estado ensayado; no elimina el fallo concurrente.

## 7. Concurrencia real: tres PASS y un FAIL

Dos conexiones independientes A/B y una tercera de monitor; READ COMMITTED.
Las sesiones A/B usaron SET LOCAL lock_timeout='15s' dentro de su transacción,
sin modificar configuración global. El error observado fue deadlock 40P01,
no expiración de ese límite de espera.
No se dedujo bloqueo por tiempo: pg_stat_activity y pg_blocking_pids lo acreditan.
PIDs circunstanciales, no identificadores persistentes.

| Escenario | PID A | PID B | Espera observada | Resultado |
|---|---:|---:|---|---|
| S1 INSERT primero / recategorización después | 22392 | 24800 | B → A; Lock / transactionid | PASS, ambos COMMIT |
| S2 Recategorización primero / INSERT después | 22716 | 4296 | A → B; Lock / transactionid | PASS, ambos COMMIT |
| S3 Cambio de producto / recategorización del destino | 12052 | 19488 | A → B; Lock / transactionid | PASS, ambos COMMIT |
| S4 Manipulación directa / recategorización, orden inverso | 25256 | 23392 | A ↔ B; Lock / transactionid | FAIL, 40P01 en B |

S1: 15:35:05.870781–15:35:08.308981; S2: 15:35:08.312005–15:35:10.820977;
S3: 15:35:10.825048–15:35:13.465326; S4: 15:35:13.467331–15:35:16.472346.
Todos corresponden a 2026-09-23, zona -03:00.

S1/S2 crean pedido 1100001 y detalle 2100001 dentro de A.
S3/S4 confirman esos fixtures antes de abrir las transacciones concurrentes.
Recategorización a categoría 8; producto fuente 1, destino 3 en S3.
Después de S1–S3, desincronizaciones = 0 y cleanup exclusivo del fixture.
No se extrapola esa aprobación a todo DML concurrente.

### S4: cronograma adversarial ejecutado

1. A inicia y bloquea detalle 2100001 mediante SELECT ... FOR UPDATE.
2. B recategoriza producto 1 a categoría 8. Su AFTER intenta actualizar detalles
   y espera el detalle retenido por A.
3. El monitor acredita B bloqueada por A.
4. A intenta UPDATE detalle_pedido SET categoria_id=7 WHERE id=2100001.
   Su BEFORE solicita FOR SHARE de producto, retenido por B.
5. El monitor acredita ambas aristas. PostgreSQL selecciona B como víctima
   de deadlock; se detiene la fase, sin reintentar el experimento.

s4_cycle.json, timestamp 2026-09-23T18:35:15.294257+00:00:

| Proceso | Transacción propia | Espera | Bloqueador |
|---|---|---|---|
| A 25256 | 1243, ExclusiveLock concedido | ShareLock en 1244 no concedido | B 23392 |
| B 23392 | 1244, ExclusiveLock concedido | ShareLock en 1243 no concedido | A 25256 |

Error real de s4_b.stderr:

~~~text
ERROR:  40P01: se ha detectado un deadlock
DETAIL:  El proceso 23392 espera ShareLock en transacción 1243; bloqueado por proceso 25256.
El proceso 25256 espera ShareLock en transacción 1244; bloqueado por proceso 23392.
HINT:  Vea el registro del servidor para obtener detalles de las consultas.
CONTEXT:  mientras se bloqueaba la tupla (225,1) de la relación «detalle_pedido»
sentencia SQL: «UPDATE public.detalle_pedido
        SET categoria_id=NEW.categoria_id
        WHERE producto_id=NEW.id
          AND categoria_id IS DISTINCT FROM NEW.categoria_id»
función PL/pgSQL fn_producto_sync_categoria_detalle() en la línea 4 en sentencia SQL
LOCATION:  DeadLockReport, deadlock.c:1135
~~~

**Causa acreditada:** inversión detalle → producto en la manipulación directa
frente a producto → detalle en el fan-out. FOR SHARE protege la lectura de
categoría, pero no hace compatibles estos órdenes de bloqueo.

Es un fallo del **candidato experimental en el ensayo productivo**, no una
incidencia del parser o de la herramienta. La condición de parada no permite
declararlo PASS porque PostgreSQL haya resuelto el deadlock abortando una TX.

## 8. Cleanup seguro y auditoría final

Se revirtieron únicamente transacciones propias, se eliminaron los fixtures
reservados y se restauraron las categorías originales registradas de los
productos afectados. No se repitió ningún escenario ni se parcheó el SQL.

Auditoría final de solo lectura:

| Comprobación | Resultado |
|---|---:|
| categoria / usuario / producto / pedido / detalle | 8 / 20.000 / 50.000 / 200.000 / 500.000 |
| Categoria redundante NULL | 0 |
| Desincronizaciones respecto de producto | 0 |
| FK huérfanas | 0 |
| Subtotal inconsistente | 0 |
| Total inconsistente | 0 |
| Pares pedido/producto duplicados | 0 |
| Violaciones CHECK | 0 |
| Fixtures pendientes | 0 |
| Sesiones de prueba pendientes | 0 |

Las huellas lógicas MD5 por todas las filas y columnas canónicas de las cinco
tablas coinciden exactamente con el preflight. En detalle se excluye únicamente
la nueva columna redundante para comparar el contrato original.
Las 14 definiciones de índices permanecen idénticas; los seis explícitos
raíz + TP5 siguen presentes.

El candidato permanece instalado: categoria_id BIGINT NOT NULL, FK RESTRICT,
dos funciones VOLATILE y dos triggers habilitados. No hay TPI, FNBC,
vistas/materializadas ni otros objetos experimentales.

## 9. Estado físico: diagnóstico, no estado estabilizado

Valores en bytes de pg_relation_size y pg_total_relation_size.
n_live_tup/n_dead_tup son diagnósticos estadísticos, no conteos exactos de filas.
Los INSERT revertidos y el backfill generan versiones físicas: no atribuir
el aumento exclusivamente a los ocho bytes nominales del BIGINT.

| Momento / tabla | Heap bytes | Total bytes | n_dead_tup |
|---|---:|---:|---:|
| Preflight / detalle_pedido | 46546944 | 73637888 | 1 |
| Preflight / pedido | 16891904 | 36552704 | 1 |
| Preflight / producto | 7454720 | 15220736 | 1 |
| Pre-UP, después de WRITE BEFORE / detalle_pedido | 47104000 | 74244096 | 6001 |
| Pre-UP, después de WRITE BEFORE / pedido | 17399808 | 37429248 | 6001 |
| Pre-UP, después de WRITE BEFORE / producto | 7454720 | 15220736 | 1 |
| Post-UP / detalle_pedido | 97673216 | 151830528 | 506001 |
| Post-UP / pedido | 17399808 | 37429248 | 6001 |
| Post-UP / producto | 7454720 | 15220736 | 1 |
| Final, sin VACUUM manual / detalle_pedido | 97673216 | 151928832 | 18260 |
| Final, sin VACUUM manual / pedido | 18415616 | 39165952 | 18008 |
| Final, sin VACUUM manual / producto | 7454720 | 15220736 | 24 |

No se ejecutó el VACUUM manual final autorizado: quedó pendiente por STOP.
Los n_live_tup finales fueron detalle_pedido = 500.000, pedido = 200.000 y
producto = 50.000; son diagnósticos estadísticos, separados de los COUNT reales.
Frente al checkpoint Phase3, el heap de detalle creció 51.126.272 bytes
(109.84 %) y su tamaño total 78.290.944 bytes (106.32 %). Estos aumentos
incluyen la evolución física del ensayo y no son el costo aislado del BIGINT.
Sí se observó mantenimiento automático de PostgreSQL sobre detalle_pedido:
last_autovacuum = 2026-09-23T15:29:22.72511-03:00;
last_autoanalyze = 2026-09-23T15:29:23.738646-03:00.
No equivale a completar la etapa manual ni acredita estabilización global.

La evolución física y el mantenimiento automático limitan la comparabilidad
temporal BEFORE/AFTER: se conserva el resultado medido sin atribuir todo el
67.09 % a una única causa ni presentarlo como una constante de producción.

## 10. Reversibilidad y checkpoint no ejecutados

El SQL contiene un DOWN explícito y limitado a los objetos candidatos, sin
CASCADE ni eliminación de tablas canónicas. **Su existencia no es prueba de
reversibilidad ejecutada.** Después del deadlock no se continuó con esa etapa.

| Etapa pendiente | Estado |
|---|---|
| VACUUM manual final | NOT_EXECUTED_STOP_40P01 |
| DOWN real y validación / ROLLBACK | NOT_EXECUTED_STOP_40P01 |
| Dump Phase6 y pg_restore --list | NOT_CREATED_STOP_40P01 |
| Benchmark READ AFTER | NOT_EXECUTED |
| ADOPT | NO |
| Staging / commit local | NOT_CREATED |

El dump Phase3 anterior no fue restaurado ni sobrescrito.

## 11. Incidencias del harness, separadas del fallo SQL

1. El alias python no estaba disponible. Se utilizó el lanzador py instalado;
   no se había intentado SQL en esa incidencia.
2. El parser temporal esperaba punto decimal y psql produjo coma en los tiempos
   del UP. La instalación ya había finalizado con exit 0/COMMIT. Se ajustó solo
   el lector del log guardado; no se repitió la instalación ni se alteró SQL.
3. El verificador final de logs trató un objeto JSON guardado como un array
   mediante [0] y produjo KeyError: 0. Se corrigió el lector en memoria, sin
   ejecutar SQL nuevamente. Las cuatro series y sus medianas se conciliaron
   independientemente con los JSON originales.

Estas tres incidencias no son el 40P01. El deadlock S4 sí pertenece al
comportamiento concurrente del candidato y es la razón del FAIL global.

## 12. Archivos y estado de entrega

Al documentar la detención, el alcance es exactamente:

- Modificado: ../sql/tp_desnormalizacion_top_categorias.sql.
- Nuevo: ../sql/pruebas_candidato_a_modelo_canonico.sql.
- Nuevo: este archivo de evidencia.

No se modifican spec, schema.sql, datos_iniciales.sql, TPI, Unidad3, FNBC,
informes históricos ni main. HEAD permanece dec15881f66b1c29baf95dbf422ff0a7774dc0b1.
No se creó commit y el working tree conserva estos tres cambios sin staging
para revisión del fallo; no se hizo push.

## 13. Conclusión y siguiente paso

La derivación y la equivalencia del estado probado funcionaron, pero el
candidato mínimo **no supera la condición de concurrencia** de esta fase.
Los costos de escritura están medidos; no existe todavía una medida READ AFTER
ni una decisión de adopción. Tres escenarios concurrentes favorables no
neutralizan el ciclo de bloqueo demostrado en el cuarto.

Siguiente acción: revisar el fallo y acordar expresamente si se rediseña
la disciplina de acceso/bloqueo o se abandona este candidato, incluyendo
autorización para cualquier limpieza estructural pendiente. No proponer como
hecho un arreglo no ensayado ni continuar automáticamente a otra fase.

## 14. Apéndice cronológico — recuperación autorizada Fase 6R

**Fecha: 2026-09-23.** Este apéndice registra actuaciones posteriores al STOP de
Fase 6. No reemplaza ni corrige retroactivamente sus resultados: **Fase 6 sigue
FAIL_CONCURRENCY_40P01**. No se repitió S4 ni se ejecutó benchmark READ AFTER.

La nueva autorización permitió preservar el candidato fallido y probar su
reversibilidad. Motor PostgreSQL 17.11; base foodstore_u4_revalidacion.
Los archivos SQL del candidato y de pruebas permanecieron sin modificaciones.

### 14.1. Dump forense nuevo

Se creó un backup custom del estado con el candidato todavía instalado,
antes de la prueba DOWN:

| Dato | Resultado real |
|---|---|
| Archivo local, ignorado por Git | backups/foodstore_u4_phase6_failed_candidate.dump |
| Formato | pg_dump custom |
| Tamaño | 11.294.222 bytes |
| Fecha UTC | 2026-09-23T22:58:23.939309+00:00 |
| pg_dump | Exit code 0 |
| pg_restore --list | Exit code 0 |
| SHA-256 | 29CB54FCD4CC5EEEB5C5155C7B439C0E8C9F2555BBCC815FE69635B28E966BBD |

Es un respaldo **forense del experimento fallido**, no un checkpoint Phase6 PASS.
No se restauró ese dump en esta actuación. No se sobrescribió el dump Phase3.

### 14.2. DOWN real posterior al fallo

Se extrajeron exactamente las seis sentencias del bloque BEGIN_DOWN / END_DOWN
del SQL preservado. Se ejecutaron dentro de una transacción BEGIN:

1. Retirar trg_producto_sync_categoria_detalle.
2. Retirar fn_producto_sync_categoria_detalle.
3. Retirar trg_detalle_pedido_set_categoria.
4. Retirar fn_detalle_pedido_set_categoria.
5. Retirar fk_detalle_pedido_categoria.
6. Retirar únicamente detalle_pedido.categoria_id.

Sin CASCADE ni eliminación de tablas canónicas. La verificación **dentro de esa
transacción**, antes del ROLLBACK, acreditó:

| Comprobación tras DOWN | Resultado |
|---|---|
| Dos funciones y dos triggers candidatos | Ausentes |
| Columna y FK redundantes | Ausentes |
| Tablas canónicas | 5 |
| Columnas canónicas | 40 |
| Restricciones canónicas | 18 |
| Definiciones de índices preservadas | 14, incluidos los seis explícitos raíz + TP5 |
| Conteos categoria / usuario / producto / pedido / detalle | 8 / 20.000 / 50.000 / 200.000 / 500.000 |
| Huellas de datos canónicos | Idénticas al estado de referencia |
| Subtotales inconsistentes | 0 |
| Totales inconsistentes | 0 |

Después se ejecutó **ROLLBACK**, no COMMIT del DOWN. Se recuperaron la columna,
la FK, las dos funciones y los dos triggers candidatos. La auditoría posterior
post_down confirmó conteos y huellas de las cinco tablas, secuencias idénticas,
índices intactos y cero errores FK, UNIQUE, CHECK, desincronización y categoría NULL.

**DOWN_TEST_AFTER_FAILURE = PASS.** Esto prueba la reversibilidad estructural
ensayada; **no convierte el resultado de concurrencia en PASS**.

### 14.3. Incidencias del helper de recuperación

- Get-FileHash no estaba disponible en el entorno utilizado; tampoco
  hashlib.file_digest. El SHA-256 se calculó leyendo el archivo por bloques.
  No hubo error SQL ni sustitución del backup por un dump anterior.
- El primer comparador temporal utilizó una fórmula de hash distinta:
  hashes individuales anidados frente a la referencia MD5 de string_agg de
  cada fila JSON separada por LF. Se corrigió solamente ese comparador temporal,
  usando la misma fórmula original; todas las huellas coincidieron.
  No se modificaron filas para hacer coincidir los hashes.

Estas incidencias son del arnés de recuperación y permanecen separadas del
deadlock real del candidato documentado en la sección 7.

Logs de Fase6R:
C:/Users/facu/AppData/Local/Temp/foodstore-u4-phase6r-xh8stnpk.
Fuentes de esta ampliación: forensic_dump.json, forensic_dump.list,
down_post_fail.sql, preflight.json y post_down.json. La ruta es temporal;
los resultados esenciales quedan resumidos en este apéndice.

### 14.4. Estado al cerrar este apéndice

- Fase6: FAIL_CONCURRENCY_40P01, sin parche ni reejecución del escenario fallido.
- Dump forense: creado y listado correctamente.
- DOWN real posterior: PASS dentro de una transacción revertida.
- Base: candidato fallido nuevamente instalado por efecto del ROLLBACK.
- Restauración del checkpoint Phase3: **pendiente**, no acreditada aquí.
- Commits de preservación/recuperación: **pendientes**, no acreditados aquí.
- Nueva alternativa: no implementada; READ AFTER no ejecutado.

Cualquier actuación posterior deberá registrarse cronológicamente, sin alterar
el resultado original ni presentar como concluida una etapa todavía pendiente.
