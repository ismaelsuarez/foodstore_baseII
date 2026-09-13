# Declaración de Uso de IA (DUIA) — TP4

Base de Datos II — Semana 4, Unidad 2: Optimización de Consultas

Esta declaración documenta honestamente los usos reales de herramientas
de IA (OpenCode y ChatGPT) durante la resolución de las Partes 1, 2, 3 y 4
del TP4. No se incluyen prompts literales cuando no están disponibles:
en su lugar, se resume fielmente el objetivo de cada intercambio.

---

## Parte 1 — Consultas analíticas lentas

### Consulta 1 — Facturación por categoría y mes

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Análisis del plan real (3 `Hash Join`, `Seq Scan` completos, `Sort` con `external merge`/`Disk: 25008kB`, `Hash` sobre `pedido` con `Batches: 2`, `Execution Time: 1213.192 ms`) | Identificar cada `JOIN`, explicar entrada hasheada/de prueba, explicar `external merge` y `Batches: 2`, proponer reescrituras/índices solo si el plan los justificaba, evaluar preagregación y `work_mem` como experimento | Análisis aceptado como diagnóstico; las dos propuestas concretas derivadas se evalúan por separado abajo |
| OpenCode | Propuesta 1: preagregar por `(pedido_id, categoria_id)` para eliminar `COUNT(DISTINCT)` | — | **Descartada** — resultado real `Execution Time: 1588.375 ms` (empeoró respecto a `1213.192 ms`), con `HashAggregate` (`Batches: 81`, `Disk Usage: 31056kB`), `Nested Loop` con `Index Scan using pedido_pkey` (`loops=400007`) y persistencia de `Sort Method: external merge` (`Disk: 18728kB`). Se registra expresamente que una propuesta razonable de IA fue rechazada después de medirla |
| OpenCode | Propuesta 2: `SET work_mem = '64MB';` como experimento de sesión | Tratarla únicamente como experimento de configuración, no como solución estructural | **Aceptada solo como experimento de configuración** — resultado real `Execution Time: 1135.058 ms`, mejora ≈1.07x (≈6.4%). `Sort` pasó de `external merge`/`Disk: 25008kB` a `quicksort`/`Memory: 43539kB`; `Hash` sobre `pedido` pasó de `Batches: 2` a `Batches: 1`. No se recomienda `64MB` globalmente; se ejecutó `RESET work_mem;` después de la prueba |
| OpenCode (matices) | Precisiones sobre el análisis de Consulta 1 | — | Matizado — no afirmar que `Nested Loop` es siempre cuadrático o malo; no afirmar que un `Seq Scan` implica necesariamente falta de índice; no afirmar como regla universal que siempre se hashea la tabla más chica; `cost` no son milisegundos; `actual time` no es tiempo exclusivo del nodo |

### Consulta 2 — Ranking de clientes por gasto

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Análisis del plan real (`Hash Join` × 2, `Sort` con `external merge`/`Disk: 28744kB`, `Hash` sobre `pedido` con `Batches: 2`, `Execution Time: 696.459 ms`) | Analizar algoritmos de `JOIN`, motivo de `Hash Join` + `Seq Scan`, relación entre `COUNT(DISTINCT pe.id)` y el `Sort Key c.id, pe.id`, posibilidad de preagregar `detalle_pedido` por `pedido_id`, y si `COUNT(*)` podía reemplazar a `COUNT(DISTINCT)` sin cambiar la semántica | Análisis aceptado; derivó en la propuesta concreta registrada abajo |
| OpenCode | Preagregar `detalle_pedido` por `pedido_id` (`SUM(cantidad)`, `SUM(cantidad * precio_unitario)`), luego `JOIN pedido`, `JOIN cliente`, `COUNT(*)` en vez de `COUNT(DISTINCT pe.id)` | — | **Aceptada** — reducción real de 500.007 filas de `detalle_pedido` a 200.005 filas tras el `GroupAggregate`. Cambio de algoritmo observado: de `Hash Join + Hash Join` a `Merge Join + Hash Join` (el `Merge Join` sobre `detalle_pedido.pedido_id = pe.id` aprovechó que ambas entradas llegaban ordenadas por `Index Scan using pk_detalle_pedido` y `Index Scan using pedido_pkey`). `Execution Time` final: `509.388 ms`, mejora ≈1.37x (≈26.9%). Equivalencia verificada: `original_minus_reescrita = 0`, `reescrita_minus_original = 0` |

