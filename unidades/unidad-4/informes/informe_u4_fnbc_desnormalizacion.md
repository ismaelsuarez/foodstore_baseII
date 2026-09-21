# Unidad 4 — FNBC y desnormalización controlada
## Food Store — Informe vigente sobre el modelo oficial

**FNBC: PASS. Desnormalización: implementación experimental válida,
candidato evaluado y descartado por relación costo/beneficio.**

Este informe resume exclusivamente la
[evidencia real del Bloque 2](evidencia_modelo_oficial.md), que conserva los
planes completos y las salidas detalladas. No se ejecutaron nuevos benchmarks
para el cierre documental. El [informe histórico](informe_u4_fnbc_desnormalizacion_historico.md)
se preserva íntegro, sin utilizar sus métricas como evidencia vigente.

## 1. Entorno y dataset

- PostgreSQL **17.11**, Windows x86_64; ejecución: **2026-09-20**.
- Copia descartable: **foodstore_u4_oficial**, clonada de foodstore_tp5_oficial.
- Modelo oficial: `usuario`, `pedido.usuario_id`, `subtotal` físico,
  `eliminado` y `pedido.fecha DATE`.
- Totales: 8 categorías, 50.000 productos, 20.000 usuarios,
  220.000 pedidos y 550.000 detalles.
- CURRENT_DATE: **20.275 pedidos vigentes / 50.272 detalles vigentes**.
- Backfill: **550.000 filas**; `categoria_id NULL = 0`;
  desincronizaciones posteriores al backfill = **0**.

Los resultados son específicos de este dataset, máquina y estado de caché;
no son valores universales. Los índices heredados de TP5 se conservaron.
La columna redundante existe únicamente en el laboratorio, no en schema.sql.

## 2. Parte FNBC — ControlLoteAlmacen

### Dependencias y claves candidatas

| Regla de negocio | Dependencia funcional |
|---|---|
| F1 / R1 | {LoteID, DepositoID} → ResponsableControlID |
| F2 / R2 | ResponsableControlID → DepositoID |

Claves candidatas: **{LoteID, DepositoID}** y
**{LoteID, ResponsableControlID}**. F2 viola FNBC porque
ResponsableControlID no es superclave: su clausura no incluye LoteID.

La descomposición genera `responsable_control_deposito` y
`control_lote_responsable`. Es **sin pérdida (lossless)**: el atributo común
responsable_control_id es clave de responsable_control_deposito. La vista
`v_control_lote_almacen` reconstruye la relación mediante JOIN.
F2 queda preservada localmente; F1 requiere verificar el JOIN y no queda
garantizada únicamente por las PK de las tablas resultantes.

### Validación real

| Control | Resultado |
|---|---:|
| Diagnóstico de F2: violaciones observadas | 0 |
| Filas originales | 3 |
| Filas reconstruidas | 3 |
| Original EXCEPT vista | 0 |
| Vista EXCEPT original | 0 |

El diagnóstico de 0 filas confirma que la instancia actual respeta la regla;
**la dependencia proviene de la regla de negocio**, no se deduce únicamente
de los datos. No debe confundirse ausencia de inconsistencias observadas
con cumplimiento de FNBC por la relación original.

`usuario` ya pertenece al modelo oficial. Se reutilizaron los usuarios 801
y 802 no eliminados. Unidad 4 **no creó ni eliminó usuario**: OID, conteo
y huella de contenido permanecieron iguales. `deposito` y `lote` son
extensiones académicas del laboratorio.

## 3. Candidato de desnormalización

Hipótesis: evitar el JOIN a producto podría reducir el costo del reporte
Top 5 por categoría. Se agregó experimentalmente
`detalle_pedido.categoria_id`, derivada exclusivamente de
**producto.categoria_id**, con backfill, NOT NULL y FK.

| Mecanismo | Responsabilidad |
|---|---|
| fn_detalle_pedido_set_categoria / trg_detalle_pedido_set_categoria | Derivar la categoría en INSERT y UPDATE de producto_id o categoria_id |
| fn_producto_sync_categoria_detalle / trg_producto_sync_categoria_detalle | Propagar cambios de categoría del producto a sus detalles |
| Auditoría | Conciliar categoría redundante contra producto.categoria_id |
| DOWN documentado | Retirar triggers, funciones, FK y columna redundante sin tocar producto.categoria_id |

