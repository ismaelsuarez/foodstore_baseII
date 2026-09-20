# Lectura crítica de planes interpretados por IA — TP3 Parte 3

Base de Datos II — Semana 3, Unidad 2: Optimización de Consultas

---

## 1. Plan real analizado

### Consulta asociada

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

### Plan real obtenido después de aplicar los índices

```
Sort  (cost=51.66..51.68 rows=10 width=25)
(actual time=0.069..0.070 rows=12 loops=1)
  Sort Key: dp.pedido_id DESC
  Sort Method: quicksort  Memory: 25kB
  InitPlan 1
    -> Index Scan using idx_producto_nombre on producto
       (cost=0.41..8.43 rows=1 width=8)
       (actual time=0.036..0.037 rows=1 loops=1)
         Index Cond:
         ((nombre)::text = 'Producto TP3 25000'::text)

  -> Bitmap Heap Scan on detalle_pedido dp
     (cost=4.50..43.06 rows=10 width=25)
     (actual time=0.060..0.061 rows=12 loops=1)
       Recheck Cond: (producto_id = (InitPlan 1).col1)
       Heap Blocks: exact=1

       -> Bitmap Index Scan on idx_detalle_pedido_producto_pedido
          (cost=0.00..4.50 rows=10 width=0)
          (actual time=0.046..0.046 rows=12 loops=1)
            Index Cond: (producto_id = (InitPlan 1).col1)

Planning Time: 0.746 ms
Execution Time: 0.093 ms
```

---

## 2. Explicación generada por IA

> Reproducida literalmente, sin corregir, tal como fue generada en la sesión de asistencia con IA. Cualquier imprecisión que contenga se analiza recién en la Sección 3.

---

### Lectura nodo por nodo del plan

Antes de arrancar: en este plan aparecen dos tipos de números por nodo — **cost** (unidades internas del planner, una estimación abstracta, no tiempo) y **actual time** (milisegundos medidos realmente durante la ejecución). Los voy a mantener separados en todo momento.

Voy a explicar los nodos siguiendo el **orden real de ejecución** (de adentro hacia afuera), que es distinto del orden en que aparecen escritos en el texto del plan.

---

#### 1. Index Scan using idx_producto_nombre on producto (dentro de InitPlan 1)

```
cost=0.41..8.43 rows=1 width=8
actual time=0.036..0.037 rows=1 loops=1
Index Cond: ((nombre)::text = 'Producto TP3 25000'::text)
```

**Qué hace**: recorre el índice `idx_producto_nombre` buscando directamente la entrada que cumple la condición de igualdad sobre `nombre`. Como el plan dice `Index Cond` (y no `Filter`), esto significa que la condición se resuelve **usando la estructura del índice** para saltar directo a la entrada buscada, sin revisar filas que no coinciden.

**Qué significan sus métricas**: cost `0.41` (costo estimado de arrancar y producir la primera fila) hasta `8.43` (costo total estimado), para una fila estimada (`rows=1`) de 8 bytes de ancho. En tiempo real: `0.036` ms hasta la primera fila, `0.037` ms en total, con 1 fila efectivamente devuelta (`rows=1`), ejecutado una sola vez (`loops=1`).

**Cómo se relaciona**: este nodo es un **InitPlan** — un subplan que se resuelve de manera independiente, una sola vez, *antes* de que el resto del plan lo necesite. Su resultado (un valor escalar, referenciado como `(InitPlan 1).col1` más abajo) se usa como parámetro dentro de condiciones de otros nodos. No entrega un flujo de filas a un padre inmediato como en una relación normal padre-hijo; entrega un valor único que otros nodos consultan.

**Conclusión técnica**: el acceso a `producto` se resuelve con una búsqueda puntual por índice sobre una condición de igualdad, sin recorrer la tabla completa — se confirma por la palabra `Index Cond` y por el tiempo mínimo medido.

---

#### 2. Bitmap Index Scan on idx_detalle_pedido_producto_pedido

