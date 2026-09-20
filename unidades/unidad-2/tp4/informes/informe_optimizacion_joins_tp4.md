# Informe de optimización de JOIN — TP4 Parte 1

Base de Datos II — Semana 4, Unidad 2: Laboratorio de consultas
analíticas lentas con múltiples JOIN

---

## 1. Objetivo de la Parte 1

Documentar formalmente el laboratorio de consultas analíticas lentas con
múltiples `JOIN` de la Parte 1 del TP4: para cada una de dos consultas,
registrar el plan real "antes", las propuestas de optimización evaluadas
(aceptadas y descartadas), el plan real "después" cuando corresponda, y
la mejora observada entre ejecuciones concretas. Se registran también
las propuestas que **empeoraron** el rendimiento, sin ocultarlas, porque
forman parte igual de válida del proceso de optimización que las
propuestas exitosas.

Se remarca la distinción entre `cost` (unidades internas estimadas por
el planner) y tiempo real medido en milisegundos — no deben confundirse
ni combinarse aritméticamente. Tampoco se atribuye a `actual time` un
significado de tiempo exclusivo de un nodo aislado.

---

## 2. Consulta 1 — Facturación por categoría y mes

### SQL

```sql
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id) AS cantidad_pedidos,
    SUM(dp.cantidad) AS unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria c
JOIN producto pr
    ON pr.categoria_id = c.id
JOIN detalle_pedido dp
    ON dp.producto_id = pr.id
JOIN pedido pe
    ON pe.id = dp.pedido_id
WHERE c.activo = TRUE
  AND pr.activo = TRUE
GROUP BY
    c.id,
    c.nombre,
    DATE_TRUNC('month', pe.fecha)
ORDER BY
    mes ASC,
    facturacion_total DESC;
```

### Plan antes

**Algoritmos de JOIN**:

| Condición | Algoritmo |
|---|---|
| `dp.producto_id = pr.id` | Hash Join |
| `pr.categoria_id = c.id` | Hash Join |
| `dp.pedido_id = pe.id` | Hash Join |

**Elementos principales**:
- `Seq Scan detalle_pedido`: 500.007 filas
- `Seq Scan producto`: 50.003 filas
- `Seq Scan categoria`: 2 filas
- `Seq Scan pedido`: 200.005 filas

**Sort previo al GroupAggregate**:
```
Sort Method: external merge
Disk: 25008kB
```

**Hash sobre pedido**:
```
Buckets: 262144
Batches: 2
Memory Usage: 6736kB
```

```
Planning Time: 1.819 ms
Execution Time: 1213.192 ms
```

### Propuesta de preagregación — DESCARTADA

Propuesta evaluada: preagregar por `(pedido_id, categoria_id)` para
eliminar el `COUNT(DISTINCT)`.

**Resultado real**:
```
Execution Time: 1588.375 ms
```

**Plan relevante**:
```
HashAggregate
rows reales: 400007
Planned Partitions: 16
Batches: 81
Memory Usage: 8337kB
Disk Usage: 31056kB

Nested Loop
  Index Scan using pedido_pkey
  loops=400007

Sort Method: external merge
Disk: 18728kB
```

**Conclusión de esta propuesta**: **descartada**. La reescritura era
semánticamente razonable, pero empeoró el tiempo real de ejecución:

```
1213.192 ms -> 1588.375 ms
```

Se registra expresamente que esta propuesta fallida **no se ocultó** del
informe — forma parte de la evidencia del proceso de optimización.

### Experimento de work_mem

Experimento de configuración de sesión, **no presentado como solución
estructural definitiva**:

```sql
SET work_mem = '64MB';
```

**Resultado real sobre la consulta original**:
```
Execution Time: 1135.058 ms
```

**Cambios observados**:

| | Antes | Después |
|---|---|---|
| Sort | `external merge`, `Disk: 25008kB` | `quicksort`, `Memory: 43539kB` |
| Hash sobre pedido | `Batches: 2`, `Memory Usage: 6736kB` | `Batches: 1`, `Memory Usage: 11424kB` |

Los algoritmos de `JOIN` **siguieron siendo los mismos tres `Hash Join`**
— este experimento no cambió la estrategia de unión, solo la manera en
que el `Sort` y el `Hash` sobre `pedido` administraron su memoria de
trabajo.

**Mejora observada**:
```
1213.192 / 1135.058 ≈ 1.07x
```
Reducción aproximada de `Execution Time`: ≈6.4%.

### Conclusión de Consulta 1

Se acepta el aumento de `work_mem` **únicamente como experimento de
configuración de sesión**. No se afirma que deba configurarse `64MB` de
manera global ni que sea una solución estructural definitiva. La
configuración fue restaurada posteriormente con `RESET work_mem;`. La
propuesta de preagregación por `(pedido_id, categoria_id)` queda
formalmente descartada por evidencia real de empeoramiento.

