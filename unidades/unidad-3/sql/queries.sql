-- Base de Datos II - Unidad 3 / Semana 5 - TP5
-- Requiere el modelo oficial indicado en las specs de este bloque.
-- No migra tablas ni acredita compatibilidad con schema.sql de la raíz.
-- Definiciones no ejecutadas en este bloque; validación real pendiente.
-- Solo consultas manuales: no contiene DDL ni resultados.
-- Las consultas 4 a 8 son las referencias de equivalencia de las vistas.
-- Para comparar rendimiento, usar el mismo ORDER BY en ambas alternativas.

-- CONSULTA 1: Stock bajo
SELECT
    id,
    nombre,
    stock,
    precio
FROM producto
WHERE eliminado = FALSE
  AND stock <= 5
ORDER BY stock ASC, nombre ASC;

-- CONSULTA 2: Pedidos recientes
SELECT
    id,
    usuario_id,
    fecha,
    estado,
    forma_pago,
    total
FROM pedido
WHERE eliminado = FALSE
  AND fecha >= DATE '2026-04-11'
ORDER BY fecha DESC;

-- CONSULTA 3: Usuario por mail sin distinguir mayúsculas
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE
  AND lower(mail) = lower('ANA.GOMEZ@FOODSTORE.TEST');

-- CONSULTA 4: Equivalente a v_productos_vigentes
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    p.disponible,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE;

-- CONSULTA 5: Equivalente a v_pedidos_resumen
SELECT
    ped.id AS pedido_id,
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
FROM pedido ped
JOIN usuario u
    ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE;

-- CONSULTA 6: Equivalente a v_pedido_detalle
SELECT
    dp.id AS detalle_id,
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id
WHERE dp.eliminado = FALSE;

-- CONSULTA 7: Equivalente a v_usuarios_publico
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE;

-- CONSULTA 8: Original de mv_facturacion_categoria_mes
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
ORDER BY
    mes ASC,
    facturacion_total DESC;