-- ============================================================================
-- Consultas TP3 - Parte 4
-- Base de Datos II - Semana 3, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp3.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA A — Resumen de productos vigentes por categoría
-- ============================================================================
-- Reglas clave de la especificación:
-- - Incluir categorías activas aunque no tengan productos activos.
-- - El filtro producto.activo = TRUE va en el ON del LEFT JOIN,
--   NO en el WHERE, para no convertir el LEFT JOIN en INNER JOIN.
-- - COUNT(p.id) cuenta productos (0 si no hay coincidencias), no filas
--   de categoria.
-- - AVG(p.precio) se calcula solo sobre las filas de producto que
--   superaron el filtro del ON; si no hay ninguna, devuelve NULL.
-- ============================================================================

SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    COUNT(p.id) AS cantidad_productos,
    AVG(p.precio) AS precio_promedio
FROM categoria c
LEFT JOIN producto p
    ON p.categoria_id = c.id
    AND p.activo = TRUE
WHERE c.activo = TRUE
GROUP BY c.id, c.nombre
ORDER BY cantidad_productos DESC, categoria_nombre ASC;

-- ============================================================================
-- CONSULTA B — Productos con precio superior al promedio de su categoría
-- ============================================================================
-- Reglas clave de la especificación:
-- - Subconsulta CORRELACIONADA: cada subconsulta referencia
--   p.categoria_id de la fila exterior actual.
-- - El promedio de la subconsulta se calcula solo con productos activos
--   de la misma categoría que el producto exterior.
-- - El producto exterior debe estar activo y su categoría también.
-- - Comparación estricta: precio > promedio.
-- ============================================================================

SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    p.precio AS precio,
    (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria_id = p.categoria_id
          AND p2.activo = TRUE
    ) AS precio_promedio_categoria
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.activo = TRUE
  AND c.activo = TRUE
  AND p.precio > (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria_id = p.categoria_id
          AND p2.activo = TRUE
    )
ORDER BY c.nombre ASC, p.precio DESC, p.nombre ASC;
