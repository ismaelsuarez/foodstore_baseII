# Spec: vista_materializada_facturacion_categoria_mes

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`categoria`: `id`, `nombre`. `producto`: `id`, `categoria_id`. `detalle_pedido`: `pedido_id`, `producto_id`, `cantidad`, `subtotal` físico, `eliminado`. `pedido`: `id`, `fecha DATE`, `eliminado`. Relaciones: categoría–producto–detalle–pedido mediante sus claves indicadas.

## OBJETIVO

Materializar la facturación por categoría y mes como hipótesis de optimización. Preservar ventas ante bajas lógicas posteriores de productos o categorías: solo filtrar pedidos y detalles eliminados. No filtrar disponibilidad. Este contrato es de TP5 y no modifica evidencia ni consultas históricas de otros TPs.

## CONSULTA

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
    date_trunc('month', ped.fecha)::date;
```

## OBJETO_CANDIDATO

Definiciones en [materializadas.sql](../sql/materializadas.sql).

```sql
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
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
WITH DATA;
```

Clave lógica `(categoria_id, mes)`; conservar el índice sin predicado para la estrategia de refresh concurrente posterior:

```sql
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes_unique
    ON mv_facturacion_categoria_mes (categoria_id, mes);
```

## CRITERIO_DE_ACEPTACION

- Agrupar por categoría y mes de tipo `DATE`; usar `COUNT(DISTINCT ped.id)`, `SUM(dp.cantidad)` y `SUM(dp.subtotal)`.
- Excluir solo pedidos y detalles eliminados; conservar ventas vinculadas a categorías/productos dados de baja o no disponibles.
- Verificar unicidad de `(categoria_id, mes)` y equivalencia mediante `EXCEPT` bidireccional tras poblar o refrescar, sin cambios concurrentes que alteren la comparación.
- Justificar cualquier beneficio con mediciones nuevas, incluyendo costo y atraso de actualización.

## RIESGOS

Instalación prevista en una copia limpia; evaluar objetos existentes y sus dependencias antes de cualquier migración. `WITH DATA` poblará la vista cuando se ejecute, no en este bloque. La agrupación usa el nombre y la categoría actuales: conserva ventas frente a bajas lógicas, no instantáneas históricas ante renombres o recategorizaciones.

No se actualiza automáticamente. Frecuencia propuesta: cada 60 minutos, pendiente de validar y programar; duración del refresh, fallos o interrupciones pueden aumentar el atraso. No prometer datos en tiempo real ni un máximo garantizado. No crear triggers ni programar tareas en este bloque.

## VALIDACION_PENDIENTE

Pendiente: comprobar equivalencia y clave lógica, probar bajas lógicas y subtotal físico, medir consulta original y lectura materializada con `EXPLAIN (ANALYZE, BUFFERS)`. Usar en ambas `ORDER BY mes ASC, facturacion_total DESC`, como la consulta 8 de [queries.sql](../sql/queries.sql). Realizar tres corridas por alternativa, descartar la primera como calentamiento y promediar las otras dos; registrar planes, filas, buffers y tiempos reales. No transferir métricas históricas.

Evaluar posteriormente costo de creación, espacio y `REFRESH MATERIALIZED VIEW CONCURRENTLY` con la vista poblada y el índice único adecuado. No se ejecuta ni se acredita ese refresh en este bloque.