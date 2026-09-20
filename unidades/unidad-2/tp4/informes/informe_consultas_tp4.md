# Informe de consultas — TP4 Parte 3

Base de Datos II — Semana 4, Unidad 2: Optimización de Consultas

Fuentes utilizadas: `spec_consultas_tp4.md`, `consultas_tp4_ia.sql`,
`consulta_a_tp4_alternativa.sql`, `consulta_b_tp4_alternativa.sql`, y los
resultados reales provistos manualmente por el equipo tras ejecutar las
consultas fuera de esta sesión.

---

## 1. Objetivo de la Parte 3

Construir, para cada una de las dos consultas especificadas en
`spec_consultas_tp4.md` (ranking de clientes por gasto con función de
ventana, y productos sobre el promedio de facturación de su categoría),
al menos dos implementaciones SQL con estructura distinta pero
semánticamente equivalentes, y verificar esa equivalencia formalmente
mediante `EXCEPT` en ambos sentidos. El alcance de esa verificación no
fue idéntico para ambas consultas: para la Consulta A, el `EXCEPT`
bidireccional se ejecutó sobre el conjunto completo de clientes; para la
Consulta B, se ejecutó sobre una muestra determinista de 100 productos
exteriores, manteniendo el promedio de categoría calculado sobre todos
los productos activos de cada categoría (no sobre la muestra). Esta
distinción se detalla en cada sección correspondiente.

---

## 2. Consulta A — Ranking de clientes por gasto total

### Spec resumida

- Incluir únicamente clientes con al menos un pedido.
- `gasto_total` = `SUM(cantidad * precio_unitario)` sobre todos los
  detalles de todos los pedidos del cliente.
- Usar una función de ventana con `RANK()` (no `ROW_NUMBER()`), para que
  clientes con `gasto_total` exactamente igual compartan puesto.
- El `ORDER BY` interno de `RANK()` depende únicamente de
  `gasto_total DESC`; `cliente_nombre` solo se usa como desempate visual
  en el `ORDER BY` final.
- Columnas: `cliente_id`, `cliente_nombre`, `cantidad_pedidos`,
  `gasto_total`, `puesto`.
- Orden final: `puesto ASC`, `cliente_nombre ASC`. Sin `LIMIT`.

### Primera versión (`consultas_tp4_ia.sql`)

```sql
WITH gasto_por_cliente AS (
    SELECT
        c.id AS cliente_id,
        c.nombre AS cliente_nombre,
        COUNT(DISTINCT pe.id) AS cantidad_pedidos,
        COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS gasto_total
    FROM cliente c
    JOIN pedido pe
        ON pe.cliente_id = c.id
    LEFT JOIN detalle_pedido dp
        ON dp.pedido_id = pe.id
    GROUP BY c.id, c.nombre
)
SELECT
    cliente_id,
    cliente_nombre,
    cantidad_pedidos,
    gasto_total,
    RANK() OVER (ORDER BY gasto_total DESC) AS puesto
FROM gasto_por_cliente
ORDER BY puesto ASC, cliente_nombre ASC;
```

Estrategia: `cliente JOIN pedido` (garantiza al menos un pedido) +
`LEFT JOIN detalle_pedido` (preserva pedidos sin detalles todavía
registrados, aportando `gasto_total = 0` vía `COALESCE`).
`COUNT(DISTINCT pe.id)` evita que la multiplicación de filas por
`detalle_pedido` infle la cantidad de pedidos contados.

### Alternativa (`consulta_a_tp4_alternativa.sql`)

