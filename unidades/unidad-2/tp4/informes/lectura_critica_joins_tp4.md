# Lectura crítica de planes de JOIN interpretados por IA — TP4 Parte 2

Base de Datos II — Semana 4, Unidad 2: Optimización de Consultas

---

## 1. Plan real analizado

```
Limit  (cost=68606.55..68606.80 rows=100 width=97)
(actual time=507.592..507.602 rows=100 loops=1)

  -> Sort
     (cost=68606.55..68656.56 rows=20003 width=97)
     (actual time=507.590..507.597 rows=100 loops=1)

       Sort Key:
         sum(sum(detalle_pedido.cantidad * detalle_pedido.precio_unitario)) DESC,
         c.nombre

       Sort Method: top-N heapsort
       Memory: 46kB

       -> HashAggregate
          (cost=67542.01..67842.05 rows=20003 width=97)
          (actual time=475.246..504.473 rows=20003 loops=1)

            Group Key: c.id
            Batches: 5
            Memory Usage: 8369kB
            Disk Usage: 7504kB

            -> Hash Join
               (cost=717.91..65598.52 rows=194349 width=65)
               (actual time=3.417..417.018 rows=200005 loops=1)

                 Hash Cond:
                   pe.cliente_id = c.id

                 -> Merge Join
                    (cost=0.84..64371.17 rows=194349 width=48)
                    (actual time=0.029..363.797 rows=200005 loops=1)

                      Merge Cond:
                        detalle_pedido.pedido_id = pe.id

                      -> GroupAggregate
                         (cost=0.42..50631.81 rows=194349 width=48)
                         (actual time=0.018..313.275 rows=200005 loops=1)

                           Group Key:
                             detalle_pedido.pedido_id

                           -> Index Scan using pk_detalle_pedido
                              on detalle_pedido
                              (cost=0.42..41952.36 rows=500007 width=17)
                              (actual time=0.008..163.054 rows=500007 loops=1)

                      -> Index Scan using pedido_pkey on pedido pe
                         (cost=0.42..8866.49 rows=200005 width=16)
                         (actual time=0.008..19.746 rows=200005 loops=1)

                 -> Hash
                    (cost=467.03..467.03 rows=20003 width=25)
                    (actual time=3.337..3.338 rows=20003 loops=1)

                      Buckets: 32768
                      Batches: 1
                      Memory Usage: 1379kB

                      -> Seq Scan on cliente c
                         (cost=0.00..467.03 rows=20003 width=25)
                         (actual time=0.012..1.594 rows=20003 loops=1)

Planning Time: 0.307 ms
Execution Time: 509.388 ms
```

---

## 2. Explicación generada por IA

> Reproducida literalmente, sin corregir. Cualquier imprecisión se analiza
> recién en la Sección 3.

---

### Lectura nodo por nodo del plan

Voy a explicar los nodos en el orden real de ejecución (de adentro hacia afuera), señalando explícitamente cuándo una afirmación es una inferencia y no evidencia literal del texto del plan. Recuerdo la regla de base: los valores `cost=...` son unidades estimadas del planner, no milisegundos; los valores `actual time` no representan tiempo exclusivo de cada nodo (incluyen el trabajo de sus hijos), así que no voy a restar tiempos entre padre e hijo para atribuir un tiempo aislado a ningún nodo.

---

#### 1. Index Scan using pk_detalle_pedido on detalle_pedido

```
cost=0.42..41952.36 rows=500007 width=17
actual time=0.008..163.054 rows=500007 loops=1
```

**Qué hace**: recorre la tabla `detalle_pedido` a través de su índice de clave primaria (`pk_detalle_pedido`). El plan no muestra ninguna línea `Filter` ni `Index Cond` para este nodo — no hay ninguna condición de búsqueda visible.

**Métricas**: filas estimadas y reales coinciden exactamente (`rows=500007` en ambos casos), lo cual es consistente con que no se está aplicando ningún filtro que reduzca el conjunto. Tiempo real: `0.008` ms hasta la primera fila, `163.054` ms hasta completar, una sola ejecución (`loops=1`).

