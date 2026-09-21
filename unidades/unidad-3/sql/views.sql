-- Base de Datos II - Unidad 3 / Semana 5 - TP5
-- Requiere el modelo oficial indicado en las specs de este bloque.
-- No migra tablas ni acredita compatibilidad con schema.sql de la raíz.
-- Definiciones no ejecutadas en este bloque; validación real pendiente.
-- Instalación futura en una copia limpia del modelo oficial.
-- CREATE OR REPLACE no garantiza compatibilidad con columnas de vistas previas.
-- Si ya existen objetos anteriores, evaluar dependencias y migración por separado.
-- Este archivo no elimina ni migra vistas instaladas; no contiene DROP.
-- Equivalencia mediante EXCEPT bidireccional pendiente; no implica rendimiento.

-- Spec: ../specs/vista_productos_vigentes.md
-- Disponible se expone, pero no se filtra: disponibilidad no es eliminación.
CREATE OR REPLACE VIEW v_productos_vigentes AS
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

-- Spec: ../specs/vista_pedidos_resumen.md
-- Una baja lógica del usuario no debe ocultar pedidos históricos.
CREATE OR REPLACE VIEW v_pedidos_resumen AS
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

-- Spec: ../specs/vista_pedido_detalle.md
-- Subtotal físico; una baja lógica del producto no debe ocultar sus detalles.
CREATE OR REPLACE VIEW v_pedido_detalle AS
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

-- Spec: ../specs/vista_usuarios_publico.md
-- No expone contrasena ni celular. Los permisos se tratan en seguridad.sql.
-- La proyección no revoca accesos directos preexistentes a la tabla base.
CREATE OR REPLACE VIEW v_usuarios_publico AS
SELECT
    id,
    nombre,
    apellido,
    mail,
    rol
FROM usuario
WHERE eliminado = FALSE;