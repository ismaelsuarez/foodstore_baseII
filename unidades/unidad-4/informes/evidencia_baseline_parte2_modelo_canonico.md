# Unidad 4 — Baseline canónico del Top 5 de categorías

**Baseline funcional y experimental: PASS. Mediana oficial: 212.668 ms** de
Execution Time en cinco corridas. Se conservan todas las observaciones, incluida
RUN_4 (324.541 ms). No se eligió ni instaló una optimización; el dataset y los
índices permanecieron intactos. El commit local se verifica por separado: este
documento registra el HEAD de ejecución y no presupone la creación de otro commit.

## 1. Entorno, fuentes y preflight

| Dato | Valor observado |
|---|---|
| Repositorio | C:\Users\facu\Documents\UTN\Base_datos_II\foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD de ejecución | 8cd1a4244965d18a6e3b8a5e6b49411b8d1125f8 |
| Fuente estructural/seed | schema.sql / datos_iniciales.sql, base e5282f68a4af6975fb953c4f4b74f2e13240a0a6 |
| Base exclusiva | foodstore_u4_revalidacion |
| PostgreSQL | 17.11 on x86_64-windows, compiled by msvc-19.44.35228, 64-bit |
| CURRENT_DATE | 2026-09-23 |
| now() de la invocación JSON | 2026-09-23 14:14:44.080489-03 |
| now() de la invocación textual | 2026-09-23 14:15:19.049097-03 |
| Working tree previo | CLEAN |
| TPI | EXCLUDED_FROM_PRIMARY_U4_BASELINE |
| FNBC | PASS previo, retirado; ausente |
| Parte 2 | Sin instalar; patrón no elegido |

Fuentes locales: [schema](../../../schema.sql), [seed](../../../datos_iniciales.sql),
[evidencia del dataset](evidencia_dataset_parte2_modelo_canonico.md) e
[índices TP5](../../unidad-3/sql/indices.sql). Las mediciones históricas no se
utilizan como baseline ni se comparan con esta ejecución.

El dump Phase 3 existe y su SHA-256 fue recalculado, sin restaurarlo:

- Archivo: `backups/foodstore_u4_revalidacion_phase3.dump`
- SHA-256: `75DE3D6B072AF714B44944C862767B1CA6E619716A425F8194C7B248F93F24CE`
- Coincidencia con el checkpoint: PASS.

Conteos iniciales y finales: **8 categorías / 20000 usuarios / 50000 productos /
200000 pedidos / 500000 detalles**. Día: 20000 pedidos, 19800 vigentes y 200
eliminados; 50000 detalles asociados, 49500 no eliminados y **48900 utilizables
al aplicar ambos filtros**; ocho categorías. Subtotal, total, FK huérfanas,
duplicados pedido/producto y violaciones de CHECK: **0**.

Solo existen las cinco tablas canónicas. Se verificaron cero rutinas de usuario,
cero triggers no internos, cero objetos FNBC/TPI/Parte 2 y ausencia de
detalle_pedido.categoria_id. Los catorce índices incluyen los seis explícitos
raíz + TP5 con sus definiciones y estados valid/ready esperados.

## 2. Configuración observada, sin SET

| SHOW | Resultado |
|---|---|
| server_version | 17.11 |
| TimeZone | America/Buenos_Aires |
| shared_buffers | 128MB |
| effective_cache_size | 4GB |
| work_mem | 4MB |
| maintenance_work_mem | 64MB |
| random_page_cost | 4 |
| seq_page_cost | 1 |
| effective_io_concurrency | 0 |
| max_parallel_workers | 8 |
| max_parallel_workers_per_gather | 2 |
| jit | on |
| track_io_timing | off |

Las trece configuraciones existen en este servidor. No se modificó ninguna.
`jit=on` es una configuración, no una prueba de que la consulta haya
utilizado compilación JIT; no se registró una sección JIT en los planes observados.

## 3. Script y protocolo reproducible

Script nuevo:
[benchmark_baseline_top_categorias_modelo_canonico.sql](../sql/benchmark_baseline_top_categorias_modelo_canonico.sql).

SHA-256 de los bytes del SQL ejecutado:
`DF948686A5993F51AD22C60F3B983A2438762E3BCFBA8A3507DD09BEFB094017`.
No se modificó el script después de ejecutarlo.

