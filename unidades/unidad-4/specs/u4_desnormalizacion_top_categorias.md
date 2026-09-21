# Spec — Unidad 4 — Desnormalización controlada — Top categorías

## 1. Modelo oficial y objetivo

Optimizar como hipótesis el reporte de las cinco categorías por monto
vendido en el día, sin cambiar su resultado. Hipótesis conservada como
contrato del experimento. **Estado final: REJECTED_AFTER_MEASUREMENT**.
La implementación fue válida; la decisión de diseño permanente fue rechazada.

El modelo oficial contiene `detalle_pedido.subtotal` físico,
`detalle_pedido.eliminado` y `pedido.eliminado`; `pedido.fecha` es
`DATE`. La PK del detalle es `id` y existe `UNIQUE (pedido_id, producto_id)`.
No sustituir el subtotal almacenado por una expresión derivada.

La ejecución del Bloque 2 utilizó foodstore_u4_oficial, copia descartable
del modelo oficial con volumen verificado en CURRENT_DATE. Para reproducir
el experimento se requiere otra copia y registrar sus conteos antes de medir.
No se adoptan fechas, volúmenes, planes ni tiempos de la iteración anterior.
El schema.sql raíz permanece histórico y no es el bootstrap de esta copia.

## 2. Consulta normalizada de referencia

```sql
SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
JOIN categoria c
    ON c.id = pr.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

La eliminación lógica de pedido/detalle excluye la venta del reporte.
No filtrar producto o categoría por `eliminado`, ni producto por
`disponible`: una baja actual no debe ocultar ventas históricas.
La atribución de categoría sigue la categoría **actual** del producto;
no representa una captura de la categoría al momento de la venta.

## 3. Estrategia conservada

Agregar `detalle_pedido.categoria_id BIGINT` solo en el laboratorio,
como columna redundante derivada de **producto.categoria_id**, que sigue
siendo la única fuente de verdad. La aplicación no decide este valor.

La hipótesis intentó evitar el JOIN a producto. Se midió junto con el costo
de escritura: eliminar ese JOIN no produjo una mejora robusta. El diseño
se conserva como evidencia experimental, no como recomendación de adopción.

Se conserva el patrón de triggers para este panel de actualización
frecuente, en lugar de una vista materializada con staleness entre refresh.
No se afirma que la alternativa materializada sea incorrecta; requeriría
otra política de actualización y otro análisis de costos.

## 4. Migración

Dentro de una transacción:

1. Agregar la columna redundante.
2. Realizar backfill desde producto:

```sql
UPDATE detalle_pedido dp
SET categoria_id = pr.categoria_id
FROM producto pr
WHERE pr.id = dp.producto_id;
```

3. Verificar que no queden NULL y agregar NOT NULL.
4. Agregar FK hacia categoria(id), sin introducir UNIQUE.
5. Crear las dos funciones y los dos triggers existentes.
6. Ejecutar auditoría de desincronización antes de confirmar.

No modificar tablas base fuera de esta extensión autorizada ni schema.sql.
Antes de ejecutar, preparar y verificar un backup de la copia oficial
fuera del repositorio. El backup de la iteración histórica no acredita
respaldo de esta nueva copia. No versionar el dump.

## 5. Sincronización y límites

### Detalle → categoría del producto

`fn_detalle_pedido_set_categoria` obtiene producto.categoria_id y lo
asigna a NEW.categoria_id. Su trigger `trg_detalle_pedido_set_categoria`
actúa BEFORE INSERT OR UPDATE OF producto_id, categoria_id.

Incluir categoria_id corrige el bypass de una actualización directa de
la columna redundante. Con los triggers habilitados, el DML ordinario de
la aplicación vuelve a derivar el valor, aunque proporcione otro.

### Producto → detalles

`fn_producto_sync_categoria_detalle` y
`trg_producto_sync_categoria_detalle` actúan AFTER UPDATE OF categoria_id
sobre producto. Si el valor realmente cambia, actualizan todos sus detalles.
No filtran bajas lógicas ni disponibilidad: preservan la misma autoridad
incluso en filas que no participan actualmente del reporte.

### Revisión estática

No hay ciclo entre estos dos mecanismos: el trigger de detalle solo
asigna NEW y no actualiza producto ni emite otro UPDATE de detalle. El
UPDATE emitido desde producto dispara esa asignación, no vuelve a producto.

Las pruebas A/B/C del Bloque 2 dieron PASS. Dos UPDATE concurrentes sobre
el mismo producto dieron PASS: la segunda sesión esperó bloqueo y la
auditoría final fue 0. No se agregó una estrategia adicional de bloqueo.
NO se ensayó INSERT concurrente de detalle contra UPDATE de categoría del
producto; no se garantiza consistencia bajo cualquier intercalación. El
UPDATE puede reescribir numerosos detalles históricos; su costo puntual
medido se registra en Resultado experimental.

## 6. Consulta desnormalizada

```sql
SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c
    ON c.id = dp.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

## 7. Equivalencia y auditoría

Comparar las agregaciones completas mediante EXCEPT en ambos sentidos,
como implementa el SQL. Resultados obtenidos en foodstore_u4_oficial:

- original_minus_desnormalizada = 0 filas.
- desnormalizada_minus_original = 0 filas.

Se comparan todos los grupos antes de LIMIT. El orden solicitado solo por
total no desempata categorías: si hay empate en el corte, distintas
selecciones Top 5 pueden ser igualmente válidas. El Top 5 exacto también
coincidió en el dataset medido; no se generaliza ese resultado a todos los
casos de empate ni se atribuye una selección diferente a desincronización.

