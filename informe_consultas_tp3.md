# Informe de consultas — TP3 Parte 4

Base de Datos II — Semana 3, Unidad 2: Optimización de Consultas

Fuentes utilizadas: `spec_consultas_tp3.md`, `consultas_tp3_ia.sql`,
`consultas_tp3_alternativas.sql`, `consulta_a_alternativa.sql`,
`consulta_b_correlacionada_optimizada.sql`, y los resultados reales
provistos manualmente por el equipo tras ejecutar las consultas fuera de
esta sesión.

---

## 1. Objetivo de la Parte 4

Construir, para cada una de las dos consultas especificadas en
`spec_consultas_tp3.md` (resumen por categoría, y productos sobre el
promedio de su categoría), al menos dos implementaciones SQL con
estructura distinta pero semánticamente equivalentes, y verificar esa
equivalencia formalmente mediante `EXCEPT` en ambos sentidos — no por
inspección visual del código, sino por comparación real de conjuntos de
filas. El alcance de esa verificación no fue idéntico para ambas
consultas: para la Consulta A, el `EXCEPT` bidireccional se ejecutó
sobre el conjunto completo; para la Consulta B, se ejecutó sobre una
muestra determinista de 100 productos exteriores, manteniendo el `AVG`
calculado sobre todos los productos activos de cada categoría (no sobre
la muestra). Esta distinción se detalla en cada sección correspondiente.

---

## 2. Consulta A — Resumen de productos vigentes por categoría

### Spec resumida

- Categorías con `categoria.activo = TRUE`, incluidas aunque no tengan
  productos activos.
- `cantidad_productos` y `precio_promedio` calculados solo sobre
  `producto.activo = TRUE`.
- `cantidad_productos = 0` y `precio_promedio = NULL` cuando no hay
  productos activos en la categoría.
- Orden: `cantidad_productos DESC`, `categoria_nombre ASC`.
- Sin `SELECT *`, sin `LIMIT`.

### SQL original (`consultas_tp3_ia.sql`)

```sql
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    COUNT(p.id) AS cantidad_productos,
    AVG(p.precio) AS precio_promedio
FROM categoria c
LEFT JOIN producto p
    ON p.categoria_id = c.id
    AND p.activo = TRUE
WHERE c.activo = TRUE
GROUP BY c.id, c.nombre
ORDER BY cantidad_productos DESC, categoria_nombre ASC;
```

Estrategia: `LEFT JOIN` directo entre `categoria` y `producto`, con el
filtro `p.activo = TRUE` colocado en el `ON` (no en el `WHERE`) para no
convertir el `LEFT JOIN` en un `INNER JOIN` implícito, seguido de
`GROUP BY` y agregación.

### Estrategia alternativa (`consulta_a_alternativa.sql`)

```sql
WITH productos_activos_por_categoria AS (
    SELECT
        categoria_id,
        COUNT(*) AS cantidad_productos,
        AVG(precio) AS precio_promedio
    FROM producto
    WHERE activo = TRUE
    GROUP BY categoria_id
)
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    COALESCE(pac.cantidad_productos, 0) AS cantidad_productos,
    pac.precio_promedio AS precio_promedio
FROM categoria c
LEFT JOIN productos_activos_por_categoria pac
    ON pac.categoria_id = c.id
WHERE c.activo = TRUE
ORDER BY cantidad_productos DESC, categoria_nombre ASC;
```

Estrategia: se agrega primero (`CTE` con `WHERE activo = TRUE` +
`GROUP BY categoria_id`) sobre un conjunto ya reducido a productos
activos, y luego se hace `LEFT JOIN` de `categoria` contra ese resultado
ya agregado — orden de operaciones invertido respecto a la versión
original (agregar antes de unir, en vez de unir y agregar al final).

### Resultado real

| categoria_id | categoria_nombre | cantidad_productos | precio_promedio |
|---|---|---|---|
| 7 | Pizzas | 25002 | 2730.3245740340772738 |
| 8 | Bebidas | 25001 | 2730.2639894404223831 |

(Resultado obtenido con la versión original; la spec exige que la
alternativa produzca el mismo conjunto, lo cual se verifica a
continuación.)

### Equivalencia (EXCEPT bidireccional)