```sql
WITH detalle_por_pedido AS (
    SELECT
        pedido_id,
        SUM(cantidad * precio_unitario) AS gasto_pedido
    FROM detalle_pedido
    GROUP BY pedido_id
),
pedido_con_gasto AS (
    SELECT
        pe.id AS pedido_id,
        pe.cliente_id AS cliente_id,
        COALESCE(dpp.gasto_pedido, 0) AS gasto_pedido
    FROM pedido pe
    LEFT JOIN detalle_por_pedido dpp
        ON dpp.pedido_id = pe.id
),
gasto_por_cliente AS (
    SELECT
        c.id AS cliente_id,
        c.nombre AS cliente_nombre,
        COUNT(*) AS cantidad_pedidos,
        SUM(pcg.gasto_pedido) AS gasto_total
    FROM cliente c
    JOIN pedido_con_gasto pcg
        ON pcg.cliente_id = c.id
    GROUP BY c.id, c.nombre
)
SELECT
    cliente_id,
    cliente_nombre,
    cantidad_pedidos,
    gasto_total,
    RANK() OVER (ORDER BY gasto_total DESC) AS puesto
FROM gasto_por_cliente
ORDER BY puesto ASC, cliente_nombre ASC;
```

Estrategia: preagrega `detalle_pedido` por `pedido_id` primero, hace
`LEFT JOIN` desde `pedido` hacia ese agregado (garantizando exactamente
una fila por pedido, con `gasto_pedido = 0` si no tiene detalles), y
recién después agrupa por cliente. Al llegar a esa última agregación,
cada pedido ya aparece una sola vez, por lo que `COUNT(*)` equivale a
`COUNT(DISTINCT pedido_id)` sin necesitar `DISTINCT`.

### Conteo real

```
clientes_en_ranking = 20003
```

### Equivalencia (EXCEPT bidireccional)

| Comparación | Filas |
|---|---|
| `original_minus_alternativa` | 0 |
| `alternativa_minus_original` | 0 |

**Conclusión**: equivalencia formal completa confirmada mediante `EXCEPT`
en ambos sentidos sobre el conjunto completo de clientes. Ambas versiones
producen exactamente el mismo conjunto de filas, incluyendo
`cantidad_pedidos`, `gasto_total` y `puesto`.

---

## 3. Consulta B — Facturación de producto vs. promedio de categoría

### Spec resumida

- Incluir únicamente productos con `producto.activo = TRUE` y
  categorías con `categoria.activo = TRUE`.
- `facturacion_producto` = `SUM(cantidad * precio_unitario)` por
  producto.
- El promedio de facturación de una categoría se calcula sobre **todos**
  los productos activos de esa categoría, incluyendo los que no
  tuvieron ventas (facturación 0).
- Comparación estricta: `facturacion_producto > promedio_facturacion_categoria`.
- Primera versión obligada a usar subconsulta correlacionada.
- Orden final: `categoria_nombre ASC`, `facturacion_producto DESC`,
  `producto_nombre ASC`. Sin `LIMIT`.

### Versión correlacionada (`consultas_tp4_ia.sql`)

```sql
WITH facturacion_producto AS (
    SELECT
        pr.id AS producto_id,
        pr.nombre AS producto_nombre,
        pr.categoria_id AS categoria_id,
        COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS facturacion_producto
    FROM producto pr
    LEFT JOIN detalle_pedido dp
        ON dp.producto_id = pr.id
    WHERE pr.activo = TRUE
    GROUP BY pr.id, pr.nombre, pr.categoria_id
)
SELECT
    fp.producto_id AS producto_id,
    fp.producto_nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    fp.facturacion_producto AS facturacion_producto,
    (
        SELECT AVG(fp2.facturacion_producto)
        FROM facturacion_producto fp2
        WHERE fp2.categoria_id = fp.categoria_id
    ) AS promedio_facturacion_categoria
FROM facturacion_producto fp
JOIN categoria c
    ON c.id = fp.categoria_id
WHERE c.activo = TRUE
  AND fp.facturacion_producto > (
        SELECT AVG(fp2.facturacion_producto)
        FROM facturacion_producto fp2
        WHERE fp2.categoria_id = fp.categoria_id
    )
ORDER BY c.nombre ASC, fp.facturacion_producto DESC, fp.producto_nombre ASC;
```