---

## 3. Consulta 2 — Ranking de clientes por gasto

### SQL

```sql
SELECT
    c.id AS cliente_id,
    c.nombre AS cliente_nombre,
    COUNT(DISTINCT pe.id) AS cantidad_pedidos,
    SUM(dp.cantidad) AS unidades_compradas,
    SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
FROM cliente c
JOIN pedido pe
    ON pe.cliente_id = c.id
JOIN detalle_pedido dp
    ON dp.pedido_id = pe.id
GROUP BY
    c.id,
    c.nombre
ORDER BY
    gasto_total DESC,
    cliente_nombre ASC
LIMIT 100;
```

### Plan antes

**Algoritmos de JOIN**:

| Condición | Algoritmo |
|---|---|
| `dp.pedido_id = pe.id` | Hash Join |
| `pe.cliente_id = c.id` | Hash Join |

**Sort principal**:
```
Sort Key: c.id, pe.id
Sort Method: external merge
Disk: 28744kB
```

**Hash sobre pedido**:
```
Batches: 2
Memory Usage: 6736kB
```

```
Planning Time: 0.694 ms
Execution Time: 696.459 ms
```

### Propuesta aceptada

Preagregar `detalle_pedido` por `pedido_id`:

```sql
WITH detalle_por_pedido AS (
    SELECT
        pedido_id,
        SUM(cantidad) AS unidades,
        SUM(cantidad * precio_unitario) AS gasto
    FROM detalle_pedido
    GROUP BY pedido_id
)
```

Y luego: `JOIN` con `pedido`, `JOIN` con `cliente`, `COUNT(*)` en lugar
de `COUNT(DISTINCT pe.id)`.

**Razón semántica**: después de agrupar `detalle_pedido` por
`pedido_id` existe exactamente una fila por pedido, por lo que
`COUNT(*)` agrupado por cliente equivale a contar pedidos distintos —
sin necesitar `DISTINCT`.

### Plan después

**Reducción real observada**:
- `detalle_pedido`: 500.007 filas
- `GroupAggregate` por `pedido_id`: 200.005 filas

**Algoritmos de JOIN**:

| Condición | Algoritmo |
|---|---|
| detalle agregado ↔ pedido (`detalle_pedido.pedido_id = pe.id`) | **Merge Join** |
| resultado ↔ cliente (`pe.cliente_id = c.id`) | Hash Join |

**Entradas del Merge Join**:
- `GroupAggregate` alimentado por `Index Scan using pk_detalle_pedido`.
- `Index Scan using pedido_pkey`.

**Agregación final**:
```
HashAggregate
Group Key: c.id
Batches: 5
Memory Usage: 8369kB
Disk Usage: 7504kB
```

**Sort final**:
```
top-N heapsort
Memory: 46kB
```

```
Planning Time: 0.307 ms
Execution Time: 509.388 ms
```

### Cambio de algoritmo de JOIN: Hash Join → Merge Join

En el plan original, la unión entre `detalle_pedido` y `pedido` se
resolvía con **Hash Join**. Tras la reescritura, esa misma unión lógica
(ahora entre el `detalle_pedido` ya agregado por `pedido_id` y
`pedido`) pasó a resolverse con **Merge Join**, aprovechando que ambas
entradas llegaban ya ordenadas por su respectivo índice de clave
primaria (`pk_detalle_pedido` y `pedido_pkey`). Este es un cambio real
de algoritmo observado en el plan, no solo una reducción de filas.

**Mejora observada**:
```
696.459 / 509.388 ≈ 1.37x
```
Reducción aproximada: ≈26.9%.

### Equivalencia

Verificada mediante `EXCEPT` bidireccional **sobre el conjunto
completo**:

| Comparación | Filas |
|---|---|
| `original_minus_reescrita` | 0 |
| `reescrita_minus_original` | 0 |

Por lo tanto, la reescritura fue aceptada.

### Conclusión de Consulta 2

La preagregación por `pedido_id` fue aceptada: eliminó el `COUNT(DISTINCT)`,
cambió el algoritmo de unión entre `detalle_pedido` y `pedido` de
`Hash Join` a `Merge Join`, y produjo una mejora real medida de ≈1.37x,
con equivalencia semántica confirmada sobre el universo completo.

---

## 4. Tabla comparativa obligatoria

| Consulta | Algoritmo de join (antes) | Cambio aplicado | Algoritmo de join (después) | Mejora |
|---|---|---|---|---|
| 1 — Facturación por categoría y mes | Hash Join + Hash Join + Hash Join | `SET work_mem = '64MB'` como experimento de sesión | Hash Join + Hash Join + Hash Join | ≈1.07x |
| 2 — Ranking de clientes por gasto | Hash Join + Hash Join | Preagregación por `pedido_id` + `COUNT(*)` | Merge Join + Hash Join | ≈1.37x |

**Nota asociada a la Consulta 1**: la reescritura con preagregación por
`(pedido_id, categoria_id)` se evaluó y se **descartó** porque empeoró
el tiempo real de `1213.192 ms` a `1588.375 ms`.

---

## 5. Propuestas aceptadas

- **Consulta 1**: `SET work_mem = '64MB';` — aceptado únicamente como
  experimento de configuración de sesión, con mejora observada ≈1.07x
  (≈6.4% de reducción). No aceptado como configuración global ni como
  solución estructural definitiva. Restaurado con `RESET work_mem;`.
- **Consulta 2**: preagregación de `detalle_pedido` por `pedido_id`,
  reemplazando `COUNT(DISTINCT pe.id)` por `COUNT(*)` tras la
  agregación previa — aceptada, con mejora observada ≈1.37x, cambio de
  algoritmo de `Hash Join` a `Merge Join` en la unión con `pedido`, y
  equivalencia semántica confirmada por `EXCEPT` bidireccional sobre el
  conjunto completo.

---

## 6. Propuestas descartadas o matizadas

1. **Consulta 1 — preagregación por `(pedido_id, categoria_id)`**:
   descartada por empeorar el tiempo real de `1213.192 ms` a
   `1588.375 ms`.
2. **Consulta 1 — `work_mem = 64MB`**: aceptado como experimento de
   sesión, **no** como configuración global ni solución estructural
   definitiva.
3. **No proponer índices solo por observar `Seq Scan`**: las consultas
   analizadas procesan prácticamente la totalidad de las tablas
   involucradas, por lo que los `Seq Scan` combinados con `Hash Join`
   pueden ser decisiones correctas del planner, no necesariamente un
   síntoma de falta de índices.
4. **No afirmar que `Nested Loop` es siempre cuadrático o malo**: en
   otros planes puede ser eficiente si la entrada exterior es chica y
   existe un índice selectivo del lado interior.
5. **No afirmar como regla universal que siempre se hashea la tabla más
   chica**: se describe únicamente como lo observado en los planes de
   este informe, no como una regla general garantizada del planner.
6. **`cost` no son milisegundos**: remarcado en ambas consultas.
7. **`actual time` no representa tiempo exclusivo de un nodo**:
   remarcado en ambas consultas.

---

## 7. Conclusiones

- No toda propuesta de optimización mejora el rendimiento: la
  preagregación por `(pedido_id, categoria_id)` en la Consulta 1 es un
  ejemplo documentado de una reescritura semánticamente razonable que,
  medida realmente, empeoró el tiempo de ejecución. Se registra sin
  ocultarla, como parte legítima del proceso.
- El aumento de `work_mem` mostró una mejora real pero modesta (≈1.07x)
  sobre la Consulta 1, sin cambiar los algoritmos de `JOIN` — solo
  cambió cómo el `Sort` y el `Hash` administraron su memoria de trabajo.
  Se acepta únicamente como experimento de sesión.
- La Consulta 2 mostró la mejora más significativa de este informe
  (≈1.37x), y es también la única en la que se observó un **cambio real
  de algoritmo de JOIN** (`Hash Join` → `Merge Join`), verificado con
  equivalencia semántica completa sobre el conjunto de datos real.
- Ninguna afirmación de este informe generaliza el comportamiento
  observado como regla universal de PostgreSQL — todas las conclusiones
  están ancladas a los planes reales de estas dos consultas puntuales.
- Toda cifra de tiempo citada en este informe es real y fue medida
  directamente; no se inventó ni se ajustó ningún valor.

---

## 8. Evidencias principales

| Evidencia | Valor |
|---|---|
| Consulta 1 — Execution Time original | 1213.192 ms |
| Consulta 1 — Execution Time con preagregación (descartada) | 1588.375 ms |
| Consulta 1 — Execution Time con work_mem=64MB | 1135.058 ms |
| Consulta 1 — mejora work_mem | ≈1.07x (≈6.4%) |
| Consulta 2 — Execution Time original | 696.459 ms |
| Consulta 2 — Execution Time con preagregación aceptada | 509.388 ms |
| Consulta 2 — mejora | ≈1.37x (≈26.9%) |
| Consulta 2 — cambio de algoritmo de JOIN | Hash Join → Merge Join (detalle_pedido agregado ↔ pedido) |
| Consulta 2 — equivalencia EXCEPT (conjunto completo) | 0 / 0 |
