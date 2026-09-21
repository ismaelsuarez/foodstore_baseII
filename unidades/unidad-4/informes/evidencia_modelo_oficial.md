# Unidad 4 — Evidencia real sobre el modelo oficial

## Resultado y alcance

La reconstrucción FNBC y las equivalencias de desnormalización dieron **0 diferencias en ambos sentidos**. Las tres pruebas reversibles de triggers fueron satisfactorias, incluida la protección frente a la modificación directa de la categoría redundante.

La mediana de lectura pasó de **200.392 ms** a **196.507 ms** (-1.94 %), pero aumentaron los buffers y la dispersión. **No se demuestra una mejora de rendimiento robusta** con estas cinco corridas por variante. El costo de escritura se informa por separado, sin trasladar resultados de TP5 ni de la iteración histórica de Unidad 4.

Ejecución exclusiva sobre la copia descartable `foodstore_u4_oficial`. Este archivo agrega evidencia nueva; no reemplaza ni modifica [el informe histórico](informe_u4_fnbc_desnormalizacion.md). Los scripts y specs conservan su estado documental del Bloque 1; los resultados ejecutados pertenecen a este documento.

## 1. Entorno y aislamiento

| Dato | Valor observado |
|---|---|
| Motor | PostgreSQL 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| Fecha SQL | 2026-09-20 |
| Inicio registrado | 2026-09-20T21:46:25.611475-03:00 |
| Zona horaria | America/Buenos_Aires |
| Base medida | foodstore_u4_oficial |
| Base fuente | foodstore_tp5_oficial |
| Conexión local | 127.0.0.1:5432, usuario postgres; autenticación pgpass/PGPASSFILE |
| work_mem | 4MB |
| shared_buffers | 128MB |
| max_parallel_workers_per_gather | 2 |

Se creó la copia mediante `CREATE DATABASE ... TEMPLATE foodstore_tp5_oficial` exitosamente. No fue necesario terminar conexiones ni usar un dump alternativo. La única base autorizada para eliminación/recreación fue `foodstore_u4_oficial`; la fuente no se modificó. Las ejecuciones SQL emplearon `psql -X -w` y `ON_ERROR_STOP=1`.

Los índices y objetos de TP5 presentes en la fuente se clonaron y conservaron. En particular, `idx_pedido_fecha_reciente` intervino en ambas consultas mediante Index Only Scan. No se borraron índices base para favorecer una variante. La materializada heredada de TP5 quedó fuera del ensayo: tras la carga adicional puede estar desactualizada; no se consultó ni refrescó.

### Modelo verificado antes de intervenir

- `usuario` preexistía; se comprobaron los responsables 801 y 802 sin alterar sus datos.
- `pedido.fecha` es DATE; existen `estado`, `total`, `usuario_id` y `eliminado`.
- `detalle_pedido` contiene su PK `id`, las dos FK, `cantidad`, `precio_unitario`, `subtotal` físico y `eliminado`.
- `producto` contiene `categoria_id`, `disponible` y `eliminado`.
- `detalle_pedido.categoria_id` **no existía** antes de aplicar la desnormalización.

El inventario completo de columnas e índices se conserva en el apéndice A.

## 2. Dataset y volumen del día

| Tabla | Fuente / copia inicial | Copia tras la carga |
|---|---:|---:|
| categoria | 8 | 8 |
| producto | 50000 | 50000 |
| usuario | 20000 | 20000 |
| pedido | 200000 | 220000 |
| detalle_pedido | 500000 | 550000 |

| Volumen vigente de CURRENT_DATE | Antes | Después |
|---|---:|---:|
| Pedidos | 275 | 20275 |
| Detalles de esos pedidos | 272 | 50272 |

El volumen inicial no alcanzaba los mínimos de 10000 pedidos y 20000 detalles vigentes del día. Se agregaron **20000 pedidos y 50000 detalles** exclusivamente en la copia. Se reutilizaron usuarios y productos existentes, los ENUM oficiales, de uno a cuatro productos distintos por pedido y `subtotal = cantidad * precio_unitario` al generar los datos. Esa expresión es la regla de carga, no sustituye la columna física en las consultas medidas.

Se reconciliaron los totales de los pedidos nuevos desde sus detalles no eliminados y se ejecutó `VACUUM ANALYZE`. La carga exacta está en el apéndice B. Los ensayos individuales de INSERT y UPDATE finalizaron con ROLLBACK; la prueba concurrente confirmó ambas transacciones y restauró la categoría original con el segundo UPDATE. No agregaron filas persistentes.

## 3. Parte 1 — FNBC

Se aplicó íntegramente [tp_fnbc_control_lote.sql](../sql/tp_fnbc_control_lote.sql) con parada ante errores.

| Comprobación | Resultado |
|---|---:|
| Usuario 801 eliminado | FALSE |
| Usuario 802 eliminado | FALSE |
| Violaciones observadas de ResponsableControlID → DepositoID | 0 |
| Filas de control_lote_almacen | 3 |
| Filas de v_control_lote_almacen | 3 |
| Original EXCEPT vista | 0 |
| Vista EXCEPT original | 0 |

Se preserva la descomposición conceptual en `responsable_control_deposito` y `control_lote_responsable`. El diagnóstico sin filas prueba que estos datos satisfacen la dependencia; no elimina la violación conceptual de FNBC en la relación original.

La tabla `usuario` no fue creada ni eliminada: su OID fue **16850 antes y 16850 después**. Su conteo se mantuvo en 20000; la huella MD5 del conjunto ordenado de filas fue idéntica antes y después: `b2c8d21531136b2981e3ac072cc235ff`. La huella es un control técnico de no alteración, no una garantía criptográfica contra manipulación deliberada.

## 4. Consultas y protocolo de lectura

### Consulta normalizada exacta

```sql
SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
JOIN categoria c
    ON c.id = pr.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

### Consulta desnormalizada exacta

```sql
SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c
    ON c.id = dp.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

Ambas suman `dp.subtotal` y excluyen solamente pedidos/detalles eliminados. No filtran por la baja actual de producto/categoría ni por disponibilidad: una baja lógica posterior no debe ocultar ventas. La categoría sigue siendo la **actual del producto**, no una fotografía de la categoría al vender.

Se ejecutó `ANALYZE` sobre detalle_pedido, pedido, producto y categoria antes del baseline. Tras aplicar la desnormalización y realizar las pruebas reversibles A/B/C se ejecutó `ANALYZE detalle_pedido` antes de la serie posterior. Cada SELECT se midió mediante `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` cinco veces. **Se conservaron las cinco; ninguna se descartó como calentamiento ni como outlier.**

Las estadísticas siguientes usan `Execution Time` del plan, no tiempo de pared de psql ni tiempo de planificación. Los buffers se leen del nodo raíz: son acumulados del plan, **no se suman otra vez los nodos hijos**. `hit + read` no representa bloques únicos ni accesos físicos al disco: read puede satisfacerse desde caché del sistema operativo.

### Cinco corridas normalizadas

| Corrida | Execution Time (ms) | Shared hit | Shared read | hit + read | Temp read / written |
|---|---:|---:|---:|---:|---:|
| 1 | 191.465 | 5505 | 2877 | 8382 | 0 / 0 |
| 2 | 188.192 | 5537 | 2845 | 8382 | 0 / 0 |
| 3 | 210.285 | 5569 | 2813 | 8382 | 0 / 0 |
| 4 | 237.785 | 5601 | 2781 | 8382 | 0 / 0 |
| 5 | 200.392 | 5633 | 2749 | 8382 | 0 / 0 |

Mediana: **200.392 ms**; mínimo: **188.192 ms**; máximo: **237.785 ms**.

### Cinco corridas desnormalizadas

| Corrida | Execution Time (ms) | Shared hit | Shared read | hit + read | Temp read / written |
|---|---:|---:|---:|---:|---:|
| 1 | 174.459 | 10652 | 2734 | 13386 | 0 / 0 |
| 2 | 177.794 | 10716 | 2670 | 13386 | 0 / 0 |
| 3 | 287.053 | 10780 | 2606 | 13386 | 0 / 0 |
| 4 | 196.507 | 10844 | 2542 | 13386 | 0 / 0 |
| 5 | 307.298 | 10908 | 2478 | 13386 | 0 / 0 |

Mediana: **196.507 ms**; mínimo: **174.459 ms**; máximo: **307.298 ms**. Las corridas de 287.053 y 307.298 ms permanecen visibles y forman parte del cálculo.

### Comparación y estructura de planes

| Medida | Normalizada | Desnormalizada | Cambio |
|---|---:|---:|---:|
| Mediana (ms) | 200.392 | 196.507 | -1.94 % |
| Mínimo (ms) | 188.192 | 174.459 | No se usa como estimación principal |
| Máximo (ms) | 237.785 | 307.298 | Mayor dispersión posterior |
| Shared hit + read por corrida | 8382 | 13386 | +5004 (+59.70 %) |
| Shared dirtied / written | 0 / 0 | 0 / 0 | Sin cambio |
| Temp read / written | 0 / 0 | 0 / 0 | Sin derrame temporal observado |

El nodo raíz es Limit con cinco filas. Ambas variantes contienen Sort (quicksort en memoria, 25 kB), agregación parcial/final, Gather Merge y joins hash paralelos; usan Seq Scan paralelo sobre detalle_pedido e Index Only Scan sobre pedido con `idx_pedido_fecha_reciente` y cero Heap Fetches. Se planificaron/lanzaron dos workers. La normalizada agrega el acceso y join a producto; la desnormalizada lo elimina, pero no evita el recorrido de detalle_pedido.

Después del backfill, ese recorrido registró 13040 accesos de bloques (hit + read) frente a 6250 antes. El UPDATE masivo genera versiones de filas y modifica el estado físico; se usó ANALYZE, no una reescritura/compactación de la tabla antes del post. Esto es una explicación compatible con los planes, **no una medición aislada de cuánto explica cada factor**. No se ejecutaron pruebas adicionales para seleccionar un resultado más favorable.

El orden fijo de las series, las cachés y la variación de ejecución limitan la comparación. La reducción nominal de mediana de 3.885 ms es pequeña frente a los rangos observados. Eliminar un JOIN no garantiza reducir tiempo ni buffers: este ensayo no respalda presentar la desnormalización como una optimización demostrada.

## 5. Backfill, restricciones y equivalencia

La salida real del script registró **UPDATE 550000**. Tras la migración:

| Control | Resultado |
|---|---:|
| Filas backfilled | 550000 |
| categoria_id NULL | 0 |
| Categorías desincronizadas | 0 |
| Original EXCEPT desnormalizada, todos los grupos | 0 |
| Desnormalizada EXCEPT original, todos los grupos | 0 |
| Original EXCEPT desnormalizada, Top 5 exacto | 0 |
| Desnormalizada EXCEPT original, Top 5 exacto | 0 |

`detalle_pedido.categoria_id` quedó BIGINT NOT NULL, con `fk_detalle_pedido_categoria` hacia categoria(id), ON DELETE RESTRICT. Ambas funciones y ambos triggers quedaron instalados. Producto continúa siendo la autoridad del dato redundante.

### Top 5 real de ambas consultas

| Categoría | Normalizada | Desnormalizada |
|---|---:|---:|
| Categoria 2 | 74012172.86 | 74012172.86 |
| Categoria 4 | 73941825.52 | 73941825.52 |
| Categoria 8 | 73745739.16 | 73745739.16 |
| Categoria 6 | 73638187.98 | 73638187.98 |
| Categoria 1 | 53087359.45 | 53087359.45 |

El EXCEPT completo evita depender del LIMIT para probar equivalencia de agregados. También se comprobó el Top 5 exacto del ensayo. La consulta no incorpora desempate: otros datos podrían producir selecciones diferentes e igualmente válidas si hay empates en el límite.

## 6. Pruebas reversibles de triggers

Las tres pruebas se ejecutaron dentro de BEGIN/ROLLBACK, con IDs seleccionados desde los datos reales.

| Prueba | IDs y cambio ensayado | Observación | Estado |
|---|---|---|---|
| A — cambio de producto del detalle | Detalle 1, pedido 1: producto 7937/categoría 1 → producto 2/categoría 2; sin conflicto UNIQUE | Categoría almacenada 2 = categoría real 2 | PASS |
| B — cambio de categoría del producto | Producto 1: categoría 1 → 2; 16 detalles asociados | Los 16 quedaron en categoría 2; auditoría global 0 | PASS |
| C — manipulación directa | Detalle 1: intento de imponer categoría 2, cuando su producto requiere 1 | El trigger restauró categoría 1 | PASS |