Dos invocaciones controladas desde la raíz, ambas con **exit code 0**:

```powershell
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -v ON_ERROR_STOP=1 -f .\unidades\unidad-4\sql\benchmark_baseline_top_categorias_modelo_canonico.sql
# Después de calcular las estadísticas y seleccionar RUN_1 como referencia:
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -v ON_ERROR_STOP=1 -v text_only=true -f .\unidades\unidad-4\sql\benchmark_baseline_top_categorias_modelo_canonico.sql
```

El script usa SELECT, SHOW, EXPLAIN y variables/condicionales psql, sin DDL
experimental ni DML. Las guardas verifican base, versión, fecha, conteos,
población diaria, integridad, objetos e índices. Una guarda falsa termina
con error bajo ON_ERROR_STOP, sin reparar nada.

Se ejecutaron únicamente estas actualizaciones de estadísticas, una vez:

```sql
ANALYZE categoria;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;
```

No se ejecutó ANALYZE usuario ni VACUUM. ANALYZE puede muestrear estadísticas:
el protocolo es reproducible, pero no garantiza planes o tiempos idénticos.

**WARM-CACHE:** prechecks y consulta semántica previos, una corrida WARMUP y
cinco oficiales RUN_1..RUN_5 con EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
No se vaciaron cachés, reinició PostgreSQL ni ejecutaron CHECKPOINT/DISCARD ALL.
Las huellas de todas las filas y los SELECT semánticos entre corridas también
calientan cachés: forman parte del protocolo observado.

WARMUP no entra en las estadísticas. Se calculó externamente la mediana de
Execution Time; RUN_1 coincide exactamente con ella. Después se ejecutó un
único plan textual adicional, identificado como REPRESENTATIVE_TEXT_PLAN:
no repite las cinco mediciones ni reemplaza RUN_1 o la mediana. En total hubo
**seis EXPLAIN ANALYZE JSON y uno textual**, además de un EXPLAIN estimado.

Las comprobaciones semánticas anteriores y posteriores a cada corrida dieron
PASS. EXPLAIN ANALYZE no devuelve las filas de resultados de la consulta:
estos SELECT separados comprueban el resultado; sus tiempos no se incorporan
a Execution Time. No se detectaron cambios de filas entre los checkpoints.

## 4. Consulta exacta y resultado semántico