| Comparación | Filas |
|---|---|
| `original_minus_alternativa` | 0 |
| `alternativa_minus_original` | 0 |

**Conclusión**: equivalencia formal completa confirmada mediante `EXCEPT`
en ambos sentidos. Ninguna fila de una versión queda fuera de la otra.

---

## 3. Consulta B — Productos con precio superior al promedio de su categoría

### Spec resumida

- Productos con `producto.activo = TRUE`, cuya categoría también tenga
  `categoria.activo = TRUE`.
- El promedio de la categoría se calcula solo sobre productos activos de
  esa misma categoría.
- Comparación estricta: `precio > promedio`.
- Primera versión obligada a usar subconsulta correlacionada.
- Orden: `categoria_nombre ASC`, `precio DESC`, `producto_nombre ASC`.

### SQL correlacionado original (`consultas_tp3_ia.sql`)

```sql
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria_id = p.categoria_id
          AND p2.activo = TRUE
    ) AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria_id = p.categoria_id
          AND p2.activo = TRUE
    )
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
```

Contiene dos subconsultas escalares correlacionadas idénticas — una en el
`SELECT`, otra en el `WHERE` — cada una referenciando `p.categoria_id` de
la fila exterior.

### Problema de rendimiento

La ejecución completa **fue cancelada manualmente** sobre
~50.000 productos porque tardaba demasiado. No existe, por lo tanto, un
`Execution Time` real completo para esta versión — solo se cuenta con el
plan estimado (`EXPLAIN` sin `ANALYZE`).

### EXPLAIN estimado (sin ANALYZE)

```
Incremental Sort  (cost=52923521.96..105847252.19 rows=16668 width=78)
  Sort Key: c.nombre, p.precio DESC, p.nombre
  Presorted Key: c.nombre
  -> Nested Loop
       -> Index Scan using categoria_nombre_key on categoria c
            Filter: activo
       -> Materialize
            -> Seq Scan on producto p
                 Filter: (activo AND (precio > (SubPlan 2)))
                 SubPlan 2
                   -> Aggregate
                        -> Seq Scan on producto p3
                             Filter:
                             (activo AND categoria_id = p.categoria_id)
       SubPlan 1
         -> Aggregate
              -> Seq Scan on producto p2
                   Filter:
                   (activo AND categoria_id = p.categoria_id)
```

**Lectura del plan**:
- El valor `cost=52923521.96..105847252.19` está expresado en unidades
  internas del planner, **no en milisegundos** — no debe confundirse con
  tiempo real.
- Se observan **dos subplanes correlacionados** (`SubPlan 1` y
  `SubPlan 2`), ambos ejecutando su propio `Aggregate` sobre un
  `Seq Scan on producto` filtrado por `categoria_id = p.categoria_id` —
  es decir, el mismo cálculo de `AVG` se dispara potencialmente una vez
  por cada fila exterior de `producto`.
- Como la consulta fue cancelada, **no existe un tiempo real completo**
  que se pueda reportar para esta versión; no se inventa ningún
  `Execution Time`.

### Alternativa CTE + JOIN (`consultas_tp3_alternativas.sql`)

```sql
WITH promedio_categoria AS (
    SELECT
        categoria_id,
        AVG(precio) AS precio_promedio_categoria
    FROM producto
    WHERE activo = TRUE
    GROUP BY categoria_id
)
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    pc.precio_promedio_categoria AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
JOIN promedio_categoria pc
    ON pc.categoria_id = p.categoria_id
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > pc.precio_promedio_categoria
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
```

### EXPLAIN ANALYZE real

```
Execution Time: 159.437 ms
Planning Time: 0.357 ms
Filas devueltas: 24970
```

Elementos principales del plan real:

- `Seq Scan on producto`
- `HashAggregate` por `categoria_id`
- `Hash Join`
- `Rows Removed by Join Filter: 25033`
- `Sort Method: quicksort`, `Memory: 2914kB`

**Lectura**: el promedio (`AVG(precio)`) se calcula **una sola vez por
categoría**, dentro del `HashAggregate` — no aparece ningún `SubPlan`
correlacionado repetido por fila, a diferencia de la versión original.
El `Hash Join` conecta ese resultado agregado (chico, una fila por
categoría) contra `producto` y `categoria`.

