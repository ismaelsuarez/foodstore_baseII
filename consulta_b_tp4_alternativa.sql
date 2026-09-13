-- ============================================================================
-- Consulta B - Versión alternativa (promedio de categoría precalculado)
-- Base de Datos II - Semana 4, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp4.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- No incluye verificaciones EXCEPT todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA B (ALTERNATIVA) — Productos cuya facturación supera el promedio
-- de su categoría, calculando ese promedio UNA SOLA VEZ por categoría
-- mediante un segundo CTE, en vez de una subconsulta correlacionada
-- ============================================================================
-- Estrategia (distinta a consultas_tp4_ia.sql, que resolvía el promedio
-- con dos subconsultas escalares correlacionadas repetidas):
--
-- 1. facturacion_producto: misma definición que la versión original —
--    parte de TODOS los productos activos, LEFT JOIN con detalle_pedido,
--    COALESCE a 0 para productos activos sin ventas.
-- 2. promedio_categoria: agrupa facturacion_producto por categoria_id y
--    calcula AVG UNA SOLA VEZ para toda la tabla, produciendo una fila
--    por categoría (no una por producto).
-- 3. SELECT final: une facturacion_producto con promedio_categoria (por
--    categoria_id) y con categoria (para el filtro activo y el nombre),
--    comparando cada producto contra el promedio ya calculado de su
--    categoría, en vez de recalcularlo por cada fila exterior.
-- ============================================================================

WITH facturacion_producto AS (
    SELECT
        pr.id AS producto_id,
        pr.nombre AS producto_nombre,
        pr.categoria_id AS categoria_id,
        COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS facturacion_producto
    FROM producto pr
    LEFT JOIN detalle_pedido dp
        ON dp.producto_id = pr.id
    WHERE pr.activo = TRUE
    GROUP BY pr.id, pr.nombre, pr.categoria_id
),
promedio_categoria AS (
    SELECT
        categoria_id,
        AVG(facturacion_producto) AS promedio_facturacion_categoria
    FROM facturacion_producto
    GROUP BY categoria_id
)
SELECT
    fp.producto_id AS producto_id,
    fp.producto_nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    fp.facturacion_producto AS facturacion_producto,
    pc.promedio_facturacion_categoria AS promedio_facturacion_categoria
FROM facturacion_producto fp
JOIN promedio_categoria pc
    ON pc.categoria_id = fp.categoria_id
JOIN categoria c
    ON c.id = fp.categoria_id
WHERE c.activo = TRUE
  AND fp.facturacion_producto > pc.promedio_facturacion_categoria
ORDER BY c.nombre ASC, fp.facturacion_producto DESC, fp.producto_nombre ASC;