Auditoría, incluyendo filas eliminadas:

```sql
SELECT
    dp.pedido_id,
    dp.producto_id,
    dp.categoria_id AS categoria_guardada,
    pr.categoria_id AS categoria_real
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id;
```

Se obtuvieron 0 filas. Cualquier diferencia futura requiere investigación; una
mejora de rendimiento no es válida si cambia el resultado.

## 8. Pruebas realizadas y límites

La [evidencia del modelo oficial](../informes/evidencia_modelo_oficial.md)
registra las ejecuciones del Bloque 2. Este cierre no ejecutó SQL nuevo.

- Trigger A: cambio de producto del detalle, categoría derivada: PASS.
- Trigger B: cambio de categoría del producto, detalles sincronizados: PASS.
- Trigger C: UPDATE directo de categoria_id, prevalece producto: PASS.
- DIRECT_TAMPERING_PROTECTED = YES, con triggers habilitados y DML ordinario.
- Pruebas A/B/C reversibles con BEGIN / ROLLBACK.
- Auditoría global y EXCEPT de agregados y Top 5: 0 / 0 diferencias.
- INSERT: ensayo de costo de 1000 detalles con y sin trigger, sin filas persistentes.
- Concurrencia: dos UPDATE del mismo producto, segunda sesión bloqueada,
  auditoría 0 al confirmar ambas transacciones.

No se ensayó la carrera INSERT de detalle frente a UPDATE de categoría del
producto. Las pruebas específicas de bajas lógicas reversibles y otros
casos límite no se presentan como ejecutadas. La ausencia de filtros de
baja/disponibilidad en la sincronización sigue siendo una propiedad del
código; las pruebas realizadas no cubren todas las intercalaciones.

Protocolo de lectura: cinco corridas EXPLAIN (ANALYZE, BUFFERS), todas
conservadas, comparadas mediante mediana sin ocultar outliers. Los planes
completos se consultan en la evidencia. La iteración anterior permanece en
[el informe histórico](../informes/informe_u4_fnbc_desnormalizacion_historico.md)
y no es baseline válido del modelo oficial.

## 9. Reversibilidad

El SQL documenta un DOWN manual, no automático, validado estáticamente
pero NO ejecutado sobre la copia medida:

1. Eliminar ambos triggers.
2. Eliminar sus funciones.
3. Eliminar la FK agregada.
4. Eliminar detalle_pedido.categoria_id.

No se pierde información original al retirar la columna redundante:
producto.categoria_id continúa como fuente de verdad.

## 10. Criterios de aceptación

- Modelo oficial: subtotal físico, eliminado y fecha DATE.
- Misma semántica histórica y misma fecha en las dos consultas.
- Backfill, NOT NULL, FK y dos caminos de sincronización conservados.
- Aplicación sin autoridad para asignar la categoría redundante mediante
  DML ordinario con triggers habilitados.
- Auditoría y EXCEPT con 0 filas: PASS en el dataset ensayado.
- Pruebas funcionales reversibles y reserva explícita de concurrencia.
- Rendimiento y costo de escritura medidos sin reutilizar cifras anteriores;
  aceptar la implementación experimental no obliga a adoptar el diseño.
- DOWN documentado, sin modificar schema.sql ni evidencia histórica.

Implementación: [tp_desnormalizacion_top_categorias.sql](../sql/tp_desnormalizacion_top_categorias.sql).

## Resultado experimental

PostgreSQL 17.11, foodstore_u4_oficial, 2026-09-20. Volumen vigente del día:
20.275 pedidos y 50.272 detalles. Backfill: 550.000 filas, 0 NULL y 0
desincronizaciones. usuario pertenece al modelo oficial; pedido.usuario_id
permanece sin cambios.

| Corrida | Normalizada (ms) | Desnormalizada (ms) |
|---|---:|---:|
| 1 | 191.465 | 174.459 |
| 2 | 188.192 | 177.794 |
| 3 | 210.285 | 287.053 |
| 4 | 237.785 | 196.507 |
| 5 | 200.392 | 307.298 |
| Mediana | 200.392 | 196.507 |
| Mínimo | 188.192 | 174.459 |
| Máximo | 237.785 | 307.298 |

Variación mediana: **-1.94 %**, marginal frente a la dispersión observada.
Buffers hit + read del nodo raíz: **8382 → 13386 (+59.70 %)**.
INSERT de 1000 detalles, promedio de dos corridas válidas tras un
calentamiento: **21.3385 → 28.8015 ms (+34.97 %)**. Es costo incremental
del trigger sobre el esquema ya desnormalizado, no todo el costo de la
columna/FK. Propagación del producto 17 a 18 detalles: **57.540 ms**, una
observación puntual, no mediana.

Las cachés, el orden fijo de las series y el estado físico posterior al
backfill limitan la comparación. Los resultados son propios de esta
máquina y dataset, no universales. No se seleccionan solo corridas favorables.

## Decisión

**REJECTED_AFTER_MEASUREMENT** — candidato evaluado y descartado por
relación costo/beneficio. La implementación experimental pasó consistencia,
equivalencia, triggers y la concurrencia ensayada, pero el beneficio temporal
es marginal frente al incremento de buffers, escrituras, dispersión y
complejidad. Decisión humana final: **NO ADOPTAR**.

Conservar producto.categoria_id como fuente de verdad del modelo canónico,
sin agregar permanentemente detalle_pedido.categoria_id a schema.sql.
Se mantiene este diseño y su SQL como evidencia del experimento controlado;
el rechazo justificado no constituye un fracaso académico.