El CTE `facturacion_producto` parte de **todos** los productos activos
(`FROM producto`, no `FROM detalle_pedido`) con `LEFT JOIN` hacia
`detalle_pedido`, de modo que un producto activo sin ventas queda con
`facturacion_producto = 0` en vez de desaparecer del cálculo del
promedio. El promedio se resuelve con dos subconsultas escalares
correlacionadas idénticas — una en el `SELECT`, otra en el `WHERE` —
ambas referenciando `fp.categoria_id` de la fila exterior.

### Problema de costo

### EXPLAIN estimado (sin ANALYZE)

```
cost total aproximado: 56.523.609,97
```

Elementos importantes observados en el plan:

- `CTE facturacion_producto`
- `GroupAggregate`
- `Merge Left Join`
- `Nested Loop`
- `SubPlan 2`
- `SubPlan 3`

**No se ejecutó `EXPLAIN ANALYZE`** sobre esta versión completa, por
precaución ante el costo estimado. No se registra ningún
`Execution Time` para esta versión — no se inventa ninguna cifra que no
se haya medido.

### Alternativa con promedio preagregado (`consulta_b_tp4_alternativa.sql`)

```sql
WITH facturacion_producto AS (
    SELECT
        pr.id AS producto_id,
        pr.nombre AS producto_nombre,
        pr.categoria_id AS categoria_id,
        COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS facturacion_producto
    FROM producto pr
    LEFT JOIN detalle_pedido dp
        ON dp.producto_id = pr.id
    WHERE pr.activo = TRUE
    GROUP BY pr.id, pr.nombre, pr.categoria_id
),
promedio_categoria AS (
    SELECT
        categoria_id,
        AVG(facturacion_producto) AS promedio_facturacion_categoria
    FROM facturacion_producto
    GROUP BY categoria_id
)
SELECT
    fp.producto_id AS producto_id,
    fp.producto_nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    fp.facturacion_producto AS facturacion_producto,
    pc.promedio_facturacion_categoria AS promedio_facturacion_categoria
FROM facturacion_producto fp
JOIN promedio_categoria pc
    ON pc.categoria_id = fp.categoria_id
JOIN categoria c
    ON c.id = fp.categoria_id
WHERE c.activo = TRUE
  AND fp.facturacion_producto > pc.promedio_facturacion_categoria
ORDER BY c.nombre ASC, fp.facturacion_producto DESC, fp.producto_nombre ASC;
```

El CTE `facturacion_producto` es idéntico al de la versión
correlacionada. Se agrega un segundo CTE, `promedio_categoria`, que
calcula `AVG(facturacion_producto) GROUP BY categoria_id` una sola vez
para toda la tabla, y el `SELECT` final une ese resultado ya calculado
mediante `JOIN`, sin ninguna subconsulta correlacionada.

### EXPLAIN ANALYZE real de la alternativa

```
Execution Time: 386.326 ms
Planning Time: 0.335 ms
Filas devueltas: 24970
```

Elementos principales del plan real:

- `Merge Left Join`
- `GroupAggregate`
- `HashAggregate` por `categoria_id`
- `Hash Join`
- `Rows Removed by Join Filter: 25033`
- `Sort Method: quicksort`, `Memory: 2914kB`

**Observación sobre estimación de cardinalidad**: PostgreSQL estimó
únicamente 167 filas finales, pero el resultado real fue de 24.970
filas. Se registra esta discrepancia como una **subestimación de
cardinalidad** del planner, sin atribuirle una causa definitiva — no se
cuenta con evidencia suficiente en este informe para afirmar con
certeza qué mecanismo específico del planner produjo esa diferencia.

---

## 4. Equivalencia — Consulta B

La equivalencia **no se verificó sobre las 50.003 filas exteriores
completas** de `producto`. Se utilizó una **muestra determinista de 100
productos** como conjunto exterior de comparación. Es importante
remarcar que, aunque el conjunto exterior se limitó a 100 productos, **el
promedio de categoría se siguió calculando sobre todos los productos
activos de la categoría correspondiente**, no sobre la muestra — de lo
contrario la comparación de equivalencia no habría sido válida.

| Comparación | Filas |
|---|---|
| `correlacionada_minus_alternativa` | 0 |
| `alternativa_minus_correlacionada` | 0 |

