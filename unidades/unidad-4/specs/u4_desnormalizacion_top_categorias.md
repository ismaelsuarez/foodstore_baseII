# Spec — Unidad 4 — Experimento canónico de Top categorías

## Decisión final de la revalidación canónica — Fase 7

**FINAL_DECISION = REJECT / DO_NOT_ADOPT.** La consulta candidata redujo la
mediana de lectura de 212.668 a **87.657 ms**, pero incumplió la puerta de buffers
predeclarada: **12091 shared hit + shared read** en cada corrida oficial, frente
a 6794 BEFORE (**+77.97 %**). Incluso los hits solos fueron mayores que 6794 en
las cinco corridas. No se flexibiliza el criterio después de medir.

Fuente: [evidencia READ AFTER y decisión](../informes/evidencia_read_after_decision_modelo_canonico.md),
2026-09-23, PostgreSQL 17.11, foodstore_u4_revalidacion, HEAD de ejecución
ac668ef21ef452c91dd0748ffc08aa7bfe7a0ef5. Protocolo: un warmup y cinco corridas
oficiales, sin descartar ninguna; un plan textual adicional fuera de estadísticas.

| Puerta predeclarada | Resultado Fase 7 |
|---|---|
| MAX AFTER < 171.081 ms | PASS: 109.291 ms |
| Mediana AFTER < 212.668 ms | PASS: 87.657 ms |
| Cada corrida shared hit + shared read < 6794 | **FAIL: 12091 en las cinco** |
| Sin nuevos spills | PASS |
| Equivalencia completa / Top 5 | PASS: EXCEPT 0/0, ocho categorías; Top 5 idéntico |

El incumplimiento de una puerta obligatoria decide REJECT, independientemente
del beneficio temporal observado. Los costos de Fase 6E —INSERT +59.16 % como
comparación aritmética no causal aislada, backfill 4853.635 ms, fan-out real/stress
67.860/91.241 ms, crecimiento físico y serialización de productos distintos— no
se ocultan ni se convierten en SLO inventados. No se elimina la reserva original
sobre presupuestos de adopción; no es necesario resolverla para este rechazo.

El 40P01 de Fase 6 permanece **FAIL_CONCURRENCY_40P01**. La remediación Fase 6E
acreditó su ruta cerrada (permisos + API SECURITY DEFINER + gate previo), no DML
administrativo arbitrario: S4 directo fue BYPASS_BLOCKED; S4 autorizado y los
hard gates ensayados pasaron. DOWN fue ejecutado y revertido en Fase 6E, no en
esta fase. Ninguna conclusión acredita ausencia universal de deadlocks.

**Cierre Fase 8: REJECT / DO_NOT_ADOPT; CLEAN_CANONICAL_NO_U4_CANDIDATE.**
El 2026-09-23 se ejecutó y confirmó el DOWN definitivo: columna, FK, funciones,
triggers, esquema u4_api y roles experimentales retirados; datos y estructuras
canónicas y seis índices explícitos intactos. No reinstalar ni integrar el
candidato automáticamente. El estado PENDING_FINAL_CLEANUP correspondió a Fase 7,
cuya evidencia permanece intacta. El retiro no compactó el heap ni restituyó
el estado físico de Phase 3. Véase el [cierre técnico](../informes/informe_u4_fnbc_desnormalizacion.md)
y el [informe de entrega](../informes/informe_entrega_u4_modelo_canonico.md).

### Lectura cronológica del contrato conservado

Las secciones 1–10 siguientes conservan el contrato predeclarado de Fase 5,
incluidos umbrales y reservas, sin reescribirlos con conocimiento del AFTER.
Las expresiones «no implementado», «futuro» o «pendiente» describen aquel punto
del proceso, no el estado actual resumido arriba. Los enlaces a SQL son rutas
vigentes: su versión anterior se consulta en Git, no se supone que el archivo
haya permanecido sin cambios después de Fase 5.


**Contrato de diseño Fase 5, 2026-09-23. CANDIDATE_SELECTED_FOR_EXPERIMENT: A,
columna redundante y triggers revisados. No implementado; no ADOPTED.**

La [decisión comparativa](../informes/decision_patron_parte2_modelo_canonico.md)
fundamenta la selección frente a una vista materializada. Este spec reemplaza
el contrato operativo anterior para una implementación futura autorizada, no
reescribe sus resultados. El rechazo histórico permanece en la sección 10.

## 1. Fuentes, alcance y precondiciones

- Fuente vigente: [schema.sql](../../../schema.sql), canónico desde
  e5282f68a4af6975fb953c4f4b74f2e13240a0a6; ya no es el bootstrap histórico anterior.
- Base: foodstore_u4_revalidacion, PostgreSQL 17.11, CURRENT_DATE=2026-09-23.
- Dataset: [Fase 3](../informes/evidencia_dataset_parte2_modelo_canonico.md),
  8 categorías, 20000 usuarios, 50000 productos, 200000 pedidos, 500000 detalles.
- Baseline: [Fase 4](../informes/evidencia_baseline_parte2_modelo_canonico.md),
  mediana 212.668 ms y 6794 hits raíz; un warmup y cinco corridas oficiales.
- Conservar tres índices raíz y tres TP5. No instalar TPI, FNBC, materializadas
  ni otro índice como parte de este candidato. No alterar schema.sql ni seed.

Fase 5 no autoriza ejecutar este contrato. Antes de implementar, revalidar rama,
HEAD, fecha, conteos, integridad, índices y ausencia de objetos experimentales.
Ante diferencia, detenerse sin reparar automáticamente.

El [SQL anterior](../sql/tp_desnormalizacion_top_categorias.sql) permanece intacto
como artefacto del experimento rechazado. **No implementa este nuevo contrato de
coordinación/pruebas y no debe ejecutarse automáticamente.**

## 2. Semántica y consulta de referencia

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

Se suma subtotal físico; pedido.fecha es DATE. La PK del detalle es id y el par
pedido/producto es UNIQUE, no PK. Excluir solo bajas de pedido/detalle; no agregar
filtros de estado, usuario, producto, disponibilidad o categoría. La categoría
atribuida es la **actual** del producto, no una captura al vender.

Tiempo real significa que un nuevo SELECT bajo READ COMMITTED que vea una venta
confirmada no debe esperar un refresh periódico para reflejarla. No promete un
SLA de respuesta ni invalida snapshots previos. Una MV estándar periódica no
satisface esa inmediatez sin aceptar explícitamente staleness.

## 3. Candidato experimental y límite de la hipótesis

Proponer detalle_pedido.categoria_id BIGINT NOT NULL, FK a categoria(id) ON DELETE
RESTRICT. producto.categoria_id sigue siendo la única fuente de verdad. La
aplicación no decide la columna redundante; no se agrega UNIQUE ni índice nuevo
inicialmente. La FK comprueba existencia, no igualdad con la fuente.

Consulta conceptual candidata, **no ejecutada ni instalada en Fase 5**:

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

Retira el JOIN y scan/hash de producto (50000 filas, 910 hits en el baseline).
Permanece el recorrido de detalle (500000 filas, 5682 hits antes), JOIN con pedido,
JOIN con categoría, agregación, Sort y LIMIT. El detalle puede crecer físicamente.
Por eso eliminar producto no garantiza menos buffers o tiempo: debe medirse.

La hipótesis será rechazada para adopción si la mejora no supera la puerta de
lectura o si sus costos/corrección no satisfacen la sección 9. El antecedente fue
rechazo; esta selección no implica adopción permanente ni reabre el schema raíz.

## 4. Migración futura controlada

1. Verificar backup Phase 3 y precondiciones, sin restaurarlo automáticamente.
2. Con escritores excluidos durante instalación, abrir transacción; agregar
   columna y poblar las 500000 filas desde producto.categoria_id.
3. Validar conteo, NULL, referencias e igualdad; agregar NOT NULL y FK RESTRICT.
4. Instalar los dos mecanismos revisados de la sección 5.
5. Auditar globalmente y abortar ante cualquier diferencia antes del COMMIT.

Registrar tiempo de backfill, tamaños heap/total/índices y estadísticas físicas
antes/después. Payload nominal: 4000000 bytes (BIGINT × 500000); no predice espacio
real, MVCC, WAL ni alineación. Mantenimiento posterior requiere autorización y
registro para no ocultar efectos del backfill. No usar VACUUM FULL/CLUSTER ni
un índice adicional para favorecer el AFTER.

## 5. Autoridad, sincronización y concurrencia propuestas

