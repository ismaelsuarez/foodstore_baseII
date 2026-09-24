# U4 — READ AFTER canónico y decisión final de desnormalización

**FINAL_DECISION = REJECT / DO_NOT_ADOPT.** La mediana mejoró a **87.657 ms**, pero las cinco corridas
consumieron **12091 accesos shared raíz**, frente al límite obligatorio de **6794**.
La puerta de buffers falla; no se flexibiliza por la mejora temporal. El candidato queda
**REJECTED_PENDING_FINAL_CLEANUP**, instalado exclusivamente hasta el cierre autorizado de Fase 8.

## 1. Identidad, fuentes y preflight

| Dato | Verificado |
|---|---|
| Fecha SQL | 2026-09-23 |
| Repo | C:/Users/facu/Documents/UTN/Base_datos_II/foodStore |
| Rama | fix/u4-revalidacion-canonica |
| HEAD de ejecución | ac668ef21ef452c91dd0748ffc08aa7bfe7a0ef5 |
| Estado Git inicial | CLEAN |
| Base | foodstore_u4_revalidacion |
| PostgreSQL | 17.11 |
| Actor de lectura | postgres, igual al baseline; no se ejercieron escrituras de aplicación |
| Columnas canónicas / índices | Intactos; 14 índices, incluidos seis explícitos raíz + TP5 |
| Candidato | categoria_id BIGINT NOT NULL, FK RESTRICT, 7 funciones y 4 triggers |
| Seguridad | u4_app/u4_owner y ACL vigentes; cuerpos de funciones iguales al SQL de HEAD |
| TPI / FNBC / MV | Ausentes |

Se verificaron conteos, huellas de todas las filas canónicas, secuencias, constraints e índices contra
el cierre 6E. Roles sin membresías privilegiadas, permisos efectivos cerrados y ninguna sesión app ni gate
pendiente. Los hard gates funcionales/concurrentes y DOWN se reutilizan de la evidencia 6E; no se repitieron.

Fuentes: [baseline Fase 4](evidencia_baseline_parte2_modelo_canonico.md),
[criterios predeclarados Fase 5](decision_patron_parte2_modelo_canonico.md),
[remediación Fase 6E](evidencia_remediacion_serializada_modelo_canonico.md) y
[spec con decisión](../specs/u4_desnormalizacion_top_categorias.md).

Dump verificado, no restaurado: `backups/foodstore_u4_revalidacion_phase6e_candidate.dump`.
SHA-256: `7BA7A261AB0923969A304A59BF6C6BF8532AE9D9BC14E036470E278E37D4628F`.

## 2. Entorno y protocolo

Las trece configuraciones consultadas coinciden con Fase 4, sin SET ni cambios globales:

| Parámetro | Valor |
|---|---|
| server_version | 17.11 |
| TimeZone | America/Buenos_Aires |
| shared_buffers | 128MB |
| effective_cache_size | 4GB |
| work_mem | 4MB |
| maintenance_work_mem | 64MB |
| random_page_cost / seq_page_cost | 4 / 1 |
| effective_io_concurrency | 0 |
| max_parallel_workers / per_gather | 8 / 2 |
| jit / track_io_timing | on / off |

Marca temporal SQL del ensayo: `2026-09-23T21:15:51.315354-03:00`.

Se ejecutaron exactamente ANALYZE categoria, producto, pedido y detalle_pedido; exit 0.
No ANALYZE usuario, VACUUM, reinicio, CHECKPOINT, DISCARD ALL, cambios de datos, índices o estructura.

**Warm-cache:** consultas diagnósticas y semánticas previas, un WARMUP y cinco oficiales,
sin vaciar cachés. No significa que todos los bloques estén en shared_buffers: hubo reads en todas las corridas.
No se mide cache fría ni se atribuyen esos reads necesariamente a disco físico.

Cada EXPLAIN JSON se ejecutó en una invocación psql nueva (`-X -w`, ON_ERROR_STOP=1), con la misma configuración
sin preparación/plan reutilizado. El baseline agrupaba sus corridas en un script; esta diferencia de sesión
se explicita, particularmente por su efecto posible sobre Planning Time. La métrica oficial sigue siendo
Execution Time del servidor, no duración del cliente ni Planning Time. No se afirma aislamiento causal perfecto.

