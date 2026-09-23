# Unidad 4 — Selección del candidato experimental de Parte 2

**Decisión Fase 5: alternativa A, columna redundante y triggers revisados, en estado
CANDIDATE_SELECTED_FOR_EXPERIMENT. No está implementada ni ADOPTED.** Se prioriza
la frescura transaccional exigida por el panel; el beneficio de lectura todavía
debe superar las pruebas de corrección y costo. La alternativa B, materializada
estándar, no se selecciona porque su contenido depende del último refresh.

## 1. Contexto y fuentes

| Dato verificado en Fase 5 | Valor |
|---|---|
| Fecha SQL | 2026-09-23 |
| Repositorio | C:\Users\facu\Documents\UTN\Base_datos_II\foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD de partida | 4e1fee66234832fa4e1f89ab19038a6abdd02718 |
| Working tree inicial | CLEAN |
| Base de laboratorio | foodstore_u4_revalidacion |
| Motor | PostgreSQL 17.11 |
| Conteos categoria/usuario/producto/pedido/detalle | 8 / 20000 / 50000 / 200000 / 500000 |
| Catálogo | Seis índices explícitos raíz + TP5 conservados; sin objetos experimentales |
| TPI | EXCLUDED_FROM_PRIMARY_U4_BASELINE |
| FNBC | PASS previo; retirado mediante DOWN |

Fuentes vigentes: [schema.sql](../../../schema.sql), base canónica
e5282f68a4af6975fb953c4f4b74f2e13240a0a6;
[dataset Fase 3](evidencia_dataset_parte2_modelo_canonico.md) y
[baseline Fase 4](evidencia_baseline_parte2_modelo_canonico.md).
El [spec](../specs/u4_desnormalizacion_top_categorias.md) fija el contrato futuro.

Esta fase solo realizó lecturas y diseño documental. No ejecutó DDL, DML,
ANALYZE, REFRESH ni mediciones AFTER. El SQL experimental anterior no se ejecutó
ni modificó. El commit de cierre se verifica por separado: este documento
registra el HEAD desde el que se decidió, no presupone otro commit.

## 2. Baseline que motiva el experimento

Consulta oficial, sin cambiar JOIN, filtros, agrupación, orden o límite:

```sql
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

| Evidencia Fase 4 | Resultado |
|---|---|
| Protocolo | Warm-cache; un warmup y cinco corridas oficiales |
| Execution Time oficiales, ms | 212.668 / 235.256 / 199.683 / 324.541 / 171.081 |
| Mediana / mínimo / máximo, ms | 212.668 / 171.081 / 324.541 |
| Buffers del nodo raíz | 6794 shared hits; 0 reads; 0 temporales |
| Scan detalle | 500000 filas recorridas; 495000 no eliminadas; 5682 hits |
| Acceso a pedido | idx_pedido_fecha_reciente; 153 hits; Heap Fetches=0 |
| JOIN pedido/detalle | 48900 filas elegibles; 5835 hits inclusivos |
| Scan/hash producto | 50000 filas; 910 hits |
| Categoría / Sort | Ocho filas; 3 hits / quicksort, 25 kB, sin spill |

No se suman buffers ni tiempos de padres e hijos. Los hits de producto no son
un ahorro futuro garantizado: la nueva anchura del detalle y la elección del
planner pueden modificar el resto del plan. Todas las corridas permanecen
incluidas, también la más lenta. Fuente: evidencia Fase 4, secciones 6–8.

## 3. Interpretación del camino dominante

**Hecho medido:** pedido ya tiene acceso selectivo por fecha y sin accesos al
heap; detalle se recorre completamente y se une con pedido y producto antes
de producir ocho agregados. LIMIT no reduce ese trabajo previo.

**Inferencia de diseño:** retirar producto del camino puede ahorrar su lectura,
hash y JOIN, pero no elimina el scan de detalle, sus filtros ni el JOIN con
pedido. No se promete una mejora porcentual. Sort no mostró presión de memoria
y no motiva este candidato. La dispersión 171.081–324.541 ms exige una puerta
conservadora antes de presentar una mejora como suficientemente clara.

## 4. Alternativa A — categoría redundante y triggers

### Contrato conceptual

Proponer `detalle_pedido.categoria_id BIGINT NOT NULL`, con FK a categoria(id)
ON DELETE RESTRICT, exclusivamente en el laboratorio. **producto.categoria_id
permanece como única fuente de verdad**. La atribución usa la categoría actual,
no la categoría histórica de la venta. La aplicación no puede imponer otra.

La consulta candidata conserva SUM(dp.subtotal), la fecha y ambos filtros de
baja. Suprime solamente la unión a producto y une categoria.id con la categoría
redundante. No filtra estado, usuario, producto.eliminado, producto.disponible
ni categoria.eliminado: esas condiciones no forman parte de la consulta oficial.

### Migración y almacenamiento pendientes

- Backfill de las 500000 filas en una transacción controlada, sin escritores
  concurrentes durante instalación/backfill; validar antes de confirmar.
- Agregar NOT NULL y FK después de poblar; abortar ante NULL, huérfanas o
  cualquier desincronización. FK por sí sola no garantiza igualdad con producto.
- BIGINT aporta 8 × 500000 = 4000000 bytes nominales de valores. **No es una
  predicción de tamaño físico:** alineación, páginas, versiones MVCC y WAL cambian
  el costo. Medir heap, total, índices y estado físico antes/después.
- No proponer un índice nuevo inicialmente. Un índice de categoria_id no es
  necesario para la integridad ni demuestra utilidad para un reporte sin filtro
  selectivo de categoría. Cualquier nuevo índice sería otro factor experimental.
- La UK existente empieza por pedido_id; no se presupone acceso selectivo por
  producto_id para propagar. La actualización puede recorrer detalle completo.

### Revisión de los mecanismos anteriores

El [SQL histórico](../sql/tp_desnormalizacion_top_categorias.sql), líneas 101–124,
deriva categoría con SELECT sin lock y ejecuta el trigger BEFORE INSERT OR
UPDATE OF producto_id, categoria_id. Corrige una categoría proporcionada
manualmente, pero no coordina esa lectura con una recategorización concurrente.
Las líneas 142–159 propagan cambios del producto a todos sus detalles; incluyen
los eliminados y no hay ciclo porque el trigger del detalle solo asigna NEW.

**Brecha inferida:** una línea puede leer la categoría anterior mientras una
recategorización no ve todavía esa inserción. Las FK de existencia no prueban
que ambos valores coincidan. La nueva implementación no debe copiar sin revisión
esa estrategia de lectura sin bloqueo.

Diseño propuesto, aún sin SQL instalado:

1. BEFORE INSERT y UPDATE OF producto_id, categoria_id: obtener y derivar siempre
   la categoría desde producto, con lectura **FOR SHARE**. No usar FOR KEY SHARE
   como sustituto: no bloquea una actualización de columna no clave.
2. AFTER UPDATE OF categoria_id de producto: si cambia realmente, propagar a
   todos sus detalles, incluidos históricos y eliminados, dentro de la misma
   transacción. No modificar stock, subtotal ni pedido.total.
3. Producto no nulo inexistente: preservar el contrato de referencia inexistente
   con error 23503 explícito e identificado; comprobarlo en pruebas futuras.
   Un producto_id NULL debe conservar el rechazo estructural correspondiente.
   El código viejo puede transformar el producto inexistente en categoria_id NULL
   y producir 23502 antes de la FK. No registrar esos códigos como observados ahora.

FOR SHARE bloquea modificaciones de la fila del producto, incluidas las que usan
FOR NO KEY UPDATE. Las funciones trigger deberán mantener su carácter VOLATILE;
la visibilidad de la propagación tras una espera también requiere ensayo bajo
READ COMMITTED. Es coordinación propuesta, **no una prueba ejecutada de
concurrencia**. Un UPDATE directo del detalle puede bloquear primero detalle y
luego producto, inversamente al fan-out producto→detalle: existe riesgo de deadlock.
Un 40P01 aborta una transacción; no debe ocultarse ni confundirse con consistencia
exitosa. Una futura política de reintento debe abarcar toda la transacción.
Referencia: [PostgreSQL 17, bloqueos explícitos](https://www.postgresql.org/docs/17/explicit-locking.html).

### Fan-out observado mediante SELECT en Fase 5

Distribución de detalles por producto, incluyendo bajas: mínimo **9**, máximo
**12**, promedio **10**, P50 **10**, P95 **11** (percentile_cont); cero productos
sin detalles. El diagnóstico SELECT cuenta detalles por producto, incluye los
productos sin líneas mediante LEFT JOIN y resume esa distribución; no mide tiempos.
La población contiene **5000 detalles eliminados** y también debe
sincronizarlos. Son conteos diagnósticos, no tiempos ni límites de producción:
el ensayo no representará productos con miles de líneas asociadas.

## 5. Alternativa B — vista materializada por fecha y categoría

Diseño conceptual: `(fecha, categoria_id, categoria_nombre, total_vendido)`;
agregar todas las fechas, no fijar CURRENT_DATE dentro de la definición. La
lectura seleccionaría la fecha actual y ordenaría sus agregados. El diagnóstico
del dataset encontró **65 fechas** y **380 grupos fecha/categoría elegibles**;
no son filas de una materializada instalada ni una medición de su tamaño.

Cada lectura evitaría recorrer detalle/producto/pedido y recalcular sus sumas.
Ese trabajo se desplazaría al REFRESH, con almacenamiento para el resultado y
su índice. PostgreSQL estándar no mantiene automáticamente este agregado de
forma incremental: REFRESH vuelve a ejecutar la definición y reemplaza contenido.

Un índice UNIQUE por columnas `(fecha, categoria_id)`, sin predicado ni expresión,
sobre una vista ya poblada permitiría REFRESH CONCURRENTLY. Esta modalidad no
bloquea SELECT ordinarios de la misma manera que el refresh normal, pero no
elimina su costo ni admite varios refresh simultáneos de esa vista. No equivale
a actualización inmediata ni incremental. Referencias:
[materializadas](https://www.postgresql.org/docs/17/rules-materializedviews.html) y
[REFRESH](https://www.postgresql.org/docs/17/sql-refreshmaterializedview.html).

Entre refresh quedan pendientes ventas nuevas, cambios de subtotal, bajas de
pedido/detalle y cambios de categoría de producto. Si se almacena el nombre,
su renombrado también espera refresh. Cambiar de día funciona como filtro sobre
fecha, pero los primeros pedidos del nuevo día no aparecen hasta actualizarla.
No se debe corregir esto fijando una fecha en la definición.

No hay un staleness máximo garantizado sin un SLA de planificación, duración y
recuperación. Bajo supuestos adicionales de intervalos máximos Δ y refresh de
duración máxima R, sin fallos ni retrasos, una cota conservadora sería Δ+R;
**aquí no se eligen Δ/R ni se declara esa garantía**. REFRESH tras cada venta
trasladaría trabajo completo y bloqueo a la escritura; no está implementado ni
probado y no se considera una solución automática al requisito.

La reversión conceptual elimina exclusivamente la MV y su índice; las tablas
fuente conservan los datos. De seleccionarse en otro alcance, habría que medir
lecturas, refresh normal/concurrente, staleness, cambio de día y DOWN real.

## 6. Matriz comparativa

Las latencias indicadas son expectativas cualitativas, no mediciones AFTER.

| Dimensión | A: columna + triggers | B: materializada estándar |
|---|---|---|
| Trabajo eliminado por lectura | Scan/hash de producto y un JOIN | Recorridos y agregación de fuentes; lee grupos persistidos |
| Trabajo restante por lectura | Detalle, pedido, categoría, agrupación, Sort, LIMIT | Filtro de fecha, orden y LIMIT sobre MV |
| Latencia de lectura esperada | Mejora posible y limitada; podría empeorar | Menor trabajo esperado; tiempo todavía desconocido |
| Frescura | Derivación en la misma transacción, si coordinación es correcta | Snapshot del último refresh |
| Tiempo real | Compatible con un nuevo SELECT que vea la venta confirmada | No garantiza visibilidad inmediata de una venta nueva |
| Costo de INSERT | Lectura/lock de producto, columna y FK adicionales | Sin mantenimiento automático; costo diferido al refresh |
| Costo de UPDATE | Recategorizar propaga; reasignar línea rederiva | Fuentes no se propagan hasta refresh |
| Fan-out | Todas las líneas del producto, aun eliminadas | Refresh procesa la definición global |
| Almacenamiento | Una categoría por detalle más efectos físicos | Agregados por fecha/categoría e índice UNIQUE |
| Complejidad | Dos vías de sincronización, locks y auditoría | Refresh, planificación, fallos y SLA de frescura |
| Desincronización | Riesgo de carreras/bypass; requiere prevención y auditoría | Desfase esperado; errores si se presenta como vigente |
| Concurrencia | Pendiente validar INSERT/UPDATE y orden inverso de locks | Lectura concurrente posible; refresh serializado por MV |
| Locks | Producto y detalles; contención y deadlocks posibles | Refresh normal bloquea lectura; concurrente tiene otros costos |
| Reversibilidad | Retirar redundante/mecanismos, conservar producto | Retirar MV/índice, conservar fuentes |
| Auditoría | Igualdad global redundante/fuente y EXCEPT | Equivalencia contra snapshot consistente al refrescar |
| Mantenimiento | Síncrono por escritura; fan-out y observación de locks | Refresh explícito, vigilancia de duración y atraso |
| Ajuste a consigna | Mejor ajuste a frescura inmediata; lectura aún a probar | Admisible como patrón, débil ajuste a tiempo real estricto |
| Evidencia existente | Baseline actual; pruebas históricas limitadas y rechazo | Principios PostgreSQL; no ensayo de esta MV |
| Evidencia faltante | AFTER, costos completos, carreras, casos negativos, DOWN | Lectura, refresh, SLA, cambio de día, concurrencia y DOWN |

## 7. Antecedente histórico y cronología

El cierre 95fbfbf mantuvo **REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT** para el
candidato anterior. Se conserva íntegramente la
[evidencia histórica oficial](evidencia_modelo_oficial.md) y el
[informe de ese cierre](informe_u4_fnbc_desnormalizacion.md).

**HISTORICAL_NOT_COMPARABLE:** ese ensayo ya tenía subtotal físico, bajas lógicas
y fecha DATE; no corresponde afirmar que carecía de ellas. Usó otra copia,
220000 pedidos/550000 detalles, otra fecha y protocolo; no es el dataset canónico
reproducible actual. Sus tiempos y tamaños no se reutilizan como baseline vigente.

Lecciones reutilizables: mejora de lectura insuficientemente clara, crecimiento
de buffers tras backfill, costo de escritura, complejidad y variabilidad. El costo
INSERT histórico aisló el trigger sobre el esquema ya extendido, no el costo total
de columna/FK. Solo se ensayaron dos UPDATE concurrentes del mismo producto;
**INSERT concurrente con recategorización no se probó y DOWN no se ejecutó**.
Fuentes: evidencia histórica, secciones 4, 7 y 8; informe, secciones 4–6.

El nuevo ensayo no anula ni reinterpreta aquel rechazo. Propone cerrar sus brechas
de diseño/prueba sobre otro checkpoint, sin convertir la columna en modelo raíz.

## 8. Interpretación de «en tiempo real y con actualización frecuente»

Se toma en serio la necesidad de reflejar escrituras confirmadas: una consulta
nueva bajo READ COMMITTED, iniciada después del COMMIT, no debe esperar un trabajo
periódico para incluir una venta. No se promete un SLA de milisegundos ni visibilidad
retroactiva dentro de un snapshot anterior; tampoco se diseña el refresco del panel
cliente. La consulta conserva el filtro oficial: no se agrega filtro por estado.

A puede satisfacer esa frescura de los datos si los triggers y la coordinación
transaccional resultan correctos. B estándar no garantiza que una venta recién
confirmada figure inmediatamente. «Refrescar frecuentemente» no equivale a esa
garantía: sin un staleness aceptado por la consigna, no se redefine tiempo real
para favorecer la alternativa con menos trabajo de lectura.

## 9. Candidato seleccionado

**A — categoria_id redundante en detalle, mantenida por triggers revisados.**

Estado único: **CANDIDATE_SELECTED_FOR_EXPERIMENT**. Fuente producto; ámbito
laboratorio; sin adopción ni modificación del schema raíz. La selección incluye
revisar el bloqueo faltante, no ejecutar automáticamente el SQL histórico.

## 10. Candidato no seleccionado

**B — MV estándar por fecha/categoría.** No seleccionada para esta iteración
porque deja una ventana de datos atrasados incompatible con el requisito de
frescura interpretado. No se la declara universalmente inferior ni se descarta
para un panel futuro que acepte un SLA explícito de atraso.

## 11. Razón de la selección

A permite ensayar una reducción identificable del plan —producto y su JOIN— sin
introducir un ciclo de refresh. Su costo y beneficio son medibles contra el
checkpoint existente. Esa coherencia con el requisito justifica **experimentar**,
no adoptar: se agrega redundancia, costo de escritura y riesgo de locks para
ahorrar solo una parte del trabajo, con un rechazo histórico que obliga a cautela.

## 12. Hipótesis falsable

Con el mismo dataset, día y configuración, retirar el JOIN a producto eliminará
ese scan/hash del plan candidato y puede reducir el costo de lectura. **Solo se
considerará justificado adoptar si la reducción pasa la puerta de lectura de la
sección 15, conserva equivalencia y supera las pruebas y presupuestos de escritura,
almacenamiento y sincronización acordados antes del AFTER.**

El scan de detalle permanece y puede crecer físicamente; por ello un plan sin
producto pero sin mejora clara, o con costo inaceptable, refuta la justificación
de adopción aunque confirme la eliminación mecánica del JOIN.

## 13. Riesgos y controles pendientes

- Backfill: versiones MVCC/WAL y más páginas pueden compensar el trabajo ahorrado.
- Fan-out y contención: el dataset observado tiene 9–12 detalles por producto;
  no acredita comportamiento con fan-out extremo ni alta carga.
- Carreras: FOR SHARE propuesto requiere pruebas en ambos órdenes y con rollback.
- Orden inverso de locks: UPDATE directo de detalle frente a propagación puede
  producir 40P01. No afirmar ausencia universal de deadlocks ni ocultar reintentos.
- SQLSTATE: el redundante no debe enmascarar silenciosamente una FK de producto
  inexistente. Verificar errores reales y nombres de restricciones.
- Bajas: sincronizar todas las líneas, no solo las usadas hoy; reactivación y
  recategorización deben mantener igualdad sin inventar reposición de stock.
- Estadística: cinco corridas y dispersión alta no prueban significancia causal.
- Integración TPI: permanece excluida. Sus efectos de trigger/locking requieren
  otra fase y no se acreditan con este ensayo académico.

## 14. Protocolo AFTER definido antes de implementar

### Lectura

Mismo dataset y CURRENT_DATE=2026-09-23, mismos seis índices explícitos y misma
configuración; si cambia alguna precondición, detenerse. Comparar la consulta
original con la candidata lógica que solo elimina producto. Verificar primero
auditoría global, agregados completos mediante EXCEPT 0/0 y Top 5 exacto sin empates.

Warm-cache como Fase 4: comprobaciones semánticas equivalentes, un warmup + cinco
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) oficiales; conservar todos. Mediana de
Execution Time como principal, MIN/MAX/MEDIA, Planning Time, buffers raíz y nodos
por separado, índices, filas, loops, workers y temporales. Captura textual adicional
excluida de estadísticas, identificada como otra ejecución. No forzar planes ni
agregar índices para favorecer el resultado; no sumar padres/hijos.

Medir y registrar por separado tiempo de backfill, tamaño/estadísticas físicas
antes y después y mantenimiento que se autorice antes del AFTER. No compactar
silenciosamente con VACUUM FULL/CLUSTER ni atribuir todo cambio al JOIN. Esta fase
no autoriza ejecutar mantenimiento ni reconstruir otro laboratorio.

### Escritura

Obtener una referencia de INSERT en esquema canónico **antes** de instalar A y
compararla con A completo, usando fixture equivalente, restricciones habilitadas,
transacciones revertidas, un warmup y cinco corridas por variante. Preparación
fuera de tiempo medido; conservar todas las corridas y documentar efectos de
identity/cachés/versiones. Si se aísla además el trigger sobre el esquema extendido,
identificarlo como otro experimento: no sustituye el costo completo de A.

Medir UPDATE de categoría en productos seleccionados por fan-out observado bajo,
mediano y alto (9/10/12); contar filas propagadas, locks, tiempos y auditoría,
revirtiendo fixtures. No extrapolar esos casos a miles de detalles. El backfill
inicial y el mantenimiento ordinario no se mezclan con tiempo de INSERT.

### Corrección, concurrencia y auditoría

Probar INSERT, cambio de producto, manipulación directa de categoria_id (también
NULL/valor incorrecto), producto inexistente, FK, UNIQUE y rollback. Incluir líneas
y pedidos eliminados, reactivación, baja de maestros y recategorización sin filtrar
historia. Comprobar que subtotal, total y stock no sean modificados por A.

Dos conexiones propias y un monitor: INSERT frente a UPDATE categoría en ambos
órdenes, tanto COMMIT como ROLLBACK del bloqueador; dos recategorizaciones del mismo
producto; reasignación de detalle y manipulación directa frente a recategorización.
Registrar pg_stat_activity/pg_locks, tiempos de espera, SQLSTATE y resultado final.
No aceptar una desincronización confirmada. Un 40P01 se registra como incidencia
de contención con rollback, no como PASS funcional ni error que se oculta repitiendo.

Auditoría global incluye todas las líneas: NULL, huérfanas e igualdad IS DISTINCT
FROM contra producto; EXCEPT bidireccional de todos los grupos y Top 5. Comparar
conteos y huellas de datos canónicos para detectar efectos ajenos al ensayo.

### DOWN real

Retirar exclusivamente triggers/funciones/FK/columna de A, en orden de dependencias
y sin CASCADE. Verificar desaparición, columnas/constraints canónicos, los seis
índices explícitos, datos fuente y salida del reporte. No perder información porque
producto.categoria_id sigue siendo fuente. TPI/FNBC continúan ausentes. No basta
una revisión estática; ejecutar la reversión en una fase autorizada y registrar
estado final. Ninguna operación de este protocolo se ejecuta en Fase 5.

## 15. Criterios ADOPT / REJECT

**Puerta de lectura predeclarada, conservadora y descriptiva:**

- Máximo de las cinco corridas AFTER **< 171.081 ms**, mínimo de las cinco BEFORE.
- Mediana AFTER **< 212.668 ms**.
- Buffers raíz de cada corrida AFTER **< 6794** accesos shared hit + shared read,
  con hits/reads separados y sin nuevos spills temporales.

Esta puerta no inventa un porcentaje ni prueba significancia estadística: exige
separación completa de los rangos observados para no adoptar por un cambio marginal
con gran dispersión. Solapamiento significa evidencia insuficiente para adoptar
bajo este criterio, **no prueba de igualdad de rendimiento**.

**ADOPT** solo si pasan conjuntamente esa puerta, EXCEPT 0/0, auditoría global,
pruebas negativas/concurrentes, mantenimiento de frescura, DOWN real y presupuestos
de escritura, espera de locks y almacenamiento previamente acordados. Falta definir
el workload esperado y esos SLO/presupuestos con el responsable: **deben aprobarse
antes del AFTER; sin ellos no hay ADOPT**, aunque la lectura mejore. No se inventan
límites numéricos de costo a partir de este dataset. Esto no bloquea la selección
experimental documental de Fase 5.

**REJECT / DO_NOT_ADOPT** si falla corrección, equivalencia, frescura o reversión;
si queda una carrera con datos inconsistentes; si no pasa la puerta de lectura;
si los costos superan los presupuestos acordados o quedan riesgos de contención
inaceptables. Si un ensayo incumple el protocolo o no es comparable, detenerse y
registrarlo: no declarar éxito ni repetir hasta seleccionar un resultado favorable.
Toda adopción futura necesita aprobación expresa; no modifica automáticamente schema.sql.

## 16. Limitaciones y cierre

Fase 5 selecciona un experimento; no demuestra su corrección concurrente ni su
rendimiento. No se instaló una alternativa, no se modificaron datos/estructura,
no se ejecutó AFTER y no se alteraron las evidencias históricas. La fecha del
dataset y el aislamiento de TPI son precondiciones, no detalles intercambiables.

El siguiente paso requiere autorización para implementar el contrato revisado y
acordar los presupuestos de costo antes de medir. Las operaciones candidatas a
optimización son **el scan/hash de producto y su JOIN**; el recorrido de detalle,
su unión con pedido y la agregación permanecen como trabajo residual a observar.
