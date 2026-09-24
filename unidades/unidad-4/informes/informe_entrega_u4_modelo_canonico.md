# BASE DE DATOS II
# Unidad 4 — FNBC y Desnormalización Controlada
# Food Store

**Integrantes:** Avalos Pablo · Blangetti Sofia · Suarez Ismael.

## 1. Objetivo

Demostrar una descomposición a FNBC y evaluar una desnormalización mediante
corrección, reversibilidad y mediciones reales. Se utilizó PostgreSQL **17.11**
y el modelo canónico de [schema.sql](../../../schema.sql), sin modificarlo.
**Resultado: Parte 1 PASS; Parte 2 implementada, medida y descartada (REJECT).**

## 2. Parte 1 — ControlLoteAlmacen

### 2.1. Dependencias funcionales

Para `ControlLoteAlmacen(LoteID, DepositoID, ResponsableControlID)`, abreviado
S(L,D,R), la consigna establece **F1: LD → R** y **F2: R → D**.
Son reglas de negocio, no dependencias inferidas únicamente del ejemplo.
Se reutilizaron usuarios existentes 1 y 2: 801 lógico → 1, 802 lógico → 2.
La instancia fue `(501,30,1)`, `(502,30,1)`, `(503,31,2)`.

### 2.2. Clausuras y claves candidatas

| Clausura | Resultado |
|---|---|
| L+ | {L} |
| D+ | {D} |
| R+ | {R,D} |
| LD+ | {L,D,R} |
| LR+ | {L,R,D} |
| DR+ | {D,R} |

Claves candidatas: **{L,D} y {L,R}**, conjunto completo. L no aparece a la
derecha de ninguna DF: toda clave debe contenerlo. L solo no alcanza; agregar
D o R determina toda S. Ambas parejas son mínimas y LDR no lo es. Los tres
atributos son primos; no existen atributos no primos.

### 2.3. Violación de FNBC

FNBC exige que todo determinante de una DF no trivial sea superclave.
LD es clave y F1 no viola FNBC. **F2 la viola:** R+ = RD no contiene L;
R no es superclave. La relación puede cumplir 3FN por sus atributos primos
sin cumplir FNBC; no se confunden ambas definiciones.

### 2.4. Anomalías

- **Actualización:** responsable 1 y depósito 30 se repiten en dos filas;
  cambiar solo una viola R → D.
- **Inserción:** no puede registrarse la asignación responsable/depósito sin lote.
- **Borrado:** quitar el único control del responsable 2 pierde su asignación al depósito 31.

### 2.5. Descomposición

Aplicando R → D se obtienen:

- **RD:** `responsable_control_deposito(responsable_control_id PK, deposito_id NOT NULL)`;
  FK a usuario y deposito.
- **LR:** `control_lote_responsable(lote_id, responsable_control_id)`;
  ambas NOT NULL, PK del par y FK a lote y RD.

R determina toda RD; LR no tiene una DF proyectada no trivial que viole FNBC.
Ambas relaciones resultantes cumplen FNBC. `lote` y `deposito` fueron soportes
académicos; no se creó ni se eliminó la tabla canónica usuario.

### 2.6. Unión sin pérdida

**RD ∩ LR = {R}** y **R → RD**: el atributo común determina una relación
completa, por lo que la descomposición es sin pérdida. La vista
`v_control_lote_almacen` reconstruye S mediante JOIN por responsable.

F2 queda preservada localmente. **F1 no queda preservada:** las DF proyectadas
no permiten obtener R desde LD. RD={(1,30),(2,30)} y LR={(501,1),(501,2)}
satisfacen sus claves locales, pero su JOIN viola LD → R. Este contraejemplo
no contradice la unión sin pérdida de las proyecciones de una instancia válida.

### 2.7. Verificación SQL

La ejecución real produjo **3 filas originales / 3 reconstruidas**, diagnóstico
F2=0, EXCEPT **0/0** y duplicados=0. EXCEPT se acompañó con conteos y control
de multiplicidad para no ocultar duplicados. Catálogo: cinco PK y siete FK.
Las negativas observaron **23505** para PK y **23503** para las tres FK probadas.
El DOWN se ejecutó realmente; las cinco tablas canónicas y los índices quedaron
intactos. [Evidencia FNBC y SQLSTATE](evidencia_revalidacion_fnbc_modelo_canonico.md).

## 3. Parte 2 — Top 5 de categorías

### 3.1. Consulta original

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

Se suman subtotales físicos y se usa fecha DATE. No se agregan filtros de estado,
disponibilidad o baja actual de maestros. La categoría atribuida es la actual
del producto, no una categoría histórica capturada al vender.