Se verificó equivalencia y Top 5 antes y después de cada corrida mediante SELECT separados. Esos SELECT también
calientan cachés y no entran en Execution Time. Ninguna corrida se descartó, repitió ni sustituyó.
Se ejecutaron seis JSON (1+5), un EXPLAIN estimado y un textual adicional. Todas las invocaciones SQL exit 0.

## 3. Consulta exacta y equivalencia

```sql
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c ON c.id = dp.categoria_id
JOIN pedido ped ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```
El BEFORE conserva la consulta original con JOIN producto, según Fase 4. La única diferencia lógica del AFTER
es suprimir ese JOIN y atribuir categoria directamente desde dp.categoria_id; se conservan filtros y orden.

Agregado completo: **8 grupos original / 8 candidato; EXCEPT original−candidato=0 y candidato−original=0**.
Resultado exacto antes, entre corridas y después:

| Categoría | total_vendido |
|---|---:|
| __U4_LAB_CATEGORIA_07__ | 194538488.00 |
| __U4_LAB_CATEGORIA_03__ | 90236048.00 |
| __U4_LAB_CATEGORIA_06__ | 88912722.00 |
| __U4_LAB_CATEGORIA_05__ | 74717570.00 |
| __U4_LAB_CATEGORIA_08__ | 40242037.00 |

## 4. Plan estimado, sin medición temporal

Raíz Limit, cinco filas estimadas, costo 16850.83..16850.84. Dos workers previstos.
Los identificadores N son etiquetas del documento, no objetos PostgreSQL.

| Nodo | Padre | Tipo | Relación / índice | Plan Rows |
|---|---|---|---|---:|
| N0 | — | Limit | — / — | 5 |
| N1 | N0 | Sort | — / — | 8 |
| N2 | N1 | Aggregate Sorted Finalize | — / — | 8 |
| N3 | N2 | Gather Merge | — / — | 16 |
| N4 | N3 | Sort | — / — | 8 |
| N5 | N4 | Aggregate Hashed Partial | — / — | 8 |
| N6 | N5 | Hash Join | — / — | 20292 |
| N7 | N6 | Parallel Hash Join | — / — | 20292 |
| N8 | N7 | Parallel Seq Scan | detalle_pedido / — | 206208 |
| N9 | N7 | Parallel Hash | — / — | 11577 |
| N10 | N9 | Parallel Index Only Scan | pedido / idx_pedido_fecha_reciente | 11577 |
| N11 | N6 | Hash | — / — | 8 |
| N12 | N11 | Seq Scan | categoria / — | 8 |

## 5. AFTER: tiempos y buffers raíz

Execution Time y Planning Time en ms. Buffers del nodo raíz; nunca suma de padres e hijos.
Dirtied, written, temp read y temp written fueron 0 en todas las corridas y nodos.
Cada corrida registró 5 filas finales, loops raíz 1 y workers planned/launched 2/2.

| Corrida | Planning ms | Execution ms | Shared hit | Shared read | Hit+read |
|---|---:|---:|---:|---:|---:|
| WARMUP | 1.636 | 95.204 | 7149 | 4942 | 12091 |
| AFTER_RUN_1 | 1.767 | 87.657 | 7373 | 4718 | 12091 |
| AFTER_RUN_2 | 1.474 | 86.012 | 7597 | 4494 | 12091 |
| AFTER_RUN_3 | 1.390 | 84.582 | 7821 | 4270 | 12091 |
| AFTER_RUN_4 | 2.358 | 109.291 | 8053 | 4038 | 12091 |
| AFTER_RUN_5 | 1.493 | 88.504 | 8277 | 3814 | 12091 |

Solo RUN1..RUN5: **MIN 84.582 / MAX 109.291 / MEDIA 91.2092 / MEDIANA 87.657 ms**.
WARMUP 95.204 ms no entra en estadísticas. RUN4 es la mayor y permanece incluida.
No se investigó la causa de variación ni se afirma significancia estadística.

