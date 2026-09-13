# Competencia de optimización — TP4 Parte 4

Base de Datos II — Semana 4, Unidad 2: Optimización de Consultas

---

## 1. Objetivo

Documentar la resolución de la Parte 4 del TP4: optimizar una consulta
analítica común (ranking, con al menos 2 `JOIN` y agregación), ejecutada
sobre `foodstore_tp4` masivo, y registrar el resultado en el formato de
"competencia" previsto por la consigna. En esta instancia participa un
único equipo, por lo que la competencia se resuelve registrando y
evaluando la estrategia propia, sin comparación contra otros grupos.

---

## 2. Consulta de competencia

Se utiliza como consulta común la **Consulta 2 de la Parte 1**:
"Ranking de clientes por gasto".

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

Cumple las condiciones exigidas: es una consulta de ranking, con 2
`JOIN`, agregación (`COUNT(DISTINCT)`, `SUM`), y fue ejecutada sobre
`foodstore_tp4` masivo.

---

## 3. Plan antes

**Algoritmos de JOIN**:

| Condición | Algoritmo |
|---|---|
| `detalle_pedido ↔ pedido` | Hash Join |
| resultado ↔ `cliente` | Hash Join |

**Elementos observados**:
```
Sort Method: external merge
Disk: 28744kB

Hash sobre pedido:
Batches: 2
Memory Usage: 6736kB
```

```
Planning Time: 0.694 ms
Execution Time: 696.459 ms
```

---

## 4. Estrategia propuesta

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

Y luego unir: `detalle_por_pedido JOIN pedido JOIN cliente`, usando
`COUNT(*)` en lugar de `COUNT(DISTINCT pe.id)`.

**Justificación**: después de agrupar por `pedido_id` existe una sola
fila por pedido, por lo que `COUNT(*)` al agrupar por cliente representa
correctamente la cantidad de pedidos, sin necesitar `DISTINCT`.

---

## 5. Plan después

**Reducción real observada**:
- `detalle_pedido`: 500.007 filas.
- Resultado agregado tras el `GroupAggregate`: 200.005 filas.

**Primer JOIN**:
```
Merge Join
Merge Cond: detalle_pedido.pedido_id = pe.id

Entradas:
Index Scan using pk_detalle_pedido
Index Scan using pedido_pkey
```

**Segundo JOIN**:
```
Hash Join
Hash Cond: pe.cliente_id = c.id
```

**Agregación final**:
```
HashAggregate
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

---

## 6. Equivalencia

La equivalencia fue verificada mediante `EXCEPT` en ambos sentidos:

| Comparación | Filas |
|---|---|
| `original_minus_reescrita` | 0 |
| `reescrita_minus_original` | 0 |

Por lo tanto, la estrategia optimizada conserva la semántica de la
consulta original.

---

## 7. Mejora obtenida

```
Tiempo antes:   696.459 ms
Tiempo después: 509.388 ms

Factor: 696.459 / 509.388 ≈ 1.37x
Reducción aproximada de Execution Time: ≈26.9%
```

---

## 8. Registro de la competencia

| Equipo | Estrategia aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|---|---|---:|---:|---:|
| Food Store | Preagregación de detalle_pedido por pedido_id + COUNT(*) | 696.459 | 509.388 | ≈1.37x |

**Aclaración**: en esta instancia existe un único equipo, por lo que no
se establece un ranking contra otros grupos. La tabla documenta el
resultado técnico obtenido por el equipo sobre la consulta seleccionada.

---

## 9. Uso de IA

- **OpenCode** fue utilizado para analizar el plan real de la consulta y
  proponer la estrategia de preagregación de `detalle_pedido` por
  `pedido_id`.
- **ChatGPT** fue utilizado para revisar la propuesta antes de
  ejecutarla, diseñar las verificaciones de equivalencia (`EXCEPT`), y
  contrastar el resultado real contra lo esperado.
- El estudiante ejecutó manualmente el SQL y los `EXPLAIN ANALYZE` en
  PostgreSQL.
- PostgreSQL fue la fuente final de verdad en todo momento.
- La estrategia fue aceptada únicamente después de medir el plan real y
  verificar la equivalencia semántica — no se aceptó por razonamiento
  teórico solamente.

---

## 10. Conclusión

La estrategia de preagregar `detalle_pedido` por `pedido_id` antes de
unir con `pedido` y `cliente`, reemplazando `COUNT(DISTINCT pe.id)` por
`COUNT(*)`, produjo una mejora real medida de ≈1.37x (≈26.9% de
reducción en `Execution Time`), con un cambio de algoritmo observable en
el primer `JOIN` (de `Hash Join` a `Merge Join`, al aprovechar que ambas
entradas llegaban ya ordenadas por sus respectivos índices de clave
primaria). La equivalencia semántica quedó confirmada mediante `EXCEPT`
bidireccional sobre el conjunto completo de datos, sin diferencias en
ninguna dirección. Como este ejercicio se realizó con un único equipo,
el resultado se registra como el desempeño propio sobre la consulta de
competencia, sin comparación contra terceros.
