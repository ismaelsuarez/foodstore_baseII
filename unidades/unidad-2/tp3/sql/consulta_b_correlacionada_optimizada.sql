-- ============================================================================
-- Consulta B - Versión correlacionada optimizada (JOIN LATERAL)
-- Base de Datos II - Semana 3, Unidad 2: Optimización de Consultas
-- Especificación: ../specs/spec_consultas_tp3.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA B (CORRELACIONADA OPTIMIZADA) — Productos con precio superior
-- al promedio de su categoría, usando JOIN LATERAL en vez de dos
-- subconsultas escalares repetidas
-- ============================================================================
-- Estrategia:
-- - Sigue siendo correlacionada: el JOIN LATERAL calcula AVG(precio)
--   referenciando p.categoria_id de la fila exterior actual.
-- - A diferencia de la primera versión (dos subconsultas escalares,
--   una en SELECT y otra en WHERE), acá el promedio se calcula UNA SOLA
--   VEZ por fila exterior, y ese mismo resultado (prom.precio_promedio_categoria)
--   se reutiliza tanto para mostrarlo como para la comparación del WHERE.
-- - Misma semántica que la Consulta B original:
--   producto.activo = TRUE, categoria.activo = TRUE,
--   precio > precio_promedio_categoria (comparación estricta),
--   promedio calculado solo sobre productos activos de la misma categoría.
-- ============================================================================

SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    prom.precio_promedio_categoria AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
JOIN LATERAL (
    SELECT AVG(p2.precio) AS precio_promedio_categoria
    FROM producto p2
    WHERE p2.categoria_id = p.categoria_id
      AND p2.activo = TRUE
) prom ON TRUE
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > prom.precio_promedio_categoria
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
