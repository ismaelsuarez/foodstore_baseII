-- ============================================================================
-- Consultas TP3 - Parte 4 - Alternativas equivalentes
-- Base de Datos II - Semana 3, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp3.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA B (ALTERNATIVA) — Productos con precio superior al promedio
-- de su categoría, usando CTE agrupado en vez de subconsulta correlacionada
-- ============================================================================
-- Estrategia:
-- - El CTE promedio_categoria calcula AVG(precio) sobre productos activos,
--   agrupado por categoria_id, UNA SOLA VEZ para toda la tabla.
-- - Se une ese resultado con producto y categoria mediante JOIN,
--   en vez de recalcular el promedio por cada fila exterior.
-- - Misma semántica que la Consulta B original:
--   producto.activo = TRUE, categoria.activo = TRUE,
--   precio > precio_promedio_categoria (comparación estricta),
--   promedio calculado solo sobre productos activos de la misma categoría.
-- ============================================================================

WITH promedio_categoria AS (
    SELECT
        categoria_id,
        AVG(precio) AS precio_promedio_categoria
    FROM producto
    WHERE activo = TRUE
    GROUP BY categoria_id
)
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    pc.precio_promedio_categoria AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
JOIN promedio_categoria pc
    ON pc.categoria_id = p.categoria_id
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > pc.precio_promedio_categoria
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
