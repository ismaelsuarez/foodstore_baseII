# Informe de mediciones — TP Unidad 3, Semana 1, Parte A

Base de Datos II — Plan de indexado asistido por IA

Base de trabajo: `foodstore_tp5` (PostgreSQL 17)

---

## 1. Objetivo

Documentar el resultado completo de la Parte A: tres índices propuestos
por IA, revisados y corregidos por el estudiante, medidos manualmente
sobre `foodstore_tp5` mediante `EXPLAIN (ANALYZE, BUFFERS)`, y
finalmente aceptados. Se registra también una propuesta descartada por
sobreindexación y un benchmark de costo de escritura.

---

## 2. Protocolo de medición

Cada consulta se midió con `EXPLAIN (ANALYZE, BUFFERS)` ejecutado tres
veces, descartando la primera ejecución (calentamiento) y promediando
las dos restantes como tiempo estable. Los buffers reportados
corresponden a las ejecuciones estables. Ningún tiempo ni buffer fue
inventado: todos los valores provienen de mediciones reales indicadas
por el estudiante.

---

## 3. Índice 1 — Stock bajo

**Consulta:**

```sql
SELECT
    id,
    nombre,
    stock,
    precio
FROM producto
WHERE activo = TRUE
  AND stock <= 5
ORDER BY stock ASC, nombre ASC;
```

**Antes:**
- Plan: `Seq Scan` + `Sort`
- Tabla `producto`: 50.003 filas
- Resultado: 1.493 filas
- `Rows Removed by Filter`: 48.510
- Buffers: 900
- Tiempos estables: 9.694 ms, 10.366 ms
- Promedio: 10.030 ms

**Después:**
- Plan: `Index Only Scan using idx_producto_stock_bajo`
- Sin nodo `Sort`
- `Heap Fetches`: 0
- Buffers estables: 14
- Tiempos estables: 0.262 ms, 0.273 ms
- Promedio: 0.2675 ms
- Mejora: ≈37.50x
- Reducción de Execution Time: ≈97.33 %

**Índice:**

```sql
CREATE INDEX idx_producto_stock_bajo
    ON producto (stock ASC, nombre ASC)
    INCLUDE (id, precio)
    WHERE activo = TRUE;
```

**Estado:** ACEPTADO.

---

## 4. Índice 2 — Pedidos recientes

**Consulta:**

```sql
SELECT
    id,
    cliente_id,
    fecha,
    forma_pago
FROM pedido
WHERE fecha >= TIMESTAMPTZ '2026-04-11 12:00:00-03'
ORDER BY fecha DESC;
```

**Antes:**
- Plan: `Seq Scan` + `Sort`
- Tabla `pedido`: 200.005 filas
- Resultado: 1.280 filas
- `Rows Removed by Filter`: 198.725
- Buffers: 1471
- Tiempos estables: 13.983 ms, 11.778 ms
- Promedio: 12.8805 ms

**Después:**
- Plan: `Index Only Scan using idx_pedido_fecha_reciente`
- Sin nodo `Sort`
- `Heap Fetches`: 85
- Buffers: 12
- Tiempos estables válidos: 0.384 ms, 0.242 ms
- Promedio: 0.313 ms
- Mejora: ≈41.15x
- Reducción de Execution Time: ≈97.57 %

**Índice:**

```sql
CREATE INDEX idx_pedido_fecha_reciente
    ON pedido (fecha DESC)
    INCLUDE (id, cliente_id, forma_pago);
```

**Estado:** ACEPTADO.

---

## 5. Índice 3 — Email case-insensitive

**Consulta:**

```sql
SELECT
    id,
    nombre,
    email
FROM cliente
WHERE lower(email) = lower('ANA.GOMEZ@FOODSTORE.TEST');
```

**Antes:**
- Plan: `Seq Scan`
- Tabla `cliente`: 20.003 filas
- Resultado: 1 fila
- `Rows Removed by Filter`: 20.002
- Buffers: 267
- Tiempos estables: 10.322 ms, 10.222 ms
- Promedio: 10.272 ms

