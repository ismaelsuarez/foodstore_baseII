# U4 — Análisis de remediación después del fallo del candidato A

**Fase 6 conserva FAIL_CONCURRENCY_40P01. Fase 6R preservó el fallo, acreditó el DOWN y restauró el laboratorio canónico
desde Phase3.** Se selecciona exclusivamente **E — serialización transaccional previa con ruta cerrada** como
**REMEDIATION_CANDIDATE_SELECTED_FOR_EXPERIMENT**, no ADOPTED.

La selección es de diseño: necesita autorización nueva y expresa para cambiar el contrato de acceso mediante
API/roles/permisos. No implementa un reemplazo, no autoriza ejecutarlo y no convierte el ensayo fallido en PASS. Si debe
seguir permitido DML arbitrario sin coordinación, **E no satisface ese requisito**.

| Contexto | Valor |
|---|---|
| Fecha / CURRENT_DATE | 2026-09-23 |
| Repositorio | C:/Users/facu/Documents/UTN/Base_datos_II/foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD al redactar | 7eea571c915101bbda7edf0264da41a1a30b5155 |
| Commit anterior preservado | test(u4): documentar fallo concurrente candidato A |
| Base | foodstore_u4_revalidacion |
| Motor | PostgreSQL 17.11 |
| Estado de la nueva alternativa | Solo análisis; no instalada |
| Commit de este análisis | Pendiente al redactar |

**Fuentes:** [evidencia Fase6 y apéndice Fase6R](evidencia_implementacion_candidato_a_modelo_canonico.md), [SQL del candidato
fallido](../sql/tp_desnormalizacion_top_categorias.sql), [pruebas
preservadas](../sql/pruebas_candidato_a_modelo_canonico.sql), [decisión Fase5](decision_patron_parte2_modelo_canonico.md),
[spec](../specs/u4_desnormalizacion_top_categorias.md), [baseline](evidencia_baseline_parte2_modelo_canonico.md), [dataset
Phase3](evidencia_dataset_parte2_modelo_canonico.md) y [schema canónico](../../../schema.sql). Se distinguen hechos
ejecutados, inferencias y pruebas futuras.

## 1. Resultado de Phase6 y recuperación posterior

### Resultado preservado

Hechos ejecutados: UP/backfill de 500.000 filas, funcionales A–I y equivalencia EXCEPT 0/0 pasaron. Tres escenarios
concurrentes pasaron; S4 produjo deadlock 40P01. Se detuvo sin parche, repetición favorable, READ AFTER, adopción o commit de
implementación exitosa. La evidencia original permanece en el commit 7eea571c915101bbda7edf0264da41a1a30b5155 junto con los
SQL del ensayo fallido.

El apéndice de esa evidencia acredita posteriormente:

- Dump forense custom backups/foodstore_u4_phase6_failed_candidate.dump,
  11.294.222 bytes, pg_dump y pg_restore --list exit 0.
- SHA-256: 29CB54FCD4CC5EEEB5C5155C7B439C0E8C9F2555BBCC815FE69635B28E966BBD.
- DOWN exacto de seis sentencias dentro de BEGIN: retiro de dos triggers,
  dos funciones, FK y columna redundantes; catálogo/datos canónicos intactos.
- ROLLBACK del DOWN: candidato recuperado, secuencias/huellas iguales.
  **DOWN_TEST_AFTER_FAILURE = PASS**, sin cambiar FAIL_CONCURRENCY_40P01.

pg_restore --list verificó el catálogo TOC del dump forense, no una restauración de ese archivo. La restauración real
posterior corresponde únicamente a Phase3.

### Restauración real posterior al apéndice

Esta actuación ocurrió **después** del estado «restauración pendiente» registrado en el apéndice anterior; se documenta aquí
sin reescribir aquella cronología.

Se confirmó que no había sesiones conectadas. Se eliminó y recreó exclusivamente foodstore_u4_revalidacion, sin FORCE ni
terminación arbitraria de sesiones. createdb utilizó template0, encoding UTF8 y locale Spanish_Argentina.1252. Se restauró el
dump Phase3 autorizado con pg_restore --exit-on-error --single-transaction. dropdb, createdb y pg_restore finalizaron con
exit code 0. Marca UTC de la recuperación: **2026-09-23T23:03:43.014547+00:00**. Los nombres/OID de las otras bases
permanecieron inalterados.