**Relación con el nodo siguiente**: alimenta al `GroupAggregate` que aparece justo arriba.

**Inferencia**: como no aparece ningún nodo `Sort` entre este Index Scan y el `GroupAggregate`/`Merge Join` posteriores, es razonable inferir que el uso del índice acá no es por selectividad (no hay predicado que filtrar), sino para aprovechar el **orden** que ese índice ya garantiza sobre `pedido_id` — orden que resulta necesario más arriba en el árbol. Esta lectura se apoya en la ausencia de un `Sort` explícito, pero la intención de "usar el índice por su orden" no está declarada literalmente en el plan.

---

#### 2. GroupAggregate (sobre detalle_pedido)

```
cost=0.42..50631.81 rows=194349 width=48
actual time=0.018..313.275 rows=200005 loops=1
Group Key: detalle_pedido.pedido_id
```

**Qué hace**: agrupa las filas de `detalle_pedido` por `pedido_id`, calculando algún agregado por grupo. El plan no lista explícitamente qué expresión de agregación calcula este nodo en particular.

**Métricas**: rows estimadas `194349` vs. rows reales `200005` — una diferencia moderada entre estimación y realidad. Ancho de fila `width=48`.

**Relación con el nodo siguiente**: alimenta al `Merge Join` como su entrada izquierda (ver más abajo).

**Inferencia**: en el `Sort Key` del nodo `Sort` que aparece en la parte superior del plan se lee literalmente `sum(sum(detalle_pedido.cantidad * detalle_pedido.precio_unitario))` — una expresión de **suma anidada dentro de otra suma**. Esa es evidencia textual directa de que en algún punto del plan se calculó un `SUM(cantidad * precio_unitario)` que después vuelve a sumarse. Es razonable inferir (aunque el plan no lo etiqueta explícitamente en este nodo) que ese `SUM` interno se calcula acá, agrupado por `pedido_id` — pero la atribución exacta de esa expresión a este nodo en particular es una inferencia, no una declaración literal del plan.

---

#### 3. Index Scan using pedido_pkey on pedido pe

```
cost=0.42..8866.49 rows=200005 width=16
actual time=0.008..19.746 rows=200005 loops=1
```

**Qué hace**: recorre la tabla `pedido` a través de su índice de clave primaria. Tampoco aparece ninguna línea `Filter` ni `Index Cond`.

**Métricas**: filas estimadas y reales coinciden (`rows=200005`), consistente con ausencia de filtro. Tiempo real: `0.008..19.746` ms.

**Relación con el nodo siguiente**: es la entrada derecha del `Merge Join`.

**Inferencia**: al igual que con `detalle_pedido`, la ausencia de un `Sort` intermedio sugiere que este índice se usa por el orden que produce sobre `id`, no por selectividad.

---

#### 4. Merge Join

```
cost=0.84..64371.17 rows=194349 width=48
actual time=0.029..363.797 rows=200005 loops=1
Merge Cond: detalle_pedido.pedido_id = pe.id
```

**Algoritmo**: `Merge Join`.

**Entrada izquierda**: el `GroupAggregate` sobre `detalle_pedido` (nodo listado primero, antes del `Index Scan` sobre `pedido`).

**Entrada derecha**: el `Index Scan using pedido_pkey on pedido pe`.

**Quién aporta la clave de comparación**: ambos lados aportan una clave — el lado izquierdo aporta `detalle_pedido.pedido_id` (ya agrupado por esa misma columna en el nodo anterior), y el lado derecho aporta `pe.id` (recorrido en orden por el índice de clave primaria). Un `Merge Join` requiere que ambas entradas lleguen ordenadas por la clave de unión; acá ninguna de las dos necesitó un `Sort` explícito, lo cual es evidencia de que ambas ya llegaban ordenadas por esa clave desde sus respectivos nodos de origen.

**Métricas**: filas estimadas `194349` vs. reales `200005`.

**Relación con el nodo siguiente**: su salida es la entrada izquierda del `Hash Join` que aparece arriba.

---

#### 5. Seq Scan on cliente c

```
cost=0.00..467.03 rows=20003 width=25
actual time=0.012..1.594 rows=20003 loops=1
```