**Fuente**: `informe_optimizacion_joins_tp4.md`.

---

## Parte 2 — Lectura crítica de planes de JOIN

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Explicación nodo por nodo del plan real optimizado de la Consulta 2 (sin entregarle la consulta SQL original ni contexto adicional) | El plan contenía: `Index Scan pk_detalle_pedido`, `GroupAggregate` por `pedido_id`, `Merge Join`, `Index Scan pedido_pkey`, `Seq Scan cliente`, `Hash`, `Hash Join`, `HashAggregate`, `Sort top-N`, `Limit` | Aceptado mayormente, con matices e imprecisiones detectadas (ver filas siguientes) |
| OpenCode | Identificación de algoritmos y entradas de `JOIN` | — | Aceptado sin corrección — identificó correctamente `Merge Join`, `Hash Join`, entrada izquierda y derecha de ambos, `Merge Cond`, `Hash Cond`, y la diferencia entre `cost` y tiempo real |
| OpenCode (inferencia aceptada con matiz) | Explicación de por qué no aparece `Sort` antes del `Merge Join` | — | Aceptada como **inferencia**, no como hecho literal del plan — el plan sugiere que los `Index Scan` se usan por el orden que entregan, pero no lo declara explícitamente |
| OpenCode (terminología corregida) | Descripción de la estructura hash del `Hash Join` sobre `cliente` | — | **Corregida** — OpenCode afirmó que "`c.id` queda indexado en la estructura hash"; corrección: `c.id` es la clave de una tabla hash **temporal**, construida solo para la duración de ese `Hash Join`; no se crea ningún índice persistente |
| OpenCode (simplificación corregida) | Descripción del orden de ejecución del plan | — | **Corregida** — OpenCode habló de "orden real de ejecución de adentro hacia afuera"; corrección: leer el árbol de abajo hacia arriba ayuda a comprender dependencias, pero PostgreSQL ejecuta operadores productores/consumidores, con nodos bloqueantes (`Sort`, `HashAggregate`) y otros que pueden trabajar en pipeline (`Merge Join`) |
| OpenCode (inferencia conservada) | Atribución del `SUM` interno al `GroupAggregate` y del `SUM` externo al `HashAggregate` | — | Registrada explícitamente como **inferencia razonable**, no como evidencia literal de esos nodos puntuales |

**Conclusión de la Parte 2**: el análisis fue mayormente aceptado, pero
corregido donde la terminología o la interpretación excedían lo que el
plan demostraba literalmente.

**Fuente**: `lectura_critica_joins_tp4.md`.

---

## Parte 3 — Ranking y subconsulta correlacionada

### Consulta A — Ranking de clientes

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Generación de la primera versión desde `spec_consultas_tp4.md` | `cliente JOIN pedido`, `COUNT(DISTINCT pe.id)`, `SUM(...)`, `RANK() OVER (ORDER BY gasto_total DESC)`, `cliente_nombre` solo en el `ORDER BY` final | Aceptada parcialmente — la versión inicial usaba `INNER JOIN` con `detalle_pedido` |
| ChatGPT / verificación humana | Revisión semántica previa a ejecución | Se detectó que el `INNER JOIN` excluía clientes con pedidos sin detalles; se pidió corregir a `LEFT JOIN` con `COALESCE(SUM(...), 0)` | Resultado corregido: **aceptado** — conteo real `clientes_en_ranking = 20003` |
| OpenCode | Segunda versión (estructura distinta): preagregación de `detalle_pedido` por `pedido_id`, `LEFT JOIN` desde `pedido` hacia el agregado, `COUNT(*)` en vez de `COUNT(DISTINCT)` | — | **Aceptada** — equivalencia completa verificada: `original_minus_alternativa = 0`, `alternativa_minus_original = 0` |

