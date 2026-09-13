# Informe de optimización — TP3 Parte 2

Base de Datos II — Semana 3, Unidad 2: Optimización de Consultas mediante
EXPLAIN ANALYZE

---

## 1. Objetivo

Documentar formalmente el laboratorio de consultas lentas de la Parte 2
del TP3: para cada una de tres consultas identificadas como costosas,
registrar el plan real "antes" (`EXPLAIN ANALYZE`), el índice propuesto
y aceptado, el plan real "después", y la mejora observada entre esas
ejecuciones concretas. Todos los valores de tiempo y de `cost` citados
en este informe son los medidos/estimados realmente — no se inventa ni
se ajusta ninguna cifra.

Se remarca en todo el documento la distinción entre `cost` (unidades
internas estimadas por el planner) y tiempo real medido en milisegundos
(`actual time`, `Planning Time`, `Execution Time`) — son magnitudes de
naturaleza distinta y no deben confundirse ni combinarse aritméticamente.

---

## 2. Consulta 1 — Productos por precio

### Consulta

```sql
SELECT
    id,
    nombre,
    precio,
    stock
FROM producto
WHERE precio >= 4500
ORDER BY precio DESC
LIMIT 100;
```

### Plan real — ANTES

```
Limit  (cost=1736.08..1736.33 rows=100 width=35)
       (actual time=7.356..7.363 rows=100 loops=1)
  -> Sort  (cost=1736.08..1749.89 rows=5522 width=35)
           (actual time=7.354..7.357 rows=100 loops=1)
       Sort Key: precio DESC
       Sort Method: top-N heapsort  Memory: 39kB
       -> Seq Scan on producto
            (cost=0.00..1525.04 rows=5522 width=35)
            (actual time=0.769..6.037 rows=5511 loops=1)
              Filter: precio >= 4500
              Rows Removed by Filter: 44492

Planning Time: 0.197 ms
Execution Time: 7.382 ms
```

### Propuesta de IA aceptada

```sql
CREATE INDEX idx_producto_precio_desc
ON producto (precio DESC);
```

### Plan real — DESPUÉS

```
Limit  (cost=0.29..68.17 rows=100 width=35)
       (actual time=0.054..0.105 rows=100 loops=1)
  -> Index Scan using idx_producto_precio_desc on producto
       (cost=0.29..3748.73 rows=5522 width=35)
       (actual time=0.053..0.099 rows=100 loops=1)
         Index Cond: precio >= 4500

Planning Time: 0.695 ms
Execution Time: 0.122 ms
```

### Mejora observada

```
7.382 / 0.122 ≈ 60.5 veces
```

### Hallazgos

- Desaparece el nodo `Seq Scan`.
- Desaparece el nodo `Sort`.
- La condición pasa de `Filter` (aplicada después de leer cada fila) a
  `Index Cond` (usada por el índice para localizar directamente las
  filas relevantes).
- No debe confundirse `cost` con milisegundos: los valores de `cost` de
  ambos planes son estimaciones del planner en unidades propias, no
  tiempo.
- Los tiempos de nodos anidados (`actual time` de un nodo hijo dentro de
  un padre) no deben sumarse ni restarse entre sí como si representaran
  un tiempo exclusivo aislado de cada nodo.

---

## 3. Consulta 2 — Pedidos TARJETA por fecha

### Consulta

```sql
SELECT
    id,
    cliente_id,
    fecha,
    forma_pago
FROM pedido
WHERE forma_pago = 'TARJETA'
ORDER BY fecha DESC
LIMIT 100;
```

### Plan real — ANTES

```
Limit  (cost=5445.26..5456.76 rows=100 width=28)
       (actual time=47.724..55.093 rows=100 loops=1)
  -> Gather Merge  (cost=5445.26..9969.59 rows=39342 width=28)
                    (actual time=47.722..55.081 rows=100 loops=1)
       Workers Planned: 1
       Workers Launched: 1
       -> Sort  (cost=4445.25..4543.60 rows=39342 width=28)
                (actual time=23.388..23.391 rows=50 loops=2)
            Sort Key: fecha DESC
            Sort Method: top-N heapsort  Memory: 39kB
            -> Parallel Seq Scan on pedido
                 (cost=0.00..2941.62 rows=39342 width=28)
                 (actual time=0.006..13.551 rows=33334 loops=2)
                   Filter: forma_pago = 'TARJETA'
                   Rows Removed by Filter: 66668

Planning Time: 0.152 ms
Execution Time: 55.123 ms
```

