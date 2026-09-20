-- ============================================================================
-- Consultas TP4 - Parte 3
-- Base de Datos II - Semana 4, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp4.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- No incluye verificaciones EXCEPT todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA A — Ranking de clientes por gasto total
-- ============================================================================
-- Reglas clave de la especificación:
-- - Solo clientes con al menos un pedido: se logra con JOIN (no LEFT JOIN)
--   contra pedido, que excluye naturalmente a los clientes sin pedidos.
-- - detalle_pedido se une con LEFT JOIN: un pedido válido puede todavía no
--   tener filas en detalle_pedido, y ese cliente no debe excluirse solo
--   por eso.
-- - cantidad_pedidos NO se multiplica por la cantidad de detalles de cada
--   pedido: se usa COUNT(DISTINCT pe.id), no COUNT(dp.*) ni COUNT(pe.id)
--   sin DISTINCT.
-- - gasto_total = SUM(cantidad * precio_unitario) sobre todos los detalles
--   de todos los pedidos del cliente; COALESCE(..., 0) cubre el caso de
--   un cliente cuyos pedidos todavía no tienen ningún detalle.
-- - RANK() OVER (ORDER BY gasto_total DESC) — el ranking depende
--   EXCLUSIVAMENTE de gasto_total. cliente_nombre NO participa del
--   ORDER BY interno de la función de ventana, para no romper el puesto
--   compartido ante un empate exacto de gasto_total.
-- - El desempate visual por cliente_nombre está únicamente en el
--   ORDER BY final de la consulta, después de calcular puesto.
-- ============================================================================

WITH gasto_por_cliente AS (
    SELECT
        c.id AS cliente_id,
        c.nombre AS cliente_nombre,
        COUNT(DISTINCT pe.id) AS cantidad_pedidos,
        COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS gasto_total
    FROM cliente c
    JOIN pedido pe
        ON pe.cliente_id = c.id
    LEFT JOIN detalle_pedido dp
        ON dp.pedido_id = pe.id
    GROUP BY c.id, c.nombre
)
SELECT
    cliente_id,
    cliente_nombre,
    cantidad_pedidos,
    gasto_total,
    RANK() OVER (ORDER BY gasto_total DESC) AS puesto
FROM gasto_por_cliente
ORDER BY puesto ASC, cliente_nombre ASC;

-- ============================================================================
-- CONSULTA B — Productos cuya facturación supera el promedio de su categoría
-- ============================================================================
-- Reglas clave de la especificación:
-- - producto.activo = TRUE y categoria.activo = TRUE.
-- - facturacion_producto = SUM(cantidad * precio_unitario) por producto,
--   calculada una sola vez en el CTE facturacion_producto (evita repetir
--   el JOIN producto + detalle_pedido en cada evaluación de la subconsulta).
-- - El CTE parte de TODOS los productos activos (FROM producto, no FROM
--   detalle_pedido) y usa LEFT JOIN contra detalle_pedido: un producto
--   activo sin ninguna venta debe seguir apareciendo, con
--   facturacion_producto = 0 vía COALESCE, y no desaparecer del cálculo
--   del promedio de su categoría.
-- - La subconsulta que calcula el promedio de la categoría es
--   CORRELACIONADA: referencia fp.categoria_id de la fila exterior actual,
--   y se repite en SELECT (para mostrar el promedio) y en WHERE (para la
--   comparación), tal como exige que la primera versión use subconsulta
--   correlacionada. Ese promedio se calcula sobre facturacion_producto,
--   que ya incluye los productos activos con facturación 0.
-- - El promedio de cada categoría se calcula únicamente sobre productos
--   activos de esa misma categoría (el CTE ya filtró pr.activo = TRUE).
-- - Comparación estricta: facturacion_producto > promedio_facturacion_categoria.
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
)
SELECT
    fp.producto_id AS producto_id,
    fp.producto_nombre AS producto_nombre,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    fp.facturacion_producto AS facturacion_producto,
    (
        SELECT AVG(fp2.facturacion_producto)
        FROM facturacion_producto fp2
        WHERE fp2.categoria_id = fp.categoria_id
    ) AS promedio_facturacion_categoria
FROM facturacion_producto fp
JOIN categoria c
    ON c.id = fp.categoria_id
WHERE c.activo = TRUE
  AND fp.facturacion_producto > (
        SELECT AVG(fp2.facturacion_producto)
        FROM facturacion_producto fp2
        WHERE fp2.categoria_id = fp.categoria_id
    )
ORDER BY c.nombre ASC, fp.facturacion_producto DESC, fp.producto_nombre ASC;
