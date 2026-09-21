# TP5: evidencia ejecutada sobre el modelo oficial

## Resultado y alcance

Validación real completada en PostgreSQL 17.11 sobre la base local descartable `foodstore_tp5_oficial`. Los tres índices candidatos redujeron el tiempo de sus consultas en esta muestra y aumentaron el tiempo de inserción de 1.000 filas en sus respectivas tablas. Las cuatro vistas y la materializada dieron diferencias bidireccionales iguales a cero; las restricciones de acceso se comprobaron con un rol temporal y el refresh concurrente finalizó correctamente.

Este documento registra únicamente resultados nuevos. No reemplaza ni reescribe `informe_mediciones.md`, la DUIA histórica, los README ni el esquema canónico. El bootstrap temporal implementa el contrato oficial autorizado para este laboratorio; **no es un `schema.sql` entregable ni una migración del repositorio**. No se reutilizaron tiempos históricos.

## 1. Entorno y procedencia

| Dato | Valor |
| --- | --- |
| Servidor | PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| server_version_num | 170011 |
| Base de trabajo | foodstore_tp5_oficial |
| Conexión | 127.0.0.1:5432, usuario postgres; autenticación local mediante pgpass/PGPASSFILE, sin credenciales en la evidencia |
| Base consultada durante el preflight | postgres |
| Fecha SQL CURRENT_DATE | 2026-09-20 |
| Zona horaria | America/Buenos_Aires |
| Timestamp real de preflight | 2026-09-20T21:01:19.853259-03:00 |
| Inicio UTC | 2026-09-21T00:01:19.625Z |
| Fin UTC | 2026-09-21T00:03:25.950Z |
| Intervalo local | 2026-09-20, aproximadamente 21:01 a 21:03 (-03:00) |
| work_mem | 4MB |
| shared_buffers | 128MB |
| jit | on |
| max_parallel_workers_per_gather | 2 |
| random_page_cost | 4 |

Cliente y servidor fueron verificados como 17.11. La autenticación previa por `localhost` falló antes de ejecutar SQL; se resolvió utilizando el endpoint local IPv4 autorizado. No se modificaron contraseñas ni configuraciones de autenticación.

Los comandos de aplicación usaron `psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_tp5_oficial -v ON_ERROR_STOP=1`. El bootstrap se aplicó además con `-1`; la carga contiene su propia transacción y un `VACUUM ANALYZE` posterior. Las dos pruebas negativas esperadas de permisos usaron `ON_ERROR_STOP=0` para registrar el SQLSTATE y ejecutar `RESET ROLE`.

La única base eliminada/recreada fue `foodstore_tp5_oficial`. El directorio temporal de ejecución y sus logs son:

```text
C:/Users/facu/AppData/Local/Temp/foodstore_tp5_oficial_run_keO2dm
```

| Fuente | SHA-256 |
| --- | --- |
| foodstore_tp5_oficial_schema.sql | acdedd0518002a1e0ba46856293e75e60620c48606a205ad682cb47fa1a8bcdf |
| foodstore_tp5_oficial_data.sql | 491830ae6cb48828c0324ce8e640da6940e584c988c0267b8fa1ecfdbf850e13 |
| results.json | 77dfcfe8c520fc43b3f27140423f4b154bbf42d8576c7adc09a69cc30e5596c3 |

Las tablas siguientes y los anexos preservan consultas, valores y planes dentro del repositorio, sin depender exclusivamente de la permanencia de esos temporales. Los anexos de bootstrap/carga permiten identificar los supuestos exactos usados.

## 2. Dataset sintético e inventario previo

La carga determinista utiliza `generate_series`. Son datos ficticios, no una muestra de producción ni el dataset oficial entregable. Los textos usan VARCHAR/TEXT, `created_at` usa TIMESTAMPTZ y los atributos esenciales son NOT NULL; descripción, imagen y celular admiten NULL. Estas elecciones de tipo/longitud/nullability no especificadas por la consigna son supuestos del laboratorio, no nuevas exigencias del modelo oficial.

| Tabla | Filas reales | Eliminadas |
| --- | --- | --- |
| categoria | 8 | 1 |
| producto | 50000 | 515 |
| usuario | 20000 | 198 |
| pedido | 200000 | 1941 |
| detalle_pedido | 500000 | 4673 |

| Control real | Resultado |
| --- | --- |
| Productos no disponibles | 2500 (5 %; independencia semántica respecto de eliminado) |
| Fecha mínima / máxima | 2024-10-01 / 2026-09-20 |
| Ventana de pedidos recientes | CURRENT_DATE - 30 = 2026-08-21; límite inclusivo |
| Detalles por pedido, mínimo / máximo | 1 / 4 |
| Pares pedido/producto duplicados | 0 |
| Totales no reconciliados | 0 |
| Subtotales distintos de cantidad × precio_unitario | 0 |
| Usuarios vigentes coincidentes con usuario8452@foodstore.test | 1 |

Una categoría eliminada entre ocho equivale al 12,5 %, mínimo no cero con ese volumen. Las otras bajas se generan con módulos primos 97/101/103/107. Los precios y stock 0..200 son deterministas; disponibilidad es verdadera para el 95 %. Los 200.000 pedidos abarcan 720 fechas y alternan exclusivamente los ENUM autorizados. Cada bloque de cuatro pedidos tiene 1, 2, 3 y 4 productos distintos, totalizando 500.000 detalles. Se cargó `hash_de_prueba` como contraseña ficticia y el rol de usuario por defecto fue USUARIO.

La igualdad de subtotal con la multiplicación se verificó como propiedad de esta carga: **las consultas corregidas utilizan la columna física `subtotal`**, no derivan de ella una restricción adicional para datos futuros.

### índices presentes antes de los candidatos

El inventario inicial completo de `public` fue el siguiente. Incluye índices de PK/UNIQUE además de los tres declarados preexistentes por la cátedra.

```sql
CREATE UNIQUE INDEX categoria_nombre_key ON public.categoria USING btree (nombre);
CREATE UNIQUE INDEX categoria_pkey ON public.categoria USING btree (id);
CREATE UNIQUE INDEX detalle_pedido_pedido_id_producto_id_key ON public.detalle_pedido USING btree (pedido_id, producto_id);
CREATE UNIQUE INDEX detalle_pedido_pkey ON public.detalle_pedido USING btree (id);
CREATE INDEX idx_pedido_usuario ON public.pedido USING btree (usuario_id);
CREATE UNIQUE INDEX pedido_pkey ON public.pedido USING btree (id);
CREATE INDEX idx_producto_categoria ON public.producto USING btree (categoria_id);
CREATE INDEX idx_producto_nombre_vig ON public.producto USING btree (nombre) WHERE (eliminado = false);
CREATE UNIQUE INDEX producto_pkey ON public.producto USING btree (id);
CREATE UNIQUE INDEX usuario_mail_key ON public.usuario USING btree (mail);
CREATE UNIQUE INDEX usuario_pkey ON public.usuario USING btree (id);
```

La consulta de existencia de `idx_producto_stock_bajo`, `idx_pedido_fecha_reciente` e `idx_usuario_mail_lower` devolvió `[]` antes de las lecturas. No se eliminaron índices base en ninguna fase.

## 3. Protocolo de medición

- Se ejecutó `ANALYZE` sobre la tabla correspondiente antes y después de crear cada candidato de lectura.
- Cada caso tuvo tres ejecuciones: corrida 1 de calentamiento, corridas 2 y 3 válidas; media = (tiempo 2 + tiempo 3) / 2.
- Se capturó `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`: los tiempos reportados son `Execution Time` en milisegundos, no el tiempo externo de iniciar psql. Cada ejecución utilizó una conexión de psql.
- Se conservaron valores sin redondear para calcular medias; las tablas muestran hasta cuatro decimales. No se desactivaron métodos de acceso ni paralelismo.
- Para escrituras, cada corrida incluyó `BEGIN; EXPLAIN ... INSERT ...; ROLLBACK;` y fue precedida por `VACUUM ANALYZE` de la tabla fuera de la transacción. El VACUUM no integra el tiempo del INSERT.
- Buffers de resumen corresponden a la raíz del plan: no se suman recursivamente, porque los nodos contienen acumulados. Los valores completos, workers y estimaciones se conservan en los anexos JSON.
- En planes paralelos, filas y filas descartadas pueden ser promedios por loop; se preservan `Actual Loops` y workers. La ausencia de `Heap Fetches` no equivale a afirmar cero.

**Límite:** dos corridas válidas constituyen la muestra solicitada, no una estimación estadística robusta. El orden BEFORE/AFTER, cachés, actividad del sistema y páginas residuales de rollback pueden influir. Los cocientes observados no garantizan mejoras universales ni miden concurrencia de producción.

## 4. Consultas e índices: resultados reales

### A. Stock bajo

```sql
SELECT
    id,
    nombre,
    stock,
    precio
FROM producto
WHERE eliminado = FALSE
  AND stock <= 5
ORDER BY stock ASC, nombre ASC;
```

```sql
CREATE INDEX idx_producto_stock_bajo
    ON producto (stock ASC, nombre ASC)
    INCLUDE (id, precio)
    WHERE eliminado = FALSE;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 9.299 | 9.338 | 9.54 | 9.439 |
| AFTER | 0.423 | 0.332 | 0.263 | 0.2975 |

Cociente observado BEFORE/AFTER: **31.7277x**; reducción de tiempo: **96.8482 %**.

| Caso / corrida | Plan real | Filas raiz | Rows Removed by Filter | Buffers raiz | Sort | Heap Fetches |
| --- | --- | --- | --- | --- | --- | --- |
| BEFORE / 2 | Sort -> [Seq Scan] | 1477 | Seq Scan: 48523 (loops=1) | shared hit=869, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 129 kB Memory | No informado |
| BEFORE / 3 | Sort -> [Seq Scan] | 1477 | Seq Scan: 48523 (loops=1) | shared hit=869, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 129 kB Memory | No informado |
| AFTER / 2 | Index Only Scan (idx_producto_stock_bajo) | 1477 | No informado | shared hit=14, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | 0 |
| AFTER / 3 | Index Only Scan (idx_producto_stock_bajo) | 1477 | No informado | shared hit=14, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | 0 |

El plan pasó de lectura secuencial con ordenamiento a `Index Only Scan` sobre el candidato. Se conservaron 1477 filas y se evitó el Sort. La consulta no filtra `disponible`, porque un producto no disponible puede necesitar reposición.

### B. Pedidos recientes

```sql
SELECT
    id,
    usuario_id,
    fecha,
    estado,
    forma_pago,
    total
FROM pedido
WHERE eliminado = FALSE
  AND fecha >= CURRENT_DATE - 30
ORDER BY fecha DESC;
```

```sql
CREATE INDEX idx_pedido_fecha_reciente
    ON pedido (fecha DESC)
    INCLUDE (id, usuario_id, estado, forma_pago, total)
    WHERE eliminado = FALSE;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 161.744 | 266.516 | 262.227 | 264.3715 |
| AFTER | 1.967 | 1.27 | 1.18 | 1.225 |

Cociente observado BEFORE/AFTER: **215.8135x**; reducción de tiempo: **99.5366 %**.

