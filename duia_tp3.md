# Declaración de Uso de IA (DUIA) — TP3

Base de Datos II — Semana 3, Unidad 2: Optimización de Consultas

Esta declaración documenta honestamente los usos reales de herramientas
de IA (OpenCode y ChatGPT) durante la resolución de las Partes 1 a 4 del
TP3. No se incluyen prompts literales cuando no están disponibles: en su
lugar, se resume fielmente el objetivo de cada intercambio. No se
inventa actividad de la Parte 5, que permanece pendiente (ver sección
correspondiente).

---

## Parte 1 — Carga masiva

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Generación inicial de `carga_masiva_tp3.sql` | Poblar Food Store con 20.000 clientes, 50.000 productos, 200.000 pedidos y detalles válidos, usando `generate_series`, sin tocar producción, compatible con transacción externa (BEGIN/ROLLBACK), con `ANALYZE` al final | Aceptado solo parcialmente — la primera versión usaba `MIN(id) + offset` y asumía IDs consecutivos, lo cual fue rechazado por no ser válido frente a posibles huecos en columnas IDENTITY |
| OpenCode | Primera corrección del script | Eliminar aritmética sobre IDs reales, usar `ROW_NUMBER()` y relaciones reales, eliminar `ON CONFLICT DO NOTHING`, tomar `precio_unitario` del producto real, identificar datos TP3 de forma exacta, generar 2 o 3 detalles por pedido | Aceptado parcialmente — subsistieron problemas de fondo detectados en la revisión siguiente |
| OpenCode | Segunda corrección del script | Corregir el cálculo de cantidad de detalles, reemplazar el subquery escalar de asignación de clientes por JOIN set-based, sustituir patrones `LIKE` con `_` sin escapar por regex exactas (`~ '^...$'`), documentar correctamente el rango de precios | Aceptado — resultado final: JOIN set-based, regex exactas, rango de precio 500..5000 inclusive, exactamente 500.000 detalles nuevos documentados |
| OpenCode / verificación humana | Prueba del script antes de aplicarlo definitivamente | Ejecutar el script dentro de `BEGIN ... ROLLBACK` como prueba, y solo después aplicarlo con `COMMIT` | Aceptado tras verificación manual — resultados reales confirmados: 20.000 clientes TP3, 50.000 productos TP3, 200.000 pedidos TP3, 500.000 detalles TP3, entre 2 y 3 detalles por pedido, promedio 2.50 |

**Fuente**: `carga_masiva_tp3.sql`.

---

## Parte 2 — Optimización

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Propuesta de índice para Consulta 1 (productos por precio) | A partir del plan real (`Seq Scan on producto`, filtro `precio >= 4500`, `Sort` con `top-N heapsort`, `Execution Time: 7.382 ms`), se pidió una optimización específica | Aceptado — `CREATE INDEX idx_producto_precio_desc ON producto (precio DESC);`. Resultado real: `Index Scan`, sin `Sort`, `Execution Time: 0.122 ms`, mejora observada ≈60.5x |
| OpenCode (matiz) | Precisión sobre atribución de tiempos en Consulta 1 | La explicación inicial atribuía porcentajes de tiempo a nodos individuales | Matizado — `actual time` no es tiempo exclusivo de un nodo; no corresponde calcular porcentajes exactos por nodo restando tiempos |
| OpenCode | Propuesta de índice para Consulta 2 (pedidos TARJETA por fecha) | A partir del plan real (`Parallel Seq Scan`, `Sort`, `Gather Merge`, `Execution Time: 55.123 ms`), se pidió una optimización específica, incluyendo justificación del orden de columnas del índice compuesto | Aceptado — `CREATE INDEX idx_pedido_forma_pago_fecha ON pedido (forma_pago, fecha DESC);`. Resultado real: `Index Scan`, sin `Sort`, sin `Gather Merge`, `Execution Time: 0.135 ms`, mejora observada ≈408x |
| OpenCode (matiz) | Precisión sobre paralelismo en Consulta 2 | Interpretación de overhead paralelo y de métricas con `loops > 1` | Matizado — no corresponde atribuir una cantidad exacta de milisegundos al overhead paralelo restando nodos, ni multiplicar mecánicamente métricas paralelas por `loops` sin explicitar que son promedios |
| OpenCode | Primera propuesta de índice para Consulta 3 (detalles por producto) | A partir del plan real (`Seq Scan` sobre `producto` dentro de un `InitPlan`, `Parallel Seq Scan` sobre `detalle_pedido`, `Sort`, `Gather Merge`, `Execution Time: 103.176 ms`) | Aceptado — `CREATE INDEX idx_producto_nombre ON producto (nombre);`. Resultado intermedio: `Execution Time: 50.617 ms` (el `Parallel Seq Scan` sobre `detalle_pedido` persistió) |
| OpenCode | Segunda propuesta de índice para Consulta 3 | Se pidió resolver el filtro `producto_id` combinado con el `ORDER BY pedido_id DESC` sobre `detalle_pedido` | Aceptado — `CREATE INDEX idx_detalle_pedido_producto_pedido ON detalle_pedido (producto_id, pedido_id DESC);`. Resultado final de la prueba: `Execution Time: 0.317 ms`, mejora ≈325x. Revalidación posterior: `0.093 ms`, registrada solo como confirmación adicional, no usada para calcular la mejora |
| OpenCode (hallazgo corregido) | Expectativa sobre eliminación del `Sort` en Consulta 3 | Se esperaba que el índice `(producto_id, pedido_id DESC)` también eliminara el `Sort` final | Corregido con evidencia real — PostgreSQL eligió `Bitmap Index Scan -> Bitmap Heap Scan -> Sort`; el acceso por bitmap no preserva un orden de salida utilizable para el `ORDER BY`, por lo que el `Sort` permaneció |