### Consulta B — Facturación de producto vs. promedio de categoría

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Generación de la primera versión correlacionada (subconsulta correlacionada sobre CTE `facturacion_producto`) | — | Generada; la corrección semántica y su aceptación se registran en la fila siguiente |
| ChatGPT / verificación humana | Detectó, antes de ejecutar, que el `INNER JOIN` entre `producto` y `detalle_pedido` eliminaba productos activos sin ventas | Se solicitó partir de todos los productos activos, `LEFT JOIN` con `detalle_pedido`, `COALESCE(SUM(...), 0)`, incluyendo esos productos con facturación 0 en el promedio | Resultado corregido: **aceptado semánticamente** |
| ChatGPT / verificación humana | `EXPLAIN` sin `ANALYZE` de la versión correlacionada corregida | ChatGPT propuso ejecutar `EXPLAIN` sin `ANALYZE` como medida de precaución; el estudiante lo ejecutó manualmente en PostgreSQL | `cost` total estimado ≈56.523.609,97, con `CTE facturacion_producto`, `GroupAggregate`, `Merge Left Join`, `Nested Loop`, `SubPlan 2`, `SubPlan 3`. Por precaución, **no se ejecutó `EXPLAIN ANALYZE` completo**; no se inventa ningún `Execution Time` para esta versión |
| OpenCode | Segunda versión (estructura distinta): CTE `promedio_categoria` (`AVG(facturacion_producto) GROUP BY categoria_id`) unido mediante `JOIN` en vez de subconsultas correlacionadas | — | **Aceptada** — `EXPLAIN ANALYZE` real: `Execution Time: 386.326 ms`, `Planning Time: 0.335 ms`, 24.970 filas reales. Plan con `Merge Left Join`, `GroupAggregate`, `HashAggregate`, `Hash Join`, `Sort quicksort`/`Memory: 2914kB`, `Rows Removed by Join Filter: 25033` |
| OpenCode (hallazgo registrado sin causa atribuida) | Discrepancia entre filas estimadas y reales de la segunda versión | — | El planner estimó 167 filas finales y obtuvo 24.970 — registrado únicamente como **subestimación de cardinalidad**, sin atribuirle una causa definitiva |
| ChatGPT / verificación humana | Verificación de equivalencia entre ambas versiones de Consulta B | Prueba segura diseñada con ChatGPT y ejecutada manualmente por el estudiante: `EXCEPT` bidireccional sobre una muestra determinista de 100 productos exteriores, con el promedio de categoría calculado siempre sobre **todos** los productos activos, no solo sobre la muestra | **Aceptada dentro del alcance muestral documentado** — resultado `correlacionada_minus_alternativa = 0`, `alternativa_minus_correlacionada = 0`. No se afirma equivalencia exhaustiva sobre las 50.003 filas completas |

**Fuente**: `spec_consultas_tp4.md`, `consultas_tp4_ia.sql`,
`consulta_a_tp4_alternativa.sql`, `consulta_b_tp4_alternativa.sql`,
`informe_consultas_tp4.md`.

---

## Uso de ChatGPT

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| ChatGPT | Revisión de las propuestas de OpenCode antes de ejecutarlas | — | Usado como capa de revisión previa a cualquier ejecución real |
| ChatGPT | Detección de errores semánticos de `JOIN` en la Parte 3 | — | Detección aceptada y trasladada como corrección obligatoria a OpenCode (Consultas A y B) |
| ChatGPT | Detección de que productos sin ventas estaban siendo excluidos del cálculo del promedio | — | Detección aceptada, derivó en la corrección de `INNER JOIN` a `LEFT JOIN` en Consulta B |
| ChatGPT | Diseño de `EXPLAIN` seguros sin `ANALYZE` cuando el costo estimado era alto | — | Aceptado como protocolo de precaución, evitando ejecutar planes de costo prohibitivo sin medir antes su magnitud |
| ChatGPT | Interpretación de planes reales | — | Usado como segunda lectura, contrastada con la explicación de OpenCode |
| ChatGPT | Contraste de propuestas de IA con resultados reales | — | Usado para detectar la propuesta descartada de la Consulta 1 (Parte 1) y las imprecisiones de la Parte 2 |
| ChatGPT | Detección de afirmaciones demasiado absolutas | — | Detección aceptada e incorporada como matices explícitos en los informes (Nested Loop, Seq Scan, hasheo de la tabla más chica) |
| ChatGPT | Diseño de pruebas `EXCEPT` | — | Aceptado como estrategia de verificación, incluyendo el diseño de la muestra acotada de 100 productos para Consulta B |
| ChatGPT | Documentación de propuestas fallidas | — | Aceptado como criterio de honestidad — la propuesta descartada de la Consulta 1 se documentó sin ocultarla |
| ChatGPT | Organización de los informes finales | — | Aceptado como apoyo de redacción, no como fuente de resultados |