**DIRECT_TAMPERING_PROTECTED = YES**, para DML ordinario con los triggers habilitados. No implica protección contra un administrador que los desactive. El trigger de detalle asigna NEW sin ejecutar un UPDATE recursivo; el trigger de producto propaga a detalles y estos vuelven a derivar el mismo valor.

La auditoría fuera de esas transacciones arrojó **0 desincronizaciones**:

```sql
SELECT count(*) FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id
```

## 7. Escritura, propagación y concurrencia

### INSERT de 1000 detalles: costo incremental del trigger

Se preparó, dentro de cada transacción, el mismo fixture de 1000 pedidos existentes y 1000 productos distintos, sin conflictos con UNIQUE(pedido_id, producto_id). La huella del fixture fue `7afa38d2afe9873b2d8d70509e3a034b`. Ambos INSERT proporcionaron la categoría correcta; con el trigger habilitado, este la volvió a derivar desde producto.

La variante sin trigger deshabilitó **solamente** `trg_detalle_pedido_set_categoria` dentro de BEGIN/ROLLBACK. Se mantuvieron NOT NULL, UNIQUE y todas las FK, incluida la de categoría; no se desactivaron restricciones base. El trigger de producto no interviene al insertar detalles. ROLLBACK revirtió tanto las filas insertadas como la deshabilitación temporal.

El tiempo medido corresponde al INSERT mediante EXPLAIN ANALYZE, sin incluir la preparación del fixture ni ALTER TABLE. Las variantes se alternaron sin/con por cada número de corrida. Se conservó una corrida de calentamiento y se promediaron las dos siguientes:

| Corrida | Sin trigger (ms) | Con trigger (ms) | Uso |
|---|---:|---:|---|
| 1 | 32.939 | 27.763 | Calentamiento; no integra el promedio |
| 2 | 21.301 | 28.342 | Válida |
| 3 | 21.376 | 29.261 | Válida |
| Promedio de 2 y 3 | **21.3385** | **28.8015** | **+34.97 %** |

El incremento observado fue **7.4630 ms por lote de 1000 detalles**. El trigger registró 1000 llamadas por corrida, con 5.309 y 4.735 ms en las dos válidas. Ese tiempo interno no es igual a la diferencia total entre ejecuciones: también varían los otros costos y el estado de caché.

Esto estima el costo incremental del trigger de detalle sobre el esquema ya desnormalizado; **no mide todo el costo de agregar la columna y su FK** frente al esquema original. La preparación equivalente del fixture excluye de ambos tiempos la obtención previa de los datos de prueba. No es una extrapolación universal a cualquier patrón de INSERT.

Los conteos antes/después fueron idénticos: 220000 pedidos y 550000 detalles. Los triggers de categoría y los triggers internos de FK quedaron habilitados (tgenabled = O). Los seis INSERT revertidos consumieron valores identity; no se reajustaron secuencias para ocultar ese efecto.

### UPDATE de producto y propagación

| Medida | Resultado |
|---|---|
| Producto seleccionado dinámicamente | 17 |
| Categoría original → temporal | 1 → 2 |
| Detalles asociados / propagados | 18 / 18 |
| Execution Time del UPDATE | 57.540 ms |
| Tiempo registrado del trigger de propagación | 56.662 ms; 1 llamada |
| Auditoría global en la verificación | 0 |

Se hizo una sola medición de costo y, por separado, una verificación funcional de las filas propagadas. Ambas transacciones finalizaron con ROLLBACK. **57.540 ms es una observación puntual**, no una mediana ni una curva de escalabilidad. El costo incluye mantener la coherencia de detalles históricos del producto; una distribución con más detalles puede tener un costo distinto.

### Concurrencia mínima real

**CONCURRENCY_TEST = PASS**. Se abrieron dos sesiones PostgreSQL propias y controladas sobre el mismo producto 17; no se terminaron sesiones ajenas ni se provocó un deadlock.

1. La sesión A, PID 2228, cambió categoría 1 → 2 y mantuvo la transacción abierta.
2. La sesión B, PID 21896, intentó cambiar el mismo producto a categoría 1.
3. pg_stat_activity confirmó B esperando **Lock / transactionid**, con pg_blocking_pids = [2228].
4. A confirmó COMMIT; B pudo completar su UPDATE y COMMIT. Así quedó restaurada la categoría original 1.
5. Tras ambas transacciones: **18 detalles** con categoría 1 y **0 desincronizaciones globales**. Las dos sesiones terminaron con código 0 y stderr vacío.

La prueba acredita serialización del caso **dos UPDATE sobre el mismo producto**. No prueba todas las carreras posibles: en particular, **INSERT de detalle concurrente con cambio de categoría del producto no fue ensayado**. No se concluye que los triggers garanticen por sí solos toda la integridad bajo cualquier intercalación.

### Auditoría y cierre de ejecución

| Control final | Resultado |
|---|---:|
| Desincronizaciones globales en la copia | 0 |
| Filas detalle_pedido en la copia | 550000 |
| Usuarios en la copia | 20000 |
| OID usuario en la copia | 16850 |
| Filas detalle_pedido en la fuente | 500000 |
| Columnas categoria_id en detalle_pedido de la fuente | 0 |
| Errores SQL | 0 |

Los conteos finales de la fuente coinciden con los iniciales. Su huella de usuario permaneció `b2c8d21531136b2981e3ac072cc235ff`, igual a la inicial y a la de la copia. No se creó la columna redundante en la fuente. Todos los archivos stderr de las ejecuciones capturadas estuvieron vacíos y los procesos psql completaron sin error.

**Conclusión:** FNBC, equivalencia, triggers A/B/C y concurrencia mínima: satisfactorios. La lectura no presenta una mejora robusta; los buffers aumentan y el INSERT tiene una penalización medida. La desnormalización se conserva en la copia como ejercicio validado funcionalmente, no como recomendación automática de producción ni como optimización aprobada para cualquier carga. No se ejecutó reversión permanente.

## 8. Reversibilidad y reservas

No se ejecutó DOWN. La validación estática del orden documentado permite eliminar primero cada trigger y luego su función; a continuación la FK redundante y, por último, detalle_pedido.categoria_id. No elimina ni modifica producto.categoria_id. La copia medida conserva la migración aplicada.

La evidencia demuestra equivalencia y protección en los casos ensayados, no corrección para todas las intercalaciones concurrentes ni para cualquier carga. Los valores son específicos de este dataset, esta máquina, su estado físico/caché y la fecha SQL registrada. El reporte utiliza CURRENT_DATE; repetirlo otro día sin preparar volumen adecuado cambia la carga consultada.

Las transacciones con ROLLBACK no dejan filas, pero pueden consumir valores identity y alterar cachés/estado físico. Por ello no se interpreta “reversible” como ausencia total de efectos físicos.

## 9. Protección del repositorio

La verificación final del proceso coordinador comparó SHA256 de los **71 archivos rastreados al inicio del Bloque 2**: todos permanecieron idénticos, incluidos los cinco archivos modificados durante el Bloque 1. La huella de `.git/index` también permaneció idéntica: no se realizó staging.

El único archivo nuevo de este bloque es `unidades/unidad-4/informes/evidencia_modelo_oficial.md`. No se modificaron Unidad 3, TP1–TP4, tpi/, schema.sql, datos_iniciales.sql ni el informe histórico de Unidad 4. No se hizo commit ni push.

## Apéndice A — Inventarios reales

### Columnas antes de la desnormalización

```json
[
  {
    "table_name": "categoria",
    "column_name": "id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 1
  },
  {
    "table_name": "categoria",
    "column_name": "nombre",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 2
  },
  {
    "table_name": "categoria",
    "column_name": "descripcion",
    "data_type": "text",
    "udt_name": "text",
    "is_nullable": "YES",
    "column_default": null,
    "ordinal_position": 3
  },
  {
    "table_name": "categoria",
    "column_name": "eliminado",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "false",
    "ordinal_position": 4
  },
  {
    "table_name": "categoria",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "udt_name": "timestamptz",
    "is_nullable": "NO",
    "column_default": "now()",
    "ordinal_position": 5
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 1
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "cantidad",
    "data_type": "integer",
    "udt_name": "int4",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 2
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "precio_unitario",
    "data_type": "numeric",
    "udt_name": "numeric",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 3
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "subtotal",
    "data_type": "numeric",
    "udt_name": "numeric",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 4
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "pedido_id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 5
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "producto_id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 6
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "eliminado",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "false",
    "ordinal_position": 7
  },
  {
    "table_name": "detalle_pedido",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "udt_name": "timestamptz",
    "is_nullable": "NO",
    "column_default": "now()",
    "ordinal_position": 8
  },
  {
    "table_name": "pedido",
    "column_name": "id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 1
  },
  {
    "table_name": "pedido",
    "column_name": "fecha",
    "data_type": "date",
    "udt_name": "date",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 2
  },
  {
    "table_name": "pedido",
    "column_name": "estado",
    "data_type": "USER-DEFINED",
    "udt_name": "estado_pedido",
    "is_nullable": "NO",
    "column_default": "'PENDIENTE'::estado_pedido",
    "ordinal_position": 3
  },
  {
    "table_name": "pedido",
    "column_name": "total",
    "data_type": "numeric",
    "udt_name": "numeric",
    "is_nullable": "NO",
    "column_default": "0",
    "ordinal_position": 4
  },
  {
    "table_name": "pedido",
    "column_name": "forma_pago",
    "data_type": "USER-DEFINED",
    "udt_name": "forma_pago",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 5
  },
  {
    "table_name": "pedido",
    "column_name": "usuario_id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 6
  },
  {
    "table_name": "pedido",
    "column_name": "eliminado",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "false",
    "ordinal_position": 7
  },
  {
    "table_name": "pedido",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "udt_name": "timestamptz",
    "is_nullable": "NO",
    "column_default": "now()",
    "ordinal_position": 8
  },
  {
    "table_name": "producto",
    "column_name": "id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 1
  },
  {
    "table_name": "producto",
    "column_name": "nombre",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 2
  },
  {
    "table_name": "producto",
    "column_name": "precio",
    "data_type": "numeric",
    "udt_name": "numeric",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 3
  },
  {
    "table_name": "producto",
    "column_name": "descripcion",
    "data_type": "text",
    "udt_name": "text",
    "is_nullable": "YES",
    "column_default": null,
    "ordinal_position": 4
  },
  {
    "table_name": "producto",
    "column_name": "stock",
    "data_type": "integer",
    "udt_name": "int4",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 5
  },
  {
    "table_name": "producto",
    "column_name": "imagen",
    "data_type": "text",
    "udt_name": "text",
    "is_nullable": "YES",
    "column_default": null,
    "ordinal_position": 6
  },
  {
    "table_name": "producto",
    "column_name": "disponible",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "true",
    "ordinal_position": 7
  },
  {
    "table_name": "producto",
    "column_name": "categoria_id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 8
  },
  {
    "table_name": "producto",
    "column_name": "eliminado",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "false",
    "ordinal_position": 9
  },
  {
    "table_name": "producto",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "udt_name": "timestamptz",
    "is_nullable": "NO",
    "column_default": "now()",
    "ordinal_position": 10
  },
  {
    "table_name": "usuario",
    "column_name": "id",
    "data_type": "bigint",
    "udt_name": "int8",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 1
  },
  {
    "table_name": "usuario",
    "column_name": "nombre",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 2
  },
  {
    "table_name": "usuario",
    "column_name": "apellido",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 3
  },
  {
    "table_name": "usuario",
    "column_name": "mail",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 4
  },
  {
    "table_name": "usuario",
    "column_name": "celular",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "YES",
    "column_default": null,
    "ordinal_position": 5
  },
  {
    "table_name": "usuario",
    "column_name": "contrasena",
    "data_type": "character varying",
    "udt_name": "varchar",
    "is_nullable": "NO",
    "column_default": null,
    "ordinal_position": 6
  },
  {
    "table_name": "usuario",
    "column_name": "rol",
    "data_type": "USER-DEFINED",
    "udt_name": "rol",
    "is_nullable": "NO",
    "column_default": "'USUARIO'::rol",
    "ordinal_position": 7
  },
  {
    "table_name": "usuario",
    "column_name": "eliminado",
    "data_type": "boolean",
    "udt_name": "bool",
    "is_nullable": "NO",
    "column_default": "false",
    "ordinal_position": 8
  },
  {
    "table_name": "usuario",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "udt_name": "timestamptz",
    "is_nullable": "NO",
    "column_default": "now()",
    "ordinal_position": 9
  }
]
```