## 6. Nodos medidos y trabajo restante

Misma topología en seis JSON: Parallel Seq Scan de detalle; Parallel Index Only Scan de pedido con
idx_pedido_fecha_reciente y Heap Fetches 0; Parallel Hash Join pedido/detalle; Hash Join con categoría;
Partial HashAggregate, Sort, Gather Merge, Finalize GroupAggregate, Sort y Limit.

No hay scan/hash/JOIN de producto. Quedan 500000 detalles recorridos, 495000 no eliminados,
48900 líneas tras filtro de pedidos, 8 grupos y 5 filas finales. Actual Rows se interpreta junto a loops:
por ejemplo 165000×3=495000 para detalle. Rows Removed es redondeado por loop, no reemplaza conteos exactos.

Sort quicksort 25 kB, memoria; agregación una tanda, Disk Usage 0; hashes una tanda. Sin spill.
El índice TP5 de fecha sigue utilizado; los otros cinco explícitos no aparecen en este plan.
Los tiempos padres incluyen hijos; no se suman ni permiten atribuir automáticamente un único cuello.

Detalle usa 11855 accesos shared por corrida, pedido 184, categoría 3. Son nodos separados, no una suma alternativa
al resumen raíz 12091. La lectura extensa de detalle y su unión con pedido siguen siendo el camino principal;
el aumento físico compensa ampliamente los 910 accesos de producto retirados del plan.

### Datos por nodo de cada corrida

En las tablas, tiempo es Actual Total Time; filas/tiempos del nodo son por ejecución cuando loops>1.
Los workers efectivos constan en Gather Merge; no se multiplican buffers por loops.

#### WARMUP

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 95.046 | 7149 | 4942 | — |
| N1 | 5 | 1 | 95.043 | 7149 | 4942 | — |
| N2 | 8 | 1 | 94.964 | 7146 | 4942 | — |
| N3 | 24 | 1 | 94.942 | 7146 | 4942 | 2/2 |
| N4 | 8 | 3 | 65.565 | 7146 | 4942 | — |
| N5 | 8 | 3 | 65.510 | 7130 | 4942 | — |
| N6 | 16300 | 3 | 60.463 | 7130 | 4942 | — |
| N7 | 16300 | 3 | 57.093 | 7097 | 4942 | — |
| N8 | 165000 | 3 | 35.408 | 6913 | 4942 | — |
| N9 | 6600 | 3 | 1.794 | 184 | 0 | — |
| N10 | 19800 | 1 | 2.871 | 184 | 0 | — |
| N11 | 8 | 3 | 0.039 | 3 | 0 | — |
| N12 | 8 | 3 | 0.034 | 3 | 0 | — |

#### AFTER_RUN_1

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 87.482 | 7373 | 4718 | — |
| N1 | 5 | 1 | 87.479 | 7373 | 4718 | — |
| N2 | 8 | 1 | 87.412 | 7370 | 4718 | — |
| N3 | 24 | 1 | 87.388 | 7370 | 4718 | 2/2 |
| N4 | 8 | 3 | 60.887 | 7370 | 4718 | — |
| N5 | 8 | 3 | 60.689 | 7354 | 4718 | — |
| N6 | 16300 | 3 | 56.596 | 7354 | 4718 | — |
| N7 | 16300 | 3 | 53.859 | 7321 | 4718 | — |
| N8 | 165000 | 3 | 32.299 | 7137 | 4718 | — |
| N9 | 6600 | 3 | 1.723 | 184 | 0 | — |
| N10 | 19800 | 1 | 2.777 | 184 | 0 | — |
| N11 | 8 | 3 | 0.038 | 3 | 0 | — |
| N12 | 8 | 3 | 0.030 | 3 | 0 | — |