| Caso / corrida | Plan real | Filas raiz | Rows Removed by Filter | Buffers raiz | Sort | Heap Fetches |
| --- | --- | --- | --- | --- | --- | --- |
| BEFORE / 2 | Gather Merge -> [Sort -> [Seq Scan [parallel]]] | 8525 | Seq Scan: 63825 (loops=3) | shared hit=4001, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 851 kB Memory | No informado |
| BEFORE / 3 | Gather Merge -> [Sort -> [Seq Scan [parallel]]] | 8525 | Seq Scan: 63825 (loops=3) | shared hit=4001, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 851 kB Memory | No informado |
| AFTER / 2 | Index Only Scan (idx_pedido_fecha_reciente) | 8525 | No informado | shared hit=72, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | 0 |
| AFTER / 3 | Index Only Scan (idx_pedido_fecha_reciente) | 8525 | No informado | shared hit=72, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | 0 |

La variante ejecutada usa `CURRENT_DATE - 30` por autorización expresa de este bloque, en lugar del literal `DATE '2026-04-11'` que sigue en `queries.sql`. El plan BEFORE fue `Gather Merge` con dos workers; AFTER usó `Index Only Scan`, sin Sort. El tiempo elevado del plan paralelo es una observación de esta ejecución: no se atribuye causalmente al arranque de workers sin una comparación controlada adicional. El resultado favorece este candidato para esta consulta, pero no demuestra que INCLUDE sea óptimo para toda carga.

### C. Usuario por mail

```sql
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE
  AND lower(mail) = lower('usuario8452@foodstore.test');
```

```sql
CREATE INDEX idx_usuario_mail_lower
    ON usuario (lower(mail))
    WHERE eliminado = FALSE;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 10.43 | 11.006 | 10.767 | 10.8865 |
| AFTER | 0.135 | 0.159 | 0.113 | 0.136 |

Cociente observado BEFORE/AFTER: **80.0478x**; reducción de tiempo: **98.7507 %**.

| Caso / corrida | Plan real | Filas raiz | Rows Removed by Filter | Buffers raiz | Sort | Heap Fetches |
| --- | --- | --- | --- | --- | --- | --- |
| BEFORE / 2 | Seq Scan | 1 | Seq Scan: 19999 (loops=1) | shared hit=344, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | No informado |
| BEFORE / 3 | Seq Scan | 1 | Seq Scan: 19999 (loops=1) | shared hit=344, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | No informado |
| AFTER / 2 | Bitmap Heap Scan -> [Bitmap Index Scan (idx_usuario_mail_lower)] | 1 | No informado | shared hit=3, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | No informado |
| AFTER / 3 | Bitmap Heap Scan -> [Bitmap Index Scan (idx_usuario_mail_lower)] | 1 | No informado | shared hit=3, read=0, dirtied=0, written=0; temp read=0, written=0 | Sin nodo Sort | No informado |

El literal autorizado `usuario8452@foodstore.test` reemplazó únicamente para la medición a `ANA.GOMEZ@FOODSTORE.TEST` del archivo estático. Se obtuvo una fila. El plan AFTER real fue **`Bitmap Heap Scan` con `Bitmap Index Scan`**, no un Index Scan simple. El índice conserva condición parcial y no es UNIQUE; el UNIQUE de `mail` no implica unicidad de `lower(mail)`.

### Síntesis de lectura

| índice | BEFORE, ms | AFTER, ms | BEFORE/AFTER | Resultado en esta muestra |
| --- | --- | --- | --- | --- |
| idx_producto_stock_bajo | 9.439 | 0.2975 | 31.7277x | Mejora observada; candidato conservado para el laboratorio |
| idx_pedido_fecha_reciente | 264.3715 | 1.225 | 215.8135x | Mejora observada; candidato conservado para el laboratorio |
| idx_usuario_mail_lower | 10.8865 | 0.136 | 80.0478x | Mejora observada; candidato conservado para el laboratorio |

## 5. Sobreindexación: alternativa descartada

```sql
BEGIN; CREATE INDEX idx_usuario_mail_lower_covering ON usuario (lower(mail)) INCLUDE (id,nombre,apellido,mail,rol) WHERE eliminado=FALSE; SELECT json_build_object('simple_bytes',pg_relation_size('idx_usuario_mail_lower'),'covering_bytes',pg_relation_size('idx_usuario_mail_lower_covering'),'matching_rows',(SELECT count(*) FROM usuario WHERE eliminado=FALSE AND lower(mail)=lower('usuario8452@foodstore.test'))); ROLLBACK;
```

| índice | Tamaño pg_relation_size, bytes |
| --- | --- |
| idx_usuario_mail_lower | 999424 |
| idx_usuario_mail_lower_covering | 2621440 |

**REJECTED: `idx_usuario_mail_lower_covering`.** Ocupó 2.623 veces el índice simple (1622016 bytes adicionales; +162.2951 %). La consulta devuelve una sola fila y el índice simple ya produjo la mejora medida. No se midió un beneficio de lectura o escritura de la alternativa: el tamaño mayor y la falta de una necesidad demostrada no justifican conservarla. Este descarte es específico de esta carga y objetivo, no una regla general contra INCLUDE.

Se creó dentro de BEGIN/ROLLBACK solo para medir tamaño. `to_regclass(...) IS NULL` posterior devolvió `true`: no quedó instalado.

## 6. Costo de escritura sobre las tablas indexadas

Para recuperar un verdadero BEFORE después de medir lecturas se eliminaron **únicamente** los tres candidatos; su inventario volvió a ser `[]`. Tras las nueve corridas BEFORE se ejecutó `sql/indices.sql`, recreando exactamente los candidatos, seguido de ANALYZE y las nueve corridas AFTER. Los índices base permanecieron instalados.

```sql
DROP INDEX idx_producto_stock_bajo;
DROP INDEX idx_pedido_fecha_reciente;
DROP INDEX idx_usuario_mail_lower;
```

| Tabla | BEFORE, ms | AFTER, ms | Diferencia, ms | Cambio porcentual |
| --- | --- | --- | --- | --- |
| producto | 16.9725 | 19.512 | 2.5395 | 14.9624 % |
| pedido | 9.524 | 10.433 | 0.909 | 9.5443 % |
| usuario | 7.6655 | 14.7085 | 7.043 | 91.8792 % |

### INSERT de 1.000 filas en producto

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
INSERT INTO producto(nombre,precio,descripcion,stock,imagen,disponible,categoria_id,eliminado) SELECT 'Benchmark producto '||g, (100+g%1000)::numeric(12,2), 'Prueba reversible',g%201,NULL,TRUE,1+(g-1)%8,FALSE FROM generate_series(1,1000) g;
ROLLBACK;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 16.742 | 17.413 | 16.532 | 16.9725 |
| AFTER | 21.217 | 19.145 | 19.879 | 19.512 |

### INSERT de 1.000 filas en pedido

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
INSERT INTO pedido(fecha,estado,total,forma_pago,usuario_id,eliminado) SELECT CURRENT_DATE-(g%30), 'PENDIENTE'::estado_pedido,0,'EFECTIVO'::forma_pago,1+(g-1)%20000,FALSE FROM generate_series(1,1000) g;
ROLLBACK;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 11.786 | 9.312 | 9.736 | 9.524 |
| AFTER | 11.606 | 10.406 | 10.46 | 10.433 |

### INSERT de 1.000 filas en usuario

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
INSERT INTO usuario(nombre,apellido,mail,celular,contrasena,eliminado) SELECT 'Benchmark','Usuario '||g,'benchmark_tp5_'||g||'@foodstore.test',NULL,'hash_de_prueba',FALSE FROM generate_series(1,1000) g;
ROLLBACK;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| BEFORE | 15.595 | 8.053 | 7.278 | 7.6655 |
| AFTER | 14.954 | 15.081 | 14.336 | 14.7085 |

Las tres medias de INSERT aumentaron al añadir los candidatos. La variación observada incluye evaluación del predicado y mantenimiento de índices, además de otros efectos del entorno; no debe interpretarse como una estimación aislada y universal del costo interno de cada índice. Los planes completos incorporan llamadas y tiempos de triggers de FK cuando existen.

Los `INSERT` efectivamente procesaron 1.000 filas por corrida, según el nodo hijo. La raíz `ModifyTable` informa cero filas de salida porque no se utilizó RETURNING; eso no significa que el INSERT no se ejecutara. Cada ROLLBACK dejó los conteos lógicos intactos. Las secuencias identity avanzan aunque se reviertan las filas; no se restauraron manualmente, y rollback no garantiza un estado físico idéntico.

| Tabla | Antes de escrituras | Después de escrituras | Final |
| --- | --- | --- | --- |
| categoria | 8 | 8 | 8 |
| producto | 50000 | 50000 | 50000 |
| usuario | 20000 | 20000 | 20000 |
| pedido | 200000 | 200000 | 200000 |
| detalle_pedido | 500000 | 500000 | 500000 |

## 7. Vistas: equivalencia real

Se aplicó `sql/views.sql` con ON_ERROR_STOP=1. Cada definición se comparó con su consulta manual correspondiente de `sql/queries.sql` mediante EXCEPT en ambos sentidos y se contó la vista.

| Vista | manual_minus_view | view_minus_manual | Filas |
| --- | --- | --- | --- |
| v_productos_vigentes | 0 | 0 | 43299 |
| v_pedidos_resumen | 0 | 0 | 198059 |
| v_pedido_detalle | 0 | 0 | 495327 |
| v_usuarios_publico | 0 | 0 | 19802 |

Las cuatro equivalencias dieron **0 / 0**. EXCEPT demuestra igualdad de conjuntos para esta carga; no sustituye una prueba universal de especificación ni una evaluación de multiplicidades con EXCEPT ALL. Las proyecciones incluyen identificadores y los joins aplicados son con PK, según el esquema utilizado.

La semántica histórica se conserva: pedidos no filtra usuarios eliminados; detalles no filtra productos eliminados; productos vigentes filtra eliminación de producto/categoría pero no disponibilidad. Los datos incluyen bajas lógicas reales. No se realizó una mutación adicional de bajas después de materializar para simular otro momento histórico.

<details>
<summary>Consulta y resultado: v_productos_vigentes</summary>

```sql
SELECT json_build_object('manual_minus_view',(SELECT count(*) FROM ((SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    p.disponible,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE) EXCEPT (SELECT * FROM v_productos_vigentes)) d),'view_minus_manual',(SELECT count(*) FROM ((SELECT * FROM v_productos_vigentes) EXCEPT (SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    p.disponible,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE)) d),'rows',(SELECT count(*) FROM v_productos_vigentes));
```

```json
{
  "name": "v_productos_vigentes",
  "manual_minus_view": 0,
  "view_minus_manual": 0,
  "rows": 43299
}
```

</details>

<details>
<summary>Consulta y resultado: v_pedidos_resumen</summary>

```sql
SELECT json_build_object('manual_minus_view',(SELECT count(*) FROM ((SELECT
    ped.id AS pedido_id,
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
FROM pedido ped
JOIN usuario u
    ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE) EXCEPT (SELECT * FROM v_pedidos_resumen)) d),'view_minus_manual',(SELECT count(*) FROM ((SELECT * FROM v_pedidos_resumen) EXCEPT (SELECT
    ped.id AS pedido_id,
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
FROM pedido ped
JOIN usuario u
    ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE)) d),'rows',(SELECT count(*) FROM v_pedidos_resumen));