### Índices clonados preexistentes

```json
[
  {
    "tablename": "categoria",
    "indexname": "categoria_nombre_key",
    "indexdef": "CREATE UNIQUE INDEX categoria_nombre_key ON public.categoria USING btree (nombre)"
  },
  {
    "tablename": "categoria",
    "indexname": "categoria_pkey",
    "indexdef": "CREATE UNIQUE INDEX categoria_pkey ON public.categoria USING btree (id)"
  },
  {
    "tablename": "detalle_pedido",
    "indexname": "detalle_pedido_pedido_id_producto_id_key",
    "indexdef": "CREATE UNIQUE INDEX detalle_pedido_pedido_id_producto_id_key ON public.detalle_pedido USING btree (pedido_id, producto_id)"
  },
  {
    "tablename": "detalle_pedido",
    "indexname": "detalle_pedido_pkey",
    "indexdef": "CREATE UNIQUE INDEX detalle_pedido_pkey ON public.detalle_pedido USING btree (id)"
  },
  {
    "tablename": "mv_facturacion_categoria_mes",
    "indexname": "idx_mv_facturacion_categoria_mes_unique",
    "indexdef": "CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes_unique ON public.mv_facturacion_categoria_mes USING btree (categoria_id, mes)"
  },
  {
    "tablename": "pedido",
    "indexname": "idx_pedido_fecha_reciente",
    "indexdef": "CREATE INDEX idx_pedido_fecha_reciente ON public.pedido USING btree (fecha DESC) INCLUDE (id, usuario_id, estado, forma_pago, total) WHERE (eliminado = false)"
  },
  {
    "tablename": "pedido",
    "indexname": "idx_pedido_usuario",
    "indexdef": "CREATE INDEX idx_pedido_usuario ON public.pedido USING btree (usuario_id)"
  },
  {
    "tablename": "pedido",
    "indexname": "pedido_pkey",
    "indexdef": "CREATE UNIQUE INDEX pedido_pkey ON public.pedido USING btree (id)"
  },
  {
    "tablename": "producto",
    "indexname": "idx_producto_categoria",
    "indexdef": "CREATE INDEX idx_producto_categoria ON public.producto USING btree (categoria_id)"
  },
  {
    "tablename": "producto",
    "indexname": "idx_producto_nombre_vig",
    "indexdef": "CREATE INDEX idx_producto_nombre_vig ON public.producto USING btree (nombre) WHERE (eliminado = false)"
  },
  {
    "tablename": "producto",
    "indexname": "idx_producto_stock_bajo",
    "indexdef": "CREATE INDEX idx_producto_stock_bajo ON public.producto USING btree (stock, nombre) INCLUDE (id, precio) WHERE (eliminado = false)"
  },
  {
    "tablename": "producto",
    "indexname": "producto_pkey",
    "indexdef": "CREATE UNIQUE INDEX producto_pkey ON public.producto USING btree (id)"
  },
  {
    "tablename": "usuario",
    "indexname": "idx_usuario_mail_lower",
    "indexdef": "CREATE INDEX idx_usuario_mail_lower ON public.usuario USING btree (lower((mail)::text)) WHERE (eliminado = false)"
  },
  {
    "tablename": "usuario",
    "indexname": "usuario_mail_key",
    "indexdef": "CREATE UNIQUE INDEX usuario_mail_key ON public.usuario USING btree (mail)"
  },
  {
    "tablename": "usuario",
    "indexname": "usuario_pkey",
    "indexdef": "CREATE UNIQUE INDEX usuario_pkey ON public.usuario USING btree (id)"
  }
]
```

### Restricción y triggers instalados

```json
{
  "column": {
    "column_name": "categoria_id",
    "data_type": "bigint",
    "is_nullable": "NO"
  },
  "fk": "FOREIGN KEY (categoria_id) REFERENCES categoria(id) ON DELETE RESTRICT",
  "triggers": [
    {
      "tgname": "trg_detalle_pedido_set_categoria",
      "tgenabled": "O",
      "definition": "CREATE TRIGGER trg_detalle_pedido_set_categoria BEFORE INSERT OR UPDATE OF producto_id, categoria_id ON public.detalle_pedido FOR EACH ROW EXECUTE FUNCTION fn_detalle_pedido_set_categoria()"
    },
    {
      "tgname": "trg_producto_sync_categoria_detalle",
      "tgenabled": "O",
      "definition": "CREATE TRIGGER trg_producto_sync_categoria_detalle AFTER UPDATE OF categoria_id ON public.producto FOR EACH ROW EXECUTE FUNCTION fn_producto_sync_categoria_detalle()"
    }
  ]
}
```

## Apéndice B — SQL ejecutado de carga y pruebas

Estos bloques documentan operaciones ya realizadas. No deben ejecutarse sobre la base fuente ni sobre una base importante. Los scripts de la unidad no son idempotentes; su reproducción requiere una copia nueva compatible.

### Carga adicional del día

```sql
BEGIN;
CREATE TEMP TABLE u4_new_orders ON COMMIT DROP AS
WITH ins AS(
 INSERT INTO pedido(fecha,estado,forma_pago,usuario_id)
 SELECT CURRENT_DATE,
 (ARRAY['PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO']::estado_pedido[])[1+g%4],
 (ARRAY['TARJETA','TRANSFERENCIA','EFECTIVO']::forma_pago[])[1+g%3],
 u.ids[1+g%cardinality(u.ids)]
 FROM generate_series(1,20000) g CROSS JOIN (SELECT array_agg(id ORDER BY id) ids FROM usuario) u
 RETURNING id)
SELECT id,row_number() OVER(ORDER BY id) AS rn FROM ins;
INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal)
SELECT o.id,p.id,1+(o.rn+j)%3,p.precio,(1+(o.rn+j)%3)*p.precio
FROM u4_new_orders o
CROSS JOIN LATERAL generate_series(1,(1+o.rn%4)::int) j
CROSS JOIN (SELECT array_agg(id ORDER BY id) ids FROM producto) v
JOIN producto p ON p.id=v.ids[1+(o.rn*17+j*997)%cardinality(v.ids)];
UPDATE pedido p SET total=x.total FROM(
 SELECT dp.pedido_id,SUM(dp.subtotal) total FROM detalle_pedido dp
 JOIN u4_new_orders n ON n.id=dp.pedido_id WHERE dp.eliminado=FALSE GROUP BY dp.pedido_id
) x WHERE x.pedido_id=p.id;
SELECT json_build_object('added_orders',(SELECT count(*) FROM u4_new_orders),'added_details',(SELECT count(*) FROM detalle_pedido dp JOIN u4_new_orders n ON n.id=dp.pedido_id));
COMMIT;
```

### Diagnóstico y equivalencia FNBC

```sql
SELECT json_build_object(
'diagnostic',(SELECT count(*) FROM (SELECT responsable_control_id FROM control_lote_almacen GROUP BY responsable_control_id HAVING count(DISTINCT deposito_id)>1) s),
'original',(SELECT count(*) FROM control_lote_almacen),'reconstructed',(SELECT count(*) FROM v_control_lote_almacen),
'original_minus_view',(SELECT count(*) FROM(SELECT * FROM control_lote_almacen EXCEPT SELECT * FROM v_control_lote_almacen) s),
'view_minus_original',(SELECT count(*) FROM(SELECT * FROM v_control_lote_almacen EXCEPT SELECT * FROM control_lote_almacen) s))
```

### Equivalencia normalizada/desnormalizada

```sql
SELECT json_build_object('original_minus_desnormalizada',(SELECT count(*) FROM ((SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre) EXCEPT (SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN categoria c ON c.id = dp.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre)) s),'desnormalizada_minus_original',(SELECT count(*) FROM ((SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN categoria c ON c.id = dp.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre) EXCEPT (SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre)) s),'top5_original_minus_desnormalizada',(SELECT count(*) FROM ((SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5) EXCEPT (SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN categoria c ON c.id = dp.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5)) s),'top5_desnormalizada_minus_original',(SELECT count(*) FROM ((SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN categoria c ON c.id = dp.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5) EXCEPT (SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.eliminado = FALSE AND dp.eliminado = FALSE AND ped.fecha = CURRENT_DATE GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5)) s))
```

### Selección dinámica y prueba A

```sql
SELECT row_to_json(t) FROM(
 SELECT dp.id detalle_id,dp.pedido_id,dp.producto_id original_product,pr.categoria_id original_category,alt.id alternative_product,alt.categoria_id alternative_category
 FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id
 CROSS JOIN LATERAL(SELECT p.id,p.categoria_id FROM producto p WHERE p.categoria_id<>pr.categoria_id AND NOT EXISTS(SELECT 1 FROM detalle_pedido x WHERE x.pedido_id=dp.pedido_id AND x.producto_id=p.id) ORDER BY p.id LIMIT 1) alt
 ORDER BY dp.id LIMIT 1)t
```

```sql
BEGIN;
UPDATE detalle_pedido SET producto_id=2 WHERE id=1;
SELECT json_build_object('detail_id',dp.id,'product_id',dp.producto_id,'stored_category',dp.categoria_id,'real_category',p.categoria_id,'pass',dp.categoria_id=p.categoria_id)
FROM detalle_pedido dp JOIN producto p ON p.id=dp.producto_id WHERE dp.id=1;
ROLLBACK;
```

### Selección dinámica y prueba B

```sql
SELECT row_to_json(t) FROM(
SELECT p.id producto_id,p.categoria_id original_category,(SELECT id FROM categoria WHERE id<>p.categoria_id ORDER BY id LIMIT 1) alternative_category,count(dp.id) detail_count
FROM producto p JOIN detalle_pedido dp ON dp.producto_id=p.id GROUP BY p.id,p.categoria_id ORDER BY p.id LIMIT 1)t
```

```sql
BEGIN;
UPDATE producto SET categoria_id=2 WHERE id=1;
SELECT json_build_object('product_id',1,'expected_category',2,'matched',(SELECT count(*) FROM detalle_pedido WHERE producto_id=1 AND categoria_id=2),'desync',(SELECT count(*) FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id));
ROLLBACK;
```

### Prueba C

```sql
BEGIN;
UPDATE detalle_pedido SET categoria_id=2 WHERE id=1;
SELECT json_build_object('detail_id',dp.id,'attempted_category',2,'stored_category',dp.categoria_id,'real_category',p.categoria_id,'protected',dp.categoria_id=p.categoria_id AND dp.categoria_id<>2)
FROM detalle_pedido dp JOIN producto p ON p.id=dp.producto_id WHERE dp.id=1;
ROLLBACK;
```

## Apéndice C — Diez planes completos de lectura

Salida estructurada real de EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON). Cada bloque mantiene todos los valores, nodos, workers y contadores obtenidos; no son planes de ejemplo. Las tablas superiores son resúmenes de estos mismos resultados.