**Importante — sobre la magnitud de la mejora**: no se puede afirmar una
mejora expresada en "X veces más rápido", porque la consulta
correlacionada original fue cancelada antes de completarse y **no tiene
un `Execution Time` real** con el cual comparar. Solo se puede comparar
el `cost` estimado de ambas (ver más abajo, en la sección del
experimento LATERAL, donde se citan los tres valores de cost juntos), y
el `cost` no equivale a tiempo real.

### Conteo independiente de filas

```
cantidad_productos_sobre_promedio = 24970
```

Este conteo, obtenido de forma independiente, coincide exactamente con
las `Filas devueltas: 24970` reportadas por el `EXPLAIN ANALYZE` de la
alternativa CTE + JOIN.

### Equivalencia sobre muestra controlada

La verificación formal **no se hizo sobre las 50.003 filas completas**
de `producto` — se hizo sobre una **muestra determinista de 100
productos activos** como conjunto exterior. Es importante remarcar que,
aunque el conjunto exterior se limitó a 100 productos, **el `AVG` de cada
categoría se siguió calculando sobre TODOS los productos activos de la
categoría**, no sobre la muestra — de lo contrario la comparación no
habría sido válida.

| Comparación | Filas |
|---|---|
| `correlacionada_minus_alternativa` | 0 |
| `alternativa_minus_correlacionada` | 0 |

**Conclusión correcta**: equivalencia verificada mediante `EXCEPT`
bidireccional sobre una muestra controlada de 100 productos. No se
afirma que esta verificación cubra el universo completo de 50.003 filas.

---

## 4. Experimento JOIN LATERAL

### Propósito

Explorar una tercera variante de Consulta B (`consulta_b_correlacionada_optimizada.sql`)
que conservara la naturaleza **correlacionada** (a diferencia de la
alternativa con CTE, que rompe la correlación agregando de una sola vez
para toda la tabla), pero evitando la duplicación del cálculo de `AVG`
que existía en la versión original (una vez en el `SELECT`, otra en el
`WHERE`).

```sql
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    prom.precio_promedio_categoria AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
JOIN LATERAL (
    SELECT AVG(p2.precio) AS precio_promedio_categoria
    FROM producto p2
    WHERE p2.categoria_id = p.categoria_id
      AND p2.activo = TRUE
) prom ON TRUE
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > prom.precio_promedio_categoria
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
```

### EXPLAIN estimado (sin ANALYZE)

```
Incremental Sort
(cost=3973113.42..7944847.55 rows=16668 width=78)
...
-> Memoize
     Cache Key: p.precio, p.categoria_id
     Cache Mode: binary
     -> Subquery Scan on prom
          -> Aggregate
               -> Seq Scan on producto p2
                    Filter:
                    (activo AND categoria_id = p.categoria_id)
```

### Memoize y Cache Key

PostgreSQL introdujo automáticamente un nodo `Memoize` para intentar
cachear el resultado de la subconsulta `LATERAL` y evitar recalcularla en
cada fila. Sin embargo, la `Cache Key` es `p.precio, p.categoria_id` — **no
se limita a `categoria_id` solamente**. Esto ocurre porque el filtro
`p.precio > prom.precio_promedio_categoria` quedó empujado dentro del
propio `Subquery Scan on prom`, así que el resultado que se cachea
depende tanto de la categoría como del precio de cada fila exterior. Como
dentro de una misma categoría los precios varían fila a fila, la
probabilidad de reutilizar una entrada de caché ya calculada baja
considerablemente respecto a un caché ideal que dependiera solo de
`categoria_id`.

### Por qué no se ejecutó EXPLAIN ANALYZE

Por seguridad, **no se ejecutó `EXPLAIN ANALYZE`** sobre esta versión. El
`cost` estimado, aunque menor que el de la versión correlacionada
original, sigue siendo órdenes de magnitud mayor que el de la
alternativa CTE + JOIN, y existía riesgo de repetir la situación ya
vivida con la versión original (tener que cancelar la ejecución).

### Comparación de costos estimados

| Versión | Cost estimado (total) |
|---|---|
| Correlacionada original (dos subconsultas escalares) | ≈ 105.847.252 |
| JOIN LATERAL (con Memoize) | ≈ 7.944.848 |
| CTE + JOIN | ≈ 4.643 |