```

```json
{
  "name": "v_pedidos_resumen",
  "manual_minus_view": 0,
  "view_minus_manual": 0,
  "rows": 198059
}
```

</details>

<details>
<summary>Consulta y resultado: v_pedido_detalle</summary>

```sql
SELECT json_build_object('manual_minus_view',(SELECT count(*) FROM ((SELECT
    dp.id AS detalle_id,
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id
WHERE dp.eliminado = FALSE) EXCEPT (SELECT * FROM v_pedido_detalle)) d),'view_minus_manual',(SELECT count(*) FROM ((SELECT * FROM v_pedido_detalle) EXCEPT (SELECT
    dp.id AS detalle_id,
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id
WHERE dp.eliminado = FALSE)) d),'rows',(SELECT count(*) FROM v_pedido_detalle));
```

```json
{
  "name": "v_pedido_detalle",
  "manual_minus_view": 0,
  "view_minus_manual": 0,
  "rows": 495327
}
```

</details>

<details>
<summary>Consulta y resultado: v_usuarios_publico</summary>

```sql
SELECT json_build_object('manual_minus_view',(SELECT count(*) FROM ((SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE) EXCEPT (SELECT * FROM v_usuarios_publico)) d),'view_minus_manual',(SELECT count(*) FROM ((SELECT * FROM v_usuarios_publico) EXCEPT (SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE)) d),'rows',(SELECT count(*) FROM v_usuarios_publico));
```

```json
{
  "name": "v_usuarios_publico",
  "manual_minus_view": 0,
  "view_minus_manual": 0,
  "rows": 19802
}
```

</details>

### Comprobación adicional de semántica histórica

Las siguientes consultas de control se ejecutaron sobre la base final y confirmaron que los filtros no eliminan indebidamente los registros históricos:

| Control | Filas reales |
| --- | --- |
| Stock bajo con producto no disponible | 74 |
| Catálogo vigente con producto no disponible | 1237 |
| Pedidos visibles de usuarios eliminados | 1960 |
| Detalles visibles de productos eliminados | 5107 |
| Detalles fuente de facturación de productos eliminados | 5057 |
| Detalles fuente de facturación de categorías eliminadas | 24526 |

El catálogo de columnas de la vista pública confirmó exactamente `id, nombre, apellido, mail, rol`. El inventario final confirmó los índices base, los tres candidatos y el índice único de la materializada; no estaban presentes el covering descartado ni el rol temporal. La base descartable queda existente al finalizar el bloque.

<details>
<summary>SQL real de comprobación adicional</summary>

```sql
SELECT json_build_object('database',current_database(),'stock_no_disponible',(SELECT count(*) FROM producto WHERE NOT eliminado AND stock<=5 AND NOT disponible),'catalogo_no_disponible',(SELECT count(*) FROM v_productos_vigentes WHERE NOT disponible),'pedidos_usuario_eliminado',(SELECT count(*) FROM v_pedidos_resumen v JOIN usuario u ON u.id=v.usuario_id WHERE u.eliminado),'detalles_producto_eliminado',(SELECT count(*) FROM v_pedido_detalle v JOIN producto p ON p.id=v.producto_id WHERE p.eliminado),'facturacion_detalles_producto_eliminado',(SELECT count(*) FROM detalle_pedido d JOIN pedido pe ON pe.id=d.pedido_id JOIN producto p ON p.id=d.producto_id WHERE NOT d.eliminado AND NOT pe.eliminado AND p.eliminado),'facturacion_detalles_categoria_eliminada',(SELECT count(*) FROM detalle_pedido d JOIN pedido pe ON pe.id=d.pedido_id JOIN producto p ON p.id=d.producto_id JOIN categoria c ON c.id=p.categoria_id WHERE NOT d.eliminado AND NOT pe.eliminado AND c.eliminado),'columnas_publicas',(SELECT json_agg(column_name ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='v_usuarios_publico'),'rol_soporte_ausente',NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='rol_soporte'),'covering_ausente',to_regclass('public.idx_usuario_mail_lower_covering') IS NULL,'indices_finales',(SELECT json_agg(t ORDER BY indexname) FROM (SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public') t));
```

</details>

## 8. Seguridad: prueba y limpieza

El inventario inicial de `pg_roles` no encontró `rol_soporte`. Se creó para la prueba mediante `CREATE ROLE rol_soporte NOLOGIN`, sin contraseña, LOGIN ni membresías. **ROLE_CREATED_FOR_TEST = YES**. No se modificaron roles preexistentes.

Se aplicó `sql/seguridad.sql`:

```sql
GRANT SELECT ON v_usuarios_publico TO rol_soporte;
```

| Privilegio consultado | Resultado |
| --- | --- |
| view_select | true |
| table_select | false |
| password_select | false |
| phone_select | false |

La vista expone únicamente `id, nombre, apellido, mail, rol`, filtra `eliminado = FALSE` y no proyecta `contrasena` ni `celular`.

```sql
SET ROLE rol_soporte;
SELECT * FROM v_usuarios_publico LIMIT 1;
RESET ROLE;
```

```text
1|Nombre 1|Apellido 1|usuario1@foodstore.test|USUARIO
```

```sql
SET ROLE rol_soporte;
SELECT contrasena FROM usuario LIMIT 1;
RESET ROLE;
```

```text
psql:C:/Users/facu/AppData/Local/Temp/foodstore_tp5_oficial_run_keO2dm/security_negative_contrasena.sql:1: ERROR:  42501: permiso denegado a la tabla usuario
LOCATION:  aclcheck_error, aclchk.c:2845
```

```sql
SET ROLE rol_soporte;
SELECT celular FROM usuario LIMIT 1;
RESET ROLE;
```

```text
psql:C:/Users/facu/AppData/Local/Temp/foodstore_tp5_oficial_run_keO2dm/security_negative_celular.sql:1: ERROR:  42501: permiso denegado a la tabla usuario
LOCATION:  aclcheck_error, aclchk.c:2845
```

Ambos SELECT sobre la tabla base fallaron con **SQLSTATE 42501, permiso denegado**. Son los dos errores esperados de la prueba, no fallas inesperadas. psql terminó con código 0 en estas invocaciones porque se pidió continuar para ejecutar RESET ROLE; el resultado negativo se validó por SQLSTATE, no por ese código de proceso.

```sql
REVOKE SELECT ON v_usuarios_publico FROM rol_soporte;
DROP ROLE rol_soporte;
```

La consulta posterior confirmó ausencia del rol: **cleaned = true**. Se revocó y eliminó exclusivamente el rol creado por esta prueba. El permiso ejercitado no queda concedido de forma persistente al terminar; un despliegue posterior deberá usar un rol autorizado y verificar también privilegios heredados y acceso directo.

## 9. Vista materializada y refresh concurrente

La consulta original se midió antes de crear la materializada. Luego se aplicó `sql/materializadas.sql` con ON_ERROR_STOP=1, incluida la clave UNIQUE `(categoria_id, mes)`. No se filtraron bajas posteriores de producto/categoría ni disponibilidad; únicamente se excluyeron pedidos/detalles eliminados y se sumó el subtotal físico.

```sql
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    date_trunc('month', ped.fecha)::date AS mes,
    COUNT(DISTINCT ped.id) AS cantidad_pedidos,
    SUM(dp.cantidad) AS unidades_vendidas,
    SUM(dp.subtotal) AS facturacion_total
FROM categoria c
JOIN producto pr
    ON pr.categoria_id = c.id
JOIN detalle_pedido dp
    ON dp.producto_id = pr.id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY
    c.id,
    c.nombre,
    date_trunc('month', ped.fecha)::date
ORDER BY
    mes ASC,
    facturacion_total DESC;
```

| Momento | original_minus_materializada | materializada_minus_original | Filas |
| --- | --- | --- | --- |
| Después de instalación | 0 | 0 | 192 |
| Después de REFRESH CONCURRENTLY | 0 | 0 | 192 |

### Lecturas medidas: separar los dos ordenamientos

```sql
SELECT * FROM mv_facturacion_categoria_mes ORDER BY categoria_id, mes;
```

```sql
SELECT * FROM mv_facturacion_categoria_mes ORDER BY mes ASC, facturacion_total DESC;
```

| Caso | Corrida 1 (calentamiento), ms | Corrida 2, ms | Corrida 3, ms | Media 2+3, ms |
| --- | --- | --- | --- | --- |
| Original: mes ASC, facturacion_total DESC | 1169.796 | 1146.073 | 1230.916 | 1188.4945 |
| Materializada solicitada: categoria_id, mes | 0.088 | 0.084 | 0.16 | 0.122 |
| Control homogéneo: mes ASC, facturacion_total DESC | 0.169 | 0.257 | 0.189 | 0.223 |

La comparación homogénea es **1188.4945 ms frente a 0.223 ms**, cociente 5329.5717x. La lectura solicitada con `ORDER BY categoria_id, mes` promedió 0.122 ms; su cociente aritmético 9741.7582x compara ordenamientos distintos y **no se presenta como la comparación homogénea**. Ambas lecturas retornan las mismas 192 filas, con distinto orden.

| Caso / corrida | Plan real | Filas raiz | Rows Removed by Filter | Buffers raiz | Sort | Heap Fetches |
| --- | --- | --- | --- | --- | --- | --- |
| Original / 2 | Incremental Sort -> [Aggregate -> [Sort -> [Hash Join -> [Hash Join -> [Hash Join -> [Seq Scan; Hash -> [Seq Scan]]; Hash -> [Seq Scan]]; Hash -> [Seq Scan]]]]] | 192 | Seq Scan: 4673 (loops=1); Seq Scan: 1941 (loops=1) | shared hit=10512, read=0, dirtied=0, written=0; temp read=5251, written=5261 | Sort: external merge, 26000 kB Disk | No informado |
| Original / 3 | Incremental Sort -> [Aggregate -> [Sort -> [Hash Join -> [Hash Join -> [Hash Join -> [Seq Scan; Hash -> [Seq Scan]]; Hash -> [Seq Scan]]; Hash -> [Seq Scan]]]]] | 192 | Seq Scan: 4673 (loops=1); Seq Scan: 1941 (loops=1) | shared hit=10512, read=0, dirtied=0, written=0; temp read=5251, written=5261 | Sort: external merge, 26000 kB Disk | No informado |
| Materializada solicitada / 2 | Sort -> [Seq Scan] | 192 | No informado | shared hit=8, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 38 kB Memory | No informado |
| Materializada solicitada / 3 | Sort -> [Seq Scan] | 192 | No informado | shared hit=8, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 38 kB Memory | No informado |
| Control mismo orden / 2 | Sort -> [Seq Scan] | 192 | No informado | shared hit=8, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 38 kB Memory | No informado |
| Control mismo orden / 3 | Sort -> [Seq Scan] | 192 | No informado | shared hit=8, read=0, dirtied=0, written=0; temp read=0, written=0 | Sort: quicksort, 38 kB Memory | No informado |

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
```

**REFRESH CONCURRENTLY: PASS.** El comando terminó sin errores y la equivalencia posterior volvió a ser 0 / 0. No se midió tiempo de refresh ni bloqueo concurrente de otra sesión; que el comando admita CONCURRENTLY no constituye por sí mismo un benchmark de concurrencia. No se programó refresh automático ni se validó la frecuencia propuesta de 60 minutos. La lectura rápida de la instantánea no incluye costos de creación, refresco, almacenamiento ni eventual desactualización.

## 10. Conclusiones técnicas y límites

1. Los candidatos A/B/C fueron utilizados por los planes y redujeron las medias de lectura en este dataset. Los planes fueron Index Only Scan, Index Only Scan y Bitmap Heap Scan + Bitmap Index Scan, respectivamente.
2. El costo de mantener índices es visible en los INSERT sobre producto/pedido/usuario; no se extrapola desde escrituras mayormente dirigidas a detalle_pedido.
3. La alternativa covering para mail quedó descartada y ausente tras rollback: mayor tamaño, una sola fila buscada y ningún beneficio adicional medido.
4. Las cuatro vistas y la materializada son equivalentes a sus consultas manuales para la carga probada. La seguridad fue efectiva para el rol temporal limpio y no supone nada sobre roles existentes en otra instalación.
5. La materialización redujo drásticamente el trabajo de lectura observado, a cambio de una instantánea que requiere refresh. Se separaron explícitamente los ordenamientos para evitar una comparación semántica engañosa.
6. No hubo errores SQL inesperados: `results.errors = []`. Se registraron dos denegaciones 42501 esperadas. Las mediciones conservan calentamientos y variación entre corridas; no se fabricaron planes o resultados.
7. No se ejecutó una aplicación ni pruebas de carga concurrente. La evidencia no certifica rendimiento en producción ni convierte el bootstrap de laboratorio en autoridad canónica.

## Anexo A. Planes originales completos de corridas válidas

Contenido obtenido de `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, copiado de los resultados reales. No es una ejecución adicional de EXPLAIN en formato texto. Se incluyen estimaciones, tiempos por nodo, buffers, workers, filtros, ordenamientos, heap fetches y triggers exactamente como los devolvió PostgreSQL.

<details>
<summary>idx_producto_stock_bajo / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 1562.77,
    "Total Cost": 1566.33,
    "Plan Rows": 1427,
    "Plan Width": 33,
    "Actual Startup Time": 9.199,
    "Actual Total Time": 9.232,
    "Actual Rows": 1477,
    "Actual Loops": 1,
    "Sort Key": [
      "stock",
      "nombre"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 129,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 869,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "producto",
        "Alias": "producto",
        "Startup Cost": 0,
        "Total Cost": 1488,
        "Plan Rows": 1427,
        "Plan Width": 33,
        "Actual Startup Time": 0.012,
        "Actual Total Time": 5.136,
        "Actual Rows": 1477,
        "Actual Loops": 1,
        "Filter": "((NOT eliminado) AND (stock <= 5))",
        "Rows Removed by Filter": 48523,
        "Shared Hit Blocks": 863,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 127,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.476,
  "Triggers": [],
  "Execution Time": 9.338
}
```

</details>

<details>
<summary>idx_producto_stock_bajo / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 1562.77,
    "Total Cost": 1566.33,
    "Plan Rows": 1427,
    "Plan Width": 33,
    "Actual Startup Time": 9.306,
    "Actual Total Time": 9.341,
    "Actual Rows": 1477,
    "Actual Loops": 1,
    "Sort Key": [
      "stock",
      "nombre"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 129,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 869,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "producto",
        "Alias": "producto",
        "Startup Cost": 0,
        "Total Cost": 1488,
        "Plan Rows": 1427,
        "Plan Width": 33,
        "Actual Startup Time": 0.029,
        "Actual Total Time": 5.907,
        "Actual Rows": 1477,
        "Actual Loops": 1,
        "Filter": "((NOT eliminado) AND (stock <= 5))",
        "Rows Removed by Filter": 48523,
        "Shared Hit Blocks": 863,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 127,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.653,
  "Triggers": [],
  "Execution Time": 9.54
}
```

</details>

<details>
<summary>idx_producto_stock_bajo / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Index Only Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Scan Direction": "Forward",
    "Index Name": "idx_producto_stock_bajo",
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0.41,
    "Total Cost": 70.11,
    "Plan Rows": 1468,
    "Plan Width": 33,
    "Actual Startup Time": 0.079,
    "Actual Total Time": 0.255,
    "Actual Rows": 1477,
    "Actual Loops": 1,
    "Index Cond": "(stock <= 5)",
    "Rows Removed by Index Recheck": 0,
    "Heap Fetches": 0,
    "Shared Hit Blocks": 14,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 155,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.661,
  "Triggers": [],
  "Execution Time": 0.332
}
```

</details>

<details>
<summary>idx_producto_stock_bajo / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Index Only Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Scan Direction": "Forward",
    "Index Name": "idx_producto_stock_bajo",
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0.41,
    "Total Cost": 70.11,
    "Plan Rows": 1468,
    "Plan Width": 33,
    "Actual Startup Time": 0.052,
    "Actual Total Time": 0.198,
    "Actual Rows": 1477,
    "Actual Loops": 1,
    "Index Cond": "(stock <= 5)",
    "Rows Removed by Index Recheck": 0,
    "Heap Fetches": 0,
    "Shared Hit Blocks": 14,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 155,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.596,
  "Triggers": [],
  "Execution Time": 0.263
}
```

</details>

<details>
<summary>idx_pedido_fecha_reciente / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Gather Merge",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 6601.52,
    "Total Cost": 7453.95,
    "Plan Rows": 7306,
    "Plan Width": 36,
    "Actual Startup Time": 262.729,
    "Actual Total Time": 266.154,
    "Actual Rows": 8525,
    "Actual Loops": 1,
    "Workers Planned": 2,
    "Workers Launched": 2,
    "Shared Hit Blocks": 4001,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Sort",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Startup Cost": 5601.5,
        "Total Cost": 5610.63,
        "Plan Rows": 3653,
        "Plan Width": 36,
        "Actual Startup Time": 9.808,
        "Actual Total Time": 10.003,
        "Actual Rows": 2842,
        "Actual Loops": 3,
        "Sort Key": [
          "fecha DESC"
        ],
        "Sort Method": "quicksort",
        "Sort Space Used": 851,
        "Sort Space Type": "Memory",
        "Shared Hit Blocks": 4001,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0,
        "Workers": [
          {
            "Worker Number": 0,
            "Sort Method": "quicksort",
            "Sort Space Used": 25,
            "Sort Space Type": "Memory"
          },
          {
            "Worker Number": 1,
            "Sort Method": "quicksort",
            "Sort Space Used": 25,
            "Sort Space Type": "Memory"
          }
        ],
        "Plans": [
          {
            "Node Type": "Seq Scan",
            "Parent Relationship": "Outer",
            "Parallel Aware": true,
            "Async Capable": false,
            "Relation Name": "pedido",
            "Alias": "pedido",
            "Startup Cost": 0,
            "Total Cost": 5385.33,
            "Plan Rows": 3653,
            "Plan Width": 36,
            "Actual Startup Time": 0.033,
            "Actual Total Time": 9.203,
            "Actual Rows": 2842,
            "Actual Loops": 3,
            "Filter": "((NOT eliminado) AND (fecha >= (CURRENT_DATE - 30)))",
            "Rows Removed by Filter": 63825,
            "Shared Hit Blocks": 3927,
            "Shared Read Blocks": 0,
            "Shared Dirtied Blocks": 0,
            "Shared Written Blocks": 0,
            "Local Hit Blocks": 0,
            "Local Read Blocks": 0,
            "Local Dirtied Blocks": 0,
            "Local Written Blocks": 0,
            "Temp Read Blocks": 0,
            "Temp Written Blocks": 0,
            "Workers": []
          }
        ]
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 110,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.596,
  "Triggers": [],
  "Execution Time": 266.516
}
```

</details>

<details>
<summary>idx_pedido_fecha_reciente / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Gather Merge",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 6601.52,
    "Total Cost": 7453.95,
    "Plan Rows": 7306,
    "Plan Width": 36,
    "Actual Startup Time": 258.749,
    "Actual Total Time": 261.876,
    "Actual Rows": 8525,
    "Actual Loops": 1,
    "Workers Planned": 2,
    "Workers Launched": 2,
    "Shared Hit Blocks": 4001,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Sort",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Startup Cost": 5601.5,
        "Total Cost": 5610.63,
        "Plan Rows": 3653,
        "Plan Width": 36,
        "Actual Startup Time": 8.296,
        "Actual Total Time": 8.524,
        "Actual Rows": 2842,
        "Actual Loops": 3,
        "Sort Key": [
          "fecha DESC"
        ],
        "Sort Method": "quicksort",
        "Sort Space Used": 851,
        "Sort Space Type": "Memory",
        "Shared Hit Blocks": 4001,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0,
        "Workers": [
          {
            "Worker Number": 0,
            "Sort Method": "quicksort",
            "Sort Space Used": 25,
            "Sort Space Type": "Memory"
          },
          {
            "Worker Number": 1,
            "Sort Method": "quicksort",
            "Sort Space Used": 25,
            "Sort Space Type": "Memory"
          }
        ],
        "Plans": [
          {
            "Node Type": "Seq Scan",
            "Parent Relationship": "Outer",
            "Parallel Aware": true,
            "Async Capable": false,
            "Relation Name": "pedido",
            "Alias": "pedido",
            "Startup Cost": 0,
            "Total Cost": 5385.33,
            "Plan Rows": 3653,
            "Plan Width": 36,
            "Actual Startup Time": 0.032,
            "Actual Total Time": 7.823,
            "Actual Rows": 2842,
            "Actual Loops": 3,
            "Filter": "((NOT eliminado) AND (fecha >= (CURRENT_DATE - 30)))",
            "Rows Removed by Filter": 63825,
            "Shared Hit Blocks": 3927,
            "Shared Read Blocks": 0,
            "Shared Dirtied Blocks": 0,
            "Shared Written Blocks": 0,
            "Local Hit Blocks": 0,
            "Local Read Blocks": 0,
            "Local Dirtied Blocks": 0,
            "Local Written Blocks": 0,
            "Temp Read Blocks": 0,
            "Temp Written Blocks": 0,
            "Workers": []
          }
        ]
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 110,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.485,
  "Triggers": [],
  "Execution Time": 262.227
}
```

</details>

<details>
<summary>idx_pedido_fecha_reciente / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Index Only Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Scan Direction": "Forward",
    "Index Name": "idx_pedido_fecha_reciente",
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0.42,
    "Total Cost": 418.01,
    "Plan Rows": 8319,
    "Plan Width": 36,
    "Actual Startup Time": 0.052,
    "Actual Total Time": 1.059,
    "Actual Rows": 8525,
    "Actual Loops": 1,
    "Index Cond": "(fecha >= (CURRENT_DATE - 30))",
    "Rows Removed by Index Recheck": 0,
    "Heap Fetches": 0,
    "Shared Hit Blocks": 72,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 144,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.584,
  "Triggers": [],
  "Execution Time": 1.27
}
```

</details>

<details>
<summary>idx_pedido_fecha_reciente / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Index Only Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Scan Direction": "Forward",
    "Index Name": "idx_pedido_fecha_reciente",
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0.42,
    "Total Cost": 418.01,
    "Plan Rows": 8319,
    "Plan Width": 36,
    "Actual Startup Time": 0.053,
    "Actual Total Time": 0.987,
    "Actual Rows": 8525,
    "Actual Loops": 1,
    "Index Cond": "(fecha >= (CURRENT_DATE - 30))",
    "Rows Removed by Index Recheck": 0,
    "Heap Fetches": 0,
    "Shared Hit Blocks": 72,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 144,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.624,
  "Triggers": [],
  "Execution Time": 1.18
}
```

</details>

<details>
<summary>idx_usuario_mail_lower / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Seq Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 644,
    "Plan Rows": 99,
    "Plan Width": 65,
    "Actual Startup Time": 4.761,
    "Actual Total Time": 10.952,
    "Actual Rows": 1,
    "Actual Loops": 1,
    "Filter": "((NOT eliminado) AND (lower((mail)::text) = 'usuario8452@foodstore.test'::text))",
    "Rows Removed by Filter": 19999,
    "Shared Hit Blocks": 344,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 92,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.665,
  "Triggers": [],
  "Execution Time": 11.006
}
```