### Normalizada — corrida 1

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 13546.88,
      "Total Cost": 13546.9,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 184.002,
      "Actual Total Time": 190.489,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 5505,
      "Shared Read Blocks": 2877,
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
          "Startup Cost": 13546.88,
          "Total Cost": 13546.9,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 183.996,
          "Actual Total Time": 190.481,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 5505,
          "Shared Read Blocks": 2877,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 13544.68,
              "Total Cost": 13546.76,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 183.926,
              "Actual Total Time": 190.429,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 5502,
              "Shared Read Blocks": 2877,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 13544.68,
                  "Total Cost": 13546.54,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 183.897,
                  "Actual Total Time": 190.396,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 5502,
                  "Shared Read Blocks": 2877,
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
                      "Startup Cost": 12544.65,
                      "Total Cost": 12544.67,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 79.024,
                      "Actual Total Time": 79.03,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 5502,
                      "Shared Read Blocks": 2877,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 12544.43,
                          "Total Cost": 12544.53,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 78.979,
                          "Actual Total Time": 78.985,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 5486,
                          "Shared Read Blocks": 2877,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 3165.59,
                              "Total Cost": 12441.01,
                              "Plan Rows": 20684,
                              "Plan Width": 20,
                              "Actual Startup Time": 13.707,
                              "Actual Total Time": 74.225,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(pr.categoria_id = c.id)",
                              "Shared Hit Blocks": 5486,
                              "Shared Read Blocks": 2877,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 3164.41,
                                  "Total Cost": 12356.77,
                                  "Plan Rows": 20684,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 13.639,
                                  "Actual Total Time": 71.104,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.producto_id = pr.id)",
                                  "Shared Hit Blocks": 5453,
                                  "Shared Read Blocks": 2877,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Hash Join",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Join Type": "Inner",
                                      "Startup Cost": 1146.41,
                                      "Total Cost": 10284.47,
                                      "Plan Rows": 20684,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 2.143,
                                      "Actual Total Time": 50.59,
                                      "Actual Rows": 16757,
                                      "Actual Loops": 3,
                                      "Inner Unique": true,
                                      "Hash Cond": "(dp.pedido_id = ped.id)",
                                      "Shared Hit Blocks": 3667,
                                      "Shared Read Blocks": 2877,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Seq Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Relation Name": "detalle_pedido",
                                          "Alias": "dp",
                                          "Startup Cost": 0,
                                          "Total Cost": 8541.67,
                                          "Plan Rows": 227196,
                                          "Plan Width": 24,
                                          "Actual Startup Time": 0.012,
                                          "Actual Total Time": 38.418,
                                          "Actual Rows": 272664,
                                          "Actual Loops": 2,
                                          "Filter": "(NOT eliminado)",
                                          "Rows Removed by Filter": 2336,
                                          "Shared Hit Blocks": 3373,
                                          "Shared Read Blocks": 2877,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": []
                                        },
                                        {
                                          "Node Type": "Hash",
                                          "Parent Relationship": "Inner",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Startup Cost": 1042.09,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 1.862,
                                          "Actual Total Time": 1.863,
                                          "Actual Rows": 6758,
                                          "Actual Loops": 3,
                                          "Hash Buckets": 32768,
                                          "Original Hash Buckets": 32768,
                                          "Hash Batches": 1,
                                          "Original Hash Batches": 1,
                                          "Peak Memory Usage": 1056,
                                          "Shared Hit Blocks": 294,
                                          "Shared Read Blocks": 0,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": [],
                                          "Plans": [
                                            {
                                              "Node Type": "Index Only Scan",
                                              "Parent Relationship": "Outer",
                                              "Parallel Aware": true,
                                              "Async Capable": false,
                                              "Scan Direction": "Forward",
                                              "Index Name": "idx_pedido_fecha_reciente",
                                              "Relation Name": "pedido",
                                              "Alias": "ped",
                                              "Startup Cost": 0.42,
                                              "Total Cost": 1042.09,
                                              "Plan Rows": 8345,
                                              "Plan Width": 8,
                                              "Actual Startup Time": 0.04,
                                              "Actual Total Time": 2.959,
                                              "Actual Rows": 20275,
                                              "Actual Loops": 1,
                                              "Index Cond": "(fecha = CURRENT_DATE)",
                                              "Rows Removed by Index Recheck": 0,
                                              "Heap Fetches": 0,
                                              "Shared Hit Blocks": 294,
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
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": false,
                                      "Async Capable": false,
                                      "Startup Cost": 1393,
                                      "Total Cost": 1393,
                                      "Plan Rows": 50000,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 17.127,
                                      "Actual Total Time": 17.127,
                                      "Actual Rows": 50000,
                                      "Actual Loops": 2,
                                      "Hash Buckets": 65536,
                                      "Original Hash Buckets": 65536,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 2856,
                                      "Shared Hit Blocks": 1786,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
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
                                          "Actual Startup Time": 0.027,
                                          "Actual Total Time": 9.161,
                                          "Actual Rows": 50000,
                                          "Actual Loops": 2,
                                          "Shared Hit Blocks": 1786,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.042,
                                  "Actual Total Time": 0.043,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.034,
                                      "Actual Total Time": 0.035,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 443,
      "Shared Read Blocks": 1,
      "Shared Dirtied Blocks": 0,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Local Read Blocks": 0,
      "Local Dirtied Blocks": 0,
      "Local Written Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0
    },
    "Planning Time": 2.315,
    "Triggers": [],
    "Execution Time": 191.465
  }
]
```

### Normalizada — corrida 2

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 13546.88,
      "Total Cost": 13546.9,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 182.315,
      "Actual Total Time": 187.737,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 5537,
      "Shared Read Blocks": 2845,
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
          "Startup Cost": 13546.88,
          "Total Cost": 13546.9,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 182.312,
          "Actual Total Time": 187.733,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 5537,
          "Shared Read Blocks": 2845,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 13544.68,
              "Total Cost": 13546.76,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 182.276,
              "Actual Total Time": 187.706,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 5534,
              "Shared Read Blocks": 2845,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 13544.68,
                  "Total Cost": 13546.54,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 182.238,
                  "Actual Total Time": 187.676,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 5534,
                  "Shared Read Blocks": 2845,
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
                      "Startup Cost": 12544.65,
                      "Total Cost": 12544.67,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 73.544,
                      "Actual Total Time": 73.552,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 5534,
                      "Shared Read Blocks": 2845,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 12544.43,
                          "Total Cost": 12544.53,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 73.489,
                          "Actual Total Time": 73.497,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 5518,
                          "Shared Read Blocks": 2845,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 3165.59,
                              "Total Cost": 12441.01,
                              "Plan Rows": 20684,
                              "Plan Width": 20,
                              "Actual Startup Time": 12.215,
                              "Actual Total Time": 69.428,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(pr.categoria_id = c.id)",
                              "Shared Hit Blocks": 5518,
                              "Shared Read Blocks": 2845,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 3164.41,
                                  "Total Cost": 12356.77,
                                  "Plan Rows": 20684,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 12.047,
                                  "Actual Total Time": 66.617,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.producto_id = pr.id)",
                                  "Shared Hit Blocks": 5485,
                                  "Shared Read Blocks": 2845,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Hash Join",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Join Type": "Inner",
                                      "Startup Cost": 1146.41,
                                      "Total Cost": 10284.47,
                                      "Plan Rows": 20684,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 1.943,
                                      "Actual Total Time": 49.466,
                                      "Actual Rows": 16757,
                                      "Actual Loops": 3,
                                      "Inner Unique": true,
                                      "Hash Cond": "(dp.pedido_id = ped.id)",
                                      "Shared Hit Blocks": 3699,
                                      "Shared Read Blocks": 2845,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Seq Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Relation Name": "detalle_pedido",
                                          "Alias": "dp",
                                          "Startup Cost": 0,
                                          "Total Cost": 8541.67,
                                          "Plan Rows": 227196,
                                          "Plan Width": 24,
                                          "Actual Startup Time": 0.023,
                                          "Actual Total Time": 37.724,
                                          "Actual Rows": 272664,
                                          "Actual Loops": 2,
                                          "Filter": "(NOT eliminado)",
                                          "Rows Removed by Filter": 2336,
                                          "Shared Hit Blocks": 3405,
                                          "Shared Read Blocks": 2845,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": []
                                        },
                                        {
                                          "Node Type": "Hash",
                                          "Parent Relationship": "Inner",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Startup Cost": 1042.09,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 1.68,
                                          "Actual Total Time": 1.681,
                                          "Actual Rows": 6758,
                                          "Actual Loops": 3,
                                          "Hash Buckets": 32768,
                                          "Original Hash Buckets": 32768,
                                          "Hash Batches": 1,
                                          "Original Hash Batches": 1,
                                          "Peak Memory Usage": 1056,
                                          "Shared Hit Blocks": 294,
                                          "Shared Read Blocks": 0,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": [],
                                          "Plans": [
                                            {
                                              "Node Type": "Index Only Scan",
                                              "Parent Relationship": "Outer",
                                              "Parallel Aware": true,
                                              "Async Capable": false,
                                              "Scan Direction": "Forward",
                                              "Index Name": "idx_pedido_fecha_reciente",
                                              "Relation Name": "pedido",
                                              "Alias": "ped",
                                              "Startup Cost": 0.42,
                                              "Total Cost": 1042.09,
                                              "Plan Rows": 8345,
                                              "Plan Width": 8,
                                              "Actual Startup Time": 0.026,
                                              "Actual Total Time": 2.652,
                                              "Actual Rows": 20275,
                                              "Actual Loops": 1,
                                              "Index Cond": "(fecha = CURRENT_DATE)",
                                              "Rows Removed by Index Recheck": 0,
                                              "Heap Fetches": 0,
                                              "Shared Hit Blocks": 294,
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
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": false,
                                      "Async Capable": false,
                                      "Startup Cost": 1393,
                                      "Total Cost": 1393,
                                      "Plan Rows": 50000,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 15.03,
                                      "Actual Total Time": 15.032,
                                      "Actual Rows": 50000,
                                      "Actual Loops": 2,
                                      "Hash Buckets": 65536,
                                      "Original Hash Buckets": 65536,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 2856,
                                      "Shared Hit Blocks": 1786,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
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
                                          "Actual Startup Time": 0.053,
                                          "Actual Total Time": 8.38,
                                          "Actual Rows": 50000,
                                          "Actual Loops": 2,
                                          "Shared Hit Blocks": 1786,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.114,
                                  "Actual Total Time": 0.114,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.092,
                                      "Actual Total Time": 0.094,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 444,
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
    "Planning Time": 2.263,
    "Triggers": [],
    "Execution Time": 188.192
  }
]
```

