-- ============================================================================
-- views.sql
-- Base de Datos II - Unidad 3, Semana 5, Parte B: Vistas
-- Especificación: ../specs/vista_productos_vigentes.md
-- ============================================================================
-- Solo definiciones de vistas (CREATE OR REPLACE VIEW). No incluye
-- materialized views, índices, EXPLAIN ni consultas de prueba.
-- Las vistas documentadas se instalan y verifican manualmente sobre
-- foodstore_tp5. Los resultados de equivalencia son obtenidos por el
-- estudiante mediante SQL ejecutado fuera de esta sesión.
-- ============================================================================

-- ============================================================================
-- VISTA 1: v_productos_vigentes
-- ============================================================================
--
-- Propósito: encapsular en un único lugar la regla de vigencia del
-- catálogo, exponiendo productos vigentes junto con los datos básicos
-- de su categoría.
--
-- Regla de vigencia: un producto aparece únicamente cuando
-- producto.activo = TRUE Y categoria.activo = TRUE. Si la categoría
-- queda inactiva, sus productos dejan de aparecer en la vista aunque
-- producto.activo siga en TRUE.
--
-- Esta vista NO es una optimización de rendimiento: es un mecanismo de
-- encapsulamiento y consistencia de criterio de vigencia. No agrega
-- índices ni cambia el plan de ejecución subyacente.
--
-- Validada manualmente mediante EXCEPT bidireccional contra la consulta
-- manual equivalente:
--
-- manual_minus_view = 0
-- view_minus_manual = 0
--
-- Resultado: VALIDADA.
-- ============================================================================

CREATE OR REPLACE VIEW v_productos_vigentes AS
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
-- VISTA 2: v_pedidos_cliente
-- ============================================================================
--
-- Especificación: ../specs/vista_pedidos_cliente.md
--
-- Propósito: simplificar reportes de pedidos junto con los datos
-- mínimos necesarios del cliente asociado.
--
-- Contexto del esquema real: la consigna teórica original menciona
-- usuario y una columna contraseña, pero nuestro esquema real NO
-- contiene usuario, contraseña ni password. La tabla equivalente del
-- dominio actual es cliente (id, nombre, email, telefono,
-- created_at). No se inventan columnas inexistentes.
--
-- Minimización de información: esta vista aplica minimización de
-- datos. NO expone cliente.telefono. NO expone cliente.created_at.
-- Expone solamente cliente_nombre y cliente_email como datos
-- necesarios del cliente para el reporte.
--
-- No se agregan filtros de activo/eliminado porque esas columnas no
-- existen en cliente. La vista representa historial de pedidos, no
-- solamente clientes considerados "vigentes".
--
-- Esta vista NO es una optimización de rendimiento: es un mecanismo de
-- encapsulamiento y consistencia de criterio de minimización de datos.
--
-- Validada manualmente mediante EXCEPT bidireccional contra la consulta
-- manual equivalente:
--
-- SELECT
--     p.id AS pedido_id,
--     p.fecha,
--     p.forma_pago,
--     c.id AS cliente_id,
--     c.nombre AS cliente_nombre,
--     c.email AS cliente_email
-- FROM pedido p
-- JOIN cliente c
--     ON c.id = p.cliente_id;
--
-- manual_minus_view = 0
-- view_minus_manual = 0
--
-- Resultado: VALIDADA.
-- ============================================================================

CREATE OR REPLACE VIEW v_pedidos_cliente AS
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
-- VISTA 3: v_detalle_pedido_producto
-- ============================================================================
--
-- Especificación: ../specs/vista_detalle_pedido_producto.md
--
-- Propósito: evitar repetir manualmente el JOIN entre detalle_pedido y
-- producto en los reportes operativos, exponiendo el detalle de cada
-- pedido junto con el nombre del producto asociado.
--
-- Regla histórica: la vista representa TODAS las líneas históricas de
-- pedido. NO filtra por producto.activo. Un pedido histórico debe
-- seguir mostrando el producto asociado aunque ese producto sea
-- marcado posteriormente como inactivo. No se agregan filtros de
-- vigencia, estado o eliminación. No se inventan columnas inexistentes.
--
-- Subtotal: subtotal = cantidad * precio_unitario. Esta columna NO
-- existe físicamente en detalle_pedido; es una columna calculada
-- dentro de la vista.
--
-- Esta vista NO es una optimización de rendimiento: es un mecanismo de
-- encapsulamiento del JOIN detalle_pedido/producto.
--
-- Validada manualmente mediante EXCEPT bidireccional contra la consulta
-- manual equivalente:
--
-- SELECT
--     dp.pedido_id,
--     dp.producto_id,
--     p.nombre AS producto_nombre,
--     dp.cantidad,
--     dp.precio_unitario,
--     dp.cantidad * dp.precio_unitario AS subtotal
-- FROM detalle_pedido dp
-- JOIN producto p
--     ON p.id = dp.producto_id;
--
-- manual_minus_view = 0
-- view_minus_manual = 0
--
-- Resultado: VALIDADA.
-- ============================================================================

CREATE OR REPLACE VIEW v_detalle_pedido_producto AS
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