**Conclusión correcta**: equivalencia verificada mediante `EXCEPT`
bidireccional sobre una muestra controlada de 100 productos. No se
afirma equivalencia exhaustiva sobre las 50.003 filas completas.

---

## 5. Hallazgos

- **Consulta A**: la reescritura con preagregación por `pedido_id` es
  formalmente equivalente a la versión con `COUNT(DISTINCT)`, verificado
  sobre el conjunto completo de 20.003 clientes en ambas direcciones del
  `EXCEPT`.
- **Consulta B — costo de la versión correlacionada**: el `EXPLAIN` sin
  `ANALYZE` mostró un costo estimado de ≈56.523.609,97, con dos
  `SubPlan` correlacionados (`SubPlan 2` y `SubPlan 3`), con potencial de
  reevaluar el `AVG` de categoría según la fila exterior. Por precaución, no se ejecutó
  `EXPLAIN ANALYZE` sobre esa versión completa, y por lo tanto no existe
  un `Execution Time` real para ella.
- **Consulta B — alternativa con promedio preagregado**: sí se ejecutó
  por completo, con `Execution Time: 386.326 ms` y 24.970 filas
  devueltas. No se puede afirmar una mejora expresada en "X veces más
  rápida" respecto a la versión correlacionada, porque esta última nunca
  se ejecutó con `ANALYZE` y no genera una cifra de tiempo real
  comparable.
- **Subestimación de cardinalidad**: el planner estimó 167 filas finales
  para la alternativa de Consulta B, frente a las 24.970 filas reales
  obtenidas — una discrepancia significativa que se registra como
  observación, no como una causa diagnosticada con certeza en este
  informe.
- **Alcance de la equivalencia**: la Consulta A se verificó sobre el
  universo completo de clientes; la Consulta B se verificó únicamente
  sobre una muestra controlada de 100 productos exteriores, con el
  promedio de categoría siempre calculado sobre el total de productos
  activos de cada categoría.

---

## 6. Conclusiones

- Ambas consultas de la Parte 3 cuentan con una segunda implementación
  estructuralmente distinta, verificada formalmente contra la versión
  original mediante `EXCEPT` bidireccional, dentro del alcance
  documentado en cada caso.
- La Consulta A demostró equivalencia completa y exhaustiva sobre el
  conjunto real de clientes (20.003), sin necesidad de ninguna muestra
  reducida.
- La Consulta B no pudo verificarse de manera exhaustiva por el volumen
  de productos (50.003) y el costo estimado prohibitivo de la versión
  correlacionada; la verificación se acotó deliberadamente a una muestra
  de 100 productos, preservando la validez del promedio de categoría
  calculado sobre el total, no sobre la muestra.
- No se ejecutó `EXPLAIN ANALYZE` sobre la versión correlacionada
  completa de la Consulta B, y por lo tanto este informe no contiene
  ningún `Execution Time` inventado para esa versión — solo se documenta
  el `cost` estimado.
- La discrepancia entre filas estimadas (167) y reales (24.970) en el
  plan de la alternativa de Consulta B se registra como hallazgo abierto,
  sin atribuírsele una causa concluyente.

---

## 7. Evidencias principales

| Evidencia | Valor |
|---|---|
| Consulta A — clientes en el ranking | 20003 |
| Consulta A — equivalencia EXCEPT (ambos sentidos, conjunto completo) | 0 / 0 |
| Consulta B correlacionada — cost estimado | ≈56.523.609,97 |
| Consulta B correlacionada — Execution Time real | No disponible (no se ejecutó EXPLAIN ANALYZE, por precaución) |
| Consulta B alternativa — Execution Time real | 386.326 ms |
| Consulta B alternativa — Planning Time real | 0.335 ms |
| Consulta B alternativa — filas devueltas | 24970 |
| Consulta B alternativa — filas estimadas por el planner | 167 |
| Consulta B — equivalencia EXCEPT (muestra de 100 productos) | 0 / 0 |
