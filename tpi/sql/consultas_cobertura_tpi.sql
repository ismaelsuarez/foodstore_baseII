-- TPI Food Store — Consultas de cobertura del Objetivo 5
-- Complementa la evidencia existente; no reemplaza TP3 ni TP4.
-- Contiene únicamente SELECT y comentarios: no modifica datos ni estructura.
-- Su objetivo principal es demostrar explícitamente GROUP BY + HAVING.
-- Las demás capacidades de la rúbrica se referencian a los TP históricos.

-- CLIENTES CON MÁS DE UN PEDIDO
-- JOIN relaciona cada pedido con su cliente mediante pedido.cliente_id.
-- COUNT(p.id) agrega la cantidad de pedidos de cada cliente.
-- GROUP BY forma un grupo por cliente usando su id y su nombre.
-- No se une detalle_pedido, evitando multiplicar pedidos por sus líneas.
-- HAVING filtra los grupos después de la agregación.
-- WHERE actúa antes de la agregación: no reemplaza a HAVING para filtrar
-- COUNT(p.id) en este nivel de la consulta.
-- El umbral > 1 es una condición del ejercicio, no un resultado esperado.
-- No se anticipan conteos ni filas de salida; requieren ejecución real.

SELECT
    c.id AS cliente_id,
    c.nombre AS cliente_nombre,
    COUNT(p.id) AS cantidad_pedidos
FROM cliente c
JOIN pedido p
    ON p.cliente_id = c.id
GROUP BY
    c.id,
    c.nombre
HAVING COUNT(p.id) > 1
ORDER BY
    cantidad_pedidos DESC,
    cliente_id ASC;

-- COBERTURA COMPLEMENTARIA EXISTENTE
-- Rutas relativas a la ubicación de este archivo (tpi/sql/).
-- A) JOIN + agregaciones + subconsulta correlacionada: consultas A y B de TP3.
-- ../../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql
-- B) Función de ventana RANK() OVER: consulta A de TP4.
-- ../../unidades/unidad-2/tp4/sql/consultas_tp4_ia.sql
-- RANK() OVER (...) ya satisface el requisito de función de ventana.
-- No se agrega otra función de ventana ni se duplican esas consultas.
-- C) DML de carga de la base canónica.
-- ../../datos_iniciales.sql