**Fuente**: `informe_optimizacion_tp3.md`.

---

## Parte 3 — Lectura crítica

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Explicación nodo por nodo del plan real optimizado de la Consulta 3 | Se le entregó únicamente el plan real (posterior a los índices) y se pidió una explicación en lenguaje natural, nodo por nodo, sin proponer optimizaciones ni suponer la consulta original | Aceptado mayormente, con imprecisiones detectadas: (1) interpretación de `width=8` como tamaño exacto de fila, demasiado literal; (2) inferencia de "alta selectividad" a partir de 12 filas devueltas sin conocer el total de filas de la tabla en ese plan aislado; (3) explicación imprecisa de por qué persistía el `Sort` |
| OpenCode (corrección principal) | Causa real de la persistencia del `Sort` | — | Corregido — la causa observable en el plan es que PostgreSQL eligió `Bitmap Index Scan -> Bitmap Heap Scan -> Sort`; el acceso bitmap no preserva un orden de salida utilizable para `ORDER BY pedido_id DESC`. La explicación original atribuía la causa a "cómo está organizado el índice", afirmación no verificable desde el plan entregado |

**Conclusión de la Parte 3**: el plan real prevalece sobre la expectativa
previa de la IA; toda interpretación se contrastó línea por línea contra
la evidencia literal del `EXPLAIN ANALYZE`.

**Fuente**: `lectura_critica_plan_tp3.md`.

---

## Parte 4 — Consultas y equivalencia

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Generación de Consulta A desde `spec_consultas_tp3.md` | Resumen de productos vigentes por categoría: `LEFT JOIN`, `p.activo = TRUE` ubicado en el `ON` (no en el `WHERE`), `COUNT(p.id)`, `AVG(p.precio)` | Aceptado |
| OpenCode | Generación de Consulta B correlacionada original desde spec | Productos con precio superior al promedio de su categoría, usando subconsulta correlacionada para el `AVG`, según lo exigido por la especificación | Aceptada semánticamente en un primer momento, pero luego se detectó que resultaba demasiado costosa para el volumen real de datos (~50.000 productos). La ejecución completa fue cancelada manualmente; no se registra ningún `Execution Time` inventado. `EXPLAIN` estimado: `cost` total ≈105.847.252 |
| OpenCode | Alternativa CTE + JOIN para Consulta B | Calcular `AVG` agrupado una sola vez por `categoria_id` (en vez de recalcularlo por cada fila), usando `HashAggregate` + `Hash Join` | Aceptado. Resultados reales: `Execution Time: 159.437 ms`, 24.970 filas devueltas. No se afirma una mejora en "X veces más rápida" respecto a la original, porque esta última nunca completó su ejecución |
| ChatGPT / verificación humana | Verificación de equivalencia de Consulta B | `EXCEPT` bidireccional entre la versión correlacionada y la alternativa CTE + JOIN, sobre una muestra determinista de 100 productos exteriores (el `AVG` se siguió calculando sobre todos los productos activos de cada categoría, no solo sobre la muestra) | Aceptado — resultado 0 / 0 en ambos sentidos, sobre la muestra controlada, no sobre el universo completo |
| OpenCode | Alternativa CTE agregado + LEFT JOIN para Consulta A | Segunda estructura para Consulta A: agregar productos activos por `categoria_id` en un CTE antes de unir contra `categoria` | Aceptado — `EXCEPT` bidireccional sobre el conjunto completo, resultado 0 / 0 |
| OpenCode | Experimento con `JOIN LATERAL` para Consulta B | Mantener la naturaleza correlacionada evitando duplicar el cálculo de `AVG` (que en la versión original aparecía dos veces: en `SELECT` y en `WHERE`) | El `EXPLAIN` mostró un nodo `Memoize` con `Cache Key: p.precio, p.categoria_id`. No se ejecutó `EXPLAIN ANALYZE` por precaución, dado el `cost` estimado elevado |
| OpenCode (imprecisión detectada) | Comparación de costos entre la versión LATERAL y la original | — | Se detectó y corrigió una afirmación incorrecta de OpenCode: había sostenido inicialmente que el `cost` del LATERAL era mayor que el de la original. Valores reales: original ≈105.847.252, LATERAL ≈7.944.848, CTE + JOIN ≈4.643. Por lo tanto, LATERAL < original, pero LATERAL sigue siendo muchísimo más costoso que CTE + JOIN |