#### AFTER_RUN_2

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 85.865 | 7597 | 4494 | — |
| N1 | 5 | 1 | 85.862 | 7597 | 4494 | — |
| N2 | 8 | 1 | 85.802 | 7594 | 4494 | — |
| N3 | 24 | 1 | 85.788 | 7594 | 4494 | 2/2 |
| N4 | 8 | 3 | 58.956 | 7594 | 4494 | — |
| N5 | 8 | 3 | 58.902 | 7578 | 4494 | — |
| N6 | 16300 | 3 | 53.843 | 7578 | 4494 | — |
| N7 | 16300 | 3 | 50.438 | 7545 | 4494 | — |
| N8 | 165000 | 3 | 31.000 | 7361 | 4494 | — |
| N9 | 6600 | 3 | 1.513 | 184 | 0 | — |
| N10 | 19800 | 1 | 2.444 | 184 | 0 | — |
| N11 | 8 | 3 | 0.057 | 3 | 0 | — |
| N12 | 8 | 3 | 0.046 | 3 | 0 | — |

#### AFTER_RUN_3

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 84.432 | 7821 | 4270 | — |
| N1 | 5 | 1 | 84.428 | 7821 | 4270 | — |
| N2 | 8 | 1 | 84.360 | 7818 | 4270 | — |
| N3 | 24 | 1 | 84.345 | 7818 | 4270 | 2/2 |
| N4 | 8 | 3 | 57.257 | 7818 | 4270 | — |
| N5 | 8 | 3 | 57.208 | 7802 | 4270 | — |
| N6 | 16300 | 3 | 52.553 | 7802 | 4270 | — |
| N7 | 16300 | 3 | 49.486 | 7769 | 4270 | — |
| N8 | 165000 | 3 | 29.921 | 7585 | 4270 | — |
| N9 | 6600 | 3 | 2.460 | 184 | 0 | — |
| N10 | 19800 | 1 | 3.671 | 184 | 0 | — |
| N11 | 8 | 3 | 0.044 | 3 | 0 | — |
| N12 | 8 | 3 | 0.036 | 3 | 0 | — |

#### AFTER_RUN_4

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 109.023 | 8053 | 4038 | — |
| N1 | 5 | 1 | 109.018 | 8053 | 4038 | — |
| N2 | 8 | 1 | 108.933 | 8050 | 4038 | — |
| N3 | 24 | 1 | 108.904 | 8050 | 4038 | 2/2 |
| N4 | 8 | 3 | 73.361 | 8050 | 4038 | — |
| N5 | 8 | 3 | 73.287 | 8034 | 4038 | — |
| N6 | 16300 | 3 | 68.328 | 8034 | 4038 | — |
| N7 | 16300 | 3 | 65.027 | 8001 | 4038 | — |
| N8 | 165000 | 3 | 39.923 | 7817 | 4038 | — |
| N9 | 6600 | 3 | 2.707 | 184 | 0 | — |
| N10 | 19800 | 1 | 4.081 | 184 | 0 | — |
| N11 | 8 | 3 | 0.089 | 3 | 0 | — |
| N12 | 8 | 3 | 0.080 | 3 | 0 | — |

#### AFTER_RUN_5

| Nodo | Rows | Loops | Total ms | Hit | Read | Workers planned/launched |
|---|---:|---:|---:|---:|---:|---|
| N0 | 5 | 1 | 88.342 | 8277 | 3814 | — |
| N1 | 5 | 1 | 88.338 | 8277 | 3814 | — |
| N2 | 8 | 1 | 88.272 | 8274 | 3814 | — |
| N3 | 24 | 1 | 88.238 | 8274 | 3814 | 2/2 |
| N4 | 8 | 3 | 58.970 | 8274 | 3814 | — |
| N5 | 8 | 3 | 58.918 | 8258 | 3814 | — |
| N6 | 16300 | 3 | 54.362 | 8258 | 3814 | — |
| N7 | 16300 | 3 | 51.360 | 8225 | 3814 | — |
| N8 | 165000 | 3 | 32.378 | 8041 | 3814 | — |
| N9 | 6600 | 3 | 1.747 | 184 | 0 | — |
| N10 | 19800 | 1 | 2.787 | 184 | 0 | — |
| N11 | 8 | 3 | 0.054 | 3 | 0 | — |
| N12 | 8 | 3 | 0.047 | 3 | 0 | — |

## 7. Comparación BEFORE / AFTER

