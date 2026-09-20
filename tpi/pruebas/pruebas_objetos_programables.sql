-- TPI-4 — Pruebas de objetos programables (PostgreSQL 16/17).
-- Ejecutar únicamente en el laboratorio, con los objetos TPI ya instalados:
-- psql -U postgres -d foodstore_tpi -v ON_ERROR_STOP=1 -f .\tpi\pruebas\pruebas_objetos_programables.sql
-- Usar el mismo esquema de resolución de nombres que al instalar los objetos.
-- Esta batería crea sus propios datos y revierte todas sus filas al terminar.
-- Las secuencias/IDENTITY no garantizan retroceder: los huecos son normales.
-- No se intenta restaurar sus valores. Si psql se detiene por un error no
-- esperado, el cierre de su conexión revierte la transacción pendiente.
-- Una sesión verifica atomicidad, reglas de negocio e integridad; los bloqueos
-- FOR UPDATE/FOR SHARE pertenecen al diseño de las rutinas instaladas.
-- No demuestra experimentalmente dos CALL concurrentes. Evidencia histórica:
-- ../../unidades/unidad-1/tp2/informes/informe_concurrencia.md
-- Ejecutar sin otras escrituras concurrentes en este laboratorio aislado.

BEGIN;

DO LANGUAGE plpgsql $pruebas$
DECLARE
    v_categoria_id categoria.id%TYPE;
    v_cliente_id cliente.id%TYPE;
    v_producto_id producto.id%TYPE;
    v_pedido_id pedido.id%TYPE;
    v_productos BIGINT[] := ARRAY[]::BIGINT[];
    v_pedidos BIGINT[] := ARRAY[]::BIGINT[];
    v_caso RECORD;
    v_cantidad INTEGER;
    v_stock producto.stock%TYPE;
    v_precio producto.precio%TYPE;
    v_limite NUMERIC;
    v_pedido_inexistente pedido.id%TYPE;
    v_producto_inexistente producto.id%TYPE;
    v_restriccion TEXT;