</details>

<details>
<summary>idx_usuario_mail_lower / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Seq Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 644,
    "Plan Rows": 99,
    "Plan Width": 65,
    "Actual Startup Time": 4.543,
    "Actual Total Time": 10.733,
    "Actual Rows": 1,
    "Actual Loops": 1,
    "Filter": "((NOT eliminado) AND (lower((mail)::text) = 'usuario8452@foodstore.test'::text))",
    "Rows Removed by Filter": 19999,
    "Shared Hit Blocks": 344,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning": {
    "Shared Hit Blocks": 92,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.454,
  "Triggers": [],
  "Execution Time": 10.767
}
```

</details>

<details>
<summary>idx_usuario_mail_lower / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Bitmap Heap Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 5.05,
    "Total Cost": 223.28,
    "Plan Rows": 99,
    "Plan Width": 65,
    "Actual Startup Time": 0.058,
    "Actual Total Time": 0.059,
    "Actual Rows": 1,
    "Actual Loops": 1,
    "Recheck Cond": "((lower((mail)::text) = 'usuario8452@foodstore.test'::text) AND (NOT eliminado))",
    "Rows Removed by Index Recheck": 0,
    "Exact Heap Blocks": 1,
    "Lossy Heap Blocks": 0,
    "Shared Hit Blocks": 3,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Bitmap Index Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Index Name": "idx_usuario_mail_lower",
        "Startup Cost": 0,
        "Total Cost": 5.03,
        "Plan Rows": 99,
        "Plan Width": 0,
        "Actual Startup Time": 0.039,
        "Actual Total Time": 0.039,
        "Actual Rows": 1,
        "Actual Loops": 1,
        "Index Cond": "(lower((mail)::text) = 'usuario8452@foodstore.test'::text)",
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 112,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.725,
  "Triggers": [],
  "Execution Time": 0.159
}
```