Las consultas usan `SUM(dp.subtotal)` y los filtros
`dp.eliminado = FALSE`, `ped.eliminado = FALSE`, `ped.fecha = CURRENT_DATE`.
No se filtra la baja actual de producto/categoría ni producto.disponible,
para no ocultar ventas históricas. La atribución usa la categoría actual
del producto, no una fotografía histórica de la categoría al vender.

## 4. Lecturas: las diez corridas

Protocolo: EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON), cinco corridas por
variante. **No se descartó ninguna**, ni como calentamiento ni como outlier.
Los tiempos corresponden a Execution Time. Los buffers son hit + read
compartidos del nodo raíz; no se suman de nuevo los nodos hijos ni se
interpretan como bloques únicos o accesos físicos al disco.

| Corrida | Baseline normalizada (ms) | Buffers | Candidato (ms) | Buffers |
|---|---:|---:|---:|---:|
| 1 | 191.465 | 8382 | 174.459 | 13386 |
| 2 | 188.192 | 8382 | 177.794 | 13386 |
| 3 | 210.285 | 8382 | 287.053 | 13386 |
| 4 | 237.785 | 8382 | 196.507 | 13386 |
| 5 | 200.392 | 8382 | 307.298 | 13386 |
| **Mediana** | **200.392** | **8382** | **196.507** | **13386** |
| Mínimo | 188.192 | — | 174.459 | — |
| Máximo | 237.785 | — | 307.298 | — |

### Comparación e interpretación

- Tiempo mediano: **200.392 → 196.507 ms**, **-1.94 %**.
- Buffers: **8382 → 13386**, **+59.70 %**.
- Mayor dispersión posterior: 287.053 y 307.298 ms superan incluso
  la corrida más lenta del baseline (237.785 ms).

La reducción mediana de 3.885 ms es pequeña y **no constituye evidencia de
mejora robusta**. Seleccionar únicamente las dos corridas favorables del
candidato alteraría la conclusión. Eliminar un JOIN no fue suficiente.

Ambos planes incluyen Limit, ordenamiento en memoria, agregación
parcial/final, Gather Merge, joins hash paralelos, Seq Scan paralelo del
detalle e Index Only Scan del pedido. El candidato elimina el JOIN a
producto, pero conserva el recorrido de detalle_pedido.

El backfill modificó el estado físico: se ejecutó ANALYZE, no una
compactación de la tabla antes de la serie posterior. Los accesos del
recorrido de detalle aumentaron. Esto es compatible con los planes,
**no una medición causal aislada**. El orden fijo de las series y las cachés
también limitan la comparación. No se ejecutaron ensayos adicionales
para seleccionar un resultado favorable.

## 5. Costo de escritura y propagación

INSERT de **1.000 detalles** con fixture equivalente, restricciones base
habilitadas y BEGIN/ROLLBACK por corrida. Solo se deshabilitó temporalmente
el trigger de categoría del detalle en la variante sin trigger.

| Corrida | Sin trigger (ms) | Con trigger (ms) | Uso |
|---|---:|---:|---|
| 1 | 32.939 | 27.763 | Calentamiento |
| 2 | 21.301 | 28.342 | Válida |
| 3 | 21.376 | 29.261 | Válida |
| Promedio de 2 y 3 | **21.3385** | **28.8015** | **+34.97 %** |

Es el costo incremental del trigger sobre el esquema ya desnormalizado,
no todo el costo de agregar columna y FK frente al original. No quedaron
filas de prueba; las secuencias sí consumieron valores.

Propagación: cambio de categoría del **producto 17**, **18 detalles**,
**57.540 ms**. Es **una observación puntual, no una mediana**. Evidencia
de costo de mantenimiento, no una predicción universal para otros volúmenes.

## 6. Corrección, consistencia y concurrencia

| Prueba | Resultado |
|---|---|
| Original menos desnormalizada | 0 filas |
| Desnormalizada menos original | 0 filas |
| Top 5 exacto, ambos sentidos | 0 / 0 |
| Trigger A: detalle cambia de producto | PASS; categoría derivada correctamente |
| Trigger B: producto cambia de categoría | PASS; detalles asociados sincronizados |
| Trigger C: categoría del detalle manipulada directamente | PASS; se impuso nuevamente producto.categoria_id |
| DIRECT_TAMPERING_PROTECTED | YES, DML ordinario con triggers habilitados |
| Auditoría final global | 0 desincronizaciones |

