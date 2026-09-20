-- ============================================================================
-- queries.sql
-- Base de Datos II - Unidad 3, Semana 5
-- Food Store
-- ============================================================================
-- Este archivo centraliza las consultas de referencia reales utilizadas
-- durante el TP5 para:
-- - la medición de índices (Parte A);
-- - la verificación de equivalencia de las vistas convencionales
--   (Parte B);
-- - el reporte original que fundamenta la vista materializada
--   (Parte C).
--
-- No contiene DDL ni modificaciones de datos: solo SELECT.
-- No incluye CREATE INDEX, CREATE VIEW, CREATE MATERIALIZED VIEW,
-- INSERT, UPDATE, DELETE, DROP ni REFRESH.
--
-- Los EXPLAIN (ANALYZE, BUFFERS) y los resultados medidos sobre estas
-- consultas están documentados en ../informes/informe_mediciones.md.
-- ============================================================================

-- ============================================================================
-- CONSULTA 1 — Stock bajo
-- ============================================================================
-- Índice evaluado: idx_producto_stock_bajo
-- ============================================================================

SELECT
    id,
    nombre,
    stock,
    precio
FROM producto
WHERE activo = TRUE
  AND stock <= 5
ORDER BY stock ASC, nombre ASC;

-- ============================================================================
-- CONSULTA 2 — Pedidos recientes
-- ============================================================================
-- Índice evaluado: idx_pedido_fecha_reciente
-- ============================================================================

SELECT
    id,
    cliente_id,
    fecha,
    forma_pago
FROM pedido
WHERE fecha >= TIMESTAMPTZ '2026-04-11 12:00:00-03'
ORDER BY fecha DESC;

-- ============================================================================
-- CONSULTA 3 — Email case-insensitive
-- ============================================================================
-- Índice evaluado: idx_cliente_email_lower
-- ============================================================================

SELECT
    id,
    nombre,
    email
FROM cliente
WHERE lower(email) = lower('ANA.GOMEZ@FOODSTORE.TEST');

-- ============================================================================
-- CONSULTA 4 — Productos vigentes
-- ============================================================================
-- Consulta manual equivalente de: v_productos_vigentes
-- ============================================================================

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

-- ============================================================================
-- CONSULTA 5 — Pedidos con cliente
-- ============================================================================
-- Consulta manual equivalente de: v_pedidos_cliente
-- ============================================================================

SELECT
    p.id AS pedido_id,
    p.fecha,
    p.forma_pago,
    c.id AS cliente_id,
    c.nombre AS cliente_nombre,
    c.email AS cliente_email
FROM pedido p
JOIN cliente c
    ON c.id = p.cliente_id;

-- ============================================================================
-- CONSULTA 6 — Detalle de pedido con producto
-- ============================================================================
-- Consulta manual equivalente de: v_detalle_pedido_producto
-- ============================================================================

SELECT
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.cantidad * dp.precio_unitario AS subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id;

-- ============================================================================
-- CONSULTA 7 — Facturación por categoría y mes
-- ============================================================================
-- Consulta original utilizada para: mv_facturacion_categoria_mes
-- ============================================================================

SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id) AS cantidad_pedidos,
    SUM(dp.cantidad) AS unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria c
JOIN producto pr
    ON pr.categoria_id = c.id
JOIN detalle_pedido dp
    ON dp.producto_id = pr.id
JOIN pedido pe
    ON pe.id = dp.pedido_id
WHERE c.activo = TRUE
  AND pr.activo = TRUE
GROUP BY
    c.id,
    c.nombre,
    DATE_TRUNC('month', pe.fecha)
ORDER BY
    mes ASC,
    facturacion_total DESC;