BEGIN
    -- Precheck: antes de crear datos. Los objetos no se crean en esta prueba.
    IF current_database() <> 'foodstore_tpi' THEN
        RAISE EXCEPTION 'TEST FAILED: ejecutar únicamente en foodstore_tpi';
    END IF;
    IF current_setting('session_replication_role') <> 'origin' THEN
        RAISE EXCEPTION 'TEST FAILED: se requiere session_replication_role = origin';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('fn_validar_producto_activo_detalle()')
          AND prokind = 'f' AND prorettype = 'trigger'::regtype
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: falta la función trigger del TPI';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('registrar_detalle_pedido(bigint,bigint,integer)')
          AND prokind = 'p'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: falta el procedimiento del TPI';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_detalle_producto_activo'
          AND tgrelid = 'detalle_pedido'::regclass
          AND tgfoid = to_regprocedure('fn_validar_producto_activo_detalle()')
          AND NOT tgisinternal AND tgenabled IN ('O', 'A')
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: falta el trigger habilitado y vinculado al TPI';
    END IF;
    IF EXISTS (SELECT 1 FROM categoria WHERE nombre = '__TPI_TEST_CATEGORIA__')
       OR EXISTS (SELECT 1 FROM cliente WHERE email = 'tpi.tests@foodstore.invalid') THEN
        RAISE EXCEPTION 'TEST FAILED: los identificadores de prueba ya están ocupados';
    END IF;

    INSERT INTO categoria (nombre)
    VALUES ('__TPI_TEST_CATEGORIA__') RETURNING id INTO v_categoria_id;
    INSERT INTO cliente (nombre, email)
    VALUES ('Cliente de pruebas TPI', 'tpi.tests@foodstore.invalid')
    RETURNING id INTO v_cliente_id;

    -- Los números son posiciones de escenarios, nunca IDs de la base.
    -- Cada ID real se obtiene por RETURNING; cada producto tiene pedido propio.
    -- D1/D2 y E1/E2 comparten deliberadamente su pareja para contrastar rutas.
    -- El producto 7 es únicamente el destino inactivo del UPDATE de F.
    FOR v_caso IN
        SELECT * FROM (VALUES
            (1, '__TPI_VALIDO__',          1000.00, 10, TRUE),
            (2, '__TPI_CANTIDAD__',        1000.00, 10, TRUE),
            (3, '__TPI_STOCK_BAJO__',       500.00,  2, TRUE),
            (4, '__TPI_INACTIVO__',         750.00, 10, FALSE),
            (5, '__TPI_DUPLICADO__',       1000.00, 10, TRUE),
            (6, '__TPI_UPDATE_ACTIVO__',   1000.00, 10, TRUE),
            (7, '__TPI_UPDATE_INACTIVO__', 1000.00, 10, FALSE),
            (8, '__TPI_REFERENCIAS__',     1000.00, 10, TRUE),
            (9, '__TPI_PRECIO_HISTORICO__',1200.00, 10, TRUE),
            (10,'__TPI_ROLLBACK__',         900.00, 10, TRUE)
        ) AS casos(posicion, nombre, precio, stock, activo)
        ORDER BY posicion
    LOOP
        INSERT INTO producto (categoria_id, nombre, precio, stock, activo)
        VALUES (v_categoria_id, v_caso.nombre, v_caso.precio, v_caso.stock, v_caso.activo)
        RETURNING id INTO v_producto_id;
        v_productos[v_caso.posicion] := v_producto_id;
        INSERT INTO pedido (cliente_id, forma_pago)
        VALUES (v_cliente_id, 'EFECTIVO') RETURNING id INTO v_pedido_id;
        v_pedidos[v_caso.posicion] := v_pedido_id;
    END LOOP;

    -- A. CALL válido: una línea, precio leído antes, descuento exacto y actividad.
    SELECT precio INTO v_precio FROM producto WHERE id = v_productos[1];
    CALL registrar_detalle_pedido(v_pedidos[1], v_productos[1], 3);
    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[1]) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM detalle_pedido
           WHERE pedido_id = v_pedidos[1] AND producto_id = v_productos[1]
             AND cantidad = 3 AND precio_unitario = v_precio
       )
       OR (SELECT stock FROM producto WHERE id = v_productos[1]) IS DISTINCT FROM 7
       OR (SELECT activo FROM producto WHERE id = v_productos[1]) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'TEST FAILED: CALL válido no conservó el contrato esperado';
    END IF;
    RAISE NOTICE 'PASS: CALL válido registra detalle y descuenta stock';

    -- B. Cada variante se ejecuta y verifica separadamente, incluida NULL.
    -- El fallo centinela usa P0001 (predeterminado), nunca el código capturado.
    FOREACH v_cantidad IN ARRAY ARRAY[0, -1, NULL]::INTEGER[] LOOP
        BEGIN
            CALL registrar_detalle_pedido(v_pedidos[2], v_productos[2], v_cantidad);
            RAISE EXCEPTION 'TEST FAILED: se esperaba 22023 para cantidad %', v_cantidad;
        EXCEPTION
            WHEN SQLSTATE '22023' THEN NULL;
        END;
        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[2])
           OR (SELECT stock FROM producto WHERE id = v_productos[2]) IS DISTINCT FROM 10 THEN
            RAISE EXCEPTION 'TEST FAILED: cantidad % dejó cambios', v_cantidad;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASS: cantidades cero, negativa y NULL rechazadas sin cambios';

    -- C. Solicitar tres unidades cuando solamente hay dos disponibles.
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[3], v_productos[3], 3);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23514 por stock insuficiente';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[3])
       OR (SELECT stock FROM producto WHERE id = v_productos[3]) IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'TEST FAILED: stock insuficiente dejó cambios';
    END IF;
    RAISE NOTICE 'PASS: stock insuficiente rechazado sin cambios';

    -- D1. Soft delete: el procedimiento rechaza un producto existente inactivo.
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[4], v_productos[4], 1);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23514 para CALL con producto inactivo';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[4])
       OR (SELECT stock FROM producto WHERE id = v_productos[4]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: CALL con producto inactivo dejó cambios';
    END IF;
    RAISE NOTICE 'PASS: procedimiento rechaza producto inactivo sin cambios';

    -- D2. Ruta directa: cantidad, precio y pedido son válidos; actúa el trigger.
    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[4], v_productos[4], 1, 750.00);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23514 para INSERT directo inactivo';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[4])
       OR (SELECT stock FROM producto WHERE id = v_productos[4]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: INSERT directo inactivo dejó cambios';
    END IF;
    RAISE NOTICE 'PASS: trigger bloquea INSERT directo de producto inactivo';

    -- E1. La segunda llamada tiene stock suficiente: debe fallar por duplicado.
    CALL registrar_detalle_pedido(v_pedidos[5], v_productos[5], 2);
    SELECT stock INTO v_stock FROM producto WHERE id = v_productos[5];
    IF v_stock IS DISTINCT FROM 8 THEN
        RAISE EXCEPTION 'TEST FAILED: preparación del duplicado no descontó dos unidades';
    END IF;
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[5], v_productos[5], 1);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23505 para CALL duplicado';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN NULL;
    END;
    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[5]) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM detalle_pedido
           WHERE pedido_id = v_pedidos[5] AND producto_id = v_productos[5]
             AND cantidad = 2 AND precio_unitario = 1000.00
       )
       OR (SELECT stock FROM producto WHERE id = v_productos[5]) IS DISTINCT FROM v_stock THEN
        RAISE EXCEPTION 'TEST FAILED: CALL duplicado alteró detalle o stock';
    END IF;
    RAISE NOTICE 'PASS: procedimiento rechaza duplicado sin un segundo descuento';

    -- E2. La PK debe rechazar la ruta directa, después de permitirla el trigger.
    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[5], v_productos[5], 1, 1000.00);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23505 para INSERT duplicado';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'pk_detalle_pedido' THEN
                RAISE;
            END IF;
    END;
    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[5]) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM detalle_pedido
           WHERE pedido_id = v_pedidos[5] AND producto_id = v_productos[5]
             AND cantidad = 2 AND precio_unitario = 1000.00
       )
       OR (SELECT stock FROM producto WHERE id = v_productos[5]) IS DISTINCT FROM v_stock THEN
        RAISE EXCEPTION 'TEST FAILED: duplicado directo alteró detalle o stock';
    END IF;
    RAISE NOTICE 'PASS: PK compuesta rechaza duplicado directo';

    -- F. El cambio de producto debe rechazarse sin modificar la línea original.
    CALL registrar_detalle_pedido(v_pedidos[6], v_productos[6], 1);
    BEGIN
        UPDATE detalle_pedido
        SET producto_id = v_productos[7]
        WHERE pedido_id = v_pedidos[6] AND producto_id = v_productos[6];
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23514 para UPDATE a producto inactivo';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;
    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[6]) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM detalle_pedido
           WHERE pedido_id = v_pedidos[6] AND producto_id = v_productos[6]
             AND cantidad = 1 AND precio_unitario = 1000.00
       )
       OR (SELECT stock FROM producto WHERE id = v_productos[6]) IS DISTINCT FROM 9
       OR (SELECT stock FROM producto WHERE id = v_productos[7]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: UPDATE rechazado dejó modificaciones parciales';
    END IF;
    RAISE NOTICE 'PASS: trigger rechaza UPDATE hacia producto inactivo';

    -- G. IDs ausentes calculados sobre datos reales, sin valores arbitrarios.
    -- La suma en NUMERIC permite detectar el límite de BIGINT sin desbordar.
    SELECT COALESCE(MAX(id)::NUMERIC, 0) + 1 INTO v_limite FROM pedido;
    IF v_limite > 9223372036854775807::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: no hay margen BIGINT para el pedido inexistente';
    END IF;
    v_pedido_inexistente := v_limite::BIGINT;
    SELECT COALESCE(MAX(id)::NUMERIC, 0) + 1 INTO v_limite FROM producto;
    IF v_limite > 9223372036854775807::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: no hay margen BIGINT para el producto inexistente';
    END IF;
    v_producto_inexistente := v_limite::BIGINT;
    IF EXISTS (SELECT 1 FROM pedido WHERE id = v_pedido_inexistente)
       OR EXISTS (SELECT 1 FROM producto WHERE id = v_producto_inexistente) THEN
        RAISE EXCEPTION 'TEST FAILED: las referencias de G deben ser inexistentes';
    END IF;

    -- G1. Pedido inexistente, producto válido.
    BEGIN
        CALL registrar_detalle_pedido(v_pedido_inexistente, v_productos[8], 1);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23503 para pedido inexistente';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedido_inexistente)
       OR (SELECT stock FROM producto WHERE id = v_productos[8]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: pedido inexistente dejó cambios';
    END IF;
    RAISE NOTICE 'PASS: procedimiento rechaza pedido inexistente';

    -- G2. Pedido válido, producto inexistente.
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[8], v_producto_inexistente, 1);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23503 para producto inexistente';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[8])
       OR (SELECT stock FROM producto WHERE id = v_productos[8]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: producto inexistente dejó cambios';
    END IF;
    RAISE NOTICE 'PASS: procedimiento rechaza producto inexistente';

    -- G3. El trigger devuelve NEW y la FK, no la regla de actividad, rechaza.
    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[8], v_producto_inexistente, 1, 1000.00);
        RAISE EXCEPTION 'TEST FAILED: se esperaba 23503 de la FK de producto';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'fk_detalle_pedido_producto' THEN
                RAISE;
            END IF;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[8]) THEN
        RAISE EXCEPTION 'TEST FAILED: INSERT con producto inexistente dejó detalle';
    END IF;
    RAISE NOTICE 'PASS: FK conserva autoridad sobre producto inexistente';

    -- H. Precio actual y precio histórico son datos distintos.
    CALL registrar_detalle_pedido(v_pedidos[9], v_productos[9], 2);
    IF (SELECT precio_unitario FROM detalle_pedido
        WHERE pedido_id = v_pedidos[9] AND producto_id = v_productos[9]) IS DISTINCT FROM 1200.00 THEN
        RAISE EXCEPTION 'TEST FAILED: no se registró el precio inicial de la venta';
    END IF;
    UPDATE producto SET precio = 1500.00 WHERE id = v_productos[9];
    IF (SELECT precio FROM producto WHERE id = v_productos[9]) IS DISTINCT FROM 1500.00
       OR (SELECT precio_unitario FROM detalle_pedido
           WHERE pedido_id = v_pedidos[9] AND producto_id = v_productos[9]) IS DISTINCT FROM 1200.00 THEN
        RAISE EXCEPTION 'TEST FAILED: precio histórico alterado al actualizar precio actual';
    END IF;
    RAISE NOTICE 'PASS: precio_unitario preserva precio histórico';

    -- I. El error exclusivo P0099 ocurre DESPUÉS del CALL y sus verificaciones.
    -- EXCEPTION revierte los cambios del subbloque, no los datos previos.
    SELECT stock INTO v_stock FROM producto WHERE id = v_productos[10];
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[10], v_productos[10], 3);
        IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[10]) <> 1
           OR NOT EXISTS (
               SELECT 1 FROM detalle_pedido
               WHERE pedido_id = v_pedidos[10] AND producto_id = v_productos[10]
                 AND cantidad = 3 AND precio_unitario = 900.00
           )
           OR (SELECT stock FROM producto WHERE id = v_productos[10]) IS DISTINCT FROM (v_stock - 3) THEN
            RAISE EXCEPTION 'TEST FAILED: faltan cambios antes del fallo deliberado';
        END IF;
        RAISE EXCEPTION 'Fallo posterior deliberado, exclusivo del caso I'
            USING ERRCODE = 'P0099';
    EXCEPTION
        WHEN SQLSTATE 'P0099' THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[10])
       OR (SELECT stock FROM producto WHERE id = v_productos[10]) IS DISTINCT FROM v_stock THEN
        RAISE EXCEPTION 'TEST FAILED: detalle y stock no se revirtieron juntos';
    END IF;
    RAISE NOTICE 'PASS: detalle y stock revierten juntos';

    RAISE NOTICE 'PASS: batería completa de objetos programables';
END;
$pruebas$;

-- Revierte únicamente datos de prueba. Los objetos se instalaron previamente.
ROLLBACK;

-- Verificación posterior de solo lectura: ambos conteos deben ser cero.
SELECT COUNT(*) AS categorias_de_prueba_restantes
FROM categoria
WHERE nombre = '__TPI_TEST_CATEGORIA__';

SELECT COUNT(*) AS clientes_de_prueba_restantes
FROM cliente
WHERE email = 'tpi.tests@foodstore.invalid';

-- Los tres booleanos deben ser TRUE: la reversión no elimina objetos del TPI.
SELECT
    EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('fn_validar_producto_activo_detalle()')
          AND prokind = 'f' AND prorettype = 'trigger'::regtype
    ) AS funcion_instalada,
    EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('registrar_detalle_pedido(bigint,bigint,integer)')
          AND prokind = 'p'
    ) AS procedimiento_instalado,
    EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_detalle_producto_activo'
          AND tgrelid = 'detalle_pedido'::regclass
          AND tgfoid = to_regprocedure('fn_validar_producto_activo_detalle()')
          AND NOT tgisinternal AND tgenabled IN ('O', 'A')
    ) AS trigger_instalado_y_habilitado;
