-- ============================================================================
-- views.sql
-- Base de Datos II - Unidad 3, Semana 1, Parte B: Vistas
-- Especificación: specs/vista_productos_vigentes.md
-- ============================================================================
-- Solo definiciones de vistas (CREATE OR REPLACE VIEW). No incluye
-- materialized views, índices, EXPLAIN ni consultas de prueba.
-- No fue ejecutado. No se ejecutó SQL ni se modificó la base.
-- ============================================================================

-- ============================================================================
-- VISTA 1: v_productos_vigentes
-- ============================================================================
--
-- Propósito: encapsular en un único lugar la regla de vigencia del
-- catálogo, exponiendo productos vigentes junto con los datos básicos
-- de su categoría.
--
-- Regla de vigencia: un producto aparece únicamente cuando
-- producto.activo = TRUE Y categoria.activo = TRUE. Si la categoría
-- queda inactiva, sus productos dejan de aparecer en la vista aunque
-- producto.activo siga en TRUE.
--
-- Esta vista NO es una optimización de rendimiento: es un mecanismo de
-- encapsulamiento y consistencia de criterio de vigencia. No agrega
-- índices ni cambia el plan de ejecución subyacente.
--
-- Será validada posteriormente mediante EXCEPT bidireccional contra la
-- consulta manual equivalente (manual_minus_view = 0,
-- view_minus_manual = 0).
-- ============================================================================

CREATE OR REPLACE VIEW v_productos_vigentes AS
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.activo = TRUE
  AND c.activo = TRUE;