BEFORE oficial preservado: [212.668,235.256,199.683,324.541,171.081] ms.
No se volvió a medir ni se sustituyó por otro ensayo histórico.

| Métrica | BEFORE | AFTER | Diferencia |
|---|---:|---:|---|
| Mediana ms | 212.668 | 87.657 | -125.011; reducción 58.7822% |
| MIN ms | 171.081 | 84.582 | -86.499 |
| MAX ms | 324.541 | 109.291 | -215.250 |
| MEDIA ms | 228.6458 | 91.2092 | -137.4366 |
| Root shared hit, por corrida | 6794 | 7373/7597/7821/8053/8277 | +579/+803/+1027/+1259/+1483 |
| Root shared read, por corrida | 0 | 4718/4494/4270/4038/3814 | aumentaron, no equivalen necesariamente a disco |
| Root hit+read, cada corrida | 6794 | 12091 | +5297; aumento 77.9659% |
| Detalle hit+read, cada corrida | 5682 | 11855 | +6173 |
| Producto hit+read | 910 | 0 | -910; eliminado del plan |
| Pedido hit+read | 153 | 184 | +31 |
| Joins | 3 | 2 | -1, se retiró producto |
| Tablas accedidas | 4 | 3 | -1 |
| Filas finales | 5 | 5 | sin cambio |
| Spills | 0 | 0 | sin cambio |
| Workers planned/launched | 2/2 | 2/2 | sin cambio |

Speedup de medianas=212.668/87.657=**2.426138x**.
Reducción temporal=(212.668−87.657)/212.668×100=**58.782233%**.
Reducción de buffers=(6794−12091)/6794×100=**−77.965852%**: es crecimiento, no ahorro.
Se usa hit+read como métrica predeclarada; las cinco cifras de hits solas también superan 6794.

La distribución efectiva entre workers y el estado físico difieren del BEFORE, aunque la configuración
sea igual. Esta comparación describe resultados bajo el protocolo, no demuestra que retirar el JOIN
cause por sí solo toda la reducción temporal. No se afirma significancia con cinco observaciones.

## 8. Hard gates y decisión inmutable

| Gate predeclarado | Observado | Resultado |
|---|---|---|
| MAX AFTER <171.081ms | 109.291 | PASS |
| MEDIANA AFTER <212.668ms | 87.657 | PASS |
| Cada root shared hit+read <6794 | 12091 en las cinco | **FAIL** |
| Sin nuevos spills | 0 | PASS |
| Equivalencia completa y Top 5 | 0/0 e idéntico | PASS |
| Corrección/concurrencia ruta autorizada y DOWN | Evidencia6E preservada | PASS en alcance ensayado |

**FINAL_DECISION=REJECT / DO_NOT_ADOPT.** Una puerta obligatoria falla y basta para rechazar.
La mejora temporal no permite negociar ese criterio después de ver los datos.
Fase 7 puede cerrarse PASS como proceso de medición/decisión aunque la adopción sea REJECT.

Fase 5 exigía presupuestos previos para escritura/esperas/almacenamiento; no hay SLO numérico aprobado.
No se inventó uno ni se convirtió esa ausencia en permiso de adopción. El rechazo ya es obligatorio por lectura.

## 9. Costos y antecedentes que no se borran

- INSERT remediado: mediana 38.640 ms frente a 24.278 ms canónico; **+59.16% aritmético**, no costo causal aislado
  del gate porque API/JSON/setup/estado físico difieren. Candidato fallido 40.567 ms y +67.09% permanecen.
- Backfill remediado: 500000 filas, 4853.635 ms. Fan-out real 12: 67.860 ms; estrés 1012: 91.241 ms.
- Gate(21812,1) serializa productos distintos; espera S5=1.395788 s incluye una retención deliberada de 1.2 s,
  no estima throughput productivo. Roles/API añaden administración y cambian la ruta operativa.
- Detalle Phase3: heap 46546944, total 73637888 bytes; ahora heap 97116160, total 151298048.
  El aumento comprende migración y pruebas/MVCC; no se atribuye solo al valor BIGINT.