### Normalizada — corrida 3

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 13546.88,
      "Total Cost": 13546.9,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 205.876,
      "Actual Total Time": 209.697,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 5569,
      "Shared Read Blocks": 2813,
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
          "Startup Cost": 13546.88,
          "Total Cost": 13546.9,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 205.87,
          "Actual Total Time": 209.691,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 5569,
          "Shared Read Blocks": 2813,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 13544.68,
              "Total Cost": 13546.76,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 205.814,
              "Actual Total Time": 209.643,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 5566,
              "Shared Read Blocks": 2813,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 13544.68,
                  "Total Cost": 13546.54,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 205.792,
                  "Actual Total Time": 209.622,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 5566,
                  "Shared Read Blocks": 2813,
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
                      "Startup Cost": 12544.65,
                      "Total Cost": 12544.67,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 64.844,
                      "Actual Total Time": 64.848,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 5566,
                      "Shared Read Blocks": 2813,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 12544.43,
                          "Total Cost": 12544.53,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 64.812,
                          "Actual Total Time": 64.816,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 5550,
                          "Shared Read Blocks": 2813,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 3165.59,
                              "Total Cost": 12441.01,
                              "Plan Rows": 20684,
                              "Plan Width": 20,
                              "Actual Startup Time": 11.967,
                              "Actual Total Time": 61.664,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(pr.categoria_id = c.id)",
                              "Shared Hit Blocks": 5550,
                              "Shared Read Blocks": 2813,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 3164.41,
                                  "Total Cost": 12356.77,
                                  "Plan Rows": 20684,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 11.904,
                                  "Actual Total Time": 59.554,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.producto_id = pr.id)",
                                  "Shared Hit Blocks": 5517,
                                  "Shared Read Blocks": 2813,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Hash Join",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Join Type": "Inner",
                                      "Startup Cost": 1146.41,
                                      "Total Cost": 10284.47,
                                      "Plan Rows": 20684,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 2.483,
                                      "Actual Total Time": 45.547,
                                      "Actual Rows": 16757,
                                      "Actual Loops": 3,
                                      "Inner Unique": true,
                                      "Hash Cond": "(dp.pedido_id = ped.id)",
                                      "Shared Hit Blocks": 3731,
                                      "Shared Read Blocks": 2813,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Seq Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Relation Name": "detalle_pedido",
                                          "Alias": "dp",
                                          "Startup Cost": 0,
                                          "Total Cost": 8541.67,
                                          "Plan Rows": 227196,
                                          "Plan Width": 24,
                                          "Actual Startup Time": 0.018,
                                          "Actual Total Time": 34.512,
                                          "Actual Rows": 272664,
                                          "Actual Loops": 2,
                                          "Filter": "(NOT eliminado)",
                                          "Rows Removed by Filter": 2336,
                                          "Shared Hit Blocks": 3437,
                                          "Shared Read Blocks": 2813,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": []
                                        },
                                        {
                                          "Node Type": "Hash",
                                          "Parent Relationship": "Inner",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Startup Cost": 1042.09,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 2.407,
                                          "Actual Total Time": 2.408,
                                          "Actual Rows": 6758,
                                          "Actual Loops": 3,
                                          "Hash Buckets": 32768,
                                          "Original Hash Buckets": 32768,
                                          "Hash Batches": 1,
                                          "Original Hash Batches": 1,
                                          "Peak Memory Usage": 1056,
                                          "Shared Hit Blocks": 294,
                                          "Shared Read Blocks": 0,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": [],
                                          "Plans": [
                                            {
                                              "Node Type": "Index Only Scan",
                                              "Parent Relationship": "Outer",
                                              "Parallel Aware": true,
                                              "Async Capable": false,
                                              "Scan Direction": "Forward",
                                              "Index Name": "idx_pedido_fecha_reciente",
                                              "Relation Name": "pedido",
                                              "Alias": "ped",
                                              "Startup Cost": 0.42,
                                              "Total Cost": 1042.09,
                                              "Plan Rows": 8345,
                                              "Plan Width": 8,
                                              "Actual Startup Time": 0.047,
                                              "Actual Total Time": 3.589,
                                              "Actual Rows": 20275,
                                              "Actual Loops": 1,
                                              "Index Cond": "(fecha = CURRENT_DATE)",
                                              "Rows Removed by Index Recheck": 0,
                                              "Heap Fetches": 0,
                                              "Shared Hit Blocks": 294,
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
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": false,
                                      "Async Capable": false,
                                      "Startup Cost": 1393,
                                      "Total Cost": 1393,
                                      "Plan Rows": 50000,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 13.959,
                                      "Actual Total Time": 13.96,
                                      "Actual Rows": 50000,
                                      "Actual Loops": 2,
                                      "Hash Buckets": 65536,
                                      "Original Hash Buckets": 65536,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 2856,
                                      "Shared Hit Blocks": 1786,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
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
                                          "Actual Startup Time": 0.048,
                                          "Actual Total Time": 7.837,
                                          "Actual Rows": 50000,
                                          "Actual Loops": 2,
                                          "Shared Hit Blocks": 1786,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.037,
                                  "Actual Total Time": 0.037,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.029,
                                      "Actual Total Time": 0.03,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 444,
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
    "Planning Time": 2.412,
    "Triggers": [],
    "Execution Time": 210.285
  }
]
```

### Normalizada — corrida 4

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 13546.88,
      "Total Cost": 13546.9,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 233.734,
      "Actual Total Time": 237.32,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 5601,
      "Shared Read Blocks": 2781,
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
          "Startup Cost": 13546.88,
          "Total Cost": 13546.9,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 233.732,
          "Actual Total Time": 237.317,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 5601,
          "Shared Read Blocks": 2781,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 13544.68,
              "Total Cost": 13546.76,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 233.692,
              "Actual Total Time": 237.286,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 5598,
              "Shared Read Blocks": 2781,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 13544.68,
                  "Total Cost": 13546.54,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 233.674,
                  "Actual Total Time": 237.27,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 5598,
                  "Shared Read Blocks": 2781,
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
                      "Startup Cost": 12544.65,
                      "Total Cost": 12544.67,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 74.453,
                      "Actual Total Time": 74.457,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 5598,
                      "Shared Read Blocks": 2781,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 12544.43,
                          "Total Cost": 12544.53,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 74.409,
                          "Actual Total Time": 74.414,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 5582,
                          "Shared Read Blocks": 2781,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 3165.59,
                              "Total Cost": 12441.01,
                              "Plan Rows": 20684,
                              "Plan Width": 20,
                              "Actual Startup Time": 11.292,
                              "Actual Total Time": 70.279,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(pr.categoria_id = c.id)",
                              "Shared Hit Blocks": 5582,
                              "Shared Read Blocks": 2781,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 3164.41,
                                  "Total Cost": 12356.77,
                                  "Plan Rows": 20684,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 11.218,
                                  "Actual Total Time": 67.536,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.producto_id = pr.id)",
                                  "Shared Hit Blocks": 5549,
                                  "Shared Read Blocks": 2781,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Hash Join",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Join Type": "Inner",
                                      "Startup Cost": 1146.41,
                                      "Total Cost": 10284.47,
                                      "Plan Rows": 20684,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 1.835,
                                      "Actual Total Time": 51.118,
                                      "Actual Rows": 16757,
                                      "Actual Loops": 3,
                                      "Inner Unique": true,
                                      "Hash Cond": "(dp.pedido_id = ped.id)",
                                      "Shared Hit Blocks": 3763,
                                      "Shared Read Blocks": 2781,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Seq Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Relation Name": "detalle_pedido",
                                          "Alias": "dp",
                                          "Startup Cost": 0,
                                          "Total Cost": 8541.67,
                                          "Plan Rows": 227196,
                                          "Plan Width": 24,
                                          "Actual Startup Time": 0.011,
                                          "Actual Total Time": 38.974,
                                          "Actual Rows": 272664,
                                          "Actual Loops": 2,
                                          "Filter": "(NOT eliminado)",
                                          "Rows Removed by Filter": 2336,
                                          "Shared Hit Blocks": 3469,
                                          "Shared Read Blocks": 2781,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": []
                                        },
                                        {
                                          "Node Type": "Hash",
                                          "Parent Relationship": "Inner",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Startup Cost": 1042.09,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 1.569,
                                          "Actual Total Time": 1.569,
                                          "Actual Rows": 6758,
                                          "Actual Loops": 3,
                                          "Hash Buckets": 32768,
                                          "Original Hash Buckets": 32768,
                                          "Hash Batches": 1,
                                          "Original Hash Batches": 1,
                                          "Peak Memory Usage": 1056,
                                          "Shared Hit Blocks": 294,
                                          "Shared Read Blocks": 0,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": [],
                                          "Plans": [
                                            {
                                              "Node Type": "Index Only Scan",
                                              "Parent Relationship": "Outer",
                                              "Parallel Aware": true,
                                              "Async Capable": false,
                                              "Scan Direction": "Forward",
                                              "Index Name": "idx_pedido_fecha_reciente",
                                              "Relation Name": "pedido",
                                              "Alias": "ped",
                                              "Startup Cost": 0.42,
                                              "Total Cost": 1042.09,
                                              "Plan Rows": 8345,
                                              "Plan Width": 8,
                                              "Actual Startup Time": 0.026,
                                              "Actual Total Time": 2.629,
                                              "Actual Rows": 20275,
                                              "Actual Loops": 1,
                                              "Index Cond": "(fecha = CURRENT_DATE)",
                                              "Rows Removed by Index Recheck": 0,
                                              "Heap Fetches": 0,
                                              "Shared Hit Blocks": 294,
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
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": false,
                                      "Async Capable": false,
                                      "Startup Cost": 1393,
                                      "Total Cost": 1393,
                                      "Plan Rows": 50000,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 13.945,
                                      "Actual Total Time": 13.945,
                                      "Actual Rows": 50000,
                                      "Actual Loops": 2,
                                      "Hash Buckets": 65536,
                                      "Original Hash Buckets": 65536,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 2856,
                                      "Shared Hit Blocks": 1786,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
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
                                          "Actual Startup Time": 0.035,
                                          "Actual Total Time": 7.595,
                                          "Actual Rows": 50000,
                                          "Actual Loops": 2,
                                          "Shared Hit Blocks": 1786,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.043,
                                  "Actual Total Time": 0.044,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.037,
                                      "Actual Total Time": 0.038,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 444,
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
    "Planning Time": 1.857,
    "Triggers": [],
    "Execution Time": 237.785
  }
]
```

### Normalizada — corrida 5

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 13546.88,
      "Total Cost": 13546.9,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 193.248,
      "Actual Total Time": 199.886,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 5633,
      "Shared Read Blocks": 2749,
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
          "Startup Cost": 13546.88,
          "Total Cost": 13546.9,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 193.246,
          "Actual Total Time": 199.882,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 5633,
          "Shared Read Blocks": 2749,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 13544.68,
              "Total Cost": 13546.76,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 193.205,
              "Actual Total Time": 199.856,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 5630,
              "Shared Read Blocks": 2749,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 13544.68,
                  "Total Cost": 13546.54,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 193.171,
                  "Actual Total Time": 199.825,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 5630,
                  "Shared Read Blocks": 2749,
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
                      "Startup Cost": 12544.65,
                      "Total Cost": 12544.67,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 74.654,
                      "Actual Total Time": 74.661,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 5630,
                      "Shared Read Blocks": 2749,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 12544.43,
                          "Total Cost": 12544.53,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 74.564,
                          "Actual Total Time": 74.571,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 5614,
                          "Shared Read Blocks": 2749,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 3165.59,
                              "Total Cost": 12441.01,
                              "Plan Rows": 20684,
                              "Plan Width": 20,
                              "Actual Startup Time": 11.579,
                              "Actual Total Time": 70.032,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(pr.categoria_id = c.id)",
                              "Shared Hit Blocks": 5614,
                              "Shared Read Blocks": 2749,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 3164.41,
                                  "Total Cost": 12356.77,
                                  "Plan Rows": 20684,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 11.429,
                                  "Actual Total Time": 66.718,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.producto_id = pr.id)",
                                  "Shared Hit Blocks": 5581,
                                  "Shared Read Blocks": 2749,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Hash Join",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Join Type": "Inner",
                                      "Startup Cost": 1146.41,
                                      "Total Cost": 10284.47,
                                      "Plan Rows": 20684,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 1.979,
                                      "Actual Total Time": 48.434,
                                      "Actual Rows": 16757,
                                      "Actual Loops": 3,
                                      "Inner Unique": true,
                                      "Hash Cond": "(dp.pedido_id = ped.id)",
                                      "Shared Hit Blocks": 3795,
                                      "Shared Read Blocks": 2749,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Seq Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Relation Name": "detalle_pedido",
                                          "Alias": "dp",
                                          "Startup Cost": 0,
                                          "Total Cost": 8541.67,
                                          "Plan Rows": 227196,
                                          "Plan Width": 24,
                                          "Actual Startup Time": 0.008,
                                          "Actual Total Time": 37.11,
                                          "Actual Rows": 272664,
                                          "Actual Loops": 2,
                                          "Filter": "(NOT eliminado)",
                                          "Rows Removed by Filter": 2336,
                                          "Shared Hit Blocks": 3501,
                                          "Shared Read Blocks": 2749,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": []
                                        },
                                        {
                                          "Node Type": "Hash",
                                          "Parent Relationship": "Inner",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Startup Cost": 1042.09,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 1.893,
                                          "Actual Total Time": 1.894,
                                          "Actual Rows": 6758,
                                          "Actual Loops": 3,
                                          "Hash Buckets": 32768,
                                          "Original Hash Buckets": 32768,
                                          "Hash Batches": 1,
                                          "Original Hash Batches": 1,
                                          "Peak Memory Usage": 1056,
                                          "Shared Hit Blocks": 294,
                                          "Shared Read Blocks": 0,
                                          "Shared Dirtied Blocks": 0,
                                          "Shared Written Blocks": 0,
                                          "Local Hit Blocks": 0,
                                          "Local Read Blocks": 0,
                                          "Local Dirtied Blocks": 0,
                                          "Local Written Blocks": 0,
                                          "Temp Read Blocks": 0,
                                          "Temp Written Blocks": 0,
                                          "Workers": [],
                                          "Plans": [
                                            {
                                              "Node Type": "Index Only Scan",
                                              "Parent Relationship": "Outer",
                                              "Parallel Aware": true,
                                              "Async Capable": false,
                                              "Scan Direction": "Forward",
                                              "Index Name": "idx_pedido_fecha_reciente",
                                              "Relation Name": "pedido",
                                              "Alias": "ped",
                                              "Startup Cost": 0.42,
                                              "Total Cost": 1042.09,
                                              "Plan Rows": 8345,
                                              "Plan Width": 8,
                                              "Actual Startup Time": 0.029,
                                              "Actual Total Time": 3.354,
                                              "Actual Rows": 20275,
                                              "Actual Loops": 1,
                                              "Index Cond": "(fecha = CURRENT_DATE)",
                                              "Rows Removed by Index Recheck": 0,
                                              "Heap Fetches": 0,
                                              "Shared Hit Blocks": 294,
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
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": false,
                                      "Async Capable": false,
                                      "Startup Cost": 1393,
                                      "Total Cost": 1393,
                                      "Plan Rows": 50000,
                                      "Plan Width": 16,
                                      "Actual Startup Time": 14.078,
                                      "Actual Total Time": 14.079,
                                      "Actual Rows": 50000,
                                      "Actual Loops": 2,
                                      "Hash Buckets": 65536,
                                      "Original Hash Buckets": 65536,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 2856,
                                      "Shared Hit Blocks": 1786,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
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
                                          "Actual Startup Time": 0.024,
                                          "Actual Total Time": 7.792,
                                          "Actual Rows": 50000,
                                          "Actual Loops": 2,
                                          "Shared Hit Blocks": 1786,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.084,
                                  "Actual Total Time": 0.084,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.072,
                                      "Actual Total Time": 0.074,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 444,
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
    "Planning Time": 1.589,
    "Triggers": [],
    "Execution Time": 200.392
  }
]
```

### Desnormalizada — corrida 1

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 18264.47,
      "Total Cost": 18264.49,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 170.718,
      "Actual Total Time": 174.327,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 10652,
      "Shared Read Blocks": 2734,
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
          "Startup Cost": 18264.47,
          "Total Cost": 18264.49,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 170.716,
          "Actual Total Time": 174.325,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 10652,
          "Shared Read Blocks": 2734,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 18262.27,
              "Total Cost": 18264.35,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 170.626,
              "Actual Total Time": 174.268,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 10649,
              "Shared Read Blocks": 2734,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 18262.27,
                  "Total Cost": 18264.13,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 170.608,
                  "Actual Total Time": 174.25,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 10649,
                  "Shared Read Blocks": 2734,
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
                      "Startup Cost": 17262.24,
                      "Total Cost": 17262.26,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 57.279,
                      "Actual Total Time": 57.282,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 10649,
                      "Shared Read Blocks": 2734,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 17262.02,
                          "Total Cost": 17262.12,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 57.223,
                          "Actual Total Time": 57.228,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 10633,
                          "Shared Read Blocks": 2734,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 1147.59,
                              "Total Cost": 17158.62,
                              "Plan Rows": 20681,
                              "Plan Width": 20,
                              "Actual Startup Time": 1.882,
                              "Actual Total Time": 53.371,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(dp.categoria_id = c.id)",
                              "Shared Hit Blocks": 10633,
                              "Shared Read Blocks": 2734,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": true,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 1146.41,
                                  "Total Cost": 17074.39,
                                  "Plan Rows": 20681,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 1.792,
                                  "Actual Total Time": 50.731,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.pedido_id = ped.id)",
                                  "Shared Hit Blocks": 10600,
                                  "Shared Read Blocks": 2734,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Seq Scan",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Relation Name": "detalle_pedido",
                                      "Alias": "dp",
                                      "Startup Cost": 0,
                                      "Total Cost": 15331.67,
                                      "Plan Rows": 227165,
                                      "Plan Width": 24,
                                      "Actual Startup Time": 0.084,
                                      "Actual Total Time": 46.568,
                                      "Actual Rows": 272664,
                                      "Actual Loops": 2,
                                      "Filter": "(NOT eliminado)",
                                      "Rows Removed by Filter": 2336,
                                      "Shared Hit Blocks": 10306,
                                      "Shared Read Blocks": 2734,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": []
                                    },
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Startup Cost": 1042.09,
                                      "Total Cost": 1042.09,
                                      "Plan Rows": 8345,
                                      "Plan Width": 8,
                                      "Actual Startup Time": 1.467,
                                      "Actual Total Time": 1.467,
                                      "Actual Rows": 6758,
                                      "Actual Loops": 3,
                                      "Hash Buckets": 32768,
                                      "Original Hash Buckets": 32768,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 1056,
                                      "Shared Hit Blocks": 294,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Index Only Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Scan Direction": "Forward",
                                          "Index Name": "idx_pedido_fecha_reciente",
                                          "Relation Name": "pedido",
                                          "Alias": "ped",
                                          "Startup Cost": 0.42,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 0.026,
                                          "Actual Total Time": 2.538,
                                          "Actual Rows": 20275,
                                          "Actual Loops": 1,
                                          "Index Cond": "(fecha = CURRENT_DATE)",
                                          "Rows Removed by Index Recheck": 0,
                                          "Heap Fetches": 0,
                                          "Shared Hit Blocks": 294,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.05,
                                  "Actual Total Time": 0.051,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.038,
                                      "Actual Total Time": 0.04,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 365,
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
    "Planning Time": 1.28,
    "Triggers": [],
    "Execution Time": 174.459
  }
]
```

### Desnormalizada — corrida 2

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 18264.47,
      "Total Cost": 18264.49,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 174.019,
      "Actual Total Time": 177.602,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 10716,
      "Shared Read Blocks": 2670,
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
          "Startup Cost": 18264.47,
          "Total Cost": 18264.49,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 174.017,
          "Actual Total Time": 177.599,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 10716,
          "Shared Read Blocks": 2670,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 18262.27,
              "Total Cost": 18264.35,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 173.939,
              "Actual Total Time": 177.532,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 10713,
              "Shared Read Blocks": 2670,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 18262.27,
                  "Total Cost": 18264.13,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 173.922,
                  "Actual Total Time": 177.515,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 10713,
                  "Shared Read Blocks": 2670,
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
                      "Startup Cost": 17262.24,
                      "Total Cost": 17262.26,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 58.99,
                      "Actual Total Time": 58.993,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 10713,
                      "Shared Read Blocks": 2670,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 17262.02,
                          "Total Cost": 17262.12,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 58.942,
                          "Actual Total Time": 58.947,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 10697,
                          "Shared Read Blocks": 2670,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 1147.59,
                              "Total Cost": 17158.62,
                              "Plan Rows": 20681,
                              "Plan Width": 20,
                              "Actual Startup Time": 2.261,
                              "Actual Total Time": 55.754,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(dp.categoria_id = c.id)",
                              "Shared Hit Blocks": 10697,
                              "Shared Read Blocks": 2670,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": true,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 1146.41,
                                  "Total Cost": 17074.39,
                                  "Plan Rows": 20681,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 2.161,
                                  "Actual Total Time": 53.461,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.pedido_id = ped.id)",
                                  "Shared Hit Blocks": 10664,
                                  "Shared Read Blocks": 2670,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Seq Scan",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Relation Name": "detalle_pedido",
                                      "Alias": "dp",
                                      "Startup Cost": 0,
                                      "Total Cost": 15331.67,
                                      "Plan Rows": 227165,
                                      "Plan Width": 24,
                                      "Actual Startup Time": 0.099,
                                      "Actual Total Time": 46.518,
                                      "Actual Rows": 272664,
                                      "Actual Loops": 2,
                                      "Filter": "(NOT eliminado)",
                                      "Rows Removed by Filter": 2336,
                                      "Shared Hit Blocks": 10370,
                                      "Shared Read Blocks": 2670,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": []
                                    },
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Startup Cost": 1042.09,
                                      "Total Cost": 1042.09,
                                      "Plan Rows": 8345,
                                      "Plan Width": 8,
                                      "Actual Startup Time": 1.806,
                                      "Actual Total Time": 1.807,
                                      "Actual Rows": 6758,
                                      "Actual Loops": 3,
                                      "Hash Buckets": 32768,
                                      "Original Hash Buckets": 32768,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 1056,
                                      "Shared Hit Blocks": 294,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Index Only Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Scan Direction": "Forward",
                                          "Index Name": "idx_pedido_fecha_reciente",
                                          "Relation Name": "pedido",
                                          "Alias": "ped",
                                          "Startup Cost": 0.42,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 0.036,
                                          "Actual Total Time": 2.918,
                                          "Actual Rows": 20275,
                                          "Actual Loops": 1,
                                          "Index Cond": "(fecha = CURRENT_DATE)",
                                          "Rows Removed by Index Recheck": 0,
                                          "Heap Fetches": 0,
                                          "Shared Hit Blocks": 294,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.062,
                                  "Actual Total Time": 0.063,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.053,
                                      "Actual Total Time": 0.054,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 365,
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
    "Planning Time": 1.634,
    "Triggers": [],
    "Execution Time": 177.794
  }
]
```

### Desnormalizada — corrida 3

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 18264.47,
      "Total Cost": 18264.49,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 282.457,
      "Actual Total Time": 286.916,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 10780,
      "Shared Read Blocks": 2606,
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
          "Startup Cost": 18264.47,
          "Total Cost": 18264.49,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 282.454,
          "Actual Total Time": 286.913,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 10780,
          "Shared Read Blocks": 2606,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 18262.27,
              "Total Cost": 18264.35,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 282.381,
              "Actual Total Time": 286.854,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 10777,
              "Shared Read Blocks": 2606,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 18262.27,
                  "Total Cost": 18264.13,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 282.348,
                  "Actual Total Time": 286.826,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 10777,
                  "Shared Read Blocks": 2606,
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
                      "Startup Cost": 17262.24,
                      "Total Cost": 17262.26,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 57.579,
                      "Actual Total Time": 57.584,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 10777,
                      "Shared Read Blocks": 2606,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 17262.02,
                          "Total Cost": 17262.12,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 57.515,
                          "Actual Total Time": 57.521,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 10761,
                          "Shared Read Blocks": 2606,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 1147.59,
                              "Total Cost": 17158.62,
                              "Plan Rows": 20681,
                              "Plan Width": 20,
                              "Actual Startup Time": 2.409,
                              "Actual Total Time": 53.963,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(dp.categoria_id = c.id)",
                              "Shared Hit Blocks": 10761,
                              "Shared Read Blocks": 2606,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": true,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 1146.41,
                                  "Total Cost": 17074.39,
                                  "Plan Rows": 20681,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 2.271,
                                  "Actual Total Time": 51.448,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.pedido_id = ped.id)",
                                  "Shared Hit Blocks": 10728,
                                  "Shared Read Blocks": 2606,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Seq Scan",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Relation Name": "detalle_pedido",
                                      "Alias": "dp",
                                      "Startup Cost": 0,
                                      "Total Cost": 15331.67,
                                      "Plan Rows": 227165,
                                      "Plan Width": 24,
                                      "Actual Startup Time": 0.098,
                                      "Actual Total Time": 45.018,
                                      "Actual Rows": 272664,
                                      "Actual Loops": 2,
                                      "Filter": "(NOT eliminado)",
                                      "Rows Removed by Filter": 2336,
                                      "Shared Hit Blocks": 10434,
                                      "Shared Read Blocks": 2606,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": []
                                    },
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Startup Cost": 1042.09,
                                      "Total Cost": 1042.09,
                                      "Plan Rows": 8345,
                                      "Plan Width": 8,
                                      "Actual Startup Time": 1.71,
                                      "Actual Total Time": 1.711,
                                      "Actual Rows": 6758,
                                      "Actual Loops": 3,
                                      "Hash Buckets": 32768,
                                      "Original Hash Buckets": 32768,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 1056,
                                      "Shared Hit Blocks": 294,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Index Only Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Scan Direction": "Forward",
                                          "Index Name": "idx_pedido_fecha_reciente",
                                          "Relation Name": "pedido",
                                          "Alias": "ped",
                                          "Startup Cost": 0.42,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 0.022,
                                          "Actual Total Time": 2.83,
                                          "Actual Rows": 20275,
                                          "Actual Loops": 1,
                                          "Index Cond": "(fecha = CURRENT_DATE)",
                                          "Rows Removed by Index Recheck": 0,
                                          "Heap Fetches": 0,
                                          "Shared Hit Blocks": 294,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.081,
                                  "Actual Total Time": 0.081,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.064,
                                      "Actual Total Time": 0.068,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 365,
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
    "Planning Time": 1.196,
    "Triggers": [],
    "Execution Time": 287.053
  }
]
```