```sql
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

Sin filtros adicionales, desempate, hints ni índices forzados.

| Orden | Categoría | total_vendido |
|---:|---|---:|
| 1 | __U4_LAB_CATEGORIA_07__ | 194538488.00 |
| 2 | __U4_LAB_CATEGORIA_03__ | 90236048.00 |
| 3 | __U4_LAB_CATEGORIA_06__ | 88912722.00 |
| 4 | __U4_LAB_CATEGORIA_05__ | 74717570.00 |
| 5 | __U4_LAB_CATEGORIA_08__ | 40242037.00 |

Coincide con Phase 3. Ocho categorías elegibles; sus importes distintos quedaron
acreditados en ese checkpoint, sin modificar filas para alterar el ranking.

## 5. Plan estimado y topología observada

La inspección previa usó EXPLAIN (COSTS, BUFFERS OFF, FORMAT JSON), sin ejecutar
la consulta como benchmark. Raíz Limit, costo **12662.37..12662.39**, cinco filas
estimadas. Se previeron dos workers y el índice de pedidos por fecha.

La misma topología se observó en los seis planes JSON y en el textual. Los IDs
N0..N15 siguientes son etiquetas documentales en recorrido del árbol, no objetos
creados en PostgreSQL. Los nombres de agregación/paralelismo usan la notación
textual; JSON representa algunos mediante Node Type + Strategy/Partial Mode/
Parallel Aware.

| Nodo | Padre | Tipo / relación / condición | Plan Rows |
|---|---|---|---:|
| N0 | — | Limit | 5 |
| N1 | N0 | Sort por sum(dp.subtotal) DESC | 8 |
| N2 | N1 | Finalize GroupAggregate, c.nombre | 8 |
| N3 | N2 | Gather Merge | 16 |
| N4 | N3 | Sort por c.nombre | 8 |
| N5 | N4 | Partial HashAggregate, c.nombre | 8 |
| N6 | N5 | Hash Join, pr.categoria_id = c.id | 20945 |
| N7 | N6 | Hash Join, dp.producto_id = pr.id | 20945 |
| N8 | N7 | Parallel Hash Join, dp.pedido_id = ped.id | 20945 |
| N9 | N8 | Parallel Seq Scan, detalle_pedido; NOT eliminado | 206076 |
| N10 | N8 | Parallel Hash, pedido | 11957 |
| N11 | N10 | Parallel Index Only Scan, pedido; idx_pedido_fecha_reciente | 11957 |
| N12 | N7 | Hash, producto | 50000 |
| N13 | N12 | Seq Scan, producto | 50000 |
| N14 | N6 | Hash, categoria | 8 |
| N15 | N14 | Seq Scan, categoria | 8 |

Plan Rows no se interpreta como volumen global sin considerar nodos y paralelismo.
No se infirió rendimiento de los costos estimados antes de medir.

## 6. Mediciones temporales oficiales

Milisegundos reportados por PostgreSQL, no tiempos del cliente psql.

| Corrida | Planning Time | Execution Time | Integra estadísticas |
|---|---:|---:|---|
| WARMUP | 0.407 | 200.279 | No |
| RUN_1 | 0.664 | 212.668 | Sí |
| RUN_2 | 0.503 | 235.256 | Sí |
| RUN_3 | 0.460 | 199.683 | Sí |
| RUN_4 | 0.695 | 324.541 | Sí |
| RUN_5 | 0.885 | 171.081 | Sí |

| Estadística, solo RUN_1..RUN_5 | Execution Time, ms |
|---|---:|
| MIN | 171.081 |
| MAX | 324.541 |
| MEDIA aritmética | 228.6458 |
| MEDIANA oficial | **212.668** |

No se descartó ninguna corrida. RUN_4 es la máxima y muestra dispersión real;
su causa no fue medida. No se atribuye automáticamente a caché fría, I/O,
concurrencia externa o fallo productivo. No hubo reintentos para reemplazarla.

## 7. Buffers, paralelismo y datos de cada nodo

Resumen global: **buffers del nodo raíz N0**, no suma de padres e hijos.

| Corrida | Shared hit | Shared read | Dirtied | Written | Temp read | Temp written | Filas finales | Loops raíz | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| WARMUP | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |
| RUN_1 | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |
| RUN_2 | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |
| RUN_3 | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |
| RUN_4 | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |
| RUN_5 | 6794 | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 2 / 2 |

Planning buffers: 29 shared hits por corrida, cero en las otras categorías.
No se suman a los buffers de ejecución para formar otra cifra de baseline.

Las tablas siguientes conservan todos los nodos de las seis corridas. **Read,
dirtied, written, temp read y temp written son 0 en todos los nodos y corridas**.
Startup/Total son Actual Startup Time/Actual Total Time en ms; rows/tiempos se
interpretan por ejecución del nodo cuando loops>1. Tiempos de padres incluyen
hijos; ni sumarlos ni multiplicarlos como si fueran wall-clock independiente.
Referencia conceptual: [PostgreSQL 17 — Using EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html).

### WARMUP

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 195.125 | 199.938 | 6794 |
| N1 | 5 | 1 | 195.124 | 199.936 | 6794 |
| N2 | 8 | 1 | 195.105 | 199.929 | 6794 |
| N3 | 8 | 1 | 195.093 | 199.906 | 6794 |
| N4 | 3 | 3 | 40.646 | 40.649 | 6794 |
| N5 | 3 | 3 | 40.622 | 40.625 | 6778 |
| N6 | 16300 | 3 | 4.914 | 37.587 | 6778 |
| N7 | 16300 | 3 | 4.861 | 35.537 | 6745 |
| N8 | 16300 | 3 | 1.469 | 28.990 | 5835 |
| N9 | 495000 | 1 | 0.006 | 42.416 | 5682 |
| N10 | 6600 | 3 | 1.418 | 1.418 | 153 |
| N11 | 19800 | 1 | 0.015 | 2.092 | 153 |
| N12 | 50000 | 1 | 10.071 | 10.072 | 910 |
| N13 | 50000 | 1 | 0.012 | 5.211 | 910 |
| N14 | 8 | 3 | 0.035 | 0.035 | 3 |
| N15 | 8 | 3 | 0.029 | 0.030 | 3 |

### RUN_1

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 207.517 | 212.246 | 6794 |
| N1 | 5 | 1 | 207.516 | 212.244 | 6794 |
| N2 | 8 | 1 | 207.499 | 212.233 | 6794 |
| N3 | 8 | 1 | 207.482 | 212.212 | 6794 |
| N4 | 3 | 3 | 51.719 | 51.724 | 6794 |
| N5 | 3 | 3 | 51.680 | 51.685 | 6778 |
| N6 | 16300 | 3 | 5.180 | 48.641 | 6778 |
| N7 | 16300 | 3 | 5.093 | 46.546 | 6745 |
| N8 | 16300 | 3 | 1.517 | 38.908 | 5835 |
| N9 | 495000 | 1 | 0.006 | 54.598 | 5682 |
| N10 | 6600 | 3 | 1.441 | 1.441 | 153 |
| N11 | 19800 | 1 | 0.027 | 1.959 | 153 |
| N12 | 50000 | 1 | 10.616 | 10.617 | 910 |
| N13 | 50000 | 1 | 0.014 | 5.346 | 910 |
| N14 | 8 | 3 | 0.057 | 0.057 | 3 |
| N15 | 8 | 3 | 0.046 | 0.047 | 3 |

### RUN_2

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 210.963 | 234.879 | 6794 |
| N1 | 5 | 1 | 210.962 | 234.878 | 6794 |
| N2 | 8 | 1 | 210.950 | 234.871 | 6794 |
| N3 | 8 | 1 | 210.939 | 234.856 | 6794 |
| N4 | 3 | 3 | 49.047 | 49.051 | 6794 |
| N5 | 3 | 3 | 49.000 | 49.004 | 6778 |
| N6 | 16300 | 3 | 5.680 | 45.840 | 6778 |
| N7 | 16300 | 3 | 5.588 | 43.597 | 6745 |
| N8 | 16300 | 3 | 1.989 | 35.242 | 5835 |
| N9 | 495000 | 1 | 0.009 | 48.527 | 5682 |
| N10 | 6600 | 3 | 1.917 | 1.917 | 153 |
| N11 | 19800 | 1 | 0.029 | 2.414 | 153 |
| N12 | 50000 | 1 | 10.668 | 10.668 | 910 |
| N13 | 50000 | 1 | 0.029 | 5.475 | 910 |
| N14 | 8 | 3 | 0.055 | 0.055 | 3 |
| N15 | 8 | 3 | 0.044 | 0.046 | 3 |

### RUN_3

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 194.091 | 199.294 | 6794 |
| N1 | 5 | 1 | 194.090 | 199.292 | 6794 |
| N2 | 8 | 1 | 194.072 | 199.282 | 6794 |
| N3 | 8 | 1 | 194.058 | 199.263 | 6794 |
| N4 | 3 | 3 | 52.798 | 52.804 | 6794 |
| N5 | 3 | 3 | 52.769 | 52.775 | 6778 |
| N6 | 16300 | 3 | 14.246 | 49.594 | 6778 |
| N7 | 16300 | 3 | 14.176 | 47.394 | 6745 |
| N8 | 16300 | 3 | 9.916 | 39.479 | 5835 |
| N9 | 247500 | 2 | 0.009 | 29.949 | 5682 |
| N10 | 6600 | 3 | 1.225 | 1.226 | 153 |
| N11 | 19800 | 1 | 0.016 | 1.817 | 153 |
| N12 | 50000 | 1 | 12.674 | 12.675 | 910 |
| N13 | 50000 | 1 | 0.010 | 6.370 | 910 |
| N14 | 8 | 3 | 0.044 | 0.044 | 3 |
| N15 | 8 | 3 | 0.035 | 0.036 | 3 |

### RUN_4

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 318.156 | 324.108 | 6794 |
| N1 | 5 | 1 | 318.155 | 324.106 | 6794 |
| N2 | 8 | 1 | 318.141 | 324.097 | 6794 |
| N3 | 8 | 1 | 318.126 | 324.079 | 6794 |
| N4 | 3 | 3 | 78.026 | 78.032 | 6794 |
| N5 | 3 | 3 | 77.976 | 77.984 | 6778 |
| N6 | 16300 | 3 | 27.579 | 73.277 | 6778 |
| N7 | 16300 | 3 | 27.481 | 69.988 | 6745 |
| N8 | 16300 | 3 | 19.643 | 54.360 | 5835 |
| N9 | 247500 | 2 | 0.011 | 40.655 | 5682 |
| N10 | 6600 | 3 | 2.536 | 2.537 | 153 |
| N11 | 19800 | 1 | 0.028 | 3.166 | 153 |
| N12 | 50000 | 1 | 23.361 | 23.362 | 910 |
| N13 | 50000 | 1 | 0.027 | 9.695 | 910 |
| N14 | 8 | 3 | 0.064 | 0.065 | 3 |
| N15 | 8 | 3 | 0.053 | 0.055 | 3 |

### RUN_5

| Nodo | Actual Rows | Actual Loops | Startup ms | Total ms | Shared hit |
|---|---:|---:|---:|---:|---:|
| N0 | 5 | 1 | 166.596 | 170.683 | 6794 |
| N1 | 5 | 1 | 166.595 | 170.681 | 6794 |
| N2 | 8 | 1 | 166.580 | 170.673 | 6794 |
| N3 | 8 | 1 | 166.567 | 170.655 | 6794 |
| N4 | 3 | 3 | 45.655 | 45.660 | 6794 |
| N5 | 3 | 3 | 45.630 | 45.635 | 6778 |
| N6 | 16300 | 3 | 11.225 | 42.448 | 6778 |
| N7 | 16300 | 3 | 11.169 | 40.328 | 6745 |
| N8 | 16300 | 3 | 8.033 | 33.389 | 5835 |
| N9 | 247500 | 2 | 0.007 | 24.905 | 5682 |
| N10 | 6600 | 3 | 1.213 | 1.213 | 153 |
| N11 | 19800 | 1 | 0.017 | 1.753 | 153 |
| N12 | 50000 | 1 | 9.300 | 9.301 | 910 |
| N13 | 50000 | 1 | 0.012 | 4.756 | 910 |
| N14 | 8 | 3 | 0.035 | 0.035 | 3 |
| N15 | 8 | 3 | 0.029 | 0.030 | 3 |

Todos los Sort utilizaron quicksort, 25kB. Partial HashAggregate utilizó
24kB y un batch; Hash de pedido 1056kB, producto 2856kB y categoría 9kB,
todos con un batch. No se observó spill a archivos temporales.

N9 eliminó 5000 filas en total: Rows Removed by Filter=5000 cuando loops=1,
y promedio 2500 cuando loops=2. N11 tuvo Heap Fetches=0 en las seis corridas.
Workers planned/launched=2/2 no implica que cada scan haya sido ejecutado tres
veces: N13 y N11 muestran loops=1; N9 cambió de loops=1 a loops=2 en RUN_3..5.

## 8. Índices y camino estructural dominante

| Índice explícito conservado | Uso observado |
|---|---|
| idx_pedido_fecha_reciente | Sí: Parallel Index Only Scan, fecha=CURRENT_DATE |
| idx_producto_categoria | No |
| idx_pedido_usuario | No |
| idx_producto_nombre_vig | No |
| idx_producto_stock_bajo | No |
| idx_usuario_mail_lower | No |

No usar un índice no implica un defecto: algunos atienden otras consultas.
No se creó, retiró ni forzó ningún índice.

**Hechos del plan y lectura descriptiva:**

1. Pedido: el índice cubre 19800 pedidos vigentes del día, 153 shared hits y
   cero Heap Fetches. No se escanea toda la tabla de pedidos.
2. Detalle: el scan recorre las 500000 filas, descarta 5000 bajas y entrega
   495000 filas al proceso de unión. Registra 5682 shared hits, frente a 6794
   del nodo raíz, aproximadamente 83.6% como referencia de accesos lógicos,
   no de tiempo ni páginas físicas únicas.
3. El Parallel Hash Join pedido/detalle reduce ese flujo a 48900 filas
   utilizables (16300 de media por loop, tres loops en N8).
4. Producto: Seq Scan de 50000 filas, 910 hits y un loop real; construye el
   hash para atribuir la categoría actual. Este trabajo forma parte del
   camino hacia la agregación y no se elimina por el LIMIT.
5. Categoría: ocho filas; 3 hits observados, con tres loops. El volumen es
   pequeño respecto de detalle/producto.
6. Agregación: ocho grupos finales. Sort final y Sort previo al Gather Merge
   usan 25kB, sin spill. LIMIT retorna cinco filas, pero se aplica después
   de producir los agregados: no evita el recorrido y las uniones previas.

**Inferencia limitada:** el trabajo estructural dominante es acceder al volumen
de detalle y unirlo con pedidos/productos antes de agrupar. Producto añade una
lectura/hash de catálogo; no se concluye que eliminar ese JOIN sea necesariamente
beneficioso. Sort/LIMIT no muestran presión de memoria en este ensayo.

RUN_1 ilustra la cautela temporal: N9 reporta 54.598 ms, mientras Execution Time
es 212.668 ms. No son cantidades sumables ni el scan explica por sí solo toda la
latencia. Gather Merge y sus padres incluyen hijos, coordinación y espera;
no se atribuye toda la diferencia al arranque de workers sin instrumentación
adicional. El cambio de loops de N9 coexistió con corridas más rápidas y más
lentas: no demuestra una causa única de la variabilidad.

## 9. Plan textual representativo completo

RUN_1 fue seleccionada por coincidir con la mediana **212.668 ms**.
El textual siguiente es una **ejecución adicional** de la misma consulta y
topología; no es una conversión del JSON de RUN_1 ni su reemplazo.

REPRESENTATIVE_TEXT_PLAN: Planning Time **0.665 ms**; Execution Time
**182.831 ms**, excluido de las cinco estadísticas oficiales.

```text
Limit  (cost=12662.37..12662.39 rows=5 width=51) (actual time=177.384..182.420 rows=5 loops=1)
  Buffers: shared hit=6794
  ->  Sort  (cost=12662.37..12662.39 rows=8 width=51) (actual time=177.383..182.418 rows=5 loops=1)
        Sort Key: (sum(dp.subtotal)) DESC
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=6794
        ->  Finalize GroupAggregate  (cost=12660.17..12662.25 rows=8 width=51) (actual time=177.370..182.411 rows=8 loops=1)
              Group Key: c.nombre
              Buffers: shared hit=6794
              ->  Gather Merge  (cost=12660.17..12662.03 rows=16 width=51) (actual time=177.354..182.391 rows=8 loops=1)
                    Workers Planned: 2
                    Workers Launched: 2
                    Buffers: shared hit=6794
                    ->  Sort  (cost=11660.14..11660.16 rows=8 width=51) (actual time=54.621..54.626 rows=3 loops=3)
                          Sort Key: c.nombre
                          Sort Method: quicksort  Memory: 25kB
                          Buffers: shared hit=6794
                          Worker 0:  Sort Method: quicksort  Memory: 25kB
                          Worker 1:  Sort Method: quicksort  Memory: 25kB
                          ->  Partial HashAggregate  (cost=11659.92..11660.02 rows=8 width=51) (actual time=54.584..54.590 rows=3 loops=3)
                                Group Key: c.nombre
                                Batches: 1  Memory Usage: 24kB
                                Buffers: shared hit=6778
                                Worker 0:  Batches: 1  Memory Usage: 24kB
                                Worker 1:  Batches: 1  Memory Usage: 24kB
                                ->  Hash Join  (cost=3109.82..11555.20 rows=20945 width=26) (actual time=15.290..51.576 rows=16300 loops=3)
                                      Hash Cond: (pr.categoria_id = c.id)
                                      Buffers: shared hit=6778
                                      ->  Hash Join  (cost=3108.64..11469.91 rows=20945 width=15) (actual time=15.158..49.510 rows=16300 loops=3)
                                            Hash Cond: (dp.producto_id = pr.id)
                                            Buffers: shared hit=6745
                                            ->  Parallel Hash Join  (cost=1073.64..9379.93 rows=20945 width=15) (actual time=11.805..43.036 rows=16300 loops=3)
                                                  Hash Cond: (dp.pedido_id = ped.id)
                                                  Buffers: shared hit=5835
                                                  ->  Parallel Seq Scan on detalle_pedido dp  (cost=0.00..7765.33 rows=206076 width=23) (actual time=0.011..32.277 rows=247500 loops=2)
                                                        Filter: (NOT eliminado)
                                                        Rows Removed by Filter: 2500
                                                        Buffers: shared hit=5682
                                                  ->  Parallel Hash  (cost=924.18..924.18 rows=11957 width=8) (actual time=1.214..1.214 rows=6600 loops=3)
                                                        Buckets: 32768  Batches: 1  Memory Usage: 1056kB
                                                        Buffers: shared hit=153
                                                        ->  Parallel Index Only Scan using idx_pedido_fecha_reciente on pedido ped  (cost=0.42..924.18 rows=11957 width=8) (actual time=0.015..1.762 rows=19800 loops=1)
                                                              Index Cond: (fecha = CURRENT_DATE)
                                                              Heap Fetches: 0
                                                              Buffers: shared hit=153
                                            ->  Hash  (cost=1410.00..1410.00 rows=50000 width=16) (actual time=9.923..9.924 rows=50000 loops=1)
                                                  Buckets: 65536  Batches: 1  Memory Usage: 2856kB
                                                  Buffers: shared hit=910
                                                  ->  Seq Scan on producto pr  (cost=0.00..1410.00 rows=50000 width=16) (actual time=0.014..4.954 rows=50000 loops=1)
                                                        Buffers: shared hit=910
                                      ->  Hash  (cost=1.08..1.08 rows=8 width=27) (actual time=0.102..0.103 rows=8 loops=3)
                                            Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                            Buffers: shared hit=3
                                            ->  Seq Scan on categoria c  (cost=0.00..1.08 rows=8 width=27) (actual time=0.093..0.095 rows=8 loops=3)
                                                  Buffers: shared hit=3
