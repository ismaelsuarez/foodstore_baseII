-- ============================================================================
-- materializadas.sql
-- Base de Datos II - Unidad 3, Semana 5, Parte C: Vistas materializadas
-- Especificación: ../specs/vista_materializada_facturacion_categoria_mes.md
-- ============================================================================
-- La vista materializada y su índice fueron instalados y validados
-- manualmente sobre foodstore_tp5. La equivalencia y las mediciones
-- reales se documentan en ../informes/informe_mediciones.md.
-- ============================================================================

-- ============================================================================
-- VISTA MATERIALIZADA: mv_facturacion_categoria_mes
-- ============================================================================
--
-- Propósito: almacenar físicamente el resultado del reporte agregado de
-- facturación por categoría y mes, evitando recalcular en cada consulta
-- los JOIN, el COUNT(DISTINCT), las sumatorias y el GROUP BY sobre las
-- tablas base. La vista conserva exactamente la semántica del reporte
-- original utilizado en TP4 (c.activo = TRUE, pr.activo = TRUE); la
-- materialización es una optimización de almacenamiento del resultado,
-- no un rediseño semántico del reporte.
--
-- Utiliza WITH DATA: la vista queda poblada desde su creación para
-- permitir las mediciones posteriores.
--
-- Validada manualmente mediante EXCEPT bidireccional contra la consulta
-- original:
--
-- original_minus_materialized = 0
-- materialized_minus_original = 0
--
-- Resultado: VALIDADA. El protocolo completo se documenta en
-- ../informes/informe_mediciones.md.
-- ============================================================================

CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
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
WITH DATA;

-- ============================================================================
-- ÍNDICE ÚNICO: idx_mv_facturacion_categoria_mes_unique
-- ============================================================================
--
-- Corresponde a la clave lógica del resultado: cada fila de la vista
-- materializada representa una combinación única de (categoria_id, mes).
--
-- Este índice UNIQUE, sin cláusula WHERE, es el requisito de PostgreSQL
-- para permitir posteriormente:
--
-- REFRESH MATERIALIZED VIEW CONCURRENTLY
--     mv_facturacion_categoria_mes;
--
-- NO se ejecuta ese REFRESH desde este archivo ni en esta etapa.
--
-- Política de refresh propuesta: cada 60 minutos mientras el sistema
-- esté en operación. La vista materializada NO se actualiza
-- automáticamente ante nuevos pedidos o detalles: entre dos refresh
-- puede existir hasta aproximadamente una hora de atraso. Por lo tanto
-- no debe considerarse información transaccional en tiempo real, sino
-- un reporte agregado para análisis y gestión.
--
-- El rendimiento fue medido manualmente con EXPLAIN (ANALYZE, BUFFERS).
-- Los resultados reales y el protocolo completo se encuentran en
-- ../informes/informe_mediciones.md.
-- ============================================================================

CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes_unique
    ON mv_facturacion_categoria_mes (categoria_id, mes);