### Desnormalizada — corrida 4

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 18264.47,
      "Total Cost": 18264.49,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 189.572,
      "Actual Total Time": 196.321,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 10844,
      "Shared Read Blocks": 2542,
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
          "Startup Cost": 18264.47,
          "Total Cost": 18264.49,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 189.57,
          "Actual Total Time": 196.317,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 10844,
          "Shared Read Blocks": 2542,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 18262.27,
              "Total Cost": 18264.35,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 189.497,
              "Actual Total Time": 196.251,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 10841,
              "Shared Read Blocks": 2542,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 18262.27,
                  "Total Cost": 18264.13,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 189.477,
                  "Actual Total Time": 196.227,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 10841,
                  "Shared Read Blocks": 2542,
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
                      "Startup Cost": 17262.24,
                      "Total Cost": 17262.26,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 71.487,
                      "Actual Total Time": 71.493,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 10841,
                      "Shared Read Blocks": 2542,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 17262.02,
                          "Total Cost": 17262.12,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 71.422,
                          "Actual Total Time": 71.431,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 10825,
                          "Shared Read Blocks": 2542,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 1147.59,
                              "Total Cost": 17158.62,
                              "Plan Rows": 20681,
                              "Plan Width": 20,
                              "Actual Startup Time": 2.126,
                              "Actual Total Time": 65.894,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(dp.categoria_id = c.id)",
                              "Shared Hit Blocks": 10825,
                              "Shared Read Blocks": 2542,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": true,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 1146.41,
                                  "Total Cost": 17074.39,
                                  "Plan Rows": 20681,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 2.061,
                                  "Actual Total Time": 62.133,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.pedido_id = ped.id)",
                                  "Shared Hit Blocks": 10792,
                                  "Shared Read Blocks": 2542,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Seq Scan",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Relation Name": "detalle_pedido",
                                      "Alias": "dp",
                                      "Startup Cost": 0,
                                      "Total Cost": 15331.67,
                                      "Plan Rows": 227165,
                                      "Plan Width": 24,
                                      "Actual Startup Time": 0.102,
                                      "Actual Total Time": 53.588,
                                      "Actual Rows": 272664,
                                      "Actual Loops": 2,
                                      "Filter": "(NOT eliminado)",
                                      "Rows Removed by Filter": 2336,
                                      "Shared Hit Blocks": 10498,
                                      "Shared Read Blocks": 2542,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": []
                                    },
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Startup Cost": 1042.09,
                                      "Total Cost": 1042.09,
                                      "Plan Rows": 8345,
                                      "Plan Width": 8,
                                      "Actual Startup Time": 1.542,
                                      "Actual Total Time": 1.543,
                                      "Actual Rows": 6758,
                                      "Actual Loops": 3,
                                      "Hash Buckets": 32768,
                                      "Original Hash Buckets": 32768,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 1056,
                                      "Shared Hit Blocks": 294,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Index Only Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Scan Direction": "Forward",
                                          "Index Name": "idx_pedido_fecha_reciente",
                                          "Relation Name": "pedido",
                                          "Alias": "ped",
                                          "Startup Cost": 0.42,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 0.025,
                                          "Actual Total Time": 2.588,
                                          "Actual Rows": 20275,
                                          "Actual Loops": 1,
                                          "Index Cond": "(fecha = CURRENT_DATE)",
                                          "Rows Removed by Index Recheck": 0,
                                          "Heap Fetches": 0,
                                          "Shared Hit Blocks": 294,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.039,
                                  "Actual Total Time": 0.04,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.033,
                                      "Actual Total Time": 0.035,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 365,
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
    "Planning Time": 1.209,
    "Triggers": [],
    "Execution Time": 196.507
  }
]
```

### Desnormalizada — corrida 5

```json
[
  {
    "Plan": {
      "Node Type": "Limit",
      "Parallel Aware": false,
      "Async Capable": false,
      "Startup Cost": 18264.47,
      "Total Cost": 18264.49,
      "Plan Rows": 5,
      "Plan Width": 44,
      "Actual Startup Time": 301.719,
      "Actual Total Time": 307.142,
      "Actual Rows": 5,
      "Actual Loops": 1,
      "Shared Hit Blocks": 10908,
      "Shared Read Blocks": 2478,
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
          "Startup Cost": 18264.47,
          "Total Cost": 18264.49,
          "Plan Rows": 8,
          "Plan Width": 44,
          "Actual Startup Time": 301.716,
          "Actual Total Time": 307.138,
          "Actual Rows": 5,
          "Actual Loops": 1,
          "Sort Key": [
            "(sum(dp.subtotal)) DESC"
          ],
          "Sort Method": "quicksort",
          "Sort Space Used": 25,
          "Sort Space Type": "Memory",
          "Shared Hit Blocks": 10908,
          "Shared Read Blocks": 2478,
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
              "Node Type": "Aggregate",
              "Strategy": "Sorted",
              "Partial Mode": "Finalize",
              "Parent Relationship": "Outer",
              "Parallel Aware": false,
              "Async Capable": false,
              "Startup Cost": 18262.27,
              "Total Cost": 18264.35,
              "Plan Rows": 8,
              "Plan Width": 44,
              "Actual Startup Time": 301.627,
              "Actual Total Time": 307.064,
              "Actual Rows": 8,
              "Actual Loops": 1,
              "Group Key": [
                "c.nombre"
              ],
              "Shared Hit Blocks": 10905,
              "Shared Read Blocks": 2478,
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
                  "Node Type": "Gather Merge",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Startup Cost": 18262.27,
                  "Total Cost": 18264.13,
                  "Plan Rows": 16,
                  "Plan Width": 44,
                  "Actual Startup Time": 301.585,
                  "Actual Total Time": 307.032,
                  "Actual Rows": 16,
                  "Actual Loops": 1,
                  "Workers Planned": 2,
                  "Workers Launched": 2,
                  "Shared Hit Blocks": 10905,
                  "Shared Read Blocks": 2478,
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
                      "Startup Cost": 17262.24,
                      "Total Cost": 17262.26,
                      "Plan Rows": 8,
                      "Plan Width": 44,
                      "Actual Startup Time": 68.121,
                      "Actual Total Time": 68.126,
                      "Actual Rows": 5,
                      "Actual Loops": 3,
                      "Sort Key": [
                        "c.nombre"
                      ],
                      "Sort Method": "quicksort",
                      "Sort Space Used": 25,
                      "Sort Space Type": "Memory",
                      "Shared Hit Blocks": 10905,
                      "Shared Read Blocks": 2478,
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
                          "Node Type": "Aggregate",
                          "Strategy": "Hashed",
                          "Partial Mode": "Partial",
                          "Parent Relationship": "Outer",
                          "Parallel Aware": false,
                          "Async Capable": false,
                          "Startup Cost": 17262.02,
                          "Total Cost": 17262.12,
                          "Plan Rows": 8,
                          "Plan Width": 44,
                          "Actual Startup Time": 68.076,
                          "Actual Total Time": 68.081,
                          "Actual Rows": 5,
                          "Actual Loops": 3,
                          "Group Key": [
                            "c.nombre"
                          ],
                          "Planned Partitions": 0,
                          "HashAgg Batches": 1,
                          "Peak Memory Usage": 24,
                          "Disk Usage": 0,
                          "Shared Hit Blocks": 10889,
                          "Shared Read Blocks": 2478,
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
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            },
                            {
                              "Worker Number": 1,
                              "HashAgg Batches": 1,
                              "Peak Memory Usage": 24,
                              "Disk Usage": 0
                            }
                          ],
                          "Plans": [
                            {
                              "Node Type": "Hash Join",
                              "Parent Relationship": "Outer",
                              "Parallel Aware": false,
                              "Async Capable": false,
                              "Join Type": "Inner",
                              "Startup Cost": 1147.59,
                              "Total Cost": 17158.62,
                              "Plan Rows": 20681,
                              "Plan Width": 20,
                              "Actual Startup Time": 1.828,
                              "Actual Total Time": 64.493,
                              "Actual Rows": 16757,
                              "Actual Loops": 3,
                              "Inner Unique": true,
                              "Hash Cond": "(dp.categoria_id = c.id)",
                              "Shared Hit Blocks": 10889,
                              "Shared Read Blocks": 2478,
                              "Shared Dirtied Blocks": 0,
                              "Shared Written Blocks": 0,
                              "Local Hit Blocks": 0,
                              "Local Read Blocks": 0,
                              "Local Dirtied Blocks": 0,
                              "Local Written Blocks": 0,
                              "Temp Read Blocks": 0,
                              "Temp Written Blocks": 0,
                              "Workers": [],
                              "Plans": [
                                {
                                  "Node Type": "Hash Join",
                                  "Parent Relationship": "Outer",
                                  "Parallel Aware": true,
                                  "Async Capable": false,
                                  "Join Type": "Inner",
                                  "Startup Cost": 1146.41,
                                  "Total Cost": 17074.39,
                                  "Plan Rows": 20681,
                                  "Plan Width": 16,
                                  "Actual Startup Time": 1.739,
                                  "Actual Total Time": 61.917,
                                  "Actual Rows": 16757,
                                  "Actual Loops": 3,
                                  "Inner Unique": true,
                                  "Hash Cond": "(dp.pedido_id = ped.id)",
                                  "Shared Hit Blocks": 10856,
                                  "Shared Read Blocks": 2478,
                                  "Shared Dirtied Blocks": 0,
                                  "Shared Written Blocks": 0,
                                  "Local Hit Blocks": 0,
                                  "Local Read Blocks": 0,
                                  "Local Dirtied Blocks": 0,
                                  "Local Written Blocks": 0,
                                  "Temp Read Blocks": 0,
                                  "Temp Written Blocks": 0,
                                  "Workers": [],
                                  "Plans": [
                                    {
                                      "Node Type": "Seq Scan",
                                      "Parent Relationship": "Outer",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Relation Name": "detalle_pedido",
                                      "Alias": "dp",
                                      "Startup Cost": 0,
                                      "Total Cost": 15331.67,
                                      "Plan Rows": 227165,
                                      "Plan Width": 24,
                                      "Actual Startup Time": 0.089,
                                      "Actual Total Time": 54.448,
                                      "Actual Rows": 272664,
                                      "Actual Loops": 2,
                                      "Filter": "(NOT eliminado)",
                                      "Rows Removed by Filter": 2336,
                                      "Shared Hit Blocks": 10562,
                                      "Shared Read Blocks": 2478,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": []
                                    },
                                    {
                                      "Node Type": "Hash",
                                      "Parent Relationship": "Inner",
                                      "Parallel Aware": true,
                                      "Async Capable": false,
                                      "Startup Cost": 1042.09,
                                      "Total Cost": 1042.09,
                                      "Plan Rows": 8345,
                                      "Plan Width": 8,
                                      "Actual Startup Time": 1.605,
                                      "Actual Total Time": 1.606,
                                      "Actual Rows": 6758,
                                      "Actual Loops": 3,
                                      "Hash Buckets": 32768,
                                      "Original Hash Buckets": 32768,
                                      "Hash Batches": 1,
                                      "Original Hash Batches": 1,
                                      "Peak Memory Usage": 1056,
                                      "Shared Hit Blocks": 294,
                                      "Shared Read Blocks": 0,
                                      "Shared Dirtied Blocks": 0,
                                      "Shared Written Blocks": 0,
                                      "Local Hit Blocks": 0,
                                      "Local Read Blocks": 0,
                                      "Local Dirtied Blocks": 0,
                                      "Local Written Blocks": 0,
                                      "Temp Read Blocks": 0,
                                      "Temp Written Blocks": 0,
                                      "Workers": [],
                                      "Plans": [
                                        {
                                          "Node Type": "Index Only Scan",
                                          "Parent Relationship": "Outer",
                                          "Parallel Aware": true,
                                          "Async Capable": false,
                                          "Scan Direction": "Forward",
                                          "Index Name": "idx_pedido_fecha_reciente",
                                          "Relation Name": "pedido",
                                          "Alias": "ped",
                                          "Startup Cost": 0.42,
                                          "Total Cost": 1042.09,
                                          "Plan Rows": 8345,
                                          "Plan Width": 8,
                                          "Actual Startup Time": 0.022,
                                          "Actual Total Time": 2.736,
                                          "Actual Rows": 20275,
                                          "Actual Loops": 1,
                                          "Index Cond": "(fecha = CURRENT_DATE)",
                                          "Rows Removed by Index Recheck": 0,
                                          "Heap Fetches": 0,
                                          "Shared Hit Blocks": 294,
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
                                {
                                  "Node Type": "Hash",
                                  "Parent Relationship": "Inner",
                                  "Parallel Aware": false,
                                  "Async Capable": false,
                                  "Startup Cost": 1.08,
                                  "Total Cost": 1.08,
                                  "Plan Rows": 8,
                                  "Plan Width": 20,
                                  "Actual Startup Time": 0.057,
                                  "Actual Total Time": 0.057,
                                  "Actual Rows": 8,
                                  "Actual Loops": 3,
                                  "Hash Buckets": 1024,
                                  "Original Hash Buckets": 1024,
                                  "Hash Batches": 1,
                                  "Original Hash Batches": 1,
                                  "Peak Memory Usage": 9,
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
                                  "Workers": [],
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
                                      "Actual Startup Time": 0.047,
                                      "Actual Total Time": 0.048,
                                      "Actual Rows": 8,
                                      "Actual Loops": 3,
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
                                      "Workers": []
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
                }
              ]
            }
          ]
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 365,
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
    "Planning Time": 1.35,
    "Triggers": [],
    "Execution Time": 307.298
  }
]
```

## Apéndice D — Escritura y concurrencia: SQL y planes completos

### Fixture y comprobación de no persistencia

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;SELECT json_build_object('rows',count(*),'orders',count(DISTINCT pedido_id),'products',count(DISTINCT producto_id),'digest',md5(string_agg(row_to_json(f)::text,'' ORDER BY pedido_id))) FROM u4_insert_fixture f; ROLLBACK;
```

Antes:

```json
{
  "categoria": 8,
  "producto": 50000,
  "usuario": 20000,
  "pedido": 220000,
  "detalle_pedido": 550000,
  "today_orders": 20275,
  "today_details": 50272
}
```

Después:

```json
{
  "categoria": 8,
  "producto": 50000,
  "usuario": 20000,
  "pedido": 220000,
  "detalle_pedido": 550000,
  "today_orders": 20275,
  "today_details": 50272
}
```

Triggers al finalizar:

```json
[
  {
    "tgname": "RI_ConstraintTrigger_a_16915",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_a_16916",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16878",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16879",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16912",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16913",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16917",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_16918",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_17070",
    "tgenabled": "O"
  },
  {
    "tgname": "RI_ConstraintTrigger_c_17071",
    "tgenabled": "O"
  },
  {
    "tgname": "trg_detalle_pedido_set_categoria",
    "tgenabled": "O"
  },
  {
    "tgname": "trg_producto_sync_categoria_detalle",
    "tgenabled": "O"
  }
]
```

### INSERT sin trigger — corrida 1

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_pedido_set_categoria;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 6.369,
      "Actual Total Time": 6.37,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 6069,
      "Shared Read Blocks": 5,
      "Shared Dirtied Blocks": 5,
      "Shared Written Blocks": 2,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.279,
          "Actual Total Time": 1.017,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1006,
          "Shared Read Blocks": 3,
          "Shared Dirtied Blocks": 1,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 12,
      "Shared Read Blocks": 1,
      "Shared Dirtied Blocks": 0,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Local Read Blocks": 0,
      "Local Dirtied Blocks": 0,
      "Local Written Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0
    },
    "Planning Time": 0.214,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 11.349,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 7.751,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 7.16,
        "Calls": 1000
      }
    ],
    "Execution Time": 32.939
  }
]
```

### INSERT sin trigger — corrida 2

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_pedido_set_categoria;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 3.186,
      "Actual Total Time": 3.186,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 6119,
      "Shared Read Blocks": 0,
      "Shared Dirtied Blocks": 3,
      "Shared Written Blocks": 3,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.039,
          "Actual Total Time": 0.335,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1009,
          "Shared Read Blocks": 0,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 13,
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
    "Planning Time": 0.058,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.355,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.044,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 5.496,
        "Calls": 1000
      }
    ],
    "Execution Time": 21.301
  }
]
```

