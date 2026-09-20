-- ============================================================================
-- Carga Masiva TP3 - Food Store
-- Semana 3, Unidad 2: Optimización de Consultas
-- Base de datos: foodstore_tp3
-- ============================================================================
-- RESTRICCIONES:
-- - NO usar DELETE, TRUNCATE, DROP ni UPDATE
-- - NO modificar el esquema
-- - NO deshabilitar FK ni CHECK
-- - Sin PL/pgSQL a menos que sea absolutamente necesario
-- - Preferir SQL set-based y generate_series por rendimiento
-- - NO incluir COMMIT ni ROLLBACK (transacción externa)
-- - NO asumir IDs consecutivos: usar relaciones reales y ROW_NUMBER()
-- ============================================================================

-- ============================================================================
-- BLOQUE 1: CARGA DE CLIENTES (20.000)
-- ============================================================================
-- Genera 20.000 clientes con:
-- - Nombre: "Cliente TP3 <número>"
-- - Email único: "tp3_cliente_<número>@foodstore.test" (patrón para identificación)
-- - Teléfono: "261" + número de 7 dígitos (simula Mendoza)
-- ============================================================================

INSERT INTO cliente (nombre, email, telefono)
SELECT
    'Cliente TP3 ' || gs.num AS nombre,
    'tp3_cliente_' || gs.num || '@foodstore.test' AS email,
    '261' || LPAD((gs.num % 9999999)::TEXT, 7, '0') AS telefono
FROM generate_series(1, 20000) AS gs(num);

-- ============================================================================
-- BLOQUE 2: CARGA DE PRODUCTOS (50.000)
-- ============================================================================
-- Genera 50.000 productos distribuidos entre categorías existentes.
-- - Nombre: "Producto TP3 <número>" (patrón para identificación)
-- - Precio: 500 + (número % 4501) → rango inclusivo [500, 5000]
-- - Stock: número % 201 → rango [0, 200]
-- - categoria_id: selecciona de categorías existentes mediante ARRAY rotación
-- ============================================================================

INSERT INTO producto (categoria_id, nombre, descripcion, precio, stock, activo)
SELECT
    -- Distribuir entre categorías existentes sin hardcoding de IDs
    (ARRAY(
        SELECT id FROM categoria ORDER BY id
    ))[
        (gs.num % (
            SELECT COUNT(*) FROM categoria
        )) + 1
    ] AS categoria_id,
    'Producto TP3 ' || gs.num AS nombre,
    'Producto masivo generado en laboratorio TP3 - item ' || gs.num AS descripcion,
    (500 + (gs.num % 4501))::NUMERIC(12, 2) AS precio,
    gs.num % 201 AS stock,
    TRUE AS activo
FROM generate_series(1, 50000) AS gs(num);

-- ============================================================================
-- BLOQUE 3: CARGA DE PEDIDOS (200.000)
-- ============================================================================
-- Genera 200.000 pedidos:
-- - cliente_id: referencia solo a clientes TP3 identificados por patrón exacto de email (~)
-- - forma_pago: distribuida entre EFECTIVO, TARJETA, TRANSFERENCIA
-- - fecha: distribuida a lo largo de ~35 días desde 2026-03-08
-- Usa ROW_NUMBER() para evitar asumir IDs consecutivos
-- ============================================================================

WITH clientes_tp3_numerados AS (
    -- Numerar clientes TP3 para distribución determinista sin asumir IDs consecutivos
    SELECT
        id,
        ROW_NUMBER() OVER (ORDER BY id) AS posicion
    FROM cliente
    WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
)
INSERT INTO pedido (cliente_id, forma_pago, fecha)
SELECT
    -- Cliente TP3 asignado vía JOIN por posición lógica (set-based, sin subquery escalar por fila)
    c.id AS cliente_id,
    -- Distribuir forma de pago cíclicamente
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA'])[
        ((gs.num - 1) % 3) + 1
    ]::forma_pago AS forma_pago,
    -- Fecha: distribuida en ~35 días (200K pedidos / 4 por minuto)
    TIMESTAMPTZ '2026-03-08 00:00:00-03' +
    (((gs.num - 1) / 4)::INTEGER || ' minutes')::INTERVAL AS fecha
FROM generate_series(1, 200000) AS gs(num)
JOIN clientes_tp3_numerados c
    ON c.posicion = ((gs.num - 1) % 20000) + 1;