**Fuente**: `spec_consultas_tp3.md`, `consultas_tp3_ia.sql`,
`consultas_tp3_alternativas.sql`, `consulta_a_alternativa.sql`,
`consulta_b_correlacionada_optimizada.sql`, `informe_consultas_tp3.md`.

---

## Uso de ChatGPT

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| ChatGPT | Revisión crítica de scripts propuestos por OpenCode | Auditar línea por línea las propuestas SQL antes de aceptarlas | Usado como capa de revisión, no como autor de SQL ejecutado sin control |
| ChatGPT | Detección de supuestos incorrectos sobre IDs consecutivos | Identificar que `MIN(id) + offset` en la carga masiva asumía continuidad de IDENTITY, algo no garantizado en PostgreSQL | Detección aceptada y trasladada como corrección obligatoria a OpenCode |
| ChatGPT | Diseño de pruebas `BEGIN / ROLLBACK` | Definir el protocolo de prueba segura antes de aplicar cambios definitivos con `COMMIT` | Aceptado como procedimiento de verificación |
| ChatGPT | Interpretación de planes reales `EXPLAIN ANALYZE` | Apoyo en la lectura de los planes antes/después de cada consulta optimizada | Usado como segunda lectura, contrastada con la explicación de OpenCode |
| ChatGPT | Contraste de afirmaciones de OpenCode contra evidencia | Verificar si las expectativas de OpenCode sobre qué nodos deberían desaparecer se cumplían en los planes reales | Usado para detectar los hallazgos críticos documentados en las Partes 2 y 3 |
| ChatGPT | Detección de errores numéricos o afirmaciones demasiado fuertes | Ejemplo: la comparación incorrecta de costos entre la versión LATERAL y la original | Detección aceptada e incorporada como corrección explícita en la documentación |
| ChatGPT | Diseño de verificaciones `EXCEPT` seguras | Definir el uso de una muestra determinista de 100 productos para verificar la Consulta B sin recorrer el universo completo | Aceptado como estrategia de verificación acotada |
| ChatGPT | Organización de la documentación final | Estructurar los informes finales (`informe_optimizacion_tp3.md`, `informe_consultas_tp3.md`, esta DUIA) | Aceptado como apoyo de redacción, no como fuente de resultados |

**Aclaración**: ChatGPT también propuso SQL de verificación y medición
(EXPLAIN / EXPLAIN ANALYZE, conteos y pruebas EXCEPT). Ese SQL fue
ejecutado manualmente por el estudiante sobre `foodstore_tp3` y sus
resultados fueron revisados antes de incorporarlos a la entrega. Las
modificaciones estructurales críticas propuestas por IA se probaron
previamente dentro de transacciones cuando correspondía.

---

## Parte 5 — Pendiente

La Parte 5 depende de la consulta lenta común que debe fijar la cátedra
para todos los equipos. Al momento de confeccionar esta DUIA, esa
consulta todavía no fue proporcionada, por lo que no se registran usos
de IA inventados ni resultados inexistentes.

---

## Conclusión

- La IA (OpenCode y ChatGPT) actuó en todo momento como asistente y
  proponente, nunca como autoridad final sobre el resultado.
- Ninguna propuesta crítica —índices, reescrituras de consultas,
  interpretaciones de planes— se aplicó a ciegas.
- Se rechazaron o corrigieron propuestas cuando la evidencia real no
  coincidía con lo afirmado, incluyendo la primera versión de la carga
  masiva (IDs consecutivos), la expectativa sobre la eliminación del
  `Sort` en la Consulta 3, y la comparación de costos entre la versión
  LATERAL y la original.
- PostgreSQL fue la fuente final de verdad. Según el caso se utilizaron
  `EXPLAIN`, `EXPLAIN ANALYZE`, conteos y verificaciones `EXCEPT` para
  contrastar las propuestas de IA con evidencia real.
- Los resultados documentados en este repositorio fueron medidos
  manualmente antes de ser incorporados a los informes finales.