**Después:**
- Plan: `Index Scan using idx_cliente_email_lower`
- Buffers: 4
- Tiempos estables: 0.104 ms, 0.111 ms
- Promedio: 0.1075 ms
- Mejora: ≈95.55x
- Reducción de Execution Time: ≈98.95 %

**Índice:**

```sql
CREATE INDEX idx_cliente_email_lower
    ON cliente (lower(email));
```

**Estado:** ACEPTADO.

---

## 6. Propuesta descartada por sobreindexación

**Propuesta de IA original:**

```sql
CREATE INDEX idx_cliente_email_lower
    ON cliente (lower(email))
    INCLUDE (id, nombre, email);
```

**Estado:** DESCARTADA.

**Motivo:** la consulta devuelve una única fila sobre 20.003. Ampliar
todas las entradas del índice con `id`, `nombre` y `email` solo para
perseguir un `Index Only Scan` no compensa el costo permanente de
almacenamiento y mantenimiento:

- mayor tamaño del índice;
- más costo de `INSERT`;
- `UPDATE nombre` pasaría a afectar el índice únicamente por estar en
  `INCLUDE`;
- `email` quedaría duplicado adicionalmente, ya que `cliente_email_key`
  ya lo indexa;
- un acceso puntual al heap, dada la selectividad extrema de esta
  consulta, es un costo aceptable frente a esas cargas permanentes.

Se optó por el índice simple de expresión (`idx_cliente_email_lower`
sin `INCLUDE`), documentado en la Sección 5.

---

## 7. Costo de escritura

**Benchmark:** transacción reversible que crea 1 pedido e inserta 500
filas en `detalle_pedido`, seguida de `ROLLBACK`.

**Antes de los nuevos índices:**
- Calentamiento: 19.063 ms
- Válidas: 17.849 ms, 16.663 ms
- Promedio estable: 17.256 ms

**Después de los nuevos índices:**
- Calentamiento: 7.400 ms
- Válidas: 7.234 ms, 7.720 ms
- Promedio estable: 7.477 ms

**Diferencia observada:** 17.256 ms → 7.477 ms (≈2.31x, ≈56.67 % menor
tiempo).

**Interpretación:** esta diferencia **no** puede atribuirse a que los
índices nuevos hayan hecho más rápida la escritura. El benchmark
inserta principalmente en `detalle_pedido`, tabla que no tiene ninguno
de los tres índices nuevos — estos están sobre `producto`, `pedido` y
`cliente`. Solo la creación de la cabecera del pedido toca directamente
uno de los índices nuevos (`idx_pedido_fecha_reciente`), y el volumen
de esa operación es mínimo frente a las 500 filas de detalle. La
diferencia favorable observada puede estar influida por estado de
caché, condiciones de la máquina en el momento de la medición, y
variabilidad entre corridas — no por un efecto causal de los índices
creados.

**Conclusión correcta:** no se observó penalización de escritura en
este benchmark.

---

## 8. Tabla resumen

| Consulta | Plan antes | Plan después | Antes (ms) | Después (ms) | Mejora |
|---|---|---|---:|---:|---:|
| Stock bajo (`producto`) | Seq Scan + Sort | Index Only Scan | 10.030 | 0.2675 | ≈37.50x |
| Pedidos recientes (`pedido`) | Seq Scan + Sort | Index Only Scan | 12.8805 | 0.313 | ≈41.15x |
| Email case-insensitive (`cliente`) | Seq Scan | Index Scan | 10.272 | 0.1075 | ≈95.55x |

---

## 9. Conclusiones

Los tres índices propuestos por IA, después de revisión y corrección
por el estudiante (terminología de selectividad, tratamiento del
predicado parcial, precisión sobre ASC/DESC y backward scan, e impacto
real de columnas `INCLUDE` sobre `UPDATE`), fueron medidos sobre
`foodstore_tp5` y aceptados: en los tres casos desapareció el `Seq
Scan`, bajaron los buffers de forma sustancial y el `Execution Time`
estable se redujo entre ≈37x y ≈95x según la consulta. Una cuarta
propuesta de IA — la variante cubridora de `idx_cliente_email_lower` —
fue descartada explícitamente por sobreindexación, documentando el
costo estructural que no se justificaba frente a un ahorro puntual de
un solo acceso al heap. El benchmark de escritura no mostró
penalización, pero esa observación se registra con la cautela
correspondiente: el benchmark no ejercita directamente a los tres
índices nuevos, por lo que no se puede afirmar como una mejora causal
sobre la escritura.