**Aclaración**: ChatGPT también propuso SQL de medición y verificación
(`EXPLAIN`, `EXPLAIN ANALYZE`, `EXCEPT`, `SET`/`RESET work_mem`). Ese SQL
fue ejecutado manualmente por el estudiante sobre `foodstore_tp4` y sus
resultados se revisaron antes de documentarse en este repositorio.

---

## Parte 4 — Competencia de optimización

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode | Analizar la consulta de ranking de clientes y proponer una estrategia de optimización | Preagregar `detalle_pedido` por `pedido_id` antes de unir con `pedido` y `cliente`, permitiendo reemplazar `COUNT(DISTINCT pe.id)` por `COUNT(*)` | **Aceptada** después de medición real y verificación de equivalencia — `Tiempo antes: 696.459 ms`, `Tiempo después: 509.388 ms`, mejora ≈1.37x (≈26.9% de reducción de `Execution Time`). Cambio de plan observado: `Hash Join + Hash Join` → `Merge Join + Hash Join` |
| ChatGPT / verificación humana | Revisar la propuesta de optimización, diseñar la verificación de equivalencia y contrastar los resultados obtenidos | `EXCEPT` bidireccional entre la versión original y la reescrita | **Aceptado** — equivalencia comprobada: `original_minus_reescrita = 0`, `reescrita_minus_original = 0` |

**Estudiante / PostgreSQL**: el estudiante ejecutó manualmente las
consultas y los `EXPLAIN ANALYZE` sobre `foodstore_tp4`. PostgreSQL fue
la fuente final de verdad para: `Execution Time`; `Planning Time`;
algoritmos del plan; cantidad de filas; resultados `EXCEPT`.

En esta instancia participa un único equipo, por lo que la Parte 4 se
documenta como desempeño propio sobre la consulta seleccionada, sin
comparación ni ranking contra terceros.

**Fuente**: `competencia_optimizacion_tp4.md`.

---

## Conclusión

- La IA (OpenCode y ChatGPT) actuó en todo momento como asistente y
  proponente, nunca como autoridad final sobre el resultado.
- Ninguna propuesta crítica se aceptó a ciegas.
- Una reescritura de IA (preagregación por `(pedido_id, categoria_id)`
  en la Consulta 1 de la Parte 1) fue **descartada** porque, medida
  realmente, empeoró el tiempo de ejecución de `1213.192 ms` a
  `1588.375 ms`.
- Se corrigieron errores semánticos **antes de ejecutar**: el `INNER
  JOIN` que excluía clientes sin detalles (Consulta A) y el que excluía
  productos activos sin ventas (Consulta B), ambos en la Parte 3.
- PostgreSQL fue la fuente final de verdad en todos los casos.
- Según el caso se utilizaron `EXPLAIN`, `EXPLAIN ANALYZE` y `EXCEPT`
  para contrastar las propuestas de IA con evidencia real.
- Toda métrica documentada en este repositorio (`Execution Time`,
  `cost`, conteos de filas, resultados de `EXCEPT`) fue realmente
  observada, no inventada.
- Las Partes 1, 2, 3 y 4 fueron completadas. En la Parte 4 se reutilizó
  la consulta de ranking de clientes por gasto (ya optimizada en la
  Parte 1) como consulta de competencia; la estrategia aceptada produjo
  una mejora real de ≈1.37x, con equivalencia verificada mediante
  `EXCEPT` en ambos sentidos. No se inventaron resultados ni
  competidores — al participar un único equipo, la Parte 4 se documentó
  como desempeño propio, sin ranking contra terceros.
