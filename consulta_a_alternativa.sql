-- ============================================================================
-- Consulta A - Versión alternativa (CTE agregado + LEFT JOIN)
-- Base de Datos II - Semana 3, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp3.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA A (ALTERNATIVA) — Resumen de productos vigentes por categoría,
-- usando CTE agregado por categoria_id en vez de LEFT JOIN directo + GROUP BY
-- ============================================================================
-- Estrategia:
-- - El CTE productos_activos_por_categoria filtra producto.activo = TRUE
--   y agrega COUNT(*) y AVG(precio) agrupando por categoria_id, ANTES
--   de tocar la tabla categoria.
-- - Luego se hace LEFT JOIN de categoria contra ese resultado ya agregado.
-- - Como el CTE solo contiene categorías con al menos un producto activo,
--   las categorías sin coincidencia en el LEFT JOIN quedan con NULL:
--   COALESCE(..., 0) para cantidad_productos, y NULL natural para
--   precio_promedio (no se fuerza a 0, se deja NULL como exige la spec).
-- ============================================================================

WITH productos_activos_por_categoria AS (
    SELECT
        categoria_id,
        COUNT(*) AS cantidad_productos,
        AVG(precio) AS precio_promedio
    FROM producto
    WHERE activo = TRUE
    GROUP BY categoria_id
)
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    COALESCE(pac.cantidad_productos, 0) AS cantidad_productos,
    pac.precio_promedio AS precio_promedio
FROM categoria c
LEFT JOIN productos_activos_por_categoria pac
    ON pac.categoria_id = c.id
WHERE c.activo = TRUE
ORDER BY cantidad_productos DESC, categoria_nombre ASC;