### INSERT sin trigger — corrida 3

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_pedido_set_categoria;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 3.097,
      "Actual Total Time": 3.097,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 6119,
      "Shared Read Blocks": 0,
      "Shared Dirtied Blocks": 3,
      "Shared Written Blocks": 3,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.04,
          "Actual Total Time": 0.342,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1009,
          "Shared Read Blocks": 0,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 13,
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
    "Planning Time": 0.058,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.337,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.132,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 5.566,
        "Calls": 1000
      }
    ],
    "Execution Time": 21.376
  }
]
```

### INSERT con trigger — corrida 1

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 9.053,
      "Actual Total Time": 9.053,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 9101,
      "Shared Read Blocks": 3,
      "Shared Dirtied Blocks": 3,
      "Shared Written Blocks": 3,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.039,
          "Actual Total Time": 0.423,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1009,
          "Shared Read Blocks": 0,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 13,
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
    "Planning Time": 0.046,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.517,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.377,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 5.598,
        "Calls": 1000
      },
      {
        "Trigger Name": "trg_detalle_pedido_set_categoria",
        "Relation": "detalle_pedido",
        "Time": 4.931,
        "Calls": 1000
      }
    ],
    "Execution Time": 27.763
  }
]
```

### INSERT con trigger — corrida 2

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 9.865,
      "Actual Total Time": 9.867,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 9150,
      "Shared Read Blocks": 0,
      "Shared Dirtied Blocks": 2,
      "Shared Written Blocks": 2,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.039,
          "Actual Total Time": 0.468,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1009,
          "Shared Read Blocks": 0,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 13,
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
    "Planning Time": 0.05,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.653,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 5.996,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 5.569,
        "Calls": 1000
      },
      {
        "Trigger Name": "trg_detalle_pedido_set_categoria",
        "Relation": "detalle_pedido",
        "Time": 5.309,
        "Calls": 1000
      }
    ],
    "Execution Time": 28.342
  }
]
```

### INSERT con trigger — corrida 3

```sql
BEGIN;CREATE TEMP TABLE u4_insert_fixture ON COMMIT DROP AS
SELECT ped.id AS pedido_id,pr.id AS producto_id,pr.categoria_id,pr.precio
FROM (SELECT id FROM pedido ORDER BY id LIMIT 1000) ped
CROSS JOIN LATERAL (
 SELECT p.id,p.categoria_id,p.precio FROM producto p
 WHERE p.id >= 1+(ped.id*37 % (SELECT max(id) FROM producto))
 AND NOT EXISTS(SELECT 1 FROM detalle_pedido dp WHERE dp.pedido_id=ped.id AND dp.producto_id=p.id)
 ORDER BY p.id LIMIT 1
) pr;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario,subtotal,categoria_id) SELECT pedido_id,producto_id,1,precio,precio,categoria_id FROM u4_insert_fixture;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Insert",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "detalle_pedido",
      "Alias": "detalle_pedido",
      "Startup Cost": 0,
      "Total Cost": 28,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 8.668,
      "Actual Total Time": 8.669,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 9104,
      "Shared Read Blocks": 0,
      "Shared Dirtied Blocks": 3,
      "Shared Written Blocks": 3,
      "Local Hit Blocks": 8,
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
          "Relation Name": "u4_insert_fixture",
          "Alias": "u4_insert_fixture",
          "Startup Cost": 0,
          "Total Cost": 28,
          "Plan Rows": 1200,
          "Plan Width": 77,
          "Actual Startup Time": 0.038,
          "Actual Total Time": 0.391,
          "Actual Rows": 1000,
          "Actual Loops": 1,
          "Shared Hit Blocks": 1009,
          "Shared Read Blocks": 0,
          "Shared Dirtied Blocks": 0,
          "Shared Written Blocks": 0,
          "Local Hit Blocks": 8,
          "Local Read Blocks": 0,
          "Local Dirtied Blocks": 0,
          "Local Written Blocks": 0,
          "Temp Read Blocks": 0,
          "Temp Written Blocks": 0
        }
      ]
    },
    "Planning": {
      "Shared Hit Blocks": 13,
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
    "Planning Time": 0.047,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16912",
        "Constraint Name": "detalle_pedido_pedido_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 7.317,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16917",
        "Constraint Name": "detalle_pedido_producto_id_fkey",
        "Relation": "detalle_pedido",
        "Time": 6.838,
        "Calls": 1000
      },
      {
        "Trigger Name": "RI_ConstraintTrigger_c_17070",
        "Constraint Name": "fk_detalle_pedido_categoria",
        "Relation": "detalle_pedido",
        "Time": 6.185,
        "Calls": 1000
      },
      {
        "Trigger Name": "trg_detalle_pedido_set_categoria",
        "Relation": "detalle_pedido",
        "Time": 4.735,
        "Calls": 1000
      }
    ],
    "Execution Time": 29.261
  }
]
```

### Selección y medición de propagación

```sql
SELECT row_to_json(t) FROM(SELECT p.id producto_id,p.categoria_id original_category,count(*) details,(SELECT id FROM categoria WHERE id<>p.categoria_id ORDER BY id LIMIT 1) alternative_category
 FROM producto p JOIN detalle_pedido dp ON dp.producto_id=p.id GROUP BY p.id,p.categoria_id ORDER BY count(*) DESC,p.id LIMIT 1)t