| Objeto conceptual | Responsabilidad futura |
|---|---|
| fn_detalle_pedido_set_categoria | Obtener categoría actual del producto con FOR SHARE y asignar NEW |
| trg_detalle_pedido_set_categoria | BEFORE INSERT OR UPDATE OF producto_id, categoria_id; siempre rederivar |
| fn_producto_sync_categoria_detalle | Ante cambio real, propagar a todos los detalles del producto |
| trg_producto_sync_categoria_detalle | AFTER UPDATE OF categoria_id de producto |

El código viejo usa SELECT sin lock. FOR SHARE se propone para coordinar con
recategorización; FOR KEY SHARE no bloquearía la actualización de una columna
no clave. Mantener funciones trigger VOLATILE y validar mediante ejecución la
visibilidad de la propagación tras esperar: el modo de lock no demuestra una
solución universal. Véase [PostgreSQL 17: bloqueos](https://www.postgresql.org/docs/17/explicit-locking.html).

Propagar también a detalles eliminados y de pedidos eliminados: una posterior
reactivación debe conservar la categoría actual. No modificar precio histórico,
subtotal, total ni stock. Baja de producto/categoría no debe ocultar historia.
No hay recursión hacia producto cuando el trigger de detalle solo asigna NEW.

INSERT/UPDATE de categoría redundante falsa debe sobrescribirse con la fuente,
incluso si se proporciona NULL. Producto no nulo inexistente debe dar 23503
explícito, identificado como referencia ausente, no 23502 provocado por el
redundante. Producto_id NULL conserva su restricción estructural. Son criterios
pendientes de prueba, no resultados de Fase 5.

Orden preferido de rutas coordinadas: producto antes de detalles, con orden
estable de IDs para varios productos. UPDATE directo puede tomar primero detalle
y luego producto, frente al fan-out producto→detalle. **Puede existir deadlock
40P01**: registrar abortos y solo reintentar la transacción completa mediante
política futura explícita. No ocultar errores ni prometer ausencia universal de
deadlocks. No se acredita seguridad de DML arbitrario, otros aislamientos o alta carga.

Diagnóstico SELECT actual de detalles por producto: MIN = 9, MAX = 12, AVG = 10,
P50 = 10 y P95 = 11 (percentile_cont); cero productos sin detalles y 5000 bajas.
UNIQUE(pedido_id,producto_id) no permite presumir acceso selectivo por producto_id:
propagar puede exigir recorrer detalle. No extrapolar el fan-out a miles de ventas.

## 6. Auditoría y equivalencia obligatorias

- Auditoría global sin filtrar bajas: categoria_id no nula, FK válida y
  dp.categoria_id IS NOT DISTINCT FROM pr.categoria_id para cada producto.
- EXCEPT bidireccional de **todos** los grupos, antes de LIMIT: 0/0.
- Top 5 exacto igual al checkpoint, ocho agregados distintos. Si hay empate o
  cambian datos, detenerse; no agregar desempate ni manipular filas.
- Conteos y huellas canónicas intactos después de pruebas revertidas. Verificar
  subtotal/total y restricciones previas, no solo el nuevo redundante.

FK y NOT NULL no sustituyen la auditoría de igualdad. Una medición no es válida
si cambia el resultado o deja una categoría desincronizada.

## 7. Pruebas y protocolo AFTER, todavía pendientes

**READ:** mismo dataset, día, configuración e índices; warm-cache de Fase 4,
SELECT semánticos equivalentes, un warmup + cinco JSON oficiales. Mediana de
Execution Time, MIN/MAX/MEDIA, Planning Time, buffers raíz, nodos, filas, loops y
workers; todos conservados. Un textual adicional fuera de estadísticas. Sin
forzar plan, descartar outliers ni sumar tiempos/buffers anidados.

**WRITE:** referencia canónica antes de instalar A y A completo después; INSERT
con mismo fixture, un warmup + cinco corridas, restricciones habilitadas y ROLLBACK.
Preparación fuera de tiempo; documentar identity/caché/MVCC. El costo aislado del
trigger, si se mide aparte, no representa columna+FK+trigger. Medir backfill/tamaños
y UPDATE de producto con fan-out bajo/mediano/alto observado (9/10/12), líneas
propagadas, locks y auditoría. No extrapolar a alta carga.

**FUNCIONAL:** INSERT, reasignación de producto, manipulación del redundante,
producto inexistente, NULL, FK/UNIQUE, rollback, bajas/reactivaciones de líneas y
pedidos, baja de maestros y recategorización de detalles eliminados. Registrar
SQLSTATE reales y ausencia de cambios en stock/subtotal/total por A.

**CONCURRENCIA:** dos conexiones más monitor. INSERT↔recategorización en ambos
órdenes, COMMIT y ROLLBACK del bloqueador; dos recategorizaciones del mismo
producto; reasignación/manipulación del detalle frente a recategorización.
Capturar espera, SQLSTATE y estado final; auditar todas las líneas. Un 40P01 no
equivale a PASS de adopción: evaluar contención/reintentos contra presupuesto.
Ninguna inconsistencia confirmada es admisible. Todo requiere autorización posterior.

## 8. Reversibilidad: DOWN real obligatorio

Retirar solo triggers y funciones del candidato, después FK y columna redundantes,
en orden de dependencias y sin CASCADE. producto.categoria_id conserva toda la
información fuente; no eliminar tablas canónicas ni datos originales.

Ejecutar y verificar DOWN, no limitarse a revisarlo. Comparar catálogo,
restricciones, datos/huellas, seis índices explícitos y salida normalizada.
Confirmar ausencia de A, TPI y FNBC; documentar estado final. El DOWN histórico
solo fue estático y no acredita esta condición.

## 9. Puertas de decisión antes del AFTER

Estado actual: CANDIDATE_SELECTED_FOR_EXPERIMENT. ADOPT queda pendiente.

Puerta de lectura conservadora:

1. MAX de cinco AFTER < 171.081 ms, mínimo BEFORE.
2. Mediana AFTER < 212.668 ms.
3. Cada corrida AFTER: buffers raíz shared hit + shared read < 6794, separando
   hits/reads y sin nuevos spills temporales.

Es separación descriptiva de rangos, no significancia estadística ni porcentaje
arbitrario. Solapamiento implica evidencia insuficiente para adoptar con este
criterio, no demuestra igualdad. No cambiar la puerta al conocer resultados.

ADOPT exige además equivalencia/auditoría 0, pruebas de errores y concurrencia,
frescura, DOWN real y costos dentro de presupuestos acordados. **Workload y SLO
de INSERT, UPDATE/esperas y almacenamiento deben aprobarse antes del AFTER**;
todavía no hay límites numéricos justificados. Sin ellos no hay ADOPT, aunque
mejore la lectura. No bloquean esta selección documental.

REJECT / DO_NOT_ADOPT ante inconsistencia, cambio semántico, carrera no controlada,
DOWN fallido, puerta de lectura incumplida, costo fuera de presupuesto o contención
inaceptable. Si el protocolo no es comparable, detenerse y documentar; no repetir
hasta conseguir un resultado favorable. Ningún resultado integra automáticamente
la columna al schema raíz.

## 10. Antecedente preservado: HISTORICAL_NOT_COMPARABLE

El cierre 95fbfbf del 2026-09-20 evaluó columna + triggers en foodstore_u4_oficial.
Su decisión permanece **REJECTED_AFTER_MEASUREMENT / DO_NOT_ADOPT**: beneficio
limitado frente a buffers, escritura, dispersión y complejidad.

Ese modelo ya tenía subtotal físico, eliminado y fecha DATE; no se declara
incorrecto por carecer de ellos. Dataset 220000 pedidos/550000 detalles, fecha y
protocolo difieren del checkpoint actual. No reutilizar tiempos históricos como
baseline ni AFTER. El aviso anterior sobre schema raíz describía aquel momento,
no la fuente canónica vigente.

Se conservan la [evidencia original](../informes/evidencia_modelo_oficial.md), el
[informe del cierre](../informes/informe_u4_fnbc_desnormalizacion.md) y el
[SQL rechazado](../sql/tp_desnormalizacion_top_categorias.sql). Derivación,
propagación, manipulación y dos UPDATE concurrentes pasaron en su alcance;
no se probó INSERT concurrente contra recategorización ni se ejecutó DOWN.
No se convierten retrospectivamente en resultados del nuevo contrato.

La nueva decisión conserva producto como autoridad y la frescura, pero exige
coordinación y evidencia faltantes. Seleccionar un nuevo experimento no invalida
el rechazo anterior ni equivale a adoptar la desnormalización.