Fuente restaurada: backups/foodstore_u4_revalidacion_phase3.dump. SHA-256 verificado nuevamente antes de restaurar:
75DE3D6B072AF714B44944C862767B1CA6E619716A425F8194C7B248F93F24CE. No se utilizó el dump forense como bootstrap ni dumps
históricos del modelo viejo.

Auditoría real posterior, conservada en restored.json bajo C:/Users/facu/AppData/Local/Temp/foodstore-u4-phase6r-xh8stnpk:

| Comprobación | Resultado |
|---|---|
| categoria / usuario / producto / pedido / detalle | 8 / 20.000 / 50.000 / 200.000 / 500.000 |
| Pedidos del día / vigentes | 20.000 / 19.800 |
| Detalles del día / utilizables por ambos filtros | 50.000 / 48.900 |
| Categorías del reporte | 8 |
| Subtotal / total / FK / duplicados / CHECK incorrectos | 0 / 0 / 0 / 0 / 0 |
| Tablas / columnas / restricciones canónicas | 5 / 40 / 18 |
| Definiciones de índices | 14 idénticas, incluidos los seis explícitos raíz + TP5 |
| Huellas de las cinco tablas | Idénticas al preflight canónico |
| Secuencias | Idénticas al checkpoint |
| Rutinas/triggers de usuario, FNBC, TPI, vistas/materializadas | 0 |
| detalle_pedido.categoria_id y FK candidata | Ausentes |

Las huellas se compararon con la misma fórmula: MD5 del string_agg de filas JSON ordenadas por id y separadas por LF; no
mezclar con hashes anidados. Los estados de secuencia (last_value, is_called) conservados son: categoria (9,true), usuario
(20001,true), producto (50001,true), pedido (200001,true), detalle_pedido (500001,true). Son los estados del dump, incluidos
los avances de secuencia ocasionados por INSERT de prueba luego revertidos; ROLLBACK no revierte nextval. No son errores de conteo.

Top 5 restaurado: 07 = 194538488.00; 03 = 90236048.00; 06 = 88912722.00; 05 = 74717570.00; 08 = 40242037.00, con nombres
__U4_LAB_CATEGORIA_07__, __U4_LAB_CATEGORIA_03__, __U4_LAB_CATEGORIA_06__, __U4_LAB_CATEGORIA_05__, __U4_LAB_CATEGORIA_08__,
respectivamente.

### Recuperación lógica, no snapshot físico idéntico

La siguiente tabla corresponde a la lectura inmediata posterior a la restauración,
conservada en restored.json; no es una promesa de tamaños físicos inmutables.

| Tabla | Heap Phase3 bytes | Heap restaurado bytes | Total Phase3 bytes | Total restaurado bytes |
|---|---:|---:|---:|---:|
| detalle_pedido | 46546944 | 46923776 | 73637888 | 73957376 |
| pedido | 16891904 | 16908288 | 36552704 | 36569088 |
| producto | 7454720 | 7536640 | 15220736 | 14974976 |

Otras tablas restauradas: usuario heap 3276800 / total 5767168 bytes; categoria heap 8192 / total 40960 bytes. La escala es
comparable, pero un dump lógico no reproduce byte a byte páginas, cachés ni estadísticas del optimizador. No se ejecutaron
ANALYZE/VACUUM manuales ni un benchmark nuevo en Fase6R. Por ello una comparación temporal futura requiere un protocolo nuevo
autorizado; no atribuir idéntico estado físico a la restauración. Antes de un nuevo READ AFTER habrá que autorizar la
preparación de estadísticas y confirmar un BEFORE comparable; **212.668 ms no es una constante portable** entre estados
físicos diferentes.

Una segunda auditoría final de solo lectura confirmó las mismas huellas, secuencias,
índices y datos. Sus tamaños fueron:

| Tabla | Heap final bytes | Total final bytes |
|---|---:|---:|
| detalle_pedido | 46923776 | 73998336 |
| pedido | 16908288 | 36601856 |
| producto | 7536640 | 15007744 |
| usuario | 2760704 | 5283840 |
| categoria | 8192 | 40960 |