-- ============================================================================
-- BLOQUE 4: CARGA DE DETALLES_PEDIDO (2 o 3 por pedido = exactamente 500.000 total)
-- ============================================================================
-- Cálculo exacto: 200.000 pedidos * 2 detalles obligatorios = 400.000
--                 100.000 pedidos con posición par * 1 detalle adicional = 100.000
--                 TOTAL = 500.000 detalles nuevos
-- Estrategia:
-- - Usar CTEs para numerar pedidos y productos sin asumir IDs consecutivos
-- - Generar 2-3 detalles por pedido de forma determinista:
--   * Todos los pedidos: detalle 1 y 2 (2 detalles) → 200.000 * 2 = 400.000
--   * Pedidos con posición par (100.000 pedidos): detalle 3 adicional → +100.000
-- - Distribuir productos usando offsets en ROW_NUMBER(): productos garantizados distintos
-- - precio_unitario = producto.precio (coherencia de datos, no inventado)
-- - Identificar pedidos TP3 mediante JOIN con cliente usando patrón exacto de email (~)
-- ============================================================================

WITH clientes_tp3 AS (
    -- Identificar clientes TP3 por patrón de email, no por rango de IDs
    SELECT id
    FROM cliente
    WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
),
productos_tp3_numerados AS (
    -- Numerar productos TP3 para lookup sin asumir IDs consecutivos
    SELECT
        id,
        precio,
        ROW_NUMBER() OVER (ORDER BY id) AS posicion
    FROM producto
    WHERE nombre ~ '^Producto TP3 [0-9]+$'
),
pedidos_tp3_numerados AS (
    -- Numerar pedidos TP3 (solo los que pertenecen a clientes TP3)
    SELECT
        id,
        ROW_NUMBER() OVER (ORDER BY id) AS posicion
    FROM pedido
    WHERE cliente_id IN (SELECT id FROM clientes_tp3)
),
estructura_detalles AS (
    -- Definir qué detalles generar por cada pedido
    -- Detalle 1 y 2 para todos; detalle 3 solo para pedidos con posición par
    SELECT
        p.id AS pedido_id,
        p.posicion AS pedido_posicion,
        d.numero_detalle,
        -- Mapear cada detalle a un producto diferente usando offsets de posición
        (CASE
            WHEN d.numero_detalle = 1 THEN (p.posicion - 1) % 50000 + 1
            WHEN d.numero_detalle = 2 THEN ((p.posicion - 1) + 16667) % 50000 + 1
            WHEN d.numero_detalle = 3 THEN ((p.posicion - 1) + 33334) % 50000 + 1
        END) AS producto_posicion_esperada,
        -- Cantidad: 2 para detalle 1, variable para otros
        (CASE WHEN d.numero_detalle = 1 THEN 2 ELSE 3 END) AS cantidad
    FROM pedidos_tp3_numerados p
    CROSS JOIN (
        SELECT 1 AS numero_detalle
        UNION ALL
        SELECT 2
        UNION ALL
        SELECT 3
    ) d
    WHERE d.numero_detalle <= 2 OR (d.numero_detalle = 3 AND p.posicion % 2 = 0)
)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT
    ed.pedido_id,
    ptp.id AS producto_id,
    ed.cantidad::INTEGER,
    ptp.precio AS precio_unitario
FROM estructura_detalles ed
JOIN productos_tp3_numerados ptp
    ON ed.producto_posicion_esperada = ptp.posicion;

-- ============================================================================
-- BLOQUE 5: ACTUALIZAR ESTADÍSTICAS (ANALYZE)
-- ============================================================================
-- Recalcular estadísticas para que el optimizador de consultas
-- tenga información precisa sobre los datos nuevos.
-- ============================================================================

ANALYZE categoria;
ANALYZE cliente;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- ============================================================================
-- BLOQUE 6: VALIDACIÓN Y CONSULTAS DE SOLO LECTURA
-- ============================================================================
-- Consultas para comprobar la carga exitosa.
-- Estas consultas pueden ejecutarse sin modificar datos.
-- Identifican pedidos TP3 mediante JOIN con cliente (patrón exacto de email con ~), no por fecha.
-- ============================================================================

-- Verificación 1: Cantidad total de categorías
SELECT
    'Total de categorías' AS verificacion,
    COUNT(*) AS cantidad
FROM categoria;