El costo estimado del LATERAL es **menor** que el de la versión
correlacionada original, pero sigue siendo **muchísimo mayor** que el de
la alternativa CTE + JOIN.

### Corrección de una imprecisión de IA

En un intercambio previo dentro de esta misma sesión, la IA (OpenCode)
afirmó inicialmente, de manera **incorrecta**, que el costo estimado de la
versión LATERAL era **mayor** que el de la consulta correlacionada
original. Esa afirmación es **falsa**: comparando los valores de `cost`
reales de ambos planes (≈105.847.252 para la original, ≈7.944.848 para
el LATERAL), el LATERAL tiene un costo estimado **menor**, aunque sigue
siendo muy superior al de la alternativa CTE + JOIN. Esta imprecisión
queda registrada acá como evidencia de que las afirmaciones de IA sobre
planes de ejecución deben verificarse siempre contra las cifras reales
del `EXPLAIN`, no darse por ciertas por default.

---

## 5. Conclusiones

- **Consulta A**: la versión con CTE agregado + `LEFT JOIN` demostró ser
  formalmente equivalente a la versión con `LEFT JOIN` directo + `GROUP BY`,
  confirmado mediante `EXCEPT` bidireccional sobre el conjunto completo
  (0 filas de diferencia en ambos sentidos).
- **Consulta B**: la versión con subconsultas correlacionadas duplicadas
  resultó inviable de ejecutar por completo sobre ~50.000 productos y
  tuvo que cancelarse. La alternativa con CTE + `JOIN` sí se ejecutó por
  completo (`Execution Time: 159.437 ms`, 24.970 filas), y su
  equivalencia lógica con la versión correlacionada se verificó — no
  sobre el universo completo, sino sobre una **muestra controlada de 100
  productos exteriores**, manteniendo el `AVG` calculado siempre sobre el
  total de productos activos de cada categoría.
- **No se puede cuantificar la mejora de rendimiento como un múltiplo
  ("X veces más rápido")** entre la versión original y la alternativa
  CTE + JOIN, porque la primera nunca completó su ejecución y no generó
  un `Execution Time` real comparable. Solo se dispone de comparaciones
  de `cost` estimado, que no son tiempo real.
- El experimento con `JOIN LATERAL` mostró que una solución
  "aparentemente más elegante" (mantener la correlación pero evitar la
  duplicación textual del `AVG`) no necesariamente resuelve el problema
  de fondo: PostgreSQL introdujo un `Memoize` cuya `Cache Key` incluye
  `p.precio`, limitando fuertemente su efectividad. El costo estimado
  mejoró respecto a la versión original, pero sigue siendo muy inferior
  en eficiencia frente a la alternativa CTE + JOIN.
- Se detectó y corrigió una imprecisión concreta de la IA sobre la
  comparación de costos entre la versión original y el experimento
  LATERAL, reforzando que toda afirmación sobre planes de ejecución debe
  contrastarse contra las cifras reales.

---

## 6. Evidencias principales

| Evidencia | Valor |
|---|---|
| Consulta A — cantidad_productos (Pizzas) | 25002 |
| Consulta A — cantidad_productos (Bebidas) | 25001 |
| Consulta A — equivalencia EXCEPT (ambos sentidos) | 0 / 0 |
| Consulta B original — cost estimado | ≈ 105.847.252 |
| Consulta B original — Execution Time real | No disponible (ejecución cancelada) |
| Consulta B alternativa CTE + JOIN — Execution Time real | 159.437 ms |
| Consulta B alternativa CTE + JOIN — Planning Time real | 0.357 ms |
| Consulta B alternativa CTE + JOIN — filas devueltas | 24970 |
| Consulta B — conteo independiente | 24970 |
| Consulta B — equivalencia EXCEPT (muestra de 100 productos) | 0 / 0 |
| Consulta B LATERAL — cost estimado | ≈ 7.944.848 |
| Consulta B LATERAL — Cache Key de Memoize | `p.precio, p.categoria_id` |
| Consulta B LATERAL — EXPLAIN ANALYZE ejecutado | No (por precaución) |
| Imprecisión de IA detectada | Comparación incorrecta de costos LATERAL vs. original |