**Qué hace**: recorre secuencialmente la tabla `cliente` completa. No hay `Filter`.

**Relación con el nodo siguiente**: alimenta al nodo `Hash` inmediatamente superior.

---

#### 6. Hash (sobre cliente)

```
cost=467.03..467.03 rows=20003 width=25
actual time=3.337..3.338 rows=20003 loops=1
Buckets: 32768
Batches: 1
Memory Usage: 1379kB
```

**Qué hace**: construye la estructura hash en memoria a partir de las filas de `cliente` obtenidas por el Seq Scan anterior, para que el `Hash Join` de arriba pueda probar contra ella. `Batches: 1` indica que esta estructura entró completa en la memoria disponible, sin necesidad de particionar.

**Relación con el nodo siguiente**: es la entrada derecha (la hasheada) del `Hash Join`.

---

#### 7. Hash Join

```
cost=717.91..65598.52 rows=194349 width=65
actual time=3.417..417.018 rows=200005 loops=1
Hash Cond: pe.cliente_id = c.id
```

**Algoritmo**: `Hash Join`.

**Entrada izquierda**: el resultado del `Merge Join` (detalle_pedido agregado + pedido).

**Entrada derecha**: el nodo `Hash` construido sobre `cliente`.

**Quién aporta la clave de comparación**: el lado izquierdo aporta `pe.cliente_id` (que llega a través del `Merge Join`, originado en `pedido`); el lado derecho aporta `c.id`, ya indexado en la estructura hash construida sobre `cliente`.

**Métricas**: filas estimadas `194349` vs. reales `200005`.

**Relación con el nodo siguiente**: alimenta al `HashAggregate` de arriba.

---

#### 8. HashAggregate

```
cost=67542.01..67842.05 rows=20003 width=97
actual time=475.246..504.473 rows=20003 loops=1
Group Key: c.id
Batches: 5
Memory Usage: 8369kB
Disk Usage: 7504kB
```

**Qué hace**: agrupa las 200.005 filas resultantes del `Hash Join` por `c.id`, calculando algún agregado por cliente.

**Métricas**: `Batches: 5` junto con `Disk Usage: 7504kB` indica que la estructura de agregación (la tabla hash de grupos) no entró completa en la memoria de trabajo disponible (`Memory Usage: 8369kB`) y tuvo que particionarse en 5 lotes, con parte del trabajo apoyado en disco — un mecanismo análogo, en espíritu, al de `Batches` en un `Hash Join`, pero aplicado acá a la agregación.

**Relación con el nodo siguiente**: alimenta al `Sort` de arriba.

**Inferencia**: por la misma evidencia textual señalada en el nodo 2 (`sum(sum(...))` en el `Sort Key` superior), es razonable inferir que este `HashAggregate` calcula un `SUM(...)` que envuelve al `SUM` ya calculado más abajo por `pedido_id` — es decir, una segunda suma, ahora agrupada por cliente. Nuevamente, la atribución exacta a este nodo puntual es una inferencia basada en la posición en el árbol y en el texto del `Sort Key`, no una declaración explícita del propio nodo.

---

#### 9. Sort

```
cost=68606.55..68656.56 rows=20003 width=97
actual time=507.590..507.597 rows=100 loops=1
Sort Key: sum(sum(detalle_pedido.cantidad * detalle_pedido.precio_unitario)) DESC, c.nombre
Sort Method: top-N heapsort
Memory: 46kB
```

**Qué hace**: ordena las 20.003 filas agrupadas por la expresión de doble suma en forma descendente, y como criterio secundario por `c.nombre`.

**Métricas**: `Sort Method: top-N heapsort` con solo `46kB` de memoria — un heap acotado, no un ordenamiento completo de las 20.003 filas. La cantidad real de filas que produce este nodo es `rows=100`, muy por debajo de las `rows=20003` estimadas como entrada.

**Relación con el nodo siguiente**: alimenta al `Limit` de arriba.