### 3.2. Baseline EXPLAIN ANALYZE

Dataset reproducible: **8 categorías / 20000 usuarios / 50000 productos /
200000 pedidos / 500000 detalles**, construido desde schema y seed canónicos
más tres índices TP5; TPI excluido. Fecha del ensayo: **2026-09-23**.
Hubo 19800 pedidos vigentes del día y 48900 detalles utilizables.

Protocolo: warm-cache, un calentamiento y cinco corridas oficiales JSON,
Execution Time como métrica, mediana **212.668 ms**.

| Métrica del baseline | Resultado |
|---|---|
| Mediana Execution Time | 212.668 ms |
| Plan resumido | Parallel Seq Scan de detalle, Index Only Scan de pedido, joins hash, agregación parcial/final, Sort y Limit |
| Tablas accedidas / joins | 4 / 3 |
| Buffers raíz shared hit + read | 6794 |

Líneas seleccionadas del plan textual real adicional (se omiten nodos intermedios):

```text
Limit  (cost=12662.37..12662.39 rows=5 width=51) (actual time=177.384..182.420 rows=5 loops=1)
  Buffers: shared hit=6794
Parallel Seq Scan on detalle_pedido dp  (cost=0.00..7765.33 rows=206076 width=23) (actual time=0.011..32.277 rows=247500 loops=2)
  Buffers: shared hit=5682
Parallel Index Only Scan using idx_pedido_fecha_reciente on pedido ped  (cost=0.42..924.18 rows=11957 width=8) (actual time=0.015..1.762 rows=19800 loops=1)
  Heap Fetches: 0
Seq Scan on producto pr  (cost=0.00..1410.00 rows=50000 width=16) (actual time=0.014..4.954 rows=50000 loops=1)
  Buffers: shared hit=910
Execution Time: 182.831 ms
```

El textual **182.831 ms no integra la mediana**. El plan recorre detalle,
lo une con pedidos/productos/categorías y agrega antes de LIMIT. Pedido ya usa
índice por fecha; Sort en memoria no motivó el candidato.
[Baseline completo y cinco corridas](evidencia_baseline_parte2_modelo_canonico.md).

### 3.3. Patrón elegido para experimentar

**Columna redundante + sincronización transaccional:**
`detalle_pedido.categoria_id BIGINT NOT NULL`, FK RESTRICT a categoria,
backfill desde producto y sin índice experimental nuevo. Se buscó retirar
scan/hash/JOIN de producto, no el recorrido de detalle. Se priorizó frescura
inmediata frente a una MV estándar que conserva el último refresh.

### 3.4. Sincronización y alcance

Fuente única: **producto.categoria_id**. El trigger del detalle deriva la categoría;
la recategorización del producto propaga a todas sus líneas, incluidas eliminadas.
El diseño inicial falló con **40P01** por orden inverso detalle/producto.
La remediación usó permisos cerrados, funciones SECURITY DEFINER y un gate
transaccional previo a los locks de datos; los triggers statement fueron defensa
adicional. S4 directo como aplicación fue **BYPASS_BLOCKED (42501)** y la ruta
autorizada pasó los escenarios ensayados. No se garantiza ausencia universal
de deadlocks ni acceso arbitrario de un administrador. El fallo original se conserva.
[Diseño y pruebas de la remediación](evidencia_remediacion_serializada_modelo_canonico.md).

### 3.5. Consulta desnormalizada

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

### 3.6. EXPLAIN ANALYZE AFTER

Mismo dataset lógico, fecha, configuración e índices; un warmup y cinco
corridas oficiales, ninguna descartada. Mediana **87.657 ms**. Líneas del
textual adicional real, con nodos intermedios omitidos:

```text
Limit  (cost=16850.83..16850.84 rows=5 width=51) (actual time=83.623..90.730 rows=5 loops=1)
  Buffers: shared hit=8405 read=3686
Parallel Seq Scan on detalle_pedido dp  (cost=0.00..13938.33 rows=206208 width=23) (actual time=0.302..31.924 rows=165000 loops=3)
  Buffers: shared hit=8169 read=3686
Parallel Index Only Scan using idx_pedido_fecha_reciente on pedido ped  (cost=0.42..1039.91 rows=11577 width=8) (actual time=0.051..3.941 rows=19800 loops=1)
  Heap Fetches: 0
Execution Time: 91.189 ms
```

El textual **91.189 ms no integra estadísticas**. Se elimina producto, pero
permanece el scan de 500000 detalles, dos joins, agregación, Sort y LIMIT.
Warm-cache no implicó cero shared reads. Los accesos compartidos y tiempos
padre/hijo no se suman; los tiempos del nodo se interpretan con sus loops.
[AFTER completo y limitaciones](evidencia_read_after_decision_modelo_canonico.md).