pg_stat_user_tables mostró mantenimiento automático en detalle, pedido, producto
y usuario. Para detalle: last_autovacuum = 2026-09-23T20:04:48.536121-03:00 y
last_autoanalyze = 2026-09-23T20:04:49.04745-03:00; categoria conservó NULL.
Los demás timestamps y el diagnóstico completo están en final_pg_stats.json,
en el directorio temporal de esta recuperación.
n_dead_tup = 0 en las cinco tablas y n_live_tup coincidió con los conteos esperados.
Esta evolución física no es un cambio lógico del dataset ni un fallo del restore.
No se ejecutaron ANALYZE/VACUUM manuales ni se modificó configuración global;
el autovacuum observado no acredita un benchmark nuevo ni igualdad física exacta.

## 2. Deadlock exacto: qué falló

S4 bajo READ COMMITTED:

1. A, PID 25256, transacción 1243, bloqueó detalle 2100001 con FOR UPDATE.
2. B, PID 23392, transacción 1244, recategorizó producto 1 a categoría 8.
3. El AFTER de B intentó propagar sobre el detalle retenido por A.
4. A intentó asignar categoria_id=7 al detalle; su BEFORE pidió FOR SHARE
   del producto retenido por B.
5. PostgreSQL abortó B con **40P01**, en
   fn_producto_sync_categoria_detalle(), línea 4, UPDATE de detalle.

El error y la secuencia están preservados en la evidencia Fase6, secciones 7 y 8, y en s4_b.stderr/s4_cycle.json del ensayo.
No fue un timeout de lock_timeout='15s' ni un error del helper.

## 3. Grafo de locks observado

~~~text
A (25256, TX 1243)
  posee: lock del detalle
  espera: ShareLock sobre TX 1244 / producto de B
            ↓
B (23392, TX 1244)
  posee: lock del producto
  espera: ShareLock sobre TX 1243 / detalle de A
            ↓
A
~~~

Ambas sesiones figuraron active, Lock / transactionid. Los ShareLock esperados no estaban concedidos; cada sesión conservaba
ExclusiveLock sobre su propia transacción. Los PIDs/TX son circunstanciales.

**Hecho:** existe este ciclo concreto. **Inferencia:** cualquier remediación que mantenga ambas rutas y sus órdenes inversos
necesita demostrar cómo evita o controla ese ciclo; no basta que otros tres cronogramas hayan pasado.

## 4. Por qué FOR SHARE no bastó

FOR SHARE protege la lectura de la categoría frente a actualizaciones conflictivas del producto. No decide qué fila se
bloqueó antes de entrar al trigger: UPDATE del detalle puede haberla retenido previamente. La propagación hace producto →
detalle y la ruta directa detalle → producto.

Fortalecer el lock del producto no reorganiza la adquisición previa. Debilitarlo a FOR KEY SHARE sobre la categoría no clave
tampoco es una reparación: puede permitir una recategorización mientras se deriva una categoría anterior. Eliminarlo pierde
la coordinación que motivó su incorporación.

