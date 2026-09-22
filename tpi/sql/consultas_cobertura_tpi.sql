-- TPI Food Store — Consultas de cobertura del Objetivo 5
-- Complementa la evidencia existente; no reemplaza TP3 ni TP4.
-- Contiene únicamente SELECT y comentarios: no modifica datos ni estructura.
-- Su objetivo principal es demostrar explícitamente GROUP BY + HAVING.
-- Las demás capacidades de la rúbrica se referencian a los TP históricos.

-- USUARIOS CON MÁS DE UN PEDIDO NO ELIMINADO
-- JOIN relaciona cada pedido con su usuario mediante pedido.usuario_id.
-- COUNT(p.id) agrega la cantidad de pedidos no eliminados de cada usuario.
-- GROUP BY forma un grupo por usuario con sus datos identificativos.
-- WHERE excluye pedidos eliminados antes de agrupar.
-- No se excluyen usuarios eliminados: se conserva el historial de pedidos.
-- No se filtra por estado: no existe un requisito que lo justifique.
-- No se une detalle_pedido, evitando multiplicar pedidos por sus líneas.
-- HAVING filtra los grupos después de la agregación.
-- WHERE actúa antes de la agregación: no reemplaza a HAVING para filtrar
-- COUNT(p.id) en este nivel de la consulta.
-- El umbral > 1 es una condición del ejercicio, no un resultado esperado.
-- No se anticipan conteos ni filas de salida; requieren ejecución real.

SELECT
    u.id AS usuario_id,
    u.nombre,
    u.apellido,
    u.mail,
    COUNT(p.id) AS cantidad_pedidos
FROM usuario u
JOIN pedido p
    ON p.usuario_id = u.id
WHERE p.eliminado = FALSE
GROUP BY
    u.id,
    u.nombre,
    u.apellido,
    u.mail
HAVING COUNT(p.id) > 1
ORDER BY
    cantidad_pedidos DESC,
    usuario_id ASC;

-- COBERTURA COMPLEMENTARIA EXISTENTE
-- TP3 y TP4 se conservan como evidencia histórica evaluada; no se presentan
-- como scripts compatibles automáticamente con el esquema canónico vigente.
-- Rutas relativas a la ubicación de este archivo (tpi/sql/).
-- A) JOIN + agregaciones + subconsulta correlacionada: consultas A y B de TP3.
-- ../../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql
-- B) Función de ventana RANK() OVER: consulta A de TP4.
-- ../../unidades/unidad-2/tp4/sql/consultas_tp4_ia.sql
-- RANK() OVER (...) ya satisface el requisito de función de ventana.
-- No se agrega otra función de ventana ni se duplican esas consultas.
-- C) DML de carga de la base canónica.
-- ../../datos_iniciales.sql