- Fase 6 mantiene **FAIL_CONCURRENCY_40P01**: detalle→producto frente a producto→detalle.
  Se conserva [evidencia del fallo](evidencia_implementacion_candidato_a_modelo_canonico.md), pruebas y dump forense.
- Fase 6E: S4 directo **BYPASS_BLOCKED, 42501**, distinto de S4 autorizado PASS; S1–S3 PASS por API,
  sin 40P01 en esos ensayos. La garantía no abarca superusuario/owner que eluda deliberadamente el contrato.
  Sus incidencias de arnés siguen documentadas, no se reinterpretan como fallos SQL ni se eliminan.
- El rechazo de 95fbfbf es HISTORICAL_NOT_COMPARABLE, no baseline vigente. No se copiaron sus tiempos como AFTER.

## 10. Plan textual representativo completo

AFTER_RUN1 coincide exactamente con la mediana; fue la referencia seleccionada.
Se ejecutó luego un EXPLAIN textual independiente: **91.189 ms**, fuera de las cinco estadísticas.

```text
Limit  (cost=16850.83..16850.84 rows=5 width=51) (actual time=83.623..90.730 rows=5 loops=1)
  Buffers: shared hit=8405 read=3686
  ->  Sort  (cost=16850.83..16850.85 rows=8 width=51) (actual time=83.615..90.722 rows=5 loops=1)
        Sort Key: (sum(dp.subtotal)) DESC
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=8405 read=3686
        ->  Finalize GroupAggregate  (cost=16848.62..16850.71 rows=8 width=51) (actual time=83.423..90.543 rows=8 loops=1)
              Group Key: c.nombre
              Buffers: shared hit=8402 read=3686
              ->  Gather Merge  (cost=16848.62..16850.49 rows=16 width=51) (actual time=83.414..90.526 rows=24 loops=1)
                    Workers Planned: 2
                    Workers Launched: 2
                    Buffers: shared hit=8402 read=3686
                    ->  Sort  (cost=15848.60..15848.62 rows=8 width=51) (actual time=57.594..57.597 rows=8 loops=3)
                          Sort Key: c.nombre
                          Sort Method: quicksort  Memory: 25kB
                          Buffers: shared hit=8402 read=3686
                          Worker 0:  Sort Method: quicksort  Memory: 25kB
                          Worker 1:  Sort Method: quicksort  Memory: 25kB
                          ->  Partial HashAggregate  (cost=15848.38..15848.48 rows=8 width=51) (actual time=57.542..57.547 rows=8 loops=3)
                                Group Key: c.nombre
                                Batches: 1  Memory Usage: 24kB
                                Buffers: shared hit=8386 read=3686
                                Worker 0:  Batches: 1  Memory Usage: 24kB
                                Worker 1:  Batches: 1  Memory Usage: 24kB
                                ->  Hash Join  (cost=1185.80..15746.92 rows=20292 width=26) (actual time=12.594..53.719 rows=16300 loops=3)
                                      Hash Cond: (dp.categoria_id = c.id)
                                      Buffers: shared hit=8386 read=3686
                                      ->  Parallel Hash Join  (cost=1184.62..15664.26 rows=20292 width=15) (actual time=12.496..51.107 rows=16300 loops=3)
                                            Hash Cond: (dp.pedido_id = ped.id)
                                            Buffers: shared hit=8353 read=3686
                                            ->  Parallel Seq Scan on detalle_pedido dp  (cost=0.00..13938.33 rows=206208 width=23) (actual time=0.302..31.924 rows=165000 loops=3)
                                                  Filter: (NOT eliminado)
                                                  Rows Removed by Filter: 1667
                                                  Buffers: shared hit=8169 read=3686
                                            ->  Parallel Hash  (cost=1039.91..1039.91 rows=11577 width=8) (actual time=2.771..2.772 rows=6600 loops=3)
                                                  Buckets: 32768  Batches: 1  Memory Usage: 1056kB
                                                  Buffers: shared hit=184
                                                  ->  Parallel Index Only Scan using idx_pedido_fecha_reciente on pedido ped  (cost=0.42..1039.91 rows=11577 width=8) (actual time=0.051..3.941 rows=19800 loops=1)
                                                        Index Cond: (fecha = CURRENT_DATE)
                                                        Heap Fetches: 0
                                                        Buffers: shared hit=184
                                      ->  Hash  (cost=1.08..1.08 rows=8 width=27) (actual time=0.059..0.060 rows=8 loops=3)
                                            Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                            Buffers: shared hit=3
                                            ->  Seq Scan on categoria c  (cost=0.00..1.08 rows=8 width=27) (actual time=0.048..0.050 rows=8 loops=3)
                                                  Buffers: shared hit=3
Planning:
  Buffers: shared hit=374
Planning Time: 2.252 ms
Execution Time: 91.189 ms
```

## 11. Auditoría posterior y estado de la base

Conteos 8/20000/50000/200000/500000. Día: 20000 pedidos / 19800 vigentes;
50000 detalles / 48900 utilizables / 8 categorías. Subtotal, total, FK, UNIQUE, CHECK, desync y NULL = 0.
EXCEPT 0/0 y Top 5 idéntico antes/después de todas las corridas.

Coinciden huellas de filas canónicas, secuencias, columnas/constraints/índices, funciones/triggers,
roles y permisos antes/después. Sin sesiones app/owner, transacciones abiertas ajenas al monitor ni gate pendiente.
No se cambiaron dataset, API, autenticación, permisos o estructura; solo estadísticas mediante ANALYZE.

Tamaños de heap/total permanecen iguales al preflight de esta fase. No se ejecutó VACUUM para alterar
el estado físico recibido de 6E; se conservan sus límites diagnósticos. Las estadísticas de tuplas no
se utilizan como conteos exactos.

**DB_STATUS_AFTER_DECISION=REJECTED_PENDING_FINAL_CLEANUP.** No se ejecutó DOWN definitivo.
El candidato sigue instalado únicamente hasta la limpieza expresamente autorizada en Fase 8.

## 12. Reproducción, alcance y límites

SQL exacto arriba, seis invocaciones JSON y una textual, siempre sobre la misma base/fecha:

```powershell
psql -X -w -h 127.0.0.1 -p 5432 -U postgres -d foodstore_u4_revalidacion -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -At -c "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) <consulta exacta>"
```

El marcador no es un comando listo para copiar: sustituirlo por el SELECT exacto de sección 3.
Repetir una medición requiere autorización; este documento no autoriza nuevas corridas ni cleanup.

Logs fuera del repo: `C:/Users/facu/AppData/Local/Temp/foodstore-u4-phase7-29bb0486`.
Se conservan phase7.py, preflight/post_read.json, auditorías, security/equivalence, environment,
analyze.sql/stdout/stderr, estimated.json, WARMUP/AFTER_RUN1..5JSON, consultas semánticas por corrida,
summary.json y representative_text.sql/stdout/stderr. La ruta temporal no se supone permanente;
las mediciones, nodos, plan textual, criterios y decisión quedan consolidados en este documento.

Limitaciones: dataset sintético, día fijo, cinco muestras, warm-cache no equivalente a residencia completa,
track_io_timing=off, falta de aislamiento del sistema operativo/carga externa y evolución física desde Fase 4.
No se ejecutaron nuevos DML, concurrencia, mantenimiento físico, integración TPI ni experimentos alternativos.
La delegación redactó solo decisión/cronología en spec e informe; la ejecución SQL y captura fueron del coordinador.
Un intento de invocar el alias python del sistema no encontró intérprete; se utilizó py 3.9 antes de cualquier
medición. No hubo fallo SQL ni corrida repetida por ese detalle del entorno.

Unidad de cambio: esta evidencia, decisión final del spec y actualización de cierre del informe vigente.
No se modifican SQL candidato, históricos, FNBC, Unidad 3, TPI, schema ni seed. Revertir esta unidad documental
no revierte objetos instalados; el DOWN definitivo pertenece a otra autorización. Commit local, sin push.

**Siguiente acción: Fase 8 de cierre/cleanup, solo tras autorización; mantener el rechazo y toda la evidencia.**