**Inferencia**: el uso de `top-N heapsort` junto con la memoria mínima (`46kB`) y el hecho de que el nodo solo produce 100 filas de salida son indicios consistentes con que existe un `LIMIT` en algún nivel superior que acota cuántas filas hace falta retener ordenadas — el propio nodo `Limit` que aparece inmediatamente arriba lo confirma estructuralmente.

---

#### 10. Limit (nodo raíz)

```
cost=68606.55..68606.80 rows=100 width=97
actual time=507.592..507.602 rows=100 loops=1
```

**Qué hace**: es el nodo raíz del plan — corta el flujo ya ordenado a las primeras 100 filas. Esta es la salida final que representa este plan.

---

#### Números finales del plan

```
Planning Time: 0.307 ms
Execution Time: 509.388 ms
```

Ambos valores son tiempo real medido en milisegundos, y son magnitudes distintas entre sí y distintas de cualquier valor `cost=...` que aparece dentro de los nodos — esos últimos son estimaciones del planner en unidades propias, no tiempo.

---

#### Resumen de inferencias marcadas explícitamente

1. Que ambos Index Scan (`pk_detalle_pedido`, `pedido_pkey`) se usan por su propiedad de orden y no por selectividad — inferido de la ausencia de `Filter`/`Index Cond` y de la ausencia de un `Sort` intermedio antes del `Merge Join`.
2. Que la expresión `sum(sum(...))` del `Sort Key` superior corresponde a un `SUM` calculado en el `GroupAggregate` (nodo 2) que luego se vuelve a sumar en el `HashAggregate` (nodo 8) — inferido de la posición de cada nodo en el árbol y del texto literal de esa expresión anidada, no declarado explícitamente en ninguno de esos dos nodos por separado.

No se supuso ninguna consulta SQL original, ni se propuso ninguna optimización — este es exclusivamente un análisis descriptivo del plan tal como fue provisto.

---

## 3. Tabla de lectura crítica

