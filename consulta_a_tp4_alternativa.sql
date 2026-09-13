-- ============================================================================
-- Consulta A - Versión alternativa (preagregación por pedido_id + LEFT JOIN)
-- Base de Datos II - Semana 4, Unidad 2: Optimización de Consultas
-- Especificación: spec_consultas_tp4.md
-- ============================================================================
-- Solo SELECT. No modifica esquema ni datos. No incluye EXPLAIN todavía.
-- No incluye verificaciones EXCEPT todavía.
-- ============================================================================

-- ============================================================================
-- CONSULTA A (ALTERNATIVA) — Ranking de clientes por gasto total,
-- preagregando detalle_pedido por pedido_id antes de llegar a cliente
-- ============================================================================
-- Estrategia (distinta a consultas_tp4_ia.sql, que unía
-- cliente + pedido + detalle_pedido directamente y usaba
-- COUNT(DISTINCT pe.id)):
--
-- 1. detalle_por_pedido: agrega detalle_pedido por pedido_id, obteniendo
--    UNA fila por pedido con su gasto total de detalles.
-- 2. pedido_con_gasto: LEFT JOIN desde pedido hacia ese agregado — un
--    pedido sin ninguna fila en detalle_pedido queda con
--    gasto_pedido = 0 (COALESCE), pero NO se pierde. El resultado tiene
--    garantizado exactamente una fila por pedido.
-- 3. gasto_por_cliente: agrupa pedido_con_gasto por cliente. Como cada
--    pedido ya aparece una sola vez desde el paso 2, COUNT(*) acá
--    equivale a contar pedidos distintos — no hace falta COUNT(DISTINCT).
-- 4. RANK() OVER (ORDER BY gasto_total DESC) sobre el resultado agregado
--    por cliente. cliente_nombre NO participa de la ventana, solo del
--    ORDER BY final.
-- ============================================================================

WITH detalle_por_pedido AS (
    SELECT
        pedido_id,
        SUM(cantidad * precio_unitario) AS gasto_pedido
    FROM detalle_pedido
    GROUP BY pedido_id
),
pedido_con_gasto AS (
    SELECT
        pe.id AS pedido_id,
        pe.cliente_id AS cliente_id,
        COALESCE(dpp.gasto_pedido, 0) AS gasto_pedido
    FROM pedido pe
    LEFT JOIN detalle_por_pedido dpp
        ON dpp.pedido_id = pe.id
),
gasto_por_cliente AS (
    SELECT
        c.id AS cliente_id,
        c.nombre AS cliente_nombre,
        COUNT(*) AS cantidad_pedidos,
        SUM(pcg.gasto_pedido) AS gasto_total
    FROM cliente c
    JOIN pedido_con_gasto pcg
        ON pcg.cliente_id = c.id
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
