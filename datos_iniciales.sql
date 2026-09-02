INSERT INTO categoria (nombre)
VALUES
    ('Pizzas'),
    ('Bebidas');
INSERT INTO cliente (nombre, email, telefono)
VALUES
    ('Ana Gómez', 'ana.gomez@foodstore.test', '2610000001'),
    ('Luis Paz', 'luis.paz@foodstore.test', '2610000002'),
    ('Marta Ruiz', 'marta.ruiz@foodstore.test', '2610000003');
INSERT INTO producto (categoria_id, nombre, descripcion, precio, stock)
VALUES
    (
        (SELECT id FROM categoria WHERE nombre = 'Pizzas'),
        'Muzzarella',
        'Pizza de muzzarella',
        1050.00,
        50
    ),
    (
        (SELECT id FROM categoria WHERE nombre = 'Pizzas'),
        'Napolitana',
        'Pizza napolitana',
        1500.00,
        40
    ),
    (
        (SELECT id FROM categoria WHERE nombre = 'Bebidas'),
        'Coca 1.5L',
        'Bebida gaseosa de 1.5 litros',
        800.00,
        100
    );

INSERT INTO pedido (cliente_id, fecha, forma_pago)
VALUES
    (
        (SELECT id FROM cliente WHERE email = 'ana.gomez@foodstore.test'),
        '2026-03-01 00:00:00-03',
        'EFECTIVO'
    ),
    (
        (SELECT id FROM cliente WHERE email = 'luis.paz@foodstore.test'),
        '2026-03-01 00:00:00-03',
        'TARJETA'
    ),
    (
        (SELECT id FROM cliente WHERE email = 'ana.gomez@foodstore.test'),
        '2026-03-05 00:00:00-03',
        'TRANSFERENCIA'
    ),
    (
        (SELECT id FROM cliente WHERE email = 'marta.ruiz@foodstore.test'),
        '2026-03-06 00:00:00-03',
        'EFECTIVO'
    ),
    (
        (SELECT id FROM cliente WHERE email = 'luis.paz@foodstore.test'),
        '2026-03-07 00:00:00-03',
        'TARJETA'
    );

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
VALUES
    (
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'ana.gomez@foodstore.test'
        AND p.fecha = '2026-03-01 00:00:00-03'
        AND p.forma_pago = 'EFECTIVO'
    ),
    (SELECT id FROM producto WHERE nombre = 'Muzzarella'),
    2,
    1000.00
),
    (
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'ana.gomez@foodstore.test'
        AND p.fecha = '2026-03-01 00:00:00-03'
        AND p.forma_pago = 'EFECTIVO'
    ),
    (SELECT id FROM producto WHERE nombre = 'Coca 1.5L'),
    1,
    800.00
),
(
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'luis.paz@foodstore.test'
        AND p.fecha = '2026-03-01 00:00:00-03'
        AND p.forma_pago = 'TARJETA'
    ),
    (SELECT id FROM producto WHERE nombre = 'Napolitana'),
    1,
    1500.00
),
(
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'ana.gomez@foodstore.test'
        AND p.fecha = '2026-03-05 00:00:00-03'
        AND p.forma_pago = 'TRANSFERENCIA'
    ),
    (SELECT id FROM producto WHERE nombre = 'Muzzarella'),
    3,
    1050.00
),
(
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'marta.ruiz@foodstore.test'
        AND p.fecha = '2026-03-06 00:00:00-03'
        AND p.forma_pago = 'EFECTIVO'
    ),
    (SELECT id FROM producto WHERE nombre = 'Coca 1.5L'),
    4,
    800.00
),
(
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'marta.ruiz@foodstore.test'
        AND p.fecha = '2026-03-06 00:00:00-03'
        AND p.forma_pago = 'EFECTIVO'
    ),
    (SELECT id FROM producto WHERE nombre = 'Napolitana'),
    2,
    1500.00
),
(
    (
        SELECT p.id
        FROM pedido p
        JOIN cliente c ON c.id = p.cliente_id
        WHERE c.email = 'luis.paz@foodstore.test'
        AND p.fecha = '2026-03-07 00:00:00-03'
        AND p.forma_pago = 'TARJETA'
    ),
    (SELECT id FROM producto WHERE nombre = 'Muzzarella'),
    1,
    1050.00
);