```
cost=0.00..4.50 rows=10 width=0
actual time=0.046..0.046 rows=12 loops=1
Index Cond: (producto_id = (InitPlan 1).col1)
```

**Qué hace**: recorre el índice `idx_detalle_pedido_producto_pedido` buscando todas las entradas donde `producto_id` sea igual al valor que entregó el InitPlan. En vez de devolver filas directamente, construye un **bitmap** en memoria que marca qué posiciones (bloques/tuplas) de la tabla `detalle_pedido` contienen coincidencias.

**Qué significan sus métricas**: cost `0.00` hasta `4.50`, con 10 filas estimadas (`rows=10`) y `width=0`. El ancho es `0` porque este nodo no transporta datos de columnas reales — solo marca posiciones candidatas, no proyecta contenido. En tiempo real: `0.046` ms tanto de arranque como total (prácticamente instantáneo), con 12 filas efectivamente marcadas (`rows=12`), una sola ejecución (`loops=1`).

**Cómo se relaciona**: es el nodo hijo del **Bitmap Heap Scan** que aparece justo arriba en el plan — el bitmap que construye se le entrega a ese nodo padre para que sepa exactamente qué bloques de la tabla visitar.

**Conclusión técnica**: la localización de candidatos en `detalle_pedido` es muy precisa (10 estimadas, 12 reales) y se apoya en una condición de igualdad (`Index Cond`) sobre `producto_id`, usando el índice mencionado.

---

#### 3. Bitmap Heap Scan on detalle_pedido dp

```
cost=4.50..43.06 rows=10 width=25
actual time=0.060..0.061 rows=12 loops=1
Recheck Cond: (producto_id = (InitPlan 1).col1)
Heap Blocks: exact=1
```

**Qué hace**: toma el bitmap generado por el nodo anterior y visita únicamente los bloques de la tabla (heap) marcados en ese bitmap, para traer los datos reales de las filas (todas las columnas necesarias). Además vuelve a verificar la condición (`Recheck Cond`) directamente sobre las filas ya leídas del heap — esto es un paso estándar de los Bitmap Scan, no algo particular de esta consulta.

**Qué significan sus métricas**: cost `4.50` de arranque (coincide exactamente con el costo total del nodo hijo — el Bitmap Index Scan — porque este nodo necesita el bitmap completo antes de poder visitar el primer bloque) hasta `43.06` de costo total, con 10 filas estimadas y ahora `width=25` (a diferencia del `width=0` del bitmap, aquí sí se transportan datos reales de columnas). En tiempo real: `0.060..0.061` ms, 12 filas devueltas, una ejecución. `Heap Blocks: exact=1` indica que **un solo bloque** de la tabla fue suficiente para satisfacer todas las coincidencias, y que el bitmap fue "exacto" (identificó tuplas puntuales, no solo páginas completas).

**Cómo se relaciona**: recibe el bitmap del Bitmap Index Scan (su hijo) y entrega sus filas de salida al nodo Sort (su padre).

**Conclusión técnica**: solo hizo falta leer un bloque de la tabla para obtener las 12 filas — un acceso muy acotado en términos de páginas físicas tocadas, coherente con una búsqueda de alta selectividad.

---

#### 4. Sort (nodo raíz del plan)

```
cost=51.66..51.68 rows=10 width=25
actual time=0.069..0.070 rows=12 loops=1
Sort Key: dp.pedido_id DESC
Sort Method: quicksort  Memory: 25kB
```

**Qué hace**: toma las filas entregadas por el Bitmap Heap Scan (12 filas) y las ordena por `dp.pedido_id` en forma descendente, usando un `quicksort` estándar — no aparece `top-N heapsort` porque no hay indicio en este plan de un `LIMIT` asociado.

**Qué significan sus métricas**: cost `51.66` hasta `51.68`, con 10 filas estimadas y `width=25` (mismo ancho que su hijo, porque ordenar no cambia la cantidad ni el contenido de columnas, solo su secuencia). En tiempo real: `0.069..0.070` ms, 12 filas de salida, una ejecución. `Memory: 25kB` muestra que el ordenamiento se hizo enteramente en memoria, sin necesidad de recurrir a disco — coherente con que son solo 12 filas.