| # | Afirmación de la IA | ¿Correcta? | Corrección / evidencia del plan real |
|---|----------------------|------------|----------------------------------------|
| 1 | "El plan contiene un Merge Join y un Hash Join" | Sí | Ambos nodos aparecen literalmente en el plan: `Merge Join` (`Merge Cond: detalle_pedido.pedido_id = pe.id`) y `Hash Join` (`Hash Cond: pe.cliente_id = c.id`). |
| 2 | "La entrada izquierda del Merge Join es el GroupAggregate de detalle_pedido" | Sí | El `GroupAggregate` sobre `detalle_pedido` aparece como primer hijo del `Merge Join`, antes del `Index Scan` sobre `pedido`. |
| 3 | "La entrada derecha del Merge Join es el Index Scan sobre pedido" | Sí | `Index Scan using pedido_pkey on pedido pe` aparece como segundo hijo del `Merge Join`. |
| 4 | "Merge Cond: detalle_pedido.pedido_id = pe.id" | Sí | Coincide literalmente con la línea del plan. |
| 5 | "Ambos lados llegan ordenados y por eso no aparece Sort" | Correcta como inferencia | El plan lo sugiere fuertemente (no hay ningún `Sort` entre los Index Scan y el `Merge Join`), pero no declara literalmente que los índices fueron elegidos por esa razón — es una lectura razonada a partir de la ausencia de un nodo, no una afirmación explícita del plan. |
| 6 | "La entrada izquierda del Hash Join es el resultado del Merge Join" | Sí | El `Merge Join` aparece como primer hijo (no bajo la rama `-> Hash`) del `Hash Join`. |
| 7 | "La entrada derecha del Hash Join es el Hash construido sobre cliente" | Sí | El nodo `Hash` (que a su vez envuelve el `Seq Scan on cliente c`) aparece como segundo hijo del `Hash Join`. |
| 8 | "c.id queda indexado en la estructura hash" | Imprecisa | **Corrección**: `c.id` es la clave utilizada en una **tabla hash temporal** construida en memoria (o parcialmente en disco) para la duración de esta única ejecución del `Hash Join`; no se crea ningún índice persistente sobre `cliente`. El término "indexado" sugiere erróneamente una estructura durable, cuando en realidad es una estructura efímera del propio nodo. |
| 9 | "Batches: 1 significa que el hash no necesitó dividirse en varios lotes" | Sí | Coincide con el significado estándar de esa métrica: la tabla hash construida sobre `cliente` entró completa en la memoria disponible. |
| 10 | "HashAggregate Batches: 5 y Disk Usage: 7504kB implica trabajo en disco" | Sí | La combinación de `Batches: 5` con `Disk Usage: 7504kB` (mayor que cero) es evidencia directa de que parte del trabajo de agregación se apoyó en disco, al no entrar completo en `Memory Usage: 8369kB`. |
| 11 | "top-N heapsort mantiene las mejores filas para el LIMIT 100" | Sí | Consistente con el comportamiento estándar de ese método de ordenamiento cuando existe un `Limit` aguas arriba, y con que el nodo `Sort` produce exactamente `rows=100`. |
| 12 | "cost no son milisegundos" | Sí | Los valores `cost=...` son estimaciones del planner en unidades propias, no milisegundos. `Planning Time`, `Execution Time` y `actual time` están expresados en milisegundos medidos durante la ejecución; `actual time` no representa tiempo exclusivo del nodo y, cuando `loops > 1`, debe interpretarse teniendo en cuenta el promedio por ejecución. |
| 13 | "actual time no es tiempo exclusivo del nodo" | Sí | Los valores `actual time` de un nodo incluyen el trabajo de sus nodos hijos; no deben restarse entre padre e hijo para aislar un tiempo exclusivo. |
| 14 | "El orden real de ejecución es simplemente de adentro hacia afuera" | Imprecisa | **Corrección**: leer el árbol de abajo hacia arriba ayuda a comprender las dependencias lógicas entre nodos, pero PostgreSQL ejecuta un árbol de productores/consumidores donde algunos nodos son bloqueantes (por ejemplo, `Sort` y `HashAggregate` deben consumir toda su entrada antes de producir salida) y otros pueden trabajar en pipeline (como el `Merge Join`, que puede ir consumiendo filas de ambos lados a medida que llegan). "De adentro hacia afuera" es una simplificación útil para explicar, pero no describe con precisión el modelo de ejecución real. |
| 15 | Atribución del `SUM` interno al `GroupAggregate` y del `SUM` externo al `HashAggregate` | Inferencia razonable, no evidencia literal del nodo | Se conserva explícitamente esa clasificación: la evidencia textual (`sum(sum(...))` en el `Sort Key` superior) confirma que existe una suma anidada en algún punto del plan, pero la atribución de cada `SUM` a un nodo específico es una lectura basada en la posición en el árbol, no una declaración explícita dentro de esos nodos. |

---

## 4. Hallazgo principal

La IA identificó correctamente los algoritmos de ambos JOIN (`Merge Join` y `Hash Join`) y sus respectivas entradas izquierda y derecha, apoyándose en evidencia literal del plan en la mayoría de los casos. Sin embargo, utilizó una terminología imprecisa al describir `c.id` como "indexado" dentro de la estructura hash — ese término sugiere una estructura persistente, cuando en realidad se trata de una tabla hash temporal, construida y descartada dentro de la misma ejecución del `Hash Join`. Además, simplificó en exceso el orden real de ejecución del plan al describirlo como "de adentro hacia afuera", sin distinguir entre nodos bloqueantes (que deben consumir toda su entrada antes de producir cualquier salida) y nodos que pueden operar en pipeline.

---

## 5. Conclusión

El análisis generado por la IA fue, en su mayor parte, correcto y estuvo bien anclado en la evidencia literal del plan — especialmente en la identificación de algoritmos, entradas de los JOIN y la distinción entre `cost` y tiempo real. Aun así, el plan real prevalece sobre cualquier simplificación conveniente para la explicación: las inferencias razonables (como la ausencia de `Sort` sugiriendo entradas ya ordenadas, o la atribución de cada `SUM` a un nodo puntual) deben distinguirse explícitamente de las afirmaciones literales del texto del plan, y la terminología técnica (como "indexado") debe usarse con precisión para no sugerir estructuras persistentes donde solo existen estructuras temporales de una sola ejecución.