---

## 10. Evidencia — EXPLAIN ANALYZE completos

Se muestra una ejecución representativa de cada estado. Los promedios
estables informados en las secciones anteriores se calcularon sobre las
ejecuciones 2 y 3 del protocolo de medición.

### Consulta 1 — Antes

```
Sort  (cost=1593.81..1597.12 rows=1326 width=35)
(actual time=9.543..9.581 rows=1493 loops=1)
  Sort Key: stock, nombre
  Sort Method: quicksort  Memory: 130kB
  Buffers: shared hit=906
  -> Seq Scan on producto
     (cost=0.00..1525.04 rows=1326 width=35)
     (actual time=0.017..5.288 rows=1493 loops=1)
       Filter: (activo AND (stock <= 5))
       Rows Removed by Filter: 48510
       Buffers: shared hit=900
Planning:
  Buffers: shared hit=154
Planning Time: 0.577 ms
Execution Time: 9.694 ms
```

### Consulta 1 — Después

```
Index Only Scan using idx_producto_stock_bajo on producto
(cost=0.41..62.69 rows=1273 width=35)
(actual time=0.053..0.198 rows=1493 loops=1)
  Index Cond: (stock <= 5)
  Heap Fetches: 0
  Buffers: shared hit=14
Planning:
  Buffers: shared hit=180
Planning Time: 0.577 ms
Execution Time: 0.262 ms
```

### Consulta 2 — Antes

```
Sort  (cost=4033.90..4036.96 rows=1225 width=28)
(actual time=13.871..13.901 rows=1280 loops=1)
  Sort Key: fecha DESC
  Sort Method: quicksort  Memory: 109kB
  Buffers: shared hit=1474
  -> Seq Scan on pedido
     (cost=0.00..3971.06 rows=1225 width=28)
     (actual time=13.635..13.725 rows=1280 loops=1)
       Filter:
       (fecha >= '2026-04-11 12:00:00-03'::timestamp with time zone)
       Rows Removed by Filter: 198725
       Buffers: shared hit=1471
Planning:
  Buffers: shared hit=138 dirtied=5
Planning Time: 0.678 ms
Execution Time: 13.983 ms
```

### Consulta 2 — Después

```
Index Only Scan using idx_pedido_fecha_reciente on pedido
(cost=0.42..58.17 rows=1243 width=28)
(actual time=0.035..0.224 rows=1280 loops=1)
  Index Cond:
  (fecha >= '2026-04-11 12:00:00-03'::timestamp with time zone)
  Heap Fetches: 85
  Buffers: shared hit=12
Planning:
  Buffers: shared hit=163
Planning Time: 0.716 ms
Execution Time: 0.384 ms
```

### Consulta 3 — Antes

```
Seq Scan on cliente
(cost=0.00..567.05 rows=100 width=57)
(actual time=0.022..10.260 rows=1 loops=1)
  Filter:
  (lower((email)::text) = 'ana.gomez@foodstore.test'::text)
  Rows Removed by Filter: 20002
  Buffers: shared hit=267
Planning:
  Buffers: shared hit=83
Planning Time: 0.405 ms
Execution Time: 10.322 ms
```

### Consulta 3 — Después

```
Index Scan using idx_cliente_email_lower on cliente
(cost=0.41..8.43 rows=1 width=57)
(actual time=0.034..0.035 rows=1 loops=1)
  Index Cond:
  (lower((email)::text) = 'ana.gomez@foodstore.test'::text)
  Buffers: shared hit=4
Planning:
  Buffers: shared hit=103
Planning Time: 0.496 ms
Execution Time: 0.104 ms
```