**Cómo se relaciona**: es el nodo **raíz** del plan — su salida es el resultado final. Recibe filas del Bitmap Heap Scan y, además, depende del valor resuelto por el InitPlan 1 (que corrió una sola vez, antes, para poder resolver las condiciones usadas más abajo en el árbol).

**Conclusión técnica**: hace falta un paso explícito de ordenamiento porque ningún nodo anterior entrega las filas ya ordenadas por `pedido_id` — el camino de acceso (índice sobre `producto_id`) está organizado según otra columna, así que el orden por `pedido_id DESC` se resuelve acá, al final, sobre un conjunto ya reducido a 12 filas.

---

#### Números finales del plan

```
Planning Time: 0.746 ms
Execution Time: 0.093 ms
```

Estas dos cifras sí son tiempo real medido en milisegundos, y son magnitudes distintas entre sí: `Planning Time` es lo que tardó el planner en generar este plan; `Execution Time` es lo que tardó en ejecutarlo una vez generado. Ninguna de las dos debe confundirse con los valores de `cost=...` que aparecen dentro de cada nodo, que son estimaciones internas del planner en unidades propias, no milisegundos.

Un detalle que se puede observar directamente en el plan, sin necesidad de suponer nada: el costo de arranque del Bitmap Heap Scan (`4.50`) coincide exactamente con el costo total de su nodo hijo, el Bitmap Index Scan (`0.00..4.50`) — así es como el modelo de costos de Postgres encadena el costo de un nodo dependiente dentro del costo de su padre.

---

## 3. Tabla de lectura crítica

| # | Afirmación de la IA | ¿Correcta? | Corrección / evidencia del plan real |
|---|----------------------|------------|----------------------------------------|
| 1 | "cost y actual time son magnitudes distintas" | Sí | `cost` son unidades estimadas del planner; `actual time` está medido en ms. |
| 2 | "El Index Scan sobre producto usa Index Cond para resolver nombre" | Sí | `Index Cond: ((nombre)::text = 'Producto TP3 25000'::text)`. |
| 3 | "El InitPlan se ejecuta una vez" | Sí | `loops=1` y el resultado aparece como `(InitPlan 1).col1`. |
| 4 | "width=8 representa una fila de 8 bytes de ancho" | Imprecisa | `width` representa un ancho promedio **estimado** por el planner, no el tamaño exacto de cada fila real. |
| 5 | "Bitmap Index Scan construye un bitmap de coincidencias" | Sí | Comportamiento estándar del nodo, consistente con lo mostrado en el plan. |
| 6 | "width=0 en Bitmap Index Scan se debe a que no proyecta columnas normales" | Sí | El nodo solo marca posiciones (TIDs), no transporta datos de columnas. |
| 7 | "Heap Blocks: exact=1 indica un único bloque exacto del heap" | Sí | Coincide literalmente con `Heap Blocks: exact=1` en el plan. |
| 8 | "Recheck Cond es normal en Bitmap Heap Scan" | Sí | Es un paso estándar de este tipo de nodo, no una particularidad de esta consulta. |
| 9 | "Obtener 12 filas es coherente con una búsqueda de alta selectividad" | Imprecisa | El plan aislado no muestra el total de filas de `detalle_pedido`, por lo que no se puede cuantificar selectividad únicamente con ese dato. |
| 10 | "El Sort usa quicksort sobre 12 filas y 25 kB" | Sí | `Sort Method: quicksort  Memory: 25kB`, `rows=12`. |
| 11 | "No aparece top-N heapsort porque no se observa LIMIT" | Sí | El plan no muestra ningún nodo `Limit` ni referencia a `LIMIT`. |
| 12 | "El Sort existe porque el índice está organizado según otra columna" | No / Imprecisa | **Corrección importante**: el plan proporcionado a la IA NO muestra la definición interna del índice, por lo que no puede afirmar cómo está ordenado. La causa observable en ESTE plan es que PostgreSQL eligió la cadena `Bitmap Index Scan -> Bitmap Heap Scan -> Sort`. El acceso bitmap no preserva el orden lógico del B-tree para la salida; por eso PostgreSQL realiza un Sort explícito. |
| 13 | "Planning Time y Execution Time son tiempos reales y distintos de cost" | Sí | Ambos están expresados en ms y son conceptualmente distintos de los valores `cost=...` de cada nodo. |
| 14 | "El startup cost 4.50 del Bitmap Heap Scan coincide con el costo total del hijo porque necesita construir el bitmap primero" | Básicamente correcta con matiz | Correcto para este caso puntual. No debe convertirse en regla universal de que el costo padre siempre hereda exactamente el costo total del hijo — es una observación válida sobre este plan, no una ley general del modelo de costos. |

