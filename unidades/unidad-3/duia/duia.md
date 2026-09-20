# DUIA — Declaración de Uso de IA
## Base de Datos II — Unidad 3, Semana 5
## Food Store

Trabajo Práctico: Índices, vistas y vistas materializadas.

---

## Introducción

- **Kiro** fue utilizado para especificar antes de generar: cada pieza
  del trabajo (índice, vista o vista materializada) partió de un
  archivo spec en `specs/` que definió el objetivo, el esquema real
  involucrado, las restricciones de diseño y el criterio de
  aceptación, antes de pedir cualquier generación de SQL.
- **OpenCode** fue utilizado para generar SQL y documentación técnica
  a partir de esas specs: propuestas de índices con su justificación,
  definiciones de vistas, la vista materializada, y los informes de
  medición.
- Las decisiones finales — qué índice aceptar, qué propuesta descartar
  por sobreindexación, qué predicado usar, si declarar `UNIQUE` o no —
  no fueron delegadas a la IA. Fueron tomadas por el estudiante después
  de revisar cada propuesta.
- Todas las ejecuciones SQL, los `EXPLAIN (ANALYZE, BUFFERS)`, las
  verificaciones `EXCEPT` y las mediciones de tiempo sobre
  `foodstore_tp5` fueron realizadas manualmente por el estudiante, en
  PostgreSQL 17, fuera de esta sesión de IA.
- Ningún resultado medido (tiempo, buffers, filas, plan real) debe
  atribuirse a una ejecución automática de Kiro u OpenCode: ninguna de
  las dos herramientas se conectó a la base ni ejecutó SQL.

---

## Parte A — Índices

### A1 — idx_producto_stock_bajo

**Herramienta de especificación:** Kiro.

**Propósito:** especificar la optimización de la consulta frecuente de
productos con stock bajo (`producto.activo = TRUE AND stock <= 5`,
`ORDER BY stock ASC, nombre ASC`).

**Spec utilizado:** `specs/indice_producto_stock_bajo.md`. El contenido
completo del spec se conserva en el repositorio y fue utilizado como
contrato para la generación.

**Herramienta de generación:** OpenCode.

**Resultado final aceptado:**

```sql
CREATE INDEX idx_producto_stock_bajo
    ON producto (stock ASC, nombre ASC)
    INCLUDE (id, precio)
    WHERE activo = TRUE;
```

**Decisiones técnicas reales:**

- Se corrigió la interpretación de selectividad: 1.493 filas sobre
  50.003 representan aproximadamente 2,99 %, por lo que el predicado se
  documenta como altamente selectivo (no como "baja selectividad",
  terminología imprecisa usada en una primera pasada).
- Se aceptó un índice parcial `WHERE activo = TRUE`, reconociendo
  expresamente que hoy no reduce la cantidad física de entradas porque
  el 100 % de los productos están activos; se conservó por coincidir
  con el predicado de la consulta y habilitar el Index Only Scan sin
  necesitar `activo` como columna del índice.
- `INCLUDE (id, precio)` permitió cobertura completa de las columnas
  proyectadas y un `Index Only Scan`.
- El resultado medido pasó de `Seq Scan + Sort` a `Index Only Scan`,
  sin `Sort` y con `Heap Fetches: 0`.
- Promedio antes: 10.030 ms. Promedio después: 0.2675 ms.
- Mejora aproximada: ≈37,50x.

La propuesta inicial de OpenCode fue revisada porque no utilizaba un
índice parcial. Después de analizar la consulta y su predicado se
modificó el diseño para incorporar:

```sql
WHERE activo = TRUE
```

También se corrigió la interpretación de selectividad. La versión
parcial fue la que finalmente se midió y aceptó.

**Commit de implementación:** `913581f`.

---

### A2 — idx_pedido_fecha_reciente

**Kiro:** `specs/indice_pedido_fecha_reciente.md`.

**OpenCode:** generación y revisión del índice candidato.