Planning:
  Buffers: shared hit=29
Planning Time: 0.665 ms
Execution Time: 182.831 ms
```

## 10. Estado posterior, alcance y reversibilidad

Ambas invocaciones finalizaron con exit code 0 y guardas PASS. Los cinco conteos,
la población diaria y el Top 5 permanecen iguales; subtotal/total, FK,
duplicados y CHECK conservan cero inconsistencias. Las huellas de todas las
filas y de las definiciones de índices coinciden antes/después de cada
invocación. No aparecen objetos FNBC/TPI/Parte 2, vistas/materializadas,
rutinas de usuario, triggers no internos ni detalle_pedido.categoria_id.

No hubo cambios de datos o estructura que revertir. ANALYZE actualizó
estadísticas y no se intentó restaurar su muestra anterior. Los dos archivos
nuevos son la única unidad de cambio versionada autorizada; el script del
generador, schema, seed, Unidad 3, TPI, FNBC y los documentos históricos no
forman parte de esta modificación. La revisión y el commit se controlan
separadamente sin presumirlos a partir del éxito de PostgreSQL.

## 11. Limitaciones y conclusión descriptiva

- Baseline deliberadamente warm-cache, sin garantía de caché fría ni rendimiento
  de disco. Shared read=0 indica hits del buffer compartido durante estas corridas;
  track_io_timing está deshabilitado.
- Solo cinco mediciones oficiales, todas conservadas. No se midieron procesos
  del sistema operativo, carga externa ni causas de la dispersión.
- El paralelismo se observó, no se forzó. Workers y loops efectivos pueden
  distribuir el trabajo de forma distinta en ejecuciones posteriores.
- Las huellas corroboran datos intactos; no sustituyen un estudio multisesión.
- El dataset es sintético y tiene correlaciones modulares documentadas. El
  reporte está anclado a CURRENT_DATE=2026-09-23: si cambia, detenerse antes de
  medir, sin alterar fechas o consulta silenciosamente.
- No se comparó con mediciones históricas ni con un AFTER; no se instaló
  desnormalización, TPI, nuevos índices o materializadas.

**Conclusión:** queda fijado un baseline de **212.668 ms de mediana**, 6794 hits
en el nodo raíz y cero lecturas/temporales en las cinco corridas oficiales.
No se elige todavía entre columna redundante y materializada ni se afirma
una mejora potencial cuantificada.

Las operaciones candidatas a analizar en la fase siguiente son el acceso al
volumen de detalle, su reducción mediante el JOIN con pedidos del día y la
lectura/hash de producto para atribuir categoría antes de agregar. Evaluar
alternativas requiere autorización, equivalencia y costos medidos; este
baseline no determina por sí solo un patrón ganador.
