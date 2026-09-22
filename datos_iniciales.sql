-- Food Store: fotografía inicial del modelo oficial, no reproducción de ventas.
-- Ejecutar sobre el esquema recién creado, antes de los objetos programables.
BEGIN;

-- Evita mezclar el seed con datos ajenos o repetir una carga ya realizada.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM categoria)
        OR EXISTS (SELECT 1 FROM usuario)
        OR EXISTS (SELECT 1 FROM producto)
        OR EXISTS (SELECT 1 FROM pedido)
        OR EXISTS (SELECT 1 FROM detalle_pedido) THEN
        RAISE EXCEPTION 'El seed requiere las cinco tablas del modelo vacías';
    END IF;
END;
$$;

INSERT INTO categoria (nombre)
VALUES
    ('Pizzas'),
    ('Bebidas');

-- SEED_NO_AUTH existe únicamente para satisfacer el modelo académico.
-- No representa una contraseña real ni un mecanismo de autenticación y
-- no debe utilizarse en producción. rol y eliminado usan sus defaults.
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena)
VALUES
    ('Ana', 'Gómez', 'ana.gomez@foodstore.test', '2610000001', 'SEED_NO_AUTH'),
    ('Luis', 'Paz', 'luis.paz@foodstore.test', '2610000002', 'SEED_NO_AUTH'),
    ('Marta', 'Ruiz', 'marta.ruiz@foodstore.test', '2610000003', 'SEED_NO_AUTH');

-- El stock representa el estado inicial del catálogo: no se vuelve a descontar
-- por los detalles históricos. disponible y eliminado usan sus defaults.
INSERT INTO producto (categoria_id, nombre, descripcion, precio, stock)
VALUES
    (
        (SELECT id FROM categoria WHERE nombre = 'Pizzas'),
        'Muzzarella', 'Pizza de muzzarella', 1050.00, 50
    ),
    (
        (SELECT id FROM categoria WHERE nombre = 'Pizzas'),
        'Napolitana', 'Pizza napolitana', 1500.00, 40
    ),
    (
        (SELECT id FROM categoria WHERE nombre = 'Bebidas'),
        'Coca 1.5L', 'Bebida gaseosa de 1.5 litros', 800.00, 100
    );

-- TERMINADO es una convención explícita del seed para estas ventas completas;
-- no es un estado recuperado del modelo anterior. total comienza en su default.
-- Cada RETURNING identifica el pedido recién creado sin IDs hardcodeados ni
-- suponer una clave candidata sobre usuario, fecha y forma de pago.
WITH pedido_ana_1 AS (
    INSERT INTO pedido (usuario_id, fecha, estado, forma_pago)
    VALUES (
        (SELECT id FROM usuario WHERE mail = 'ana.gomez@foodstore.test'),
        DATE '2026-03-01', 'TERMINADO', 'EFECTIVO'
    )
    RETURNING id
), pedido_luis_1 AS (
    INSERT INTO pedido (usuario_id, fecha, estado, forma_pago)
    VALUES (
        (SELECT id FROM usuario WHERE mail = 'luis.paz@foodstore.test'),
        DATE '2026-03-01', 'TERMINADO', 'TARJETA'
    )
    RETURNING id
), pedido_ana_2 AS (
    INSERT INTO pedido (usuario_id, fecha, estado, forma_pago)
    VALUES (
        (SELECT id FROM usuario WHERE mail = 'ana.gomez@foodstore.test'),
        DATE '2026-03-05', 'TERMINADO', 'TRANSFERENCIA'
    )
    RETURNING id
), pedido_marta_1 AS (
    INSERT INTO pedido (usuario_id, fecha, estado, forma_pago)
    VALUES (
        (SELECT id FROM usuario WHERE mail = 'marta.ruiz@foodstore.test'),
        DATE '2026-03-06', 'TERMINADO', 'EFECTIVO'
    )
    RETURNING id
), pedido_luis_2 AS (
    INSERT INTO pedido (usuario_id, fecha, estado, forma_pago)
    VALUES (
        (SELECT id FROM usuario WHERE mail = 'luis.paz@foodstore.test'),
        DATE '2026-03-07', 'TERMINADO', 'TARJETA'
    )
    RETURNING id
), detalles (pedido_id, producto_nombre, cantidad, precio_unitario) AS (
    VALUES
        ((SELECT id FROM pedido_ana_1), 'Muzzarella', 2, 1000.00),
        ((SELECT id FROM pedido_ana_1), 'Coca 1.5L', 1, 800.00),
        ((SELECT id FROM pedido_luis_1), 'Napolitana', 1, 1500.00),
        ((SELECT id FROM pedido_ana_2), 'Muzzarella', 3, 1050.00),
        ((SELECT id FROM pedido_marta_1), 'Coca 1.5L', 4, 800.00),
        ((SELECT id FROM pedido_marta_1), 'Napolitana', 2, 1500.00),
        ((SELECT id FROM pedido_luis_2), 'Muzzarella', 1, 1050.00)
)
-- Los nombres de producto son inequívocos solo en este dataset controlado;
-- no son una clave de negocio. La subconsulta falla si hay más de una fila.
-- El subtotal usa el precio histórico, incluido 1000.00 para Muzzarella,
-- nunca su precio actual de catálogo (1050.00).
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    d.pedido_id,
    (SELECT p.id FROM producto p WHERE p.nombre = d.producto_nombre),
    d.cantidad,
    d.precio_unitario,
    d.cantidad * d.precio_unitario
FROM detalles d;

-- Reconciliación explícita de la fotografía inicial, sin totales hardcodeados.
-- El mantenimiento automático posterior se implementará en otra capa.
UPDATE pedido p
SET total = (
    SELECT COALESCE(SUM(dp.subtotal), 0)
    FROM detalle_pedido dp
    WHERE dp.pedido_id = p.id
      AND dp.eliminado = FALSE
);

-- Verificación lógica: ambas consultas deben devolver cero filas.
SELECT id AS detalle_id, subtotal, cantidad * precio_unitario AS subtotal_calculado
FROM detalle_pedido
WHERE subtotal IS DISTINCT FROM cantidad * precio_unitario;

SELECT p.id AS pedido_id, p.total, x.total_calculado
FROM pedido p
CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(dp.subtotal), 0) AS total_calculado
    FROM detalle_pedido dp
    WHERE dp.pedido_id = p.id
      AND dp.eliminado = FALSE
) x
WHERE p.total IS DISTINCT FROM x.total_calculado;

COMMIT;