La defensa por orden consistente y las diferencias de modos se documentan en [PostgreSQL 17 — Explicit
Locking](https://www.postgresql.org/docs/17/explicit-locking.html). No se promete ausencia universal de deadlocks.

## 5. Costos observados y límite de la hipótesis

Hechos conservados de Phase6, con 1 warmup + 5 oficiales:

| Medición | Mediana |
|---|---:|
| INSERT 1.000 detalles BEFORE | 24.278 ms |
| INSERT 1.000 detalles AFTER | 40.567 ms |
| UPDATE de categoría, fan-out 12 | 32.051 ms |
| UPDATE de categoría, fan-out 1.012 | 76.184 ms |

Incremento observado de mediana INSERT: **67.09 %**. Backfill: 6001.146 ms según timing de psql. Estos valores no son
benchmark READ AFTER ni costo aislado del trigger: el candidato agrega columna, FK, sincronización y locking. Hubo residuos
físicos de ROLLBACK/backfill y autovacuum automático; no se extrapolan a otro workload ni se suman buffers de padres/hijos.

El baseline READ vigente acreditado fue 212.668 ms de mediana, 6794 hits raíz, 5682 en detalle y 910 en producto. Eliminar el
JOIN de producto no elimina el recorrido de detalle ni la unión con pedidos/agregación. No existe prueba de que el costo
adicional de una nueva serialización quede compensado.

## 6. Alternativas A–F

### A. Cambiar modos de lock

Mantener lock conflictivo conserva el posible ciclo; quitarlo puede sacrificar consistencia. NOWAIT/timeouts cambiarían
espera por error, no demostrarían progreso correcto de ambas transacciones. No seleccionado.

### B. Restringir DML directo

Prohibir solo la escritura de categoria_id no cubre cambio de producto, otras modificaciones del detalle ni SELECT FOR UPDATE
previo. Una ruta cerrada puede reducir ese universo, pero sin protocolo de adquisición sigue incompleta. **B es requisito de
enforcement de E, no un segundo candidato seleccionado.**

### C. Categoría snapshot de venta

Evita parte de la propagación posterior conservando el valor al vender. Sin embargo, la consulta oficial atribuye ventas a la
categoría **actual** de producto. Cambia los resultados tras recategorizar y requiere una decisión de negocio distinta; no es
una remediación equivalente.

### D. FK compuesta con ON UPDATE CASCADE

Conceptualmente, (producto_id,categoria_id) del detalle referenciaría (id,categoria_id) de producto mediante una clave UNIQUE
adicional y ON UPDATE CASCADE. Fortalece la relación declarativa y desplaza la propagación a mecanismos nativos; no completa
por sí sola una categoría omitida ni garantiza ausencia de deadlocks entre padre/hijo u operaciones multifila.

Requeriría evaluar el nuevo índice/constraint, derivación, FK originales, SQLSTATE y cascadas. No se afirma que reproduzca
exactamente S4 ni que lo evite: es otra implementación sin ensayo. Referencia: [PostgreSQL 17 —
Constraints](https://www.postgresql.org/docs/17/ddl-constraints.html).

### E. Serialización explícita previa y ruta cerrada

Proponer un gate transaccional exclusivo para el universo producto/detalle, adquirido **antes de cualquier lock relevante** y
mantenido hasta terminar la transacción. Un gate global es el diseño inicial más simple de razonar; serializa también
productos distintos y varias llamadas de la misma transacción.

La coordinación no puede incorporarse tarde en BEFORE ROW. Tampoco basta un BEFORE STATEMENT si la transacción ya bloqueó
filas anteriormente. Debe existir una ruta de entrada cerrada que haga imposible ese prebloqueo para el rol operativo, no una
recomendación voluntaria al llamante.

Un advisory lock transaccional es una posible implementación futura del gate, no algo instalado: PostgreSQL no obliga a los
demás clientes a respetarlo. Por ello permisos y control de todas las rutas son parte de la solución.

### F. Vista materializada

Una MV por fecha/categoría reduciría lecturas, pero necesita refresh. CONCURRENTLY permite consultas durante refresh; no
ofrece actualización incremental automática ni visibilidad inmediata de toda venta recién confirmada. Un refresh periódico
cambia el contrato de frescura y necesita staleness aceptado. No se selecciona bajo tiempo real estricto. Referencia:
[PostgreSQL 17 — REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/17/sql-refreshmaterializedview.html).

## 7. Matriz comparativa

Sin scores ni porcentajes hipotéticos. «Pendiente» no significa garantía probada.

| Opción | Consistencia | Tiempo real | Riesgo de deadlock | Costo esperado | Complejidad |
|---|---|---|---|---|---|
| A | Puede debilitarse al retirar conflicto | Solo si deriva correctamente | Orden inverso permanece | Cambio pequeño; errores/esperas posibles | Cambio local, razonamiento insuficiente |
| B | Depende de cubrir rutas | Compatible | Restricción parcial no lo elimina | Control de acceso/API | Inventario y cierre de privilegios |
| C | Coherente como snapshot, no como categoría actual | Inmediato para otra semántica | Reduce propagación; no garantía global | Menos fan-out; redundancia persiste | Nueva regla de negocio |
| D | FK compuesta más fuerte | Cascada en la transacción | Ciclos padre/hijo aún a probar | UNIQUE/FK/cascada, posible índice hijo | Rediseño declarativo y derivación |
| E | Invariante bajo rutas coordinadas, pendiente de prueba | Misma transacción, sin refresh | Ataca ciclo ensayado dentro del universo cerrado | Serialización, cola, fan-out y storage | Gate, API, roles, pruebas multifila |
| F | Consistente con snapshot materializado | No inmediato entre refresh | Riesgos de refresh/otras operaciones | Lectura reducida; costo desplazado a refresh | Scheduler, SLA y control de refresh |

| Opción | Impacto en contrato | Encaje en consigna | Cambio semántico | Evidencia faltante |
|---|---|---|---|---|
| A | Puede alterar errores/esperas | No demuestra remedio suficiente | Riesgo de categoría obsoleta | Carreras, errores y progreso |
| B | Restringe DML previamente libre | Soporte de un patrón, no patrón autónomo | No cambia agregación; sí acceso | Permisos reales y bypass |
| C | Cambia atribución de ventas | No equivalente a consulta vigente | Sí: categoría histórica | Aceptación académica/de negocio y nueva equivalencia |
| D | Nuevas claves/FK e interacción con errores | Variante de redundancia, a justificar | No necesariamente; requiere derivación equivalente | Cascadas concurrentes, costos, reversión |
| E | Ruta cerrada obligatoria, nuevo contrato operativo | Redundancia sincronizada con tiempo real, condicional | No cambia agregado; sí acceso/concurrencia | Permisos, snapshots, rollback, colas, costos, DOWN |
| F | Aceptar staleness y mantenimiento | Patrón permitido, frescura incompatible hoy | Cambia frescura; no necesariamente agregado | SLA, refresh, carga, concurrencia y cambio de día |

## 8. Único candidato seleccionado para un próximo ensayo

**E = REMEDIATION_CANDIDATE_SELECTED_FOR_EXPERIMENT. No ADOPTED.** B es su prerrequisito de control de acceso, no una segunda alternativa
experimental.

Esta selección **no cambia el contrato vigente** de manera tácita. Antes de implementar hay que autorizar explícitamente
API/roles/permisos y aceptar que el DML directo arbitrario deja de ser ruta soportada para el rol operativo. Si el ejercicio
exige conservarlo libre, rechazar E y detener ese diseño.

Contrato conceptual futuro mínimo:

1. Toda transacción que vaya a tomar locks relevantes de producto/detalle
   adquiere el gate antes de tocar esas filas; abarca escrituras, borrados y
   lecturas bloqueantes, no solo las dos columnas de categoría.
2. El gate se conserva durante toda la transacción, incluidas múltiples llamadas.
   No se libera entre una modificación y la propagación, ni se adquiere después.
3. El rol operativo no es superuser ni propietario y carece de bypass por DML,
   privilegios heredados, SET ROLE indebido, funciones alternativas o desactivación
   de triggers. Debe seguir pudiendo efectuar las operaciones autorizadas por API.
4. El diseño de privilegios elevados de esa API, si fueran necesarios, requiere
   revisión separada: propietario, search_path, grants y alcance, sin inventar
   una solución segura solo por nombrar una rutina.
5. Bajo READ COMMITTED, la fuente debe leerse con snapshot adecuado **después**
   de adquirir el gate/esperar, no reutilizar datos capturados antes. Debe probarse.
6. Operaciones multifila y varias recategorizaciones deben obedecer el mismo
   protocolo; no introducir una segunda adquisición en orden incompatible.
7. No se promete protección ante superusuarios que ignoran el protocolo ni
   ante ciclos con tablas/recursos fuera del universo cubierto, incluidas otras FK.

## 9. Razones de la selección

El antecedente 95fbfbf ya concluyó **REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT**:
mejora de lectura limitada frente a buffers, escrituras y complejidad de sincronización.
Sus métricas no son comparables con este laboratorio y no se importan como resultados actuales.
Ese rechazo, el 40P01 real y el incremento INSERT observado de 67.09 % exigen evidencia fuerte
para cualquier nuevo ensayo; no se adopta una alternativa por necesidad de presentar una optimización.

E trata la causa acreditada —dos órdenes opuestos— antes de que se forme el ciclo, en vez de cambiar el modo de espera una
vez retenida la primera fila. Mantiene categoría actual, bajas incluidas y sincronización dentro de la transacción; no
depende de refresh ni redefine historial.

Es una hipótesis falsable, no un éxito anticipado: **si la ruta cerrada realmente impone el gate previo, los cronogramas
autorizados deben esperar antes de adquirir locks incompatibles y finalizar con el invariante conservado, incluso con
rollback y operaciones múltiples.** El beneficio debe superar costos admitidos. No garantiza rendimiento mejor ni ausencia
universal de deadlocks.

## 10. Riesgos y límites

- El gate global limita concurrencia aunque las operaciones usen productos distintos.
- Una transacción larga prolonga la cola; no hay SLA de espera aprobado.
- Un permiso residual o una ruta administrativa no coordinada puede romper el orden.
- Un gate tomado desde un trigger después de un lock previo vuelve a ser tardío.
- Locks de otras tablas/FK, orden de varias operaciones y nivel de aislamiento
  pueden crear ciclos fuera del caso probado.
- Snapshots tomados antes de la espera pueden invalidar una derivación aparentemente
  serializada. No asumir que adquirir el lock renueva toda lectura anterior.
- Rollback, errores, cancelaciones y desconexiones requieren pruebas de liberación
  y atomicidad; no ocultar abortos con reintentos ilimitados.
- Persisten redundancia, backfill, costo de propagación y recorrido de detalle.
- El laboratorio restaurado es lógicamente equivalente, no físicamente idéntico.
  Repetir tiempos contra caché/estadísticas distintas requiere protocolo comparable.
- TPI permanece excluido; integrar sus locks/derivados es otra fase, no algo probado.

## 11. Pruebas necesarias antes de continuar

Ninguna de las siguientes se ejecuta en este análisis:

| Área | Prueba futura obligatoria |
|---|---|
| Preflight | Base restaurada, fecha, integridad, índices, sin restos experimentales |
| Privilegios | Rol operativo no superuser; DML/SELECT FOR UPDATE bypass rechazados realmente |
| Ruta autorizada | INSERT, cambio de producto, recategorización, manipulación y bajas |
| Orden | Gate observado antes del primer lock de datos; ambos órdenes de llegada |
| S4 | Bypass rechazado y operación equivalente por API sin ciclo del ensayo anterior |
| Multifila | Productos en órdenes opuestos, varias filas y varias llamadas por transacción |
| Visibilidad | READ COMMITTED después de espera ve fuente confirmada correcta |
| Atomicidad | COMMIT/ROLLBACK, error, cancelación y desconexión; liberar gate |
| Concurrencia | Dos conexiones y monitor; bloqueos, SQLSTATE y resultado final registrados |
| Consistencia | Auditoría global sin filtrar bajas, NULL/FK/UNIQUE/CHECK y EXCEPT 0/0 |
| Escritura | Mismo fixture/protocolo, incluir espera/cola y productos distintos |
| Lectura | Solo después de autorización, protocolo comparable 1 warmup + 5, sin outliers retirados |
| Costos físicos | Backfill, tamaños, versiones muertas y mantenimiento documentado |
| Reversibilidad | DOWN real de objetos y cambios de permisos, sin dañar fuentes canónicas |

Los presupuestos de INSERT, UPDATE, espera, throughput y almacenamiento deben acordarse antes de pretender ADOPT. No se
inventan umbrales favorables a posteriori. Las puertas de lectura de Fase5 no se rebajan silenciosamente; si la recuperación
requiere un nuevo BEFORE por estado físico, debe autorizarse y documentarse antes de comparar, no reemplazar retroactivamente
el baseline medido.

## 12. Condiciones de rechazo y siguiente autorización

Rechazar E o detener su ensayo si:

- No se acepta formalmente la ruta cerrada, o debe mantenerse DML arbitrario libre.
- El rol puede tomar locks de datos antes del gate o eludir la API.
- Se reproduce un ciclo relevante, una carrera, inconsistencia o pérdida de atomicidad.
- Cambia la categoría actual por snapshot o se requiere refresh para tiempo real.
- La cola/costo de escritura excede presupuestos aprobados, o no existen presupuestos
  suficientes para sostener una decisión de adopción.
- El nuevo READ no demuestra mejora bajo el protocolo y puertas aceptados.
- DOWN/recuperación de permisos deja objetos, accesos o datos fuera de contrato.
- La comparación no es reproducible o se descartan fallos/corridas para fabricar PASS.

**Siguiente paso propuesto:** solicitar autorización para diseñar y probar la ruta cerrada/gate, sus roles y pruebas, con
alcance reversible definido. Hasta entonces no instalar otra desnormalización, no modificar schema.sql ni TPI y no ejecutar
un AFTER. La recuperación del laboratorio ya está acreditada; la remediación del candidato todavía no.