---

## 4. Hallazgo principal

Antes de medir con `EXPLAIN ANALYZE` real, la expectativa previa era que el índice

```sql
idx_detalle_pedido_producto_pedido (producto_id, pedido_id DESC)
```

eliminara el nodo `Sort`, dado que el orden `pedido_id DESC` coincide con el orden lógico del índice.

Sin embargo, el plan real mostró que PostgreSQL eligió la siguiente cadena:

```
Bitmap Index Scan
  -> Bitmap Heap Scan
  -> Sort
```

El índice **sí mejoró enormemente la localización de las filas** (de un Parallel Seq Scan sobre ~500.000 filas a un acceso puntual que toca un solo bloque del heap). Pero PostgreSQL decidió resolver el acceso mediante un **bitmap**, y el bitmap **no entrega las filas en un orden utilizable directamente** para `ORDER BY pedido_id DESC` — el bitmap se construye para localizar posiciones eficientemente, no para preservar el orden del índice en la salida.

Por eso el nodo `Sort` permaneció en el plan final, a pesar de que el índice se usó exactamente como se había previsto para el filtro.

**Esto demuestra por qué una propuesta de IA debe verificarse siempre con `EXPLAIN ANALYZE` real**: la expectativa sobre qué nodos "deberían" desaparecer es una hipótesis basada en el mecanismo general del planner, no una garantía — la decisión final de qué estrategia de acceso usar (Index Scan directo, Bitmap Scan, Seq Scan, con o sin paralelismo) la toma el planner en tiempo de planificación según sus propias estimaciones de costo, y solo se confirma midiendo.

---

## 5. Conclusión

- La mayor parte de la explicación generada por IA fue **correcta** y estuvo bien anclada en la evidencia literal del plan (nodos, condiciones, métricas).
- Se detectaron **imprecisiones reales**, puntualmente en la interpretación de `width` como tamaño exacto de fila (punto 4), en la afirmación sobre selectividad sin contar con el total de la tabla (punto 9), y sobre todo en la explicación de la causa del `Sort` remanente (punto 12), donde se atribuyó el resultado a la organización interna del índice sin tener evidencia de esa organización en el plan analizado.
- **El plan real prevalece sobre cualquier expectativa previa de la IA**: la hipótesis de que el índice eliminaría el Sort era razonable como expectativa, pero el plan real mostró una estrategia distinta (bitmap), y esa es la única fuente válida de verdad.
- La decisión técnica sobre si una optimización "funcionó" debe apoyarse siempre en mediciones y evidencia concreta del `EXPLAIN ANALYZE`, no en el razonamiento anticipado sobre cómo debería comportarse el planner.
- **No se consideró incorrecta la optimización solo porque el Sort permaneció**: el tiempo real final (`Execution Time: 0.093 ms`) fue extremadamente bajo, y el índice cumplió su función principal — evitar el escaneo completo de `detalle_pedido` — incluso si no eliminó el nodo Sort. Persistencia de un nodo no implica automáticamente fracaso de la optimización.