</details>

<details>
<summary>idx_usuario_mail_lower / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Bitmap Heap Scan",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 5.05,
    "Total Cost": 223.28,
    "Plan Rows": 99,
    "Plan Width": 65,
    "Actual Startup Time": 0.04,
    "Actual Total Time": 0.041,
    "Actual Rows": 1,
    "Actual Loops": 1,
    "Recheck Cond": "((lower((mail)::text) = 'usuario8452@foodstore.test'::text) AND (NOT eliminado))",
    "Rows Removed by Index Recheck": 0,
    "Exact Heap Blocks": 1,
    "Lossy Heap Blocks": 0,
    "Shared Hit Blocks": 3,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Bitmap Index Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Index Name": "idx_usuario_mail_lower",
        "Startup Cost": 0,
        "Total Cost": 5.03,
        "Plan Rows": 99,
        "Plan Width": 0,
        "Actual Startup Time": 0.027,
        "Actual Total Time": 0.027,
        "Actual Rows": 1,
        "Actual Loops": 1,
        "Index Cond": "(lower((mail)::text) = 'usuario8452@foodstore.test'::text)",
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 112,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.519,
  "Triggers": [],
  "Execution Time": 0.113
}
```

</details>

<details>
<summary>INSERT producto / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0,
    "Total Cost": 47.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 11.833,
    "Actual Total Time": 11.834,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 8130,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 35,
    "Shared Written Blocks": 27,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 47.5,
        "Plan Rows": 1000,
        "Plan Width": 368,
        "Actual Startup Time": 0.097,
        "Actual Total Time": 0.726,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 24,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.237,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16878",
      "Constraint Name": "producto_categoria_id_fkey",
      "Relation": "producto",
      "Time": 5.465,
      "Calls": 1000
    }
  ],
  "Execution Time": 17.413
}
```

</details>

<details>
<summary>INSERT producto / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0,
    "Total Cost": 47.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 9.927,
    "Actual Total Time": 9.928,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 8143,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 9,
    "Shared Written Blocks": 9,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 47.5,
        "Plan Rows": 1000,
        "Plan Width": 368,
        "Actual Startup Time": 0.107,
        "Actual Total Time": 0.669,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 24,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.254,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16878",
      "Constraint Name": "producto_categoria_id_fkey",
      "Relation": "producto",
      "Time": 6.475,
      "Calls": 1000
    }
  ],
  "Execution Time": 16.532
}
```

</details>

<details>
<summary>INSERT producto / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0,
    "Total Cost": 47.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 13.543,
    "Actual Total Time": 13.544,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 11210,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 47.5,
        "Plan Rows": 1000,
        "Plan Width": 368,
        "Actual Startup Time": 0.093,
        "Actual Total Time": 0.68,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 24,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.224,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16878",
      "Constraint Name": "producto_categoria_id_fkey",
      "Relation": "producto",
      "Time": 5.489,
      "Calls": 1000
    }
  ],
  "Execution Time": 19.145
}
```

</details>

<details>
<summary>INSERT producto / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "producto",
    "Alias": "producto",
    "Startup Cost": 0,
    "Total Cost": 47.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 13.274,
    "Actual Total Time": 13.275,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 11232,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 1,
    "Shared Written Blocks": 1,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 47.5,
        "Plan Rows": 1000,
        "Plan Width": 368,
        "Actual Startup Time": 0.124,
        "Actual Total Time": 0.631,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 24,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.329,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16878",
      "Constraint Name": "producto_categoria_id_fkey",
      "Relation": "producto",
      "Time": 6.446,
      "Calls": 1000
    }
  ],
  "Execution Time": 19.879
}
```

</details>

<details>
<summary>INSERT pedido / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0,
    "Total Cost": 32.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 3.55,
    "Actual Total Time": 3.55,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 6100,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 2,
    "Shared Written Blocks": 2,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 32.5,
        "Plan Rows": 1000,
        "Plan Width": 53,
        "Actual Startup Time": 0.102,
        "Actual Total Time": 0.527,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1010,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 9,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.21,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16894",
      "Constraint Name": "pedido_usuario_id_fkey",
      "Relation": "pedido",
      "Time": 5.647,
      "Calls": 1000
    }
  ],
  "Execution Time": 9.312
}
```

</details>

<details>
<summary>INSERT pedido / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0,
    "Total Cost": 32.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 3.764,
    "Actual Total Time": 3.764,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 6106,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 3,
    "Shared Written Blocks": 3,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 32.5,
        "Plan Rows": 1000,
        "Plan Width": 53,
        "Actual Startup Time": 0.095,
        "Actual Total Time": 0.494,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1010,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 9,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.209,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16894",
      "Constraint Name": "pedido_usuario_id_fkey",
      "Relation": "pedido",
      "Time": 5.861,
      "Calls": 1000
    }
  ],
  "Execution Time": 9.736
}
```

</details>

<details>
<summary>INSERT pedido / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0,
    "Total Cost": 32.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 4.947,
    "Actual Total Time": 4.947,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 9148,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 8,
    "Shared Written Blocks": 8,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 32.5,
        "Plan Rows": 1000,
        "Plan Width": 53,
        "Actual Startup Time": 0.104,
        "Actual Total Time": 0.455,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1010,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 9,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.21,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16894",
      "Constraint Name": "pedido_usuario_id_fkey",
      "Relation": "pedido",
      "Time": 5.329,
      "Calls": 1000
    }
  ],
  "Execution Time": 10.406
}
```

</details>

<details>
<summary>INSERT pedido / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "pedido",
    "Alias": "pedido",
    "Startup Cost": 0,
    "Total Cost": 32.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 4.942,
    "Actual Total Time": 4.942,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 9158,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 11,
    "Shared Written Blocks": 11,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 32.5,
        "Plan Rows": 1000,
        "Plan Width": 53,
        "Actual Startup Time": 0.115,
        "Actual Total Time": 0.455,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1010,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 9,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.194,
  "Triggers": [
    {
      "Trigger Name": "RI_ConstraintTrigger_c_16894",
      "Constraint Name": "pedido_usuario_id_fkey",
      "Relation": "pedido",
      "Time": 5.398,
      "Calls": 1000
    }
  ],
  "Execution Time": 10.46
}
```

</details>

<details>
<summary>INSERT usuario / BEFORE / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 37.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 8.013,
    "Actual Total Time": 8.013,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 7138,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 14,
    "Shared Written Blocks": 14,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 37.5,
        "Plan Rows": 1000,
        "Plan Width": 1647,
        "Actual Startup Time": 0.086,
        "Actual Total Time": 0.581,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 27,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.279,
  "Triggers": [],
  "Execution Time": 8.053
}
```

</details>

<details>
<summary>INSERT usuario / BEFORE / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 37.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 7.244,
    "Actual Total Time": 7.244,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 7208,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 37.5,
        "Plan Rows": 1000,
        "Plan Width": 1647,
        "Actual Startup Time": 0.13,
        "Actual Total Time": 0.587,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 27,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.32,
  "Triggers": [],
  "Execution Time": 7.278
}
```

</details>

<details>
<summary>INSERT usuario / AFTER / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 37.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 15.041,
    "Actual Total Time": 15.041,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 9251,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 12,
    "Shared Written Blocks": 12,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 37.5,
        "Plan Rows": 1000,
        "Plan Width": 1647,
        "Actual Startup Time": 0.088,
        "Actual Total Time": 0.613,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 27,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.283,
  "Triggers": [],
  "Execution Time": 15.081
}
```

</details>