### 3.7. Comparación de mediciones oficiales

| Métrica | BEFORE | AFTER |
|---|---:|---:|
| Cinco Execution Time, ms | 212.668 / 235.256 / 199.683 / 324.541 / 171.081 | 87.657 / 86.012 / 84.582 / 109.291 / 88.504 |
| Mínimo, ms | 171.081 | 84.582 |
| Máximo, ms | 324.541 | 109.291 |
| Media, ms | 228.6458 | 91.2092 |
| Mediana, ms | 212.668 | 87.657 |
| Buffers raíz hit + read, cada corrida | 6794 | 12091 |
| Buffers detalle, cada corrida | 5682 | 11855 |
| Buffers producto | 910 | 0 |
| Joins / tablas accedidas | 3 / 4 | 2 / 3 |
| Filas finales / spills | 5 / 0 | 5 / 0 |
| Workers previstos / lanzados | 2 / 2 | 2 / 2 |

Speedup de medianas **2.4261x**, reducción temporal **58.78 %**, aumento de
buffers raíz **77.97 %**. Son resultados descriptivos: no se afirma significancia
estadística ni causalidad aislada del JOIN. El estado físico y distribución de
trabajo entre workers evolucionaron; AFTER usó sesiones psql nuevas por corrida.

### 3.8. Auditoría y equivalencia

El agregado completo de ocho categorías dio **EXCEPT 0/0** y el Top 5 fue
idéntico antes, entre corridas y después. Desincronización, NULL de categoría,
FK, subtotal, total, UNIQUE y CHECK: **0**. Los conteos y huellas canónicas
permanecieron iguales. DOWN pasó transaccionalmente en Fase 6E; en Fase 8 se
confirmó definitivamente sin afectar tablas, datos ni los seis índices explícitos.

### 3.9. Costos del candidato

- INSERT: mediana **38.640 ms** frente a **24.278 ms** canónico, **+59.16 %**
  aritmético; no aísla el costo del trigger porque API/JSON/setup difieren.
- Backfill de 500000 filas: **4853.635 ms**.
- Recategorización: fan-out real 12, mediana **67.860 ms**; estrés 1012,
  **91.241 ms**. Este último no representa la distribución habitual.
- El gate serializa incluso productos distintos; añade contención y gestión
  de roles/API. No se extrapoló throughput productivo.
- Tamaño de detalle respecto de Phase 3: heap **46546944 → 97116160 bytes**;
  tamaño total **73637888 → 151298048 bytes**. Incluye migración y versiones
  generadas por pruebas, no solo el BIGINT adicional; el DOWN no restituye
  automáticamente el tamaño físico inicial.

### 3.10. Decisión final: REJECT

Los umbrales se fijaron antes de medir: MAX AFTER <171.081 ms, mediana <212.668 ms,
**cada corrida shared hit + read <6794**, sin spill y con equivalencia.
Los criterios temporales y funcionales pasaron; **buffers falló en las cinco**.
Por tanto, **REJECT / DO_NOT_ADOPT**, sin flexibilizar la puerta para salvar
el candidato. Los costos adicionales tampoco se ocultan mediante un SLO inventado.

## 4. Conclusión

FNBC se demostró formalmente y se verificó por migración, conteos, EXCEPT y DOWN.
La desnormalización fue un experimento válido, no una optimización adoptada:
redujo tiempo, pero incumplió el criterio obligatorio de buffers y añadió costos.
El rechazo no es un fallo académico; el **40P01 inicial sí fue un fallo real**
y permanece documentado, separado de la remediación posterior.

El DOWN definitivo dejó `foodstore_u4_revalidacion` sin columna, FK, funciones,
triggers, esquema ni roles experimentales. Datos y estructuras canónicas intactos;
TPI y FNBC ausentes. No se restauró una imagen física de Phase 3 ni se repitieron
benchmarks para el cierre. [Cierre técnico verificable](informe_u4_fnbc_desnormalizacion.md).

## 5. Artefactos

1. [tp_fnbc_control_lote.sql](../sql/tp_fnbc_control_lote.sql): migración FNBC,
   vista, verificaciones, negativas y DOWN académico.
2. [tp_desnormalizacion_top_categorias.sql](../sql/tp_desnormalizacion_top_categorias.sql):
   UP experimental, sincronización, consulta, auditoría y DOWN completo.

Son artefactos reproducibles con guardas, **no migraciones a ejecutar automáticamente**.
El segundo se conserva para trazabilidad de un candidato descartado. Las evidencias
completas permanecen enlazadas sin copiar sus logs ni alterar sus resultados históricos.