Las pruebas A/B/C terminaron con ROLLBACK. La protección no implica
resistencia a un administrador que desactive los triggers. El EXCEPT
completo valida todos los grupos; el Top 5 también coincidió en el dataset
medido, sin garantizar una selección determinista ante futuros empates.

**Concurrencia ensayada: PASS**. Dos sesiones controladas actualizaron
producto.categoria_id sobre el **mismo producto 17**. La segunda esperó
un bloqueo Lock / transactionid. Ambas confirmaron, la segunda restauró
la categoría original y la auditoría final dio **0**.

**No se probó INSERT concurrente de detalle_pedido contra UPDATE de
producto.categoria_id.** El PASS se limita al intercalado observado y no
garantiza integridad bajo cualquier carrera. El DOWN fue validado
estáticamente, **no ejecutado** sobre la copia medida.

## Decisión final

**DECISIÓN = DESCARTAR LA DESNORMALIZACIÓN COMO CAMBIO PERMANENTE.**

**Estado: REJECTED_AFTER_MEASUREMENT.** La propuesta demostró consistencia
en las pruebas realizadas y dispone de una reversión documentada, pero el
workload observado arroja:

- Reducción mediana de solo **1.94 %**, sin mejora robusta.
- **+59.70 %** de buffers y mayor dispersión de tiempos.
- **+34.97 %** en el INSERT medido por mantenimiento del trigger.
- Mayor complejidad y costo de propagar cambios de categoría.

La decisión humana final es **NO ADOPTAR**. El modelo canónico debe conservar
**producto.categoria_id**, sin agregar permanentemente
**detalle_pedido.categoria_id**. La implementación experimental válida no
equivale a una decisión de diseño aceptada.

No se presenta como fracaso: es un experimento controlado que permitió
decidir con evidencia. Se conserva el diseño y su SQL para trazabilidad
académica, no como migración pendiente. El criterio es medir antes de
optimizar y conservar una desnormalización solo si sus beneficios
justifican claramente sus costos.

## 7. Rúbrica técnica

| Criterio | Estado | Evidencia o reserva |
|---|---|---|
| FNBC | PASS | F2 viola FNBC en la relación original |
| Claves candidatas | PASS | Dos claves y clausuras documentadas |
| Descomposición lossless | PASS | Atributo común clave en una relación |
| EXCEPT FNBC | PASS | 0 / 0; conteos 3 / 3 |
| Motivo medido | PASS | Cinco corridas por variante, sin ocultar outliers |
| Dueño único del redundante | PASS | producto.categoria_id; prueba C satisfactoria |
| Conciliación | PASS | Auditoría final 0 |
| Reversibilidad | PASS | DOWN documentado y revisado estáticamente, no ejecutado |
| Equivalencia | PASS | Agregados y Top 5: 0 / 0 |
| Triggers | PASS | A/B/C; alcance de concurrencia limitado |
| Costo de escritura | PASS | +34.97 %; propagación puntual documentada |
| Concurrencia ensayada | PASS | Dos UPDATE del mismo producto; no carrera INSERT/UPDATE |
| Decisión basada en evidencia | PASS | Candidato descartado por costo/beneficio |

Rechazar justificadamente el candidato no constituye un FAIL académico.

## 8. Trazabilidad y defensa

La evidencia detallada del Bloque 2 permanece intacta. Su enlace congelado
«informe histórico» apunta al nombre usado entonces; el histórico real
ahora se encuentra en `informe_u4_fnbc_desnormalizacion_historico.md`.
Los resultados anteriores no se mezclan con los del modelo oficial.

Para defender el trabajo: explicar por qué F2 viola FNBC, por qué la
descomposición es lossless pero no preserva localmente F1, cómo se mantiene
el dato redundante, qué prueban EXCEPT y los ensayos concurrentes, y por
qué consistencia correcta y eliminación de un JOIN no bastan para adoptar
una optimización cuyo costo supera el beneficio observado.