**Resultado final:**

```sql
CREATE INDEX idx_pedido_fecha_reciente
    ON pedido (fecha DESC)
    INCLUDE (id, cliente_id, forma_pago);
```

**Correcciones conceptuales reales:**

- Se corrigió una afirmación inicial de que `fecha DESC` era necesario
  para eliminar el `Sort`: PostgreSQL puede recorrer un B-tree en ambos
  sentidos, así que un índice `fecha ASC` también podría satisfacer
  `ORDER BY fecha DESC` mediante backward scan. `DESC` se conservó por
  claridad de intención, no como requisito técnico.
- Se corrigió una afirmación inicial de que `UPDATE cliente_id` no
  afectaba este índice: `cliente_id` está en `INCLUDE`, por lo que
  modificarlo sí requiere mantenimiento del índice y puede impedir un
  HOT update, igual que `forma_pago`.
- Promedio antes: 12.8805 ms. Promedio después: 0.313 ms.
- Mejora aproximada: ≈41,15x.
- Plan final medido: `Index Only Scan`, sin `Sort`.

**Commit:** `c1a2178`.

---

### A3 — idx_cliente_email_lower

**Kiro:** `specs/indice_cliente_email_lower.md`.

**OpenCode:** generación y evaluación del índice, incluyendo un caso
explícito de sobreindexación.

**Propuesta descartada:**

```sql
CREATE INDEX idx_cliente_email_lower
    ON cliente (lower(email))
    INCLUDE (id, nombre, email);
```

**Decisión:** DESCARTADA POR SOBREINDEXACIÓN.

**Justificación:**

- La consulta devuelve una única fila sobre 20.003.
- Ampliar todas las entradas del índice con `id`, `nombre` y `email`
  solo para intentar un `Index Only Scan` no justificaba el costo
  permanente de almacenamiento y mantenimiento.
- Aumentaba el tamaño del índice y el costo de `INSERT`.
- `UPDATE nombre` pasaría a afectar este índice únicamente por estar
  en `INCLUDE`.
- `email` ya está indexado por `cliente_email_key`; duplicarlo acá no
  aportaba valor adicional.
- Un acceso puntual al heap, dada la selectividad extrema de la
  consulta, era un costo aceptable frente a esas cargas permanentes.

**Versión finalmente aceptada:**

```sql
CREATE INDEX idx_cliente_email_lower
    ON cliente (lower(email));
```

No se declaró `UNIQUE` porque eso introduciría una nueva regla de
negocio de unicidad case-insensitive que no existe en el esquema
actual — una decisión de negocio que no correspondía tomar como efecto
colateral de una optimización de lectura.

**Resultados:**

- Antes: 10.272 ms. Después: 0.1075 ms.
- Mejora aproximada: ≈95,55x.
- Plan final: `Index Scan`.

**Commit:** `799e0f5`.

---

### Costo de escritura (Parte A)

- Benchmark: transacción reversible que crea 1 pedido e inserta 500
  filas en `detalle_pedido`, seguida de `ROLLBACK`.
- Antes de los tres índices: promedio estable 17.256 ms.
- Después de los tres índices: promedio estable 7.477 ms.
- **No se concluyó** que los índices aceleraron las escrituras: el
  benchmark inserta principalmente en `detalle_pedido`, tabla que no
  tiene ninguno de los tres índices nuevos. La diferencia favorable
  observada puede deberse a caché, condiciones de la máquina o
  variabilidad entre corridas, no a un efecto causal de los índices.
- Conclusión correcta registrada: "no se observó penalización de
  escritura en este benchmark".

**Informe de Parte A:** commit `95db4dd`.

---

## Parte B — Vistas

### B1 — v_productos_vigentes

**Spec:** `specs/vista_productos_vigentes.md`.

**Regla de vigencia:**

```
producto.activo = TRUE
AND categoria.activo = TRUE
```