```

```sql
BEGIN;EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) UPDATE producto SET categoria_id=2 WHERE id=17;ROLLBACK;
```

```json
[
  {
    "Plan": {
      "Node Type": "ModifyTable",
      "Operation": "Update",
      "Parallel Aware": false,
      "Async Capable": false,
      "Relation Name": "producto",
      "Alias": "producto",
      "Startup Cost": 0.29,
      "Total Cost": 8.31,
      "Plan Rows": 0,
      "Plan Width": 0,
      "Actual Startup Time": 0.386,
      "Actual Total Time": 0.387,
      "Actual Rows": 0,
      "Actual Loops": 1,
      "Shared Hit Blocks": 35,
      "Shared Read Blocks": 8,
      "Shared Dirtied Blocks": 2,
      "Shared Written Blocks": 0,
      "Local Hit Blocks": 0,
      "Local Read Blocks": 0,
      "Local Dirtied Blocks": 0,
      "Local Written Blocks": 0,
      "Temp Read Blocks": 0,
      "Temp Written Blocks": 0,
      "Plans": [
        {
          "Node Type": "Index Scan",
          "Parent Relationship": "Outer",
          "Parallel Aware": false,
          "Async Capable": false,
          "Scan Direction": "Forward",
          "Index Name": "producto_pkey",
          "Relation Name": "producto",
          "Alias": "producto",
          "Startup Cost": 0.29,
          "Total Cost": 8.31,
          "Plan Rows": 1,
          "Plan Width": 14,
          "Actual Startup Time": 0.029,
          "Actual Total Time": 0.031,
          "Actual Rows": 1,
          "Actual Loops": 1,
          "Index Cond": "(id = 17)",
          "Rows Removed by Index Recheck": 0,
          "Shared Hit Blocks": 6,
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
      "Shared Hit Blocks": 123,
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
    "Planning Time": 0.645,
    "Triggers": [
      {
        "Trigger Name": "RI_ConstraintTrigger_c_16879",
        "Constraint Name": "producto_categoria_id_fkey",
        "Relation": "producto",
        "Time": 0.381,
        "Calls": 1
      },
      {
        "Trigger Name": "trg_producto_sync_categoria_detalle",
        "Relation": "producto",
        "Time": 56.662,
        "Calls": 1
      }
    ],
    "Execution Time": 57.54
  }
]
```

Verificación funcional independiente, también revertida:

```sql
BEGIN;UPDATE producto SET categoria_id=2 WHERE id=17;
SELECT json_build_object('affected_details',(SELECT count(*) FROM detalle_pedido WHERE producto_id=17 AND categoria_id=2),'desync',(SELECT count(*) FROM detalle_pedido dp JOIN producto pr ON pr.id=dp.producto_id WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id));ROLLBACK;
```

```json
{
  "affected_details": 18,
  "desync": 0
}
```

### Sesiones controladas de concurrencia

Sesión A; su COMMIT se envió únicamente después de observar el bloqueo de B:

```sql
BEGIN;SELECT 'A_PID='||pg_backend_pid();UPDATE producto SET categoria_id=2 WHERE id=17;SELECT 'A_UPDATED';
COMMIT;
```

```text
A_PID=2228
A_UPDATED
```

Sesión B:

```sql
BEGIN;SELECT 'B_PID='||pg_backend_pid();UPDATE producto SET categoria_id=1 WHERE id=17;SELECT 'B_UPDATED';COMMIT;
```

```text
B_PID=21896
B_UPDATED
```

Observación real de bloqueo:

```json
[
  {
    "pid": 2228,
    "application_name": "u4_b2_concurrency_A",
    "state": "idle in transaction",
    "wait_event_type": "Client",
    "wait_event": "ClientRead",
    "blocking_pids": []
  },
  {
    "pid": 21896,
    "application_name": "u4_b2_concurrency_B",
    "state": "active",
    "wait_event_type": "Lock",
    "wait_event": "transactionid",
    "blocking_pids": [
      2228
    ]
  }
]
```

Resultado tras ambas transacciones:

```json
{
  "status": "PASS",
  "before": {
    "category": 1,
    "details": 18
  },
  "after": {
    "category": 1,
    "matching_details": 18,
    "desync": 0
  }
}
```