-- Verificación 2: Cantidad total de clientes
SELECT
    'Total de clientes' AS verificacion,
    COUNT(*) AS cantidad
FROM cliente;

-- Verificación 3: Cantidad total de productos
SELECT
    'Total de productos' AS verificacion,
    COUNT(*) AS cantidad
FROM producto;

-- Verificación 4: Cantidad total de pedidos
SELECT
    'Total de pedidos' AS verificacion,
    COUNT(*) AS cantidad
FROM pedido;

-- Verificación 5: Cantidad total de detalles de pedido
SELECT
    'Total de detalles_pedido' AS verificacion,
    COUNT(*) AS cantidad
FROM detalle_pedido;

-- Verificación 6: Cantidad de clientes TP3 generados
SELECT
    'Clientes TP3 generados' AS verificacion,
    COUNT(*) AS cantidad
FROM cliente
WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$';

-- Verificación 7: Cantidad de productos TP3 generados
SELECT
    'Productos TP3 generados' AS verificacion,
    COUNT(*) AS cantidad
FROM producto
WHERE nombre ~ '^Producto TP3 [0-9]+$';

-- Verificación 8: Cantidad de pedidos TP3 (identif. por cliente TP3)
SELECT
    'Pedidos TP3 generados' AS verificacion,
    COUNT(*) AS cantidad
FROM pedido p
WHERE p.cliente_id IN (
    SELECT id FROM cliente
    WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
);

-- Verificación 9: Cantidad de detalles TP3 (asociados a productos TP3)
SELECT
    'Detalles TP3 generados' AS verificacion,
    COUNT(*) AS cantidad
FROM detalle_pedido dp
WHERE dp.producto_id IN (
    SELECT id FROM producto
    WHERE nombre ~ '^Producto TP3 [0-9]+$'
);

-- Verificación 10: Cantidad de detalles asociados a pedidos TP3
SELECT
    'Detalles asociados a pedidos TP3' AS verificacion,
    COUNT(*) AS cantidad
FROM detalle_pedido dp
WHERE dp.pedido_id IN (
    SELECT p.id FROM pedido p
    WHERE p.cliente_id IN (
        SELECT id FROM cliente
        WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
    )
);

-- Verificación 11: Distribución de forma_pago en pedidos TP3
SELECT
    'Distribución de forma_pago en pedidos TP3' AS verificacion,
    forma_pago,
    COUNT(*) AS cantidad
FROM pedido p
WHERE p.cliente_id IN (
    SELECT id FROM cliente
    WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
)
GROUP BY forma_pago
ORDER BY forma_pago;

-- Verificación 12: Mínimo de detalles por pedido TP3
SELECT
    'Detalles por pedido TP3 - mínimo' AS verificacion,
    MIN(detalle_count) AS cantidad
FROM (
    SELECT
        pedido_id,
        COUNT(*) AS detalle_count
    FROM detalle_pedido
    WHERE pedido_id IN (
        SELECT p.id FROM pedido p
        WHERE p.cliente_id IN (
            SELECT id FROM cliente
            WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
        )
    )
    GROUP BY pedido_id
) AS pedidos_detalle;

-- Verificación 13: Promedio de detalles por pedido TP3
SELECT
    'Detalles por pedido TP3 - promedio' AS verificacion,
    ROUND(AVG(detalle_count), 2) AS cantidad
FROM (
    SELECT
        pedido_id,
        COUNT(*) AS detalle_count
    FROM detalle_pedido
    WHERE pedido_id IN (
        SELECT p.id FROM pedido p
        WHERE p.cliente_id IN (
            SELECT id FROM cliente
            WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
        )
    )
    GROUP BY pedido_id
) AS pedidos_detalle;

-- Verificación 14: Máximo de detalles por pedido TP3
SELECT
    'Detalles por pedido TP3 - máximo' AS verificacion,
    MAX(detalle_count) AS cantidad
FROM (
    SELECT
        pedido_id,
        COUNT(*) AS detalle_count
    FROM detalle_pedido
    WHERE pedido_id IN (
        SELECT p.id FROM pedido p
        WHERE p.cliente_id IN (
            SELECT id FROM cliente
            WHERE email ~ '^tp3_cliente_[0-9]+@foodstore[.]test$'
        )
    )
    GROUP BY pedido_id
) AS pedidos_detalle;

-- ============================================================================
-- FIN DE LA CARGA MASIVA TP3
-- ============================================================================