Si la categoría está inactiva, sus productos no aparecen aunque
`producto.activo` siga en `TRUE`.

**Kiro:** especificación de la regla de vigencia y de las columnas a
exponer. **OpenCode:** generación de la definición `CREATE OR REPLACE
VIEW` a partir de esa spec.

**Revisión realizada:** verificación de que no se exponen columnas no
pedidas (`created_at`, `activo`) y de que el `JOIN` respeta
`producto.categoria_id = categoria.id`.

**Equivalencia (EXCEPT bidireccional):**

```
manual_minus_view = 0
view_minus_manual = 0
```

**Filas:** 50.003.

**Decisión:** ACEPTADA.

**Commit:** `e4240dc`.

---

### B2 — v_pedidos_cliente

**Spec:** `specs/vista_pedidos_cliente.md`.

**Adaptación de seguridad al esquema real:** la consigna teórica
original menciona una tabla `usuario` y una columna `contraseña`. El
esquema real del proyecto **no contiene** `usuario` ni `contraseña` ni
`password` — no se inventaron esas columnas. Se utilizó la tabla real
`cliente`, aplicando minimización de datos: se exponen `cliente_nombre`
y `cliente_email` como datos necesarios del reporte, pero **no** se
exponen `cliente.telefono` ni `cliente.created_at`.

**Kiro:** especificación de la minimización de datos sobre el esquema
real. **OpenCode:** generación de la vista y de los comentarios que
documentan esa adaptación.

**Equivalencia (EXCEPT bidireccional):**

```
manual_minus_view = 0
view_minus_manual = 0
```

**Filas:** 200.005.

**Decisión:** ACEPTADA.

**Commit:** `2ef7cf1`.

---

### B3 — v_detalle_pedido_producto

**Spec:** `specs/vista_detalle_pedido_producto.md`.

**Puntos documentados:**

- `subtotal = cantidad * precio_unitario`.
- `subtotal` es una columna calculada dentro de la vista; no existe
  físicamente en `detalle_pedido`.
- La vista **no** filtra por `producto.activo`, para preservar el
  historial: un pedido histórico debe seguir mostrando el producto
  asociado aunque ese producto sea marcado como inactivo después.

**Kiro:** especificación de la regla histórica y del cálculo de
`subtotal`. **OpenCode:** generación de la vista.

**Equivalencia (EXCEPT bidireccional):**

```
manual_minus_view = 0
view_minus_manual = 0
```

**Filas:** 500.007.

**Decisión:** ACEPTADA.

**Commit:** `2b0c9b0`.

**Cierre documental de la Parte B:** commit `a767f6c`.

---

## Parte C — Vista materializada

**Spec:** `specs/vista_materializada_facturacion_categoria_mes.md`. El
contenido completo del spec se conserva en el repositorio y fue
utilizado como contrato para la generación.

**Kiro:** especificación del reporte a materializar, su semántica
(idéntica a la del reporte de facturación por categoría y mes del
TP4), la clave lógica del resultado (`categoria_id, mes`), el
protocolo de medición y la política de refresh.

**OpenCode:** generación de `materializadas.sql`.

**Objeto creado:** `mv_facturacion_categoria_mes`.

**Índice:** `idx_mv_facturacion_categoria_mes_unique`, `UNIQUE
(categoria_id, mes)`.

**Puntos documentados:**

- `CREATE MATERIALIZED VIEW ... WITH DATA` — la vista quedó poblada
  desde su creación, con 4 filas.
- El índice `UNIQUE` sobre `(categoria_id, mes)` corresponde a la clave
  lógica del resultado y habilita un futuro `REFRESH MATERIALIZED VIEW
  CONCURRENTLY`, que **no** fue ejecutado en esta etapa.
- Equivalencia semántica verificada:

```
original_minus_materialized = 0
materialized_minus_original = 0
```

**Mediciones reales:**

- Consulta original: promedio estable 1131.224 ms. Plan con `Hash
  Join` + `Sort` + `GroupAggregate`, `Sort Method: external merge`,
  `Disk: 25008 kB`.