<details>
<summary>INSERT usuario / AFTER / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "ModifyTable",
    "Operation": "Insert",
    "Parallel Aware": false,
    "Async Capable": false,
    "Relation Name": "usuario",
    "Alias": "usuario",
    "Startup Cost": 0,
    "Total Cost": 37.5,
    "Plan Rows": 0,
    "Plan Width": 0,
    "Actual Startup Time": 14.3,
    "Actual Total Time": 14.3,
    "Actual Rows": 0,
    "Actual Loops": 1,
    "Shared Hit Blocks": 9311,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Function Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Function Name": "generate_series",
        "Alias": "g",
        "Startup Cost": 0,
        "Total Cost": 37.5,
        "Plan Rows": 1000,
        "Plan Width": 1647,
        "Actual Startup Time": 0.091,
        "Actual Total Time": 0.658,
        "Actual Rows": 1000,
        "Actual Loops": 1,
        "Shared Hit Blocks": 1009,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 27,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.294,
  "Triggers": [],
  "Execution Time": 14.336
}
```

</details>

<details>
<summary>Original materializada / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Incremental Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 99560.22,
    "Total Cost": 107199.84,
    "Plan Rows": 5760,
    "Plan Width": 72,
    "Actual Startup Time": 996.1,
    "Actual Total Time": 1142.142,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
      "(sum(dp.subtotal)) DESC"
    ],
    "Presorted Key": [
      "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)"
    ],
    "Full-sort Groups": {
      "Group Count": 6,
      "Sort Methods Used": [
        "quicksort"
      ],
      "Sort Space Memory": {
        "Average Sort Space Used": 27,
        "Peak Sort Space Used": 27
      }
    },
    "Shared Hit Blocks": 10512,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 5251,
    "Temp Written Blocks": 5261,
    "Plans": [
      {
        "Node Type": "Aggregate",
        "Strategy": "Sorted",
        "Partial Mode": "Simple",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Startup Cost": 99549.72,
        "Total Cost": 107027.04,
        "Plan Rows": 5760,
        "Plan Width": 72,
        "Actual Startup Time": 966.812,
        "Actual Total Time": 1141.913,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Group Key": [
          "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
          "c.id"
        ],
        "Shared Hit Blocks": 10506,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 5251,
        "Temp Written Blocks": 5261,
        "Plans": [
          {
            "Node Type": "Sort",
            "Parent Relationship": "Outer",
            "Parallel Aware": false,
            "Async Capable": false,
            "Startup Cost": 99549.72,
            "Total Cost": 100776.74,
            "Plan Rows": 490808,
            "Plan Width": 44,
            "Actual Startup Time": 965.185,
            "Actual Total Time": 1069.689,
            "Actual Rows": 490518,
            "Actual Loops": 1,
            "Sort Key": [
              "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
              "c.id",
              "ped.id"
            ],
            "Sort Method": "external merge",
            "Sort Space Used": 26000,
            "Sort Space Type": "Disk",
            "Shared Hit Blocks": 10506,
            "Shared Read Blocks": 0,
            "Shared Dirtied Blocks": 0,
            "Shared Written Blocks": 0,
            "Local Hit Blocks": 0,
            "Local Read Blocks": 0,
            "Local Dirtied Blocks": 0,
            "Local Written Blocks": 0,
            "Temp Read Blocks": 5251,
            "Temp Written Blocks": 5261,
            "Plans": [
              {
                "Node Type": "Hash Join",
                "Parent Relationship": "Outer",
                "Parallel Aware": false,
                "Async Capable": false,
                "Join Type": "Inner",
                "Startup Cost": 11390.34,
                "Total Cost": 38057.58,
                "Plan Rows": 490808,
                "Plan Width": 44,
                "Actual Startup Time": 70.036,
                "Actual Total Time": 624.32,
                "Actual Rows": 490518,
                "Actual Loops": 1,
                "Inner Unique": true,
                "Hash Cond": "(pr.categoria_id = c.id)",
                "Shared Hit Blocks": 10503,
                "Shared Read Blocks": 0,
                "Shared Dirtied Blocks": 0,
                "Shared Written Blocks": 0,
                "Local Hit Blocks": 0,
                "Local Read Blocks": 0,
                "Local Dirtied Blocks": 0,
                "Local Written Blocks": 0,
                "Temp Read Blocks": 2001,
                "Temp Written Blocks": 2001,
                "Plans": [
                  {
                    "Node Type": "Hash Join",
                    "Parent Relationship": "Outer",
                    "Parallel Aware": false,
                    "Async Capable": false,
                    "Join Type": "Inner",
                    "Startup Cost": 11389.16,
                    "Total Cost": 32404.44,
                    "Plan Rows": 490808,
                    "Plan Width": 32,
                    "Actual Startup Time": 69.992,
                    "Actual Total Time": 469.992,
                    "Actual Rows": 490518,
                    "Actual Loops": 1,
                    "Inner Unique": true,
                    "Hash Cond": "(dp.producto_id = pr.id)",
                    "Shared Hit Blocks": 10502,
                    "Shared Read Blocks": 0,
                    "Shared Dirtied Blocks": 0,
                    "Shared Written Blocks": 0,
                    "Local Hit Blocks": 0,
                    "Local Read Blocks": 0,
                    "Local Dirtied Blocks": 0,
                    "Local Written Blocks": 0,
                    "Temp Read Blocks": 2001,
                    "Temp Written Blocks": 2001,
                    "Plans": [
                      {
                        "Node Type": "Hash Join",
                        "Parent Relationship": "Outer",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Join Type": "Inner",
                        "Startup Cost": 9371.16,
                        "Total Cost": 29097.96,
                        "Plan Rows": 490808,
                        "Plan Width": 32,
                        "Actual Startup Time": 56.126,
                        "Actual Total Time": 316.557,
                        "Actual Rows": 490518,
                        "Actual Loops": 1,
                        "Inner Unique": true,
                        "Hash Cond": "(dp.pedido_id = ped.id)",
                        "Shared Hit Blocks": 9609,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 2001,
                        "Temp Written Blocks": 2001,
                        "Plans": [
                          {
                            "Node Type": "Seq Scan",
                            "Parent Relationship": "Outer",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Relation Name": "detalle_pedido",
                            "Alias": "dp",
                            "Startup Cost": 0,
                            "Total Cost": 10682,
                            "Plan Rows": 495533,
                            "Plan Width": 28,
                            "Actual Startup Time": 0.028,
                            "Actual Total Time": 67.792,
                            "Actual Rows": 495327,
                            "Actual Loops": 1,
                            "Filter": "(NOT eliminado)",
                            "Rows Removed by Filter": 4673,
                            "Shared Hit Blocks": 5682,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 0
                          },
                          {
                            "Node Type": "Hash",
                            "Parent Relationship": "Inner",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Startup Cost": 5927,
                            "Total Cost": 5927,
                            "Plan Rows": 198093,
                            "Plan Width": 12,
                            "Actual Startup Time": 55.75,
                            "Actual Total Time": 55.751,
                            "Actual Rows": 198059,
                            "Actual Loops": 1,
                            "Hash Buckets": 262144,
                            "Original Hash Buckets": 262144,
                            "Hash Batches": 2,
                            "Original Hash Batches": 2,
                            "Peak Memory Usage": 6706,
                            "Shared Hit Blocks": 3927,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 433,
                            "Plans": [
                              {
                                "Node Type": "Seq Scan",
                                "Parent Relationship": "Outer",
                                "Parallel Aware": false,
                                "Async Capable": false,
                                "Relation Name": "pedido",
                                "Alias": "ped",
                                "Startup Cost": 0,
                                "Total Cost": 5927,
                                "Plan Rows": 198093,
                                "Plan Width": 12,
                                "Actual Startup Time": 0.02,
                                "Actual Total Time": 26.302,
                                "Actual Rows": 198059,
                                "Actual Loops": 1,
                                "Filter": "(NOT eliminado)",
                                "Rows Removed by Filter": 1941,
                                "Shared Hit Blocks": 3927,
                                "Shared Read Blocks": 0,
                                "Shared Dirtied Blocks": 0,
                                "Shared Written Blocks": 0,
                                "Local Hit Blocks": 0,
                                "Local Read Blocks": 0,
                                "Local Dirtied Blocks": 0,
                                "Local Written Blocks": 0,
                                "Temp Read Blocks": 0,
                                "Temp Written Blocks": 0
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "Node Type": "Hash",
                        "Parent Relationship": "Inner",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Startup Cost": 1393,
                        "Total Cost": 1393,
                        "Plan Rows": 50000,
                        "Plan Width": 16,
                        "Actual Startup Time": 13.777,
                        "Actual Total Time": 13.778,
                        "Actual Rows": 50000,
                        "Actual Loops": 1,
                        "Hash Buckets": 65536,
                        "Original Hash Buckets": 65536,
                        "Hash Batches": 1,
                        "Original Hash Batches": 1,
                        "Peak Memory Usage": 2856,
                        "Shared Hit Blocks": 893,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 0,
                        "Temp Written Blocks": 0,
                        "Plans": [
                          {
                            "Node Type": "Seq Scan",
                            "Parent Relationship": "Outer",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Relation Name": "producto",
                            "Alias": "pr",
                            "Startup Cost": 0,
                            "Total Cost": 1393,
                            "Plan Rows": 50000,
                            "Plan Width": 16,
                            "Actual Startup Time": 0.01,
                            "Actual Total Time": 7.3,
                            "Actual Rows": 50000,
                            "Actual Loops": 1,
                            "Shared Hit Blocks": 893,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 0
                          }
                        ]
                      }
                    ]
                  },
                  {
                    "Node Type": "Hash",
                    "Parent Relationship": "Inner",
                    "Parallel Aware": false,
                    "Async Capable": false,
                    "Startup Cost": 1.08,
                    "Total Cost": 1.08,
                    "Plan Rows": 8,
                    "Plan Width": 20,
                    "Actual Startup Time": 0.019,
                    "Actual Total Time": 0.019,
                    "Actual Rows": 8,
                    "Actual Loops": 1,
                    "Hash Buckets": 1024,
                    "Original Hash Buckets": 1024,
                    "Hash Batches": 1,
                    "Original Hash Batches": 1,
                    "Peak Memory Usage": 9,
                    "Shared Hit Blocks": 1,
                    "Shared Read Blocks": 0,
                    "Shared Dirtied Blocks": 0,
                    "Shared Written Blocks": 0,
                    "Local Hit Blocks": 0,
                    "Local Read Blocks": 0,
                    "Local Dirtied Blocks": 0,
                    "Local Written Blocks": 0,
                    "Temp Read Blocks": 0,
                    "Temp Written Blocks": 0,
                    "Plans": [
                      {
                        "Node Type": "Seq Scan",
                        "Parent Relationship": "Outer",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Relation Name": "categoria",
                        "Alias": "c",
                        "Startup Cost": 0,
                        "Total Cost": 1.08,
                        "Plan Rows": 8,
                        "Plan Width": 20,
                        "Actual Startup Time": 0.013,
                        "Actual Total Time": 0.013,
                        "Actual Rows": 8,
                        "Actual Loops": 1,
                        "Shared Hit Blocks": 1,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 0,
                        "Temp Written Blocks": 0
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 389,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 1.654,
  "Triggers": [],
  "Execution Time": 1146.073
}
```

</details>

<details>
<summary>Original materializada / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Incremental Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 99560.22,
    "Total Cost": 107199.84,
    "Plan Rows": 5760,
    "Plan Width": 72,
    "Actual Startup Time": 1048.203,
    "Actual Total Time": 1225.318,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
      "(sum(dp.subtotal)) DESC"
    ],
    "Presorted Key": [
      "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)"
    ],
    "Full-sort Groups": {
      "Group Count": 6,
      "Sort Methods Used": [
        "quicksort"
      ],
      "Sort Space Memory": {
        "Average Sort Space Used": 27,
        "Peak Sort Space Used": 27
      }
    },
    "Shared Hit Blocks": 10512,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 5251,
    "Temp Written Blocks": 5261,
    "Plans": [
      {
        "Node Type": "Aggregate",
        "Strategy": "Sorted",
        "Partial Mode": "Simple",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Startup Cost": 99549.72,
        "Total Cost": 107027.04,
        "Plan Rows": 5760,
        "Plan Width": 72,
        "Actual Startup Time": 1003.275,
        "Actual Total Time": 1225.003,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Group Key": [
          "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
          "c.id"
        ],
        "Shared Hit Blocks": 10506,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 5251,
        "Temp Written Blocks": 5261,
        "Plans": [
          {
            "Node Type": "Sort",
            "Parent Relationship": "Outer",
            "Parallel Aware": false,
            "Async Capable": false,
            "Startup Cost": 99549.72,
            "Total Cost": 100776.74,
            "Plan Rows": 490808,
            "Plan Width": 44,
            "Actual Startup Time": 1000.848,
            "Actual Total Time": 1133.227,
            "Actual Rows": 490518,
            "Actual Loops": 1,
            "Sort Key": [
              "((date_trunc('month'::text, (ped.fecha)::timestamp with time zone))::date)",
              "c.id",
              "ped.id"
            ],
            "Sort Method": "external merge",
            "Sort Space Used": 26000,
            "Sort Space Type": "Disk",
            "Shared Hit Blocks": 10506,
            "Shared Read Blocks": 0,
            "Shared Dirtied Blocks": 0,
            "Shared Written Blocks": 0,
            "Local Hit Blocks": 0,
            "Local Read Blocks": 0,
            "Local Dirtied Blocks": 0,
            "Local Written Blocks": 0,
            "Temp Read Blocks": 5251,
            "Temp Written Blocks": 5261,
            "Plans": [
              {
                "Node Type": "Hash Join",
                "Parent Relationship": "Outer",
                "Parallel Aware": false,
                "Async Capable": false,
                "Join Type": "Inner",
                "Startup Cost": 11390.34,
                "Total Cost": 38057.58,
                "Plan Rows": 490808,
                "Plan Width": 44,
                "Actual Startup Time": 74.192,
                "Actual Total Time": 641.31,
                "Actual Rows": 490518,
                "Actual Loops": 1,
                "Inner Unique": true,
                "Hash Cond": "(pr.categoria_id = c.id)",
                "Shared Hit Blocks": 10503,
                "Shared Read Blocks": 0,
                "Shared Dirtied Blocks": 0,
                "Shared Written Blocks": 0,
                "Local Hit Blocks": 0,
                "Local Read Blocks": 0,
                "Local Dirtied Blocks": 0,
                "Local Written Blocks": 0,
                "Temp Read Blocks": 2001,
                "Temp Written Blocks": 2001,
                "Plans": [
                  {
                    "Node Type": "Hash Join",
                    "Parent Relationship": "Outer",
                    "Parallel Aware": false,
                    "Async Capable": false,
                    "Join Type": "Inner",
                    "Startup Cost": 11389.16,
                    "Total Cost": 32404.44,
                    "Plan Rows": 490808,
                    "Plan Width": 32,
                    "Actual Startup Time": 74.145,
                    "Actual Total Time": 476.349,
                    "Actual Rows": 490518,
                    "Actual Loops": 1,
                    "Inner Unique": true,
                    "Hash Cond": "(dp.producto_id = pr.id)",
                    "Shared Hit Blocks": 10502,
                    "Shared Read Blocks": 0,
                    "Shared Dirtied Blocks": 0,
                    "Shared Written Blocks": 0,
                    "Local Hit Blocks": 0,
                    "Local Read Blocks": 0,
                    "Local Dirtied Blocks": 0,
                    "Local Written Blocks": 0,
                    "Temp Read Blocks": 2001,
                    "Temp Written Blocks": 2001,
                    "Plans": [
                      {
                        "Node Type": "Hash Join",
                        "Parent Relationship": "Outer",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Join Type": "Inner",
                        "Startup Cost": 9371.16,
                        "Total Cost": 29097.96,
                        "Plan Rows": 490808,
                        "Plan Width": 32,
                        "Actual Startup Time": 61.578,
                        "Actual Total Time": 324.382,
                        "Actual Rows": 490518,
                        "Actual Loops": 1,
                        "Inner Unique": true,
                        "Hash Cond": "(dp.pedido_id = ped.id)",
                        "Shared Hit Blocks": 9609,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 2001,
                        "Temp Written Blocks": 2001,
                        "Plans": [
                          {
                            "Node Type": "Seq Scan",
                            "Parent Relationship": "Outer",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Relation Name": "detalle_pedido",
                            "Alias": "dp",
                            "Startup Cost": 0,
                            "Total Cost": 10682,
                            "Plan Rows": 495533,
                            "Plan Width": 28,
                            "Actual Startup Time": 0.03,
                            "Actual Total Time": 65.771,
                            "Actual Rows": 495327,
                            "Actual Loops": 1,
                            "Filter": "(NOT eliminado)",
                            "Rows Removed by Filter": 4673,
                            "Shared Hit Blocks": 5682,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 0
                          },
                          {
                            "Node Type": "Hash",
                            "Parent Relationship": "Inner",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Startup Cost": 5927,
                            "Total Cost": 5927,
                            "Plan Rows": 198093,
                            "Plan Width": 12,
                            "Actual Startup Time": 61.228,
                            "Actual Total Time": 61.229,
                            "Actual Rows": 198059,
                            "Actual Loops": 1,
                            "Hash Buckets": 262144,
                            "Original Hash Buckets": 262144,
                            "Hash Batches": 2,
                            "Original Hash Batches": 2,
                            "Peak Memory Usage": 6706,
                            "Shared Hit Blocks": 3927,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 433,
                            "Plans": [
                              {
                                "Node Type": "Seq Scan",
                                "Parent Relationship": "Outer",
                                "Parallel Aware": false,
                                "Async Capable": false,
                                "Relation Name": "pedido",
                                "Alias": "ped",
                                "Startup Cost": 0,
                                "Total Cost": 5927,
                                "Plan Rows": 198093,
                                "Plan Width": 12,
                                "Actual Startup Time": 0.02,
                                "Actual Total Time": 27.052,
                                "Actual Rows": 198059,
                                "Actual Loops": 1,
                                "Filter": "(NOT eliminado)",
                                "Rows Removed by Filter": 1941,
                                "Shared Hit Blocks": 3927,
                                "Shared Read Blocks": 0,
                                "Shared Dirtied Blocks": 0,
                                "Shared Written Blocks": 0,
                                "Local Hit Blocks": 0,
                                "Local Read Blocks": 0,
                                "Local Dirtied Blocks": 0,
                                "Local Written Blocks": 0,
                                "Temp Read Blocks": 0,
                                "Temp Written Blocks": 0
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "Node Type": "Hash",
                        "Parent Relationship": "Inner",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Startup Cost": 1393,
                        "Total Cost": 1393,
                        "Plan Rows": 50000,
                        "Plan Width": 16,
                        "Actual Startup Time": 12.462,
                        "Actual Total Time": 12.462,
                        "Actual Rows": 50000,
                        "Actual Loops": 1,
                        "Hash Buckets": 65536,
                        "Original Hash Buckets": 65536,
                        "Hash Batches": 1,
                        "Original Hash Batches": 1,
                        "Peak Memory Usage": 2856,
                        "Shared Hit Blocks": 893,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 0,
                        "Temp Written Blocks": 0,
                        "Plans": [
                          {
                            "Node Type": "Seq Scan",
                            "Parent Relationship": "Outer",
                            "Parallel Aware": false,
                            "Async Capable": false,
                            "Relation Name": "producto",
                            "Alias": "pr",
                            "Startup Cost": 0,
                            "Total Cost": 1393,
                            "Plan Rows": 50000,
                            "Plan Width": 16,
                            "Actual Startup Time": 0.012,
                            "Actual Total Time": 7.197,
                            "Actual Rows": 50000,
                            "Actual Loops": 1,
                            "Shared Hit Blocks": 893,
                            "Shared Read Blocks": 0,
                            "Shared Dirtied Blocks": 0,
                            "Shared Written Blocks": 0,
                            "Local Hit Blocks": 0,
                            "Local Read Blocks": 0,
                            "Local Dirtied Blocks": 0,
                            "Local Written Blocks": 0,
                            "Temp Read Blocks": 0,
                            "Temp Written Blocks": 0
                          }
                        ]
                      }
                    ]
                  },
                  {
                    "Node Type": "Hash",
                    "Parent Relationship": "Inner",
                    "Parallel Aware": false,
                    "Async Capable": false,
                    "Startup Cost": 1.08,
                    "Total Cost": 1.08,
                    "Plan Rows": 8,
                    "Plan Width": 20,
                    "Actual Startup Time": 0.022,
                    "Actual Total Time": 0.023,
                    "Actual Rows": 8,
                    "Actual Loops": 1,
                    "Hash Buckets": 1024,
                    "Original Hash Buckets": 1024,
                    "Hash Batches": 1,
                    "Original Hash Batches": 1,
                    "Peak Memory Usage": 9,
                    "Shared Hit Blocks": 1,
                    "Shared Read Blocks": 0,
                    "Shared Dirtied Blocks": 0,
                    "Shared Written Blocks": 0,
                    "Local Hit Blocks": 0,
                    "Local Read Blocks": 0,
                    "Local Dirtied Blocks": 0,
                    "Local Written Blocks": 0,
                    "Temp Read Blocks": 0,
                    "Temp Written Blocks": 0,
                    "Plans": [
                      {
                        "Node Type": "Seq Scan",
                        "Parent Relationship": "Outer",
                        "Parallel Aware": false,
                        "Async Capable": false,
                        "Relation Name": "categoria",
                        "Alias": "c",
                        "Startup Cost": 0,
                        "Total Cost": 1.08,
                        "Plan Rows": 8,
                        "Plan Width": 20,
                        "Actual Startup Time": 0.015,
                        "Actual Total Time": 0.016,
                        "Actual Rows": 8,
                        "Actual Loops": 1,
                        "Shared Hit Blocks": 1,
                        "Shared Read Blocks": 0,
                        "Shared Dirtied Blocks": 0,
                        "Shared Written Blocks": 0,
                        "Local Hit Blocks": 0,
                        "Local Read Blocks": 0,
                        "Local Dirtied Blocks": 0,
                        "Local Written Blocks": 0,
                        "Temp Read Blocks": 0,
                        "Temp Written Blocks": 0
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 389,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 2.007,
  "Triggers": [],
  "Execution Time": 1230.916
}
```

</details>

<details>
<summary>Lectura materializada solicitada / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 11.2,
    "Total Cost": 11.68,
    "Plan Rows": 192,
    "Plan Width": 278,
    "Actual Startup Time": 0.056,
    "Actual Total Time": 0.06,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "categoria_id",
      "mes"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 38,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 8,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "mv_facturacion_categoria_mes",
        "Alias": "mv_facturacion_categoria_mes",
        "Startup Cost": 0,
        "Total Cost": 3.92,
        "Plan Rows": 192,
        "Plan Width": 278,
        "Actual Startup Time": 0.008,
        "Actual Total Time": 0.015,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 88,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.391,
  "Triggers": [],
  "Execution Time": 0.084
}
```

</details>

<details>
<summary>Lectura materializada solicitada / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 11.2,
    "Total Cost": 11.68,
    "Plan Rows": 192,
    "Plan Width": 278,
    "Actual Startup Time": 0.11,
    "Actual Total Time": 0.117,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "categoria_id",
      "mes"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 38,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 8,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "mv_facturacion_categoria_mes",
        "Alias": "mv_facturacion_categoria_mes",
        "Startup Cost": 0,
        "Total Cost": 3.92,
        "Plan Rows": 192,
        "Plan Width": 278,
        "Actual Startup Time": 0.012,
        "Actual Total Time": 0.025,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 88,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.421,
  "Triggers": [],
  "Execution Time": 0.16
}
```

</details>

<details>
<summary>Lectura materializada mismo orden / corrida 2</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 11.2,
    "Total Cost": 11.68,
    "Plan Rows": 192,
    "Plan Width": 278,
    "Actual Startup Time": 0.164,
    "Actual Total Time": 0.171,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "mes",
      "facturacion_total DESC"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 38,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 8,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "mv_facturacion_categoria_mes",
        "Alias": "mv_facturacion_categoria_mes",
        "Startup Cost": 0,
        "Total Cost": 3.92,
        "Plan Rows": 192,
        "Plan Width": 278,
        "Actual Startup Time": 0.016,
        "Actual Total Time": 0.029,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 96,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.584,
  "Triggers": [],
  "Execution Time": 0.257
}
```

</details>

<details>
<summary>Lectura materializada mismo orden / corrida 3</summary>

```json
{
  "Plan": {
    "Node Type": "Sort",
    "Parallel Aware": false,
    "Async Capable": false,
    "Startup Cost": 11.2,
    "Total Cost": 11.68,
    "Plan Rows": 192,
    "Plan Width": 278,
    "Actual Startup Time": 0.119,
    "Actual Total Time": 0.124,
    "Actual Rows": 192,
    "Actual Loops": 1,
    "Sort Key": [
      "mes",
      "facturacion_total DESC"
    ],
    "Sort Method": "quicksort",
    "Sort Space Used": 38,
    "Sort Space Type": "Memory",
    "Shared Hit Blocks": 8,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0,
    "Plans": [
      {
        "Node Type": "Seq Scan",
        "Parent Relationship": "Outer",
        "Parallel Aware": false,
        "Async Capable": false,
        "Relation Name": "mv_facturacion_categoria_mes",
        "Alias": "mv_facturacion_categoria_mes",
        "Startup Cost": 0,
        "Total Cost": 3.92,
        "Plan Rows": 192,
        "Plan Width": 278,
        "Actual Startup Time": 0.009,
        "Actual Total Time": 0.019,
        "Actual Rows": 192,
        "Actual Loops": 1,
        "Shared Hit Blocks": 2,
        "Shared Read Blocks": 0,
        "Shared Dirtied Blocks": 0,
        "Shared Written Blocks": 0,
        "Local Hit Blocks": 0,
        "Local Read Blocks": 0,
        "Local Dirtied Blocks": 0,
        "Local Written Blocks": 0,
        "Temp Read Blocks": 0,
        "Temp Written Blocks": 0
      }
    ]
  },
  "Planning": {
    "Shared Hit Blocks": 96,
    "Shared Read Blocks": 0,
    "Shared Dirtied Blocks": 0,
    "Shared Written Blocks": 0,
    "Local Hit Blocks": 0,
    "Local Read Blocks": 0,
    "Local Dirtied Blocks": 0,
    "Local Written Blocks": 0,
    "Temp Read Blocks": 0,
    "Temp Written Blocks": 0
  },
  "Planning Time": 0.4,
  "Triggers": [],
  "Execution Time": 0.189
}
```

</details>

## Anexo B. Bootstrap y carga realmente ejecutados

Copias documentales del contenido temporal usado, no nuevos scripts entregables. Deben leerse con sus supuestos de laboratorio y aplicarse únicamente a una base vacía y autorizada.

<details>
<summary>Bootstrap temporal</summary>

```sql
-- Bootstrap temporal de laboratorio TP5: no reemplaza schema.sql del repositorio.
-- Solo para una base vacia foodstore_tp5_oficial; ejecutar con ON_ERROR_STOP=1.
-- Supuestos de laboratorio para atributos no tipados por el contrato:
-- textos VARCHAR/TEXT, celular VARCHAR(30), created_at TIMESTAMPTZ;
-- nombres, mail, contrasena, rol, claves, importes y booleanos NOT NULL;
-- descripcion, imagen y celular opcionales. No se asume unicidad de lower(mail).

CREATE TYPE rol AS ENUM ('ADMIN', 'USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO');
CREATE TYPE forma_pago AS ENUM ('TARJETA', 'TRANSFERENCIA', 'EFECTIVO');

CREATE TABLE categoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE usuario (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    apellido VARCHAR(120) NOT NULL,
    mail VARCHAR(255) NOT NULL UNIQUE,
    celular VARCHAR(30),
    contrasena VARCHAR(255) NOT NULL,
    rol rol NOT NULL DEFAULT 'USUARIO',
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE producto (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    precio NUMERIC(12,2) NOT NULL CHECK (precio >= 0),
    descripcion TEXT,
    stock INTEGER NOT NULL CHECK (stock >= 0),
    imagen TEXT,
    disponible BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id BIGINT NOT NULL REFERENCES categoria(id),
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE NOT NULL,
    estado estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    forma_pago forma_pago NOT NULL,
    usuario_id BIGINT NOT NULL REFERENCES usuario(id),
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE detalle_pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    pedido_id BIGINT NOT NULL REFERENCES pedido(id),
    producto_id BIGINT NOT NULL REFERENCES producto(id),
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (pedido_id, producto_id)
);

-- Indices base declarados preexistentes por la catedra, no candidatos TP5.
CREATE INDEX idx_producto_categoria ON producto(categoria_id);
CREATE INDEX idx_pedido_usuario ON pedido(usuario_id);
CREATE INDEX idx_producto_nombre_vig ON producto(nombre) WHERE eliminado = FALSE;
```

</details>

<details>
<summary>Carga determinista temporal</summary>

```sql
-- Carga sintetica determinista de laboratorio TP5, no dataset oficial entregable.
-- Requiere bootstrap vacio. Orden explicito para identidades reproducibles.
-- No modifica secuencias manualmente. VACUUM debe ejecutarse fuera de transaccion.
BEGIN;

-- Una categoria eliminada entre ocho: minimo no nulo posible (12,5 %).
INSERT INTO categoria (nombre, descripcion, eliminado)
SELECT 'Categoria ' || g, 'Categoria sintetica de laboratorio ' || g, g = 8
FROM generate_series(1, 8) AS s(g)
ORDER BY g;

INSERT INTO producto (nombre, precio, descripcion, stock, imagen, disponible,
                      categoria_id, eliminado)
SELECT 'Producto ' || lpad(g::text, 5, '0'),
       (100 + (g::bigint * 137) % 999900)::numeric / 100,
       'Producto sintetico de laboratorio ' || g,
       (g * 17) % 201,
       NULL,
       g % 20 <> 0,
       1 + (g - 1) % 8,
       g % 97 = 0
FROM generate_series(1, 50000) AS s(g)
ORDER BY g;

INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, eliminado)
SELECT 'Nombre ' || g, 'Apellido ' || g,
       'usuario' || g || '@foodstore.test',
       '54911' || lpad(g::text, 8, '0'),
       'hash_de_prueba',
       g % 101 = 0
FROM generate_series(1, 20000) AS s(g)
ORDER BY g;

INSERT INTO pedido (fecha, estado, forma_pago, usuario_id, eliminado)
SELECT CURRENT_DATE - ((g - 1) % 720),
       (ARRAY['PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO']::estado_pedido[])
           [1 + (g - 1) % 4],
       (ARRAY['TARJETA', 'TRANSFERENCIA', 'EFECTIVO']::forma_pago[])
           [1 + (g - 1) % 3],
       1 + (g::bigint * 7919) % 20000,
       g % 103 = 0
FROM generate_series(1, 200000) AS s(g)
ORDER BY g;

-- Cada grupo de cuatro pedidos tiene 1+2+3+4 = 10 detalles: 500000 exactos.
-- El paso 7919 produce hasta cuatro productos distintos por pedido modulo 50000.
INSERT INTO detalle_pedido (cantidad, precio_unitario, subtotal, pedido_id,
                            producto_id, eliminado)
SELECT 1 + (ped.id + posicion.n) % 5,
       pr.precio,
       (1 + (ped.id + posicion.n) % 5) * pr.precio,
       ped.id,
       pr.id,
       (ped.id * 31 + posicion.n) % 107 = 0
FROM pedido ped
CROSS JOIN LATERAL generate_series(1, (1 + (ped.id - 1) % 4)::integer) AS posicion(n)
JOIN producto pr ON pr.id = (ped.id * 17 + posicion.n * 7919) % 50000 + 1
ORDER BY ped.id, posicion.n;

-- Conserva cero por default si un pedido no tiene detalles no eliminados.
UPDATE pedido p
SET total = x.total
FROM (
    SELECT pedido_id, SUM(subtotal) AS total
    FROM detalle_pedido
    WHERE eliminado = FALSE
    GROUP BY pedido_id
) x
WHERE x.pedido_id = p.id;

COMMIT;
VACUUM ANALYZE;
```

</details>

## Anexo C. Registro de fases

| Fase | Finalización UTC |
| --- | --- |
| bootstrap | 2026-09-21T00:01:40.145Z |
| reads | 2026-09-21T00:02:05.183Z |
| writes | 2026-09-21T00:02:25.484Z |
| views | 2026-09-21T00:03:07.836Z |
| security | 2026-09-21T00:03:09.446Z |
| materialized | 2026-09-21T00:03:25.950Z |

Los archivos base SQL/specs del Bloque 1 y toda evidencia histórica permanecen fuera del alcance de escritura de este documento. La comprobación Git final se realiza separadamente por comparación contra el estado inicial del bloque; no se declara aquí una limpieza del working tree, que ya contenía cambios autorizados.

## Protección del repositorio

La validación final comparó 71 rutas preexistentes contra el estado inicial del bloque: 68 archivos presentes conservaron su SHA-256 y tres rutas previamente ausentes continuaron ausentes. Todas permanecieron intactas. El SHA-256 de `.git/index` también se mantuvo idéntico.

El único archivo agregado durante este bloque fue `unidades/unidad-3/informes/evidencia_modelo_oficial.md`. La comprobación se realizó mediante un script Node; no representa una prueba SQL ni implica que el working tree esté limpio, porque conserva los cambios autorizados del Bloque 1.