### Propuesta de IA aceptada

```sql
CREATE INDEX idx_pedido_forma_pago_fecha
ON pedido (forma_pago, fecha DESC);
```

### Plan real — DESPUÉS

```
Limit  (cost=0.42..11.84 rows=100 width=28)
       (actual time=0.088..0.115 rows=100 loops=1)
  -> Index Scan using idx_pedido_forma_pago_fecha on pedido
       (cost=0.42..7641.57 rows=66882 width=28)
       (actual time=0.087..0.107 rows=100 loops=1)
         Index Cond: forma_pago = 'TARJETA'

Planning Time: 0.353 ms
Execution Time: 0.135 ms
```

### Mejora observada

```
55.123 / 0.135 ≈ 408 veces
```

### Hallazgos

- Desaparece el `Parallel Seq Scan`.
- Desaparece el `Sort`.
- Desaparece el `Gather Merge`.
- Desaparecen los workers paralelos (`Workers Planned` / `Workers
  Launched`).
- El índice compuesto ubica la igualdad (`forma_pago`) primero, y la
  columna de orden (`fecha DESC`) después, para poder satisfacer tanto el
  filtro como el `ORDER BY` sin necesidad de un `Sort` adicional.
- No corresponde atribuir una cantidad exacta de milisegundos al
  overhead de coordinación paralela restando el tiempo de un nodo hijo
  al de su padre — esa resta no es una medición válida del costo
  exclusivo de un nodo.
- En nodos paralelos, las métricas reportadas (`rows`, `Rows Removed by
  Filter`) están expresadas como promedio por proceso participante
  (`loops`); no deben multiplicarse mecánicamente por el valor de
  `loops` como si fuera una operación aritmética exacta y garantizada.

---

## 4. Consulta 3 — Detalles por producto

### Consulta

```sql
SELECT
    dp.pedido_id,
    dp.producto_id,
    dp.cantidad,
    dp.precio_unitario
FROM detalle_pedido dp
WHERE dp.producto_id = (
    SELECT id
    FROM producto
    WHERE nombre = 'Producto TP3 25000'
)
ORDER BY dp.pedido_id DESC;
```

### Plan real — ANTES

```
Gather Merge  (cost=8806.30..8807.24 rows=8 width=25)
              (actual time=95.830..103.139 rows=12 loops=1)
  Workers Planned: 2
  Workers Launched: 2

  InitPlan 1
    -> Seq Scan on producto
         (cost=0.00..1525.04 rows=1 width=8)
         (actual time=3.308..6.834 rows=1 loops=1)
           Filter: nombre = 'Producto TP3 25000'
           Rows Removed by Filter: 50002

  -> Sort  (cost=6281.24..6281.25 rows=4 width=25)
           (actual time=19.951..19.953 rows=4 loops=3)
       -> Parallel Seq Scan on detalle_pedido
            (cost=0.00..6281.20 rows=4 width=25)
            (actual time=13.423..19.807 rows=4 loops=3)
              Filter: producto_id = InitPlan
              Rows Removed by Filter: 166665

Planning Time: 0.421 ms
Execution Time: 103.176 ms
```

### Primer cambio propuesto y aplicado

```sql
CREATE INDEX idx_producto_nombre
ON producto (nombre);
```

**Resultado intermedio**: el `InitPlan` pasa a resolverse con
`Index Scan using idx_producto_nombre`, pero el `Parallel Seq Scan` sobre
`detalle_pedido` seguía presente.

```
Execution Time: 50.617 ms
```

### Segundo cambio propuesto y aplicado

```sql
CREATE INDEX idx_detalle_pedido_producto_pedido
ON detalle_pedido (producto_id, pedido_id DESC);
```

### Plan real — DESPUÉS de aplicar ambos índices

```
Sort  (cost=51.66..51.68 rows=10 width=25)
      (actual time=0.154..0.155 rows=12 loops=1)

  InitPlan
    -> Index Scan using idx_producto_nombre
         (actual time=0.063..0.064 rows=1 loops=1)

  -> Bitmap Heap Scan on detalle_pedido
       (cost=4.50..43.06 rows=10 width=25)
       (actual time=0.138..0.139 rows=12 loops=1)
         Recheck Cond: producto_id = InitPlan
         Heap Blocks: exact=1

       -> Bitmap Index Scan using idx_detalle_pedido_producto_pedido
            (cost=0.00..4.50 rows=10 width=0)
            (actual time=0.124..0.124 rows=12 loops=1)
              Index Cond: producto_id = InitPlan

Planning Time: 0.714 ms
Execution Time: 0.317 ms
```