- Consulta sobre la vista materializada: promedio estable 0.060 ms.
  Plan: `Seq Scan` de 4 filas + `Sort` (`quicksort`, `Memory: 25 kB`).
- Mejora aproximada: ≈18.853,7x.
- Reducción aproximada de Execution Time: ≈99,9947 %.

**Política de refresh:** cada 60 minutos mientras el sistema esté en
operación.

**Costo documentado explícitamente:** puede existir hasta
aproximadamente una hora de staleness entre dos refresh. La vista
materializada **no** representa información transaccional en tiempo
real; es un reporte agregado para análisis y gestión.

**Commit:** `af4e14c`.

**Corrección documental posterior:** commit `0a951c0`.

---

## Sección final — Decisiones del estudiante

Las siguientes decisiones fueron tomadas por el estudiante y no
delegadas a Kiro ni a OpenCode:

- Aceptar o rechazar cada uno de los tres índices candidatos, después
  de revisar la justificación técnica propuesta.
- Descartar explícitamente el índice covering de
  `idx_cliente_email_lower` por sobreindexación, en lugar de aceptarlo
  automáticamente.
- No introducir un índice `UNIQUE` sobre `lower(email)`, para no
  imponer una regla de negocio de unicidad case-insensitive que no
  existe en el esquema actual.
- Adaptar la vista de seguridad (`v_pedidos_cliente`) al esquema real
  del proyecto, sin inventar una columna `contraseña` inexistente.
- Preservar el historial de pedidos en `v_detalle_pedido_producto`, sin
  filtrar por `producto.activo`.
- Elegir el reporte de facturación por categoría y mes como candidato
  a materializar.
- Aceptar una staleness de hasta una hora para ese reporte analítico,
  documentándola explícitamente en lugar de ocultarla.
- Validar los índices mediante mediciones reales con
  `EXPLAIN (ANALYZE, BUFFERS)` antes y después de crearlos.
- Validar las vistas convencionales mediante `EXCEPT` bidireccional
  contra sus consultas manuales equivalentes.
- Validar la vista materializada mediante `EXCEPT` bidireccional y,
  además, comparar su rendimiento con la consulta original mediante
  `EXPLAIN (ANALYZE, BUFFERS)`.

### Tabla resumen

| Pieza | Kiro | OpenCode | Revisión humana | Estado |
|---|---|---|---|---|
| idx_producto_stock_bajo | Spec de optimización de stock bajo | Propuesta y generación del índice | Corrección de terminología de selectividad; reconocimiento del efecto nulo actual del predicado parcial | ACEPTADO |
| idx_pedido_fecha_reciente | Spec de pedidos recientes | Propuesta y generación del índice | Corrección sobre ASC/DESC y backward scan; corrección del impacto de `UPDATE cliente_id` | ACEPTADO |
| idx_cliente_email_lower | Spec de búsqueda case-insensitive | Propuesta cubridora y propuesta simple | Descarte de la variante cubridora por sobreindexación; decisión de no usar `UNIQUE` | ACEPTADO (versión simple) |
| v_productos_vigentes | Spec de vigencia de catálogo | Generación de la vista | Verificación de columnas expuestas y equivalencia EXCEPT | ACEPTADA |
| v_pedidos_cliente | Spec de minimización de datos | Generación de la vista y adaptación al esquema real | Verificación de que no se inventaron columnas; verificación de equivalencia EXCEPT | ACEPTADA |
| v_detalle_pedido_producto | Spec de regla histórica | Generación de la vista | Verificación de que no se filtra por `activo`; verificación de equivalencia EXCEPT | ACEPTADA |
| mv_facturacion_categoria_mes | Spec de reporte y política de refresh | Generación de la vista materializada y su índice UNIQUE | Verificación de equivalencia EXCEPT y medición real de mejora; documentación de staleness | ACEPTADA |
