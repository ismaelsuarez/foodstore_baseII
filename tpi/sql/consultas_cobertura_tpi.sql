-- TPI Food Store — Consultas de cobertura del Objetivo 5
-- Complementa la evidencia existente; no reemplaza TP3 ni TP4.
-- Contiene únicamente SELECT y comentarios: no modifica datos ni estructura.
-- Demuestra GROUP BY + HAVING y una función de ventana sobre el modelo canónico.
-- Los TP históricos se conservan como antecedentes, no como sustitutos de SQL vigente.

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

-- Función de ventana — ranking de usuarios por gasto
-- Historial de importes de pedidos no eliminados, sin filtrar fecha ni estado.
-- No se filtra usuario.eliminado: su baja posterior no borra las compras previas.
-- INNER JOIN incluye usuarios con al menos un pedido no eliminado, no usuarios
-- sin compras. Se suma pedido.total físico, sin unir detalles ni duplicar importes.
-- La CTE agrega por usuario; RANK opera después sobre los gastos agregados.
-- OVER ordena solo por gasto: los empates comparten ranking y dejan saltos.
-- El id en el ORDER BY final estabiliza la presentación, sin romper los empates
-- dentro de RANK. No se necesita PARTITION BY para un único ranking global.
WITH gasto_usuario AS (
    SELECT
        u.id,
        u.nombre,
        u.apellido,
        SUM(p.total) AS gasto_total
    FROM usuario u
    JOIN pedido p ON p.usuario_id = u.id
    WHERE p.eliminado = FALSE
    GROUP BY u.id, u.nombre, u.apellido
)
SELECT
    id,
    nombre,
    apellido,
    gasto_total,
    RANK() OVER (ORDER BY gasto_total DESC) AS ranking
FROM gasto_usuario
ORDER BY ranking, id;

-- COBERTURA COMPLEMENTARIA EXISTENTE
-- TP3 y TP4 se conservan como evidencia histórica evaluada; no se presentan
-- como scripts compatibles automáticamente con el esquema canónico vigente.
-- Rutas relativas a la ubicación de este archivo (tpi/sql/).
-- A) JOIN + agregaciones + subconsulta correlacionada: consultas A y B de TP3.
-- ../../unidades/unidad-2/tp3/sql/consultas_tp3_ia.sql
-- B) Función de ventana RANK() OVER: consulta A de TP4.
-- ../../unidades/unidad-2/tp4/sql/consultas_tp4_ia.sql
-- Esa ventana histórica no es compatible automáticamente con el modelo actual.
-- La sección canónica anterior cubre la ventana sin modificar los TP evaluados.
-- C) DML de carga de la base canónica.
-- ../../datos_iniciales.sql