### Mejora comparable

```
103.176 / 0.317 ≈ 325 veces
```

### Validación posterior después del commit

```
Execution Time: 0.093 ms
```

Este valor se registra **únicamente como revalidación posterior** de que
la mejora se mantiene tras confirmar los cambios; **no se usa** para
calcular la razón de mejora de la tabla comparativa, para no inflar
artificialmente el resultado. La cifra usada para la comparación
antes/después es `0.317 ms`, porque corresponde a la medición
inmediatamente posterior a aplicar ambos índices, dentro de la misma
prueba.

### Hallazgo crítico

Antes de medir, existía la expectativa de que el índice
`(producto_id, pedido_id DESC)` eliminara también el nodo `Sort`, dado
que ese orden de columnas coincide con el `ORDER BY pedido_id DESC` de la
consulta.

**Eso no ocurrió.** PostgreSQL eligió la siguiente estrategia de acceso:

```
Bitmap Index Scan
  -> Bitmap Heap Scan
  -> Sort
```

El bitmap localizó eficientemente las 12 filas necesarias (`Heap Blocks:
exact=1`), pero el mecanismo de bitmap **no preserva un orden utilizable**
para el `ORDER BY pedido_id DESC` de salida — construye un mapa de
posiciones a visitar, no un flujo ya ordenado. Por eso PostgreSQL
mantuvo un `Sort` explícito sobre las 12 filas finales, a pesar de que el
índice se usó correctamente para el filtro.

Este hallazgo demuestra que una expectativa formada antes de medir —
incluso una razonable, basada en el diseño del índice — debe verificarse
siempre contra el `EXPLAIN ANALYZE` real antes de darse por confirmada.

---

## 5. Tabla comparativa obligatoria

| Consulta | Plan antes (nodo, cost, tiempo real) | Cambio aplicado | Plan después (nodo, cost, tiempo real) | Mejora |
|---|---|---|---|---|
| 1 — Productos por precio | `Seq Scan` + `Sort` + `Limit` — cost total `1736.33`, `Execution Time: 7.382 ms` | `CREATE INDEX idx_producto_precio_desc ON producto (precio DESC)` | `Index Scan` + `Limit` (sin `Sort`) — cost total `68.17`, `Execution Time: 0.122 ms` | ≈ 60.5x |
| 2 — Pedidos TARJETA por fecha | `Parallel Seq Scan` + `Sort` + `Gather Merge` + `Limit` — cost total `5456.76`, `Execution Time: 55.123 ms` | `CREATE INDEX idx_pedido_forma_pago_fecha ON pedido (forma_pago, fecha DESC)` | `Index Scan` + `Limit` (sin `Sort`, sin `Gather Merge`, sin workers) — cost total `11.84`, `Execution Time: 0.135 ms` | ≈ 408x |
| 3 — Detalles por producto | `Seq Scan` (InitPlan) + `Parallel Seq Scan` + `Sort` + `Gather Merge` — cost total `8807.24`, `Execution Time: 103.176 ms` | `CREATE INDEX idx_producto_nombre ON producto (nombre)` + `CREATE INDEX idx_detalle_pedido_producto_pedido ON detalle_pedido (producto_id, pedido_id DESC)` | `Index Scan` (InitPlan) + `Bitmap Index Scan` + `Bitmap Heap Scan` + `Sort` (persiste) — cost total `51.68`, `Execution Time: 0.317 ms` | ≈ 325x |

**Aclaración obligatoria**: las razones de mejora (`60.5x`, `408x`,
`325x`) son proporciones observadas entre esas ejecuciones concretas —
no son garantías de rendimiento futuro ni valores universales. Los
tiempos reales pueden variar entre corridas por efectos de caché del
sistema operativo y de PostgreSQL (buffer cache, page cache), carga del
sistema en el momento de la medición, y otras condiciones del entorno de
ejecución.

---

## 6. Propuestas de IA aceptadas

