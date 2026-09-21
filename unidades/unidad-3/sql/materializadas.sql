-- Base de Datos II - Unidad 3 / Semana 5 - TP5
-- Requiere el modelo oficial indicado en las specs de este bloque.
-- No migra tablas ni acredita compatibilidad con schema.sql de la raíz.
-- Definiciones no ejecutadas en este bloque; validación real pendiente.
-- Spec: ../specs/vista_materializada_facturacion_categoria_mes.md
-- Instalación futura en una copia limpia; evaluar objetos existentes por separado.
-- Semántica histórica: solo se excluyen pedidos y detalles eliminados.
-- Las bajas lógicas de productos/categorías y la disponibilidad no filtran ventas.
-- Se suma el subtotal físico. No se modifica el reporte histórico de otros TPs.

CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    date_trunc('month', ped.fecha)::date AS mes,
    COUNT(DISTINCT ped.id) AS cantidad_pedidos,
    SUM(dp.cantidad) AS unidades_vendidas,
    SUM(dp.subtotal) AS facturacion_total
FROM categoria c
JOIN producto pr
    ON pr.categoria_id = c.id
JOIN detalle_pedido dp
    ON dp.producto_id = pr.id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY
    c.id,
    c.nombre,
    date_trunc('month', ped.fecha)::date
WITH DATA;

-- Clave lógica sin predicado: conserva la estrategia de refresh concurrente.
-- No se ejecuta REFRESH ni se programa actualización automática en este archivo.
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes_unique
    ON mv_facturacion_categoria_mes (categoria_id, mes);

-- Comparación futura: consulta 8 de queries.sql frente a esta materializada,
-- ambas con ORDER BY mes ASC, facturacion_total DESC.
-- Equivalencia, tiempos, buffers y costo de refresh: pendientes de validación.
-- Frecuencia propuesta: cada 60 minutos, sujeta a validación y programación futura.
-- No es información en tiempo real; el atraso depende del refresh real y sus fallos.