- **Consulta 1**: `CREATE INDEX idx_producto_precio_desc ON producto (precio DESC);` — aceptada y aplicada; eliminó tanto el `Seq Scan` como el `Sort`.
- **Consulta 2**: `CREATE INDEX idx_pedido_forma_pago_fecha ON pedido (forma_pago, fecha DESC);` — aceptada y aplicada; eliminó el `Parallel Seq Scan`, el `Sort` y el `Gather Merge` con sus workers.
- **Consulta 3 (primer cambio)**: `CREATE INDEX idx_producto_nombre ON producto (nombre);` — aceptada y aplicada; resolvió el `InitPlan` mediante `Index Scan`, aunque por sí sola no bastó (el `Parallel Seq Scan` sobre `detalle_pedido` persistió, con `Execution Time: 50.617 ms`).
- **Consulta 3 (segundo cambio)**: `CREATE INDEX idx_detalle_pedido_producto_pedido ON detalle_pedido (producto_id, pedido_id DESC);` — aceptada y aplicada; junto con el índice anterior, redujo el `Execution Time` a `0.317 ms`.

---

## 7. Propuestas o afirmaciones de IA corregidas o matizadas

- **Expectativa incorrecta sobre la Consulta 3**: se esperaba que el
  índice `(producto_id, pedido_id DESC)` eliminara también el `Sort`
  final, por coincidir su segunda columna con el `ORDER BY`. El plan
  real mostró que esto no ocurrió, porque PostgreSQL resolvió el acceso
  mediante `Bitmap Index Scan` + `Bitmap Heap Scan`, y ese mecanismo de
  bitmap no preserva el orden del índice en la salida. Se corrige la
  expectativa: un índice que coincide con el `ORDER BY` no garantiza por
  sí solo la eliminación del `Sort` si el planner elige una estrategia de
  acceso basada en bitmap en lugar de un `Index Scan` simple.
- **Uso de la cifra de revalidación posterior (0.093 ms)**: se aclara
  explícitamente que ese valor no debe usarse para calcular la mejora
  reportada en la tabla comparativa (que usa `0.317 ms`), para evitar
  inflar artificialmente la razón de mejora con una medición posterior
  potencialmente favorecida por caché ya "caliente".
- **Distinción cost vs. tiempo real**: se remarca en las tres consultas
  que ningún valor de `cost` debe interpretarse como milisegundos, ni
  compararse directamente contra `actual time`, `Planning Time` o
  `Execution Time`.
- **Atribución de tiempo exclusivo a nodos anidados**: los valores
  `actual time` de un nodo no representan tiempo exclusivo de ese nodo:
  incluyen el trabajo necesario de sus nodos hijos. Además, cuando
  `loops > 1`, los tiempos mostrados corresponden al promedio por
  ejecución del nodo. Por eso no corresponde restar mecánicamente el
  tiempo de un hijo al de su padre para atribuir un tiempo exclusivo.
- **Métricas en nodos paralelos**: se aclara que valores como `rows` o
  `Rows Removed by Filter` en nodos con `loops > 1` representan un
  promedio por proceso participante, y no deben multiplicarse
  mecánicamente por `loops` para inferir un total exacto sin explicitar
  que se trata de una aproximación basada en un promedio reportado.

---

## 8. Conclusiones

- En las tres consultas, la causa raíz del bajo rendimiento fue la
  ausencia de un índice adecuado para el filtro y/o el orden solicitado,
  forzando a PostgreSQL a recorrer la tabla completa (`Seq Scan` o
  `Parallel Seq Scan`) y, en dos de los tres casos, a paralelizar el
  trabajo para compensar ese costo.
- Las propuestas de índice aceptadas resultaron efectivas en las tres
  consultas, con mejoras observadas de ≈60.5x, ≈408x y ≈325x
  respectivamente, medidas siempre sobre `Execution Time` real, nunca
  sobre valores de `cost`.
- La Consulta 3 mostró que **no toda expectativa formada antes de medir
  se cumple**: el índice compuesto mejoró drásticamente el acceso a los
  datos, pero no eliminó el `Sort`, porque la estrategia de bitmap
  elegida por el planner no preserva orden. Esto no invalida la
  optimización — el tiempo real final (`0.317 ms`, revalidado luego en
  `0.093 ms`) sigue siendo extremadamente bajo — pero exige verificar
  siempre el plan real antes de dar por válida una hipótesis sobre qué
  nodos deberían desaparecer.
- Toda afirmación sobre mejora de rendimiento en este informe está
  anclada a mediciones concretas de `Execution Time` entre ejecuciones
  específicas, y se aclara explícitamente que esas razones pueden variar
  entre corridas por condiciones de caché y carga del sistema — no son
  garantías de comportamiento futuro.
