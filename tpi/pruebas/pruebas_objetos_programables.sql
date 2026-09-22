-- TPI Food Store — Batería del modelo oficial; PostgreSQL 17.
-- VALIDACIÓN ESTÁTICA: este archivo todavía no acredita ejecución ni PASS reales.
-- Ejecución futura: psql -X -w -d foodstore_tpi_oficial -v ON_ERROR_STOP=1 -f este_archivo.sql
-- Instalar antes schema, seed y objetos programables; no envolver con -1.
-- Usar el mismo search_path de instalación, sin otras escrituras en el laboratorio.
-- 29 grupos / 37 variantes: A–Z, MAIL_UNIQUE, TOTAL_CERO y ATOMICIDAD.
-- B tiene 3 variantes; D/E/F/G/H/J tienen 2; el resto tiene 1.
-- Los subpasos de mantenimiento y sus aserciones no inflan ese conteo.
-- CONCURRENCY_MULTISESSION: NOT_TESTED_HERE. Dos conexiones se probarán después.
-- CALL registra ventas y descuenta stock. DML directo del detalle no administra
-- inventario; bajas, reactivaciones y borrados no inventan reposición de stock.
-- La baja posterior de entidades padre no debe destruir historia existente.
-- Los fixtures se revierten; las secuencias IDENTITY pueden conservar huecos.
-- Ante un error inesperado, ON_ERROR_STOP y el cierre de la conexión evitan
-- continuar la batería y revierten su transacción pendiente.

BEGIN;

DO LANGUAGE plpgsql $pruebas$
DECLARE
    v_categoria_id BIGINT;
    v_usuario_id BIGINT;
    v_usuario_baja_id BIGINT;
    v_producto_id BIGINT;
    v_pedido_id BIGINT;
    v_detalle_id BIGINT;
    v_productos BIGINT[] := ARRAY[]::BIGINT[];
    v_pedidos BIGINT[] := ARRAY[]::BIGINT[];
    v_caso RECORD;
    v_cantidad INTEGER;
    v_ruta INTEGER;
    v_limite NUMERIC;
    v_pedido_inexistente BIGINT;
    v_producto_inexistente BIGINT;
    v_restriccion TEXT;
    v_stock INTEGER;
    v_total NUMERIC(12,2);
BEGIN
    -- Guardas antes de crear fixtures. Los tipos de DECLARE no requieren tablas.
    IF current_database() IS DISTINCT FROM 'foodstore_tpi_oficial' THEN
        RAISE EXCEPTION 'TEST FAILED: ejecutar únicamente en foodstore_tpi_oficial';
    END IF;
    IF current_setting('session_replication_role') IS DISTINCT FROM 'origin' THEN
        RAISE EXCEPTION 'TEST FAILED: se requiere session_replication_role = origin';
    END IF;
    FOR v_caso IN SELECT unnest(ARRAY['usuario','categoria','producto','pedido','detalle_pedido']) AS tabla LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = to_regclass(v_caso.tabla) AND relkind = 'r') THEN
            RAISE EXCEPTION 'TEST FAILED: falta tabla base %', v_caso.tabla;
        END IF;
    END LOOP;
    FOR v_caso IN SELECT * FROM (VALUES
        ('usuario','mail'), ('usuario','eliminado'),
        ('producto','stock'), ('producto','disponible'), ('producto','eliminado'),
        ('pedido','usuario_id'), ('pedido','total'), ('pedido','eliminado'),
        ('detalle_pedido','id'), ('detalle_pedido','subtotal'), ('detalle_pedido','eliminado')
    ) AS columnas(tabla, columna) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass(v_caso.tabla)
              AND attname = v_caso.columna AND attnum > 0 AND NOT attisdropped
        ) THEN
            RAISE EXCEPTION 'TEST FAILED: falta columna %.%', v_caso.tabla, v_caso.columna;
        END IF;
    END LOOP;
    FOR v_caso IN SELECT * FROM (VALUES
        ('producto','fk_producto_categoria','f'), ('pedido','fk_pedido_usuario','f'),
        ('detalle_pedido','fk_detalle_pedido_pedido','f'), ('detalle_pedido','fk_detalle_pedido_producto','f'),
        ('detalle_pedido','uq_detalle_pedido_pedido_producto','u'),
        ('producto','chk_producto_precio','c'), ('producto','chk_producto_stock','c'),
        ('pedido','chk_pedido_total','c'), ('detalle_pedido','chk_detalle_pedido_cantidad','c'),
        ('detalle_pedido','chk_detalle_pedido_precio_unitario','c'),
        ('detalle_pedido','chk_detalle_pedido_subtotal','c')
    ) AS restricciones(tabla, nombre, tipo) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass(v_caso.tabla)
              AND conname = v_caso.nombre AND contype::TEXT = v_caso.tipo AND convalidated
        ) THEN
            RAISE EXCEPTION 'TEST FAILED: falta restricción válida %.%', v_caso.tabla, v_caso.nombre;
        END IF;
    END LOOP;
    FOR v_caso IN SELECT * FROM (VALUES
            ('calcular_total_pedido(bigint)', 'f', 'numeric'),
            ('fn_set_subtotal()', 'f', 'trigger'),
            ('fn_validar_detalle_vigente()', 'f', 'trigger'),
            ('fn_recalcular_total_insert()', 'f', 'trigger'),
            ('fn_recalcular_total_update()', 'f', 'trigger'),
            ('fn_recalcular_total_delete()', 'f', 'trigger'),
            ('registrar_detalle_pedido(bigint,bigint,integer)', 'p', 'void')
    ) AS rutinas(firma, clase, retorno) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc WHERE oid = to_regprocedure(v_caso.firma)
              AND prokind::TEXT = v_caso.clase AND prorettype = to_regtype(v_caso.retorno)
        ) THEN
            RAISE EXCEPTION 'TEST FAILED: falta rutina con tipo correcto %', v_caso.firma;
        END IF;
    END LOOP;
    FOR v_caso IN SELECT * FROM (VALUES
            ('trg_subtotal', 'fn_set_subtotal()', 23, NULL, NULL),
            ('trg_detalle_vigente', 'fn_validar_detalle_vigente()', 23, NULL, NULL),
            ('trg_total_detalle_insert', 'fn_recalcular_total_insert()', 4, NULL, 'nuevos'),
            ('trg_total_detalle_update', 'fn_recalcular_total_update()', 16, 'anteriores', 'nuevos'),
            ('trg_total_detalle_delete', 'fn_recalcular_total_delete()', 8, 'anteriores', NULL)
    ) AS disparadores(nombre, funcion, eventos, anterior, nueva) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger WHERE tgrelid = 'detalle_pedido'::regclass
              AND tgname = v_caso.nombre AND tgfoid = to_regprocedure(v_caso.funcion)
              AND NOT tgisinternal AND tgenabled IN ('O','A') AND tgtype = v_caso.eventos
              AND tgoldtable::TEXT IS NOT DISTINCT FROM v_caso.anterior
              AND tgnewtable::TEXT IS NOT DISTINCT FROM v_caso.nueva
        ) THEN
            RAISE EXCEPTION 'TEST FAILED: trigger ausente, deshabilitado o mal vinculado %', v_caso.nombre;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM categoria WHERE nombre = '__TPI_TEST_CATEGORIA__')
       OR EXISTS (SELECT 1 FROM usuario WHERE mail IN ('tpi.tests@foodstore.invalid','tpi.tests.baja@foodstore.invalid'))
       OR EXISTS (SELECT 1 FROM producto WHERE left(nombre, 6) = '__TPI_') THEN
        RAISE EXCEPTION 'TEST FAILED: los nombres reservados de fixtures ya están ocupados';
    END IF;

    INSERT INTO categoria (nombre) VALUES ('__TPI_TEST_CATEGORIA__') RETURNING id INTO v_categoria_id;
    INSERT INTO usuario (nombre, apellido, mail, contrasena, rol, eliminado)
    VALUES ('TPI','Tests','tpi.tests@foodstore.invalid','SEED_NO_AUTH','USUARIO',FALSE)
    RETURNING id INTO v_usuario_id;
    INSERT INTO usuario (nombre, apellido, mail, contrasena, rol, eliminado)
    VALUES ('TPI','Tests baja','tpi.tests.baja@foodstore.invalid','SEED_NO_AUTH','USUARIO',FALSE)
    RETURNING id INTO v_usuario_baja_id;

    -- Posiciones de escenarios, nunca IDs hardcodeados. Cada grupo dispone de
    -- producto/pedido propios; las posiciones 29–33 son destinos o líneas extras.
    FOR v_caso IN SELECT * FROM (VALUES
        (1, '__TPI_A_VALIDO__', 1000.00, 10, TRUE, FALSE),
        (2, '__TPI_B_CANTIDAD__', 1000.00, 10, TRUE, FALSE),
        (3, '__TPI_C_STOCK__', 500.00, 2, TRUE, FALSE),
        (4, '__TPI_D_ELIMINADO__', 750.00, 10, TRUE, TRUE),
        (5, '__TPI_E_NO_DISPONIBLE__', 750.00, 10, FALSE, FALSE),
        (6, '__TPI_F_PEDIDO_BAJA__', 600.00, 10, TRUE, FALSE),
        (7, '__TPI_G_USUARIO_BAJA__', 600.00, 10, TRUE, FALSE),
        (8, '__TPI_H_DUPLICADO__', 1000.00, 10, TRUE, FALSE),
        (9, '__TPI_I_PEDIDO_AUSENTE__', 1000.00, 10, TRUE, FALSE),
        (10, '__TPI_J_PRODUCTO_AUSENTE__', 1000.00, 10, TRUE, FALSE),
        (11, '__TPI_K_FK_PEDIDO__', 1000.00, 10, TRUE, FALSE),
        (12, '__TPI_L_PRECIO_NULL__', 1200.00, 10, TRUE, FALSE),
        (13, '__TPI_M_HISTORICO__', 1200.00, 10, TRUE, FALSE),
        (14, '__TPI_N_CANTIDAD__', 500.00, 10, TRUE, FALSE),
        (15, '__TPI_O_PRECIO__', 500.00, 10, TRUE, FALSE),
        (16, '__TPI_P_SUBTOTAL__', 500.00, 10, TRUE, FALSE),
        (17, '__TPI_Q_PRODUCTO__', 1000.00, 10, TRUE, FALSE),
        (18, '__TPI_R_PRECIO_ESPECIAL__', 1000.00, 10, TRUE, FALSE),
        (19, '__TPI_S_BAJA_DETALLE__', 500.00, 10, TRUE, FALSE),
        (20, '__TPI_T_DELETE__', 500.00, 10, TRUE, FALSE),
        (21, '__TPI_U_MOVER__', 500.00, 10, TRUE, FALSE),
        (22, '__TPI_V_MASIVO__', 100.00, 10, TRUE, FALSE),
        (23, '__TPI_W_FUNCION__', 500.00, 10, TRUE, FALSE),
        (24, '__TPI_X_CHECK_CANTIDAD__', 500.00, 10, TRUE, FALSE),
        (25, '__TPI_Y_CHECK_STOCK__', 500.00, 10, TRUE, FALSE),
        (26, '__TPI_Z_CHECK_TOTAL__', 500.00, 10, TRUE, FALSE),
        (27, '__TPI_TOTAL_CERO__', 500.00, 10, TRUE, FALSE),
        (28, '__TPI_ATOMICIDAD__', 900.00, 10, TRUE, FALSE),
        (29, '__TPI_Q_DESTINO__', 1800.00, 10, TRUE, FALSE),
        (30, '__TPI_R_DESTINO__', 1800.00, 10, TRUE, FALSE),
        (31, '__TPI_S_SEGUNDO__', 700.00, 10, TRUE, FALSE),
        (32, '__TPI_V_SEGUNDO__', 200.00, 10, TRUE, FALSE),
        (33, '__TPI_V_TERCERO__', 300.00, 10, TRUE, FALSE)
    ) AS escenarios(posicion, nombre, precio, stock, disponible, eliminado) ORDER BY posicion LOOP
        INSERT INTO producto (categoria_id, nombre, precio, stock, disponible, eliminado)
        VALUES (v_categoria_id, v_caso.nombre, v_caso.precio, v_caso.stock, v_caso.disponible, v_caso.eliminado)
        RETURNING id INTO v_producto_id;
        v_productos[v_caso.posicion] := v_producto_id;
        INSERT INTO pedido (usuario_id, forma_pago, estado, eliminado)
        VALUES (CASE WHEN v_caso.posicion = 7 THEN v_usuario_baja_id ELSE v_usuario_id END,
                'EFECTIVO', 'PENDIENTE', FALSE)
        RETURNING id INTO v_pedido_id;
        v_pedidos[v_caso.posicion] := v_pedido_id;
    END LOOP;
    INSERT INTO pedido (usuario_id, forma_pago)
    VALUES (v_usuario_id, 'EFECTIVO') RETURNING id INTO v_pedido_id;
    v_pedidos[34] := v_pedido_id; -- Destino inicialmente vacío para U.
    UPDATE pedido SET eliminado = TRUE WHERE id = v_pedidos[6];
    UPDATE usuario SET eliminado = TRUE WHERE id = v_usuario_baja_id;

    -- Referencias inexistentes calculadas después de crear todos los fixtures.
    -- NUMERIC evita desbordar antes de comprobar el límite BIGINT.
    SELECT COALESCE(MAX(id)::NUMERIC, 0) + 1 INTO v_limite FROM pedido;
    IF v_limite > 9223372036854775807::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: no hay margen BIGINT para referencia de pedido';
    END IF;
    v_pedido_inexistente := v_limite::BIGINT;
    SELECT COALESCE(MAX(id)::NUMERIC, 0) + 1 INTO v_limite FROM producto;
    IF v_limite > 9223372036854775807::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: no hay margen BIGINT para referencia de producto';
    END IF;
    v_producto_inexistente := v_limite::BIGINT;
    IF EXISTS (SELECT 1 FROM pedido WHERE id = v_pedido_inexistente)
       OR EXISTS (SELECT 1 FROM producto WHERE id = v_producto_inexistente) THEN
        RAISE EXCEPTION 'TEST FAILED: las referencias ausentes deben ser inexistentes';
    END IF;

    -- A. CALL válido: el identificador de detalle lo genera el modelo.
    CALL registrar_detalle_pedido(v_pedidos[1], v_productos[1], 3);

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[1]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[1]
           AND producto_id = v_productos[1] AND cantidad = 3
           AND precio_unitario = 1000 AND subtotal = 3 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[1]) IS DISTINCT FROM 3000
       OR (SELECT stock FROM producto WHERE id = v_productos[1]) IS DISTINCT FROM 7 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 1';
    END IF;

    RAISE NOTICE 'PASS: CALL válido mantiene detalle, subtotal, total y stock';

    -- B. Tres variantes, cada una rechazada y comprobada por separado.
    FOREACH v_cantidad IN ARRAY ARRAY[0, -1, NULL]::INTEGER[] LOOP

        BEGIN
            CALL registrar_detalle_pedido(v_pedidos[2], v_productos[2], v_cantidad);
            RAISE EXCEPTION 'TEST FAILED: cantidad inválida; se esperaba 22023';
        EXCEPTION
            WHEN SQLSTATE '22023' THEN NULL;
        END;

        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[2])
           OR (SELECT stock FROM producto WHERE id = v_productos[2]) IS DISTINCT FROM 10
           OR (SELECT total FROM pedido WHERE id = v_pedidos[2]) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'TEST FAILED: el escenario 2 dejó efectos parciales';
        END IF;

    END LOOP;

    RAISE NOTICE 'PASS: cantidades 0, -1 y NULL rechazadas sin efectos';

    -- C. Regla de stock, no el CHECK de la tabla.

    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[3], v_productos[3], 3);
        RAISE EXCEPTION 'TEST FAILED: stock insuficiente; se esperaba 23514';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[3])
       OR (SELECT stock FROM producto WHERE id = v_productos[3]) IS DISTINCT FROM 2
       OR (SELECT total FROM pedido WHERE id = v_pedidos[3]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 3 dejó efectos parciales';
    END IF;

    RAISE NOTICE 'PASS: stock insuficiente rechazado sin efectos';

    -- D. producto eliminado: CALL y DML directo son variantes independientes.
    FOR v_ruta IN 1..2 LOOP

        BEGIN
            IF v_ruta = 1 THEN
                CALL registrar_detalle_pedido(v_pedidos[4], v_productos[4], 1);
            ELSE
                INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
                VALUES (v_pedidos[4], v_productos[4], 1, 600.00);
            END IF;
            RAISE EXCEPTION 'TEST FAILED: producto eliminado; se esperaba 23514';
        EXCEPTION
            WHEN SQLSTATE '23514' THEN NULL;
        END;

        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[4])
           OR (SELECT stock FROM producto WHERE id = v_productos[4]) IS DISTINCT FROM 10
           OR (SELECT total FROM pedido WHERE id = v_pedidos[4]) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'TEST FAILED: el escenario 4 dejó efectos parciales';
        END IF;

    END LOOP;

    RAISE NOTICE 'PASS: producto eliminado rechazado por ambas rutas sin efectos';

    -- E. producto no disponible: CALL y DML directo son variantes independientes.
    FOR v_ruta IN 1..2 LOOP

        BEGIN
            IF v_ruta = 1 THEN
                CALL registrar_detalle_pedido(v_pedidos[5], v_productos[5], 1);
            ELSE
                INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
                VALUES (v_pedidos[5], v_productos[5], 1, 600.00);
            END IF;
            RAISE EXCEPTION 'TEST FAILED: producto no disponible; se esperaba 23514';
        EXCEPTION
            WHEN SQLSTATE '23514' THEN NULL;
        END;

        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[5])
           OR (SELECT stock FROM producto WHERE id = v_productos[5]) IS DISTINCT FROM 10
           OR (SELECT total FROM pedido WHERE id = v_pedidos[5]) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'TEST FAILED: el escenario 5 dejó efectos parciales';
        END IF;

    END LOOP;

    RAISE NOTICE 'PASS: producto no disponible rechazado por ambas rutas sin efectos';

    -- F. pedido eliminado: CALL y DML directo son variantes independientes.
    FOR v_ruta IN 1..2 LOOP

        BEGIN
            IF v_ruta = 1 THEN
                CALL registrar_detalle_pedido(v_pedidos[6], v_productos[6], 1);
            ELSE
                INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
                VALUES (v_pedidos[6], v_productos[6], 1, 600.00);
            END IF;
            RAISE EXCEPTION 'TEST FAILED: pedido eliminado; se esperaba 23514';
        EXCEPTION
            WHEN SQLSTATE '23514' THEN NULL;
        END;

        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[6])
           OR (SELECT stock FROM producto WHERE id = v_productos[6]) IS DISTINCT FROM 10
           OR (SELECT total FROM pedido WHERE id = v_pedidos[6]) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'TEST FAILED: el escenario 6 dejó efectos parciales';
        END IF;

    END LOOP;

    RAISE NOTICE 'PASS: pedido eliminado rechazado por ambas rutas sin efectos';

    -- G. usuario eliminado: CALL y DML directo son variantes independientes.
    FOR v_ruta IN 1..2 LOOP

        BEGIN
            IF v_ruta = 1 THEN
                CALL registrar_detalle_pedido(v_pedidos[7], v_productos[7], 1);
            ELSE
                INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
                VALUES (v_pedidos[7], v_productos[7], 1, 600.00);
            END IF;
            RAISE EXCEPTION 'TEST FAILED: usuario eliminado; se esperaba 23514';
        EXCEPTION
            WHEN SQLSTATE '23514' THEN NULL;
        END;

        IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[7])
           OR (SELECT stock FROM producto WHERE id = v_productos[7]) IS DISTINCT FROM 10
           OR (SELECT total FROM pedido WHERE id = v_pedidos[7]) IS DISTINCT FROM 0 THEN
            RAISE EXCEPTION 'TEST FAILED: el escenario 7 dejó efectos parciales';
        END IF;

    END LOOP;

    RAISE NOTICE 'PASS: usuario eliminado rechazado por ambas rutas sin efectos';

    -- H. El par sigue siendo único, independientemente de la identidad del detalle.
    CALL registrar_detalle_pedido(v_pedidos[8], v_productos[8], 2);

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[8]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[8]
           AND producto_id = v_productos[8] AND cantidad = 2
           AND precio_unitario = 1000 AND subtotal = 2 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[8]) IS DISTINCT FROM 2000
       OR (SELECT stock FROM producto WHERE id = v_productos[8]) IS DISTINCT FROM 8 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 8';
    END IF;

    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[8], v_productos[8], 1);
        RAISE EXCEPTION 'TEST FAILED: CALL duplicado; se esperaba 23505';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN NULL;
    END;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[8]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[8]
           AND producto_id = v_productos[8] AND cantidad = 2
           AND precio_unitario = 1000 AND subtotal = 2 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[8]) IS DISTINCT FROM 2000
       OR (SELECT stock FROM producto WHERE id = v_productos[8]) IS DISTINCT FROM 8 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 8';
    END IF;

    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[8], v_productos[8], 1, 1000.00);
        RAISE EXCEPTION 'TEST FAILED: INSERT duplicado; se esperaba 23505';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'uq_detalle_pedido_pedido_producto' THEN
                RAISE;
            END IF;
    END;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[8]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[8]
           AND producto_id = v_productos[8] AND cantidad = 2
           AND precio_unitario = 1000 AND subtotal = 2 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[8]) IS DISTINCT FROM 2000
       OR (SELECT stock FROM producto WHERE id = v_productos[8]) IS DISTINCT FROM 8 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 8';
    END IF;

    RAISE NOTICE 'PASS: duplicados CALL y directo no alteran línea, total ni stock';

    -- I. Pedido inexistente: producto válido y sin efectos.

    BEGIN
        CALL registrar_detalle_pedido(v_pedido_inexistente, v_productos[9], 1);
        RAISE EXCEPTION 'TEST FAILED: pedido inexistente; se esperaba 23503';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN NULL;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[9])
       OR (SELECT stock FROM producto WHERE id = v_productos[9]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[9]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 9 dejó efectos parciales';
    END IF;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedido_inexistente) THEN
        RAISE EXCEPTION 'TEST FAILED: pedido inexistente dejó detalle';
    END IF;

    RAISE NOTICE 'PASS: pedido inexistente rechazado';

    -- J. Precio explícito en DML directo: se aísla la FK sin enmascararla por NOT NULL.

    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[10], v_producto_inexistente, 1);
        RAISE EXCEPTION 'TEST FAILED: producto inexistente CALL; se esperaba 23503';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN NULL;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[10])
       OR (SELECT stock FROM producto WHERE id = v_productos[10]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[10]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 10 dejó efectos parciales';
    END IF;

    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[10], v_producto_inexistente, 1, 1000.00);
        RAISE EXCEPTION 'TEST FAILED: producto inexistente directo; se esperaba 23503';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'fk_detalle_pedido_producto' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[10])
       OR (SELECT stock FROM producto WHERE id = v_productos[10]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[10]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 10 dejó efectos parciales';
    END IF;

    RAISE NOTICE 'PASS: producto inexistente rechazado; FK identificada en ruta directa';

    -- K. FK de pedido aislada con cantidad, producto y precio válidos.

    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedido_inexistente, v_productos[11], 1, 1000.00);
        RAISE EXCEPTION 'TEST FAILED: FK de pedido; se esperaba 23503';
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'fk_detalle_pedido_pedido' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[11])
       OR (SELECT stock FROM producto WHERE id = v_productos[11]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[11]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 11 dejó efectos parciales';
    END IF;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedido_inexistente) THEN
        RAISE EXCEPTION 'TEST FAILED: FK de pedido dejó una fila';
    END IF;

    RAISE NOTICE 'PASS: FK de pedido conserva autoridad estructural';

    -- L. BEFORE completa precio NULL; DML directo no descuenta stock.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[12], v_productos[12], 2, NULL)
    RETURNING id INTO v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[12]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[12]
           AND producto_id = v_productos[12] AND cantidad = 2
           AND precio_unitario = 1200 AND subtotal = 2 * 1200 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[12]) IS DISTINCT FROM 2400
       OR (SELECT stock FROM producto WHERE id = v_productos[12]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 12';
    END IF;

    RAISE NOTICE 'PASS: precio NULL completado y stock intacto en INSERT directo';

    -- M. El precio explícito histórico no sigue modificaciones del catálogo.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[13], v_productos[13], 2, 1000)
    RETURNING id INTO v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[13]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[13]
           AND producto_id = v_productos[13] AND cantidad = 2
           AND precio_unitario = 1000 AND subtotal = 2 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[13]) IS DISTINCT FROM 2000
       OR (SELECT stock FROM producto WHERE id = v_productos[13]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 13';
    END IF;

    UPDATE producto SET precio = 1500.00 WHERE id = v_productos[13];

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[13]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[13]
           AND producto_id = v_productos[13] AND cantidad = 2
           AND precio_unitario = 1000 AND subtotal = 2 * 1000 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[13]) IS DISTINCT FROM 2000
       OR (SELECT stock FROM producto WHERE id = v_productos[13]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 13';
    END IF;

    IF (SELECT precio FROM producto WHERE id = v_productos[13]) IS DISTINCT FROM 1500 THEN
        RAISE EXCEPTION 'TEST FAILED: M no actualizó catálogo';
    END IF;

    RAISE NOTICE 'PASS: precio explícito histórico preservado frente al catálogo';

    -- N. Cantidad modifica el derivado y no el precio histórico.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[14], v_productos[14], 2, 500)
    RETURNING id INTO v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[14]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[14]
           AND producto_id = v_productos[14] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[14]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[14]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 14';
    END IF;

    UPDATE detalle_pedido SET cantidad = 3 WHERE id = v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[14]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[14]
           AND producto_id = v_productos[14] AND cantidad = 3
           AND precio_unitario = 500 AND subtotal = 3 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[14]) IS DISTINCT FROM 1500
       OR (SELECT stock FROM producto WHERE id = v_productos[14]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 14';
    END IF;

    RAISE NOTICE 'PASS: UPDATE cantidad mantiene precio y recalcula derivados';

    -- O. Precio explícito nuevo se acepta y propaga al total.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[15], v_productos[15], 2, 500)
    RETURNING id INTO v_detalle_id;

    UPDATE detalle_pedido SET precio_unitario = 700.00 WHERE id = v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[15]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[15]
           AND producto_id = v_productos[15] AND cantidad = 2
           AND precio_unitario = 700 AND subtotal = 2 * 700 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[15]) IS DISTINCT FROM 1400
       OR (SELECT stock FROM producto WHERE id = v_productos[15]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 15';
    END IF;

    RAISE NOTICE 'PASS: UPDATE precio_unitario recalcula subtotal y total';

    -- P. Una manipulación del derivado no puede persistir.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[16], v_productos[16], 2, 500)
    RETURNING id INTO v_detalle_id;

    UPDATE detalle_pedido SET subtotal = 999999.00 WHERE id = v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[16]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[16]
           AND producto_id = v_productos[16] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[16]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[16]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 16';
    END IF;

    RAISE NOTICE 'PASS: DIRECT_SUBTOTAL_TAMPERING_PROTECTED = YES';

    -- Q. Cambiar producto sin cambiar precio adopta catálogo del destino.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[17], v_productos[17], 2, 1000)
    RETURNING id INTO v_detalle_id;

    UPDATE detalle_pedido SET producto_id = v_productos[29] WHERE id = v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[17]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[17]
           AND producto_id = v_productos[29] AND cantidad = 2
           AND precio_unitario = 1800 AND subtotal = 2 * 1800 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[17]) IS DISTINCT FROM 3600
       OR (SELECT stock FROM producto WHERE id = v_productos[29]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 17';
    END IF;

    IF (SELECT stock FROM producto WHERE id = v_productos[17]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: Q modificó stock del origen';
    END IF;

    RAISE NOTICE 'PASS: cambio de producto deriva precio nuevo sin reconciliar stock';

    -- R. Precio especial distinto de OLD se conserva al cambiar producto.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[18], v_productos[18], 2, 1000)
    RETURNING id INTO v_detalle_id;

    UPDATE detalle_pedido SET producto_id = v_productos[30], precio_unitario = 900.00 WHERE id = v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[18]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[18]
           AND producto_id = v_productos[30] AND cantidad = 2
           AND precio_unitario = 900 AND subtotal = 2 * 900 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[18]) IS DISTINCT FROM 1800
       OR (SELECT stock FROM producto WHERE id = v_productos[30]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 18';
    END IF;

    IF (SELECT stock FROM producto WHERE id = v_productos[18]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: R modificó stock del origen';
    END IF;

    RAISE NOTICE 'PASS: cambio de producto conserva precio especial explícito';

    -- S. Baja y reactivación cambian total; no implican política de inventario.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[19], v_productos[19], 2, 500)
    RETURNING id INTO v_detalle_id;

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[19], v_productos[31], 1, 700)
    RETURNING id INTO v_detalle_id;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[19]) IS DISTINCT FROM 1700 THEN
        RAISE EXCEPTION 'TEST FAILED: S total inicial';
    END IF;

    UPDATE detalle_pedido SET eliminado = TRUE WHERE id = v_detalle_id;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[19]) IS DISTINCT FROM 1000
       OR (SELECT eliminado FROM detalle_pedido WHERE id = v_detalle_id) IS DISTINCT FROM TRUE
       OR (SELECT stock FROM producto WHERE id = v_productos[19]) IS DISTINCT FROM 10
       OR (SELECT stock FROM producto WHERE id = v_productos[31]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: S baja lógica o stock';
    END IF;

    UPDATE detalle_pedido SET eliminado = FALSE WHERE id = v_detalle_id;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[19]) IS DISTINCT FROM 1700
       OR (SELECT eliminado FROM detalle_pedido WHERE id = v_detalle_id) IS DISTINCT FROM FALSE
       OR (SELECT stock FROM producto WHERE id = v_productos[19]) IS DISTINCT FROM 10
       OR (SELECT stock FROM producto WHERE id = v_productos[31]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: S reactivación o stock';
    END IF;

    RAISE NOTICE 'PASS: baja y reactivación del detalle mantienen total sin administrar stock';

    -- T. CALL descontó stock; DELETE no lo repone. Es un límite documentado.
    CALL registrar_detalle_pedido(v_pedidos[20], v_productos[20], 2);

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[20]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[20]
           AND producto_id = v_productos[20] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[20]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[20]) IS DISTINCT FROM 8 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 20';
    END IF;

    SELECT id INTO v_detalle_id FROM detalle_pedido WHERE pedido_id = v_pedidos[20];
    SELECT stock INTO v_stock FROM producto WHERE id = v_productos[20];
    DELETE FROM detalle_pedido WHERE id = v_detalle_id;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[20])
       OR (SELECT stock FROM producto WHERE id = v_productos[20]) IS DISTINCT FROM v_stock
       OR (SELECT total FROM pedido WHERE id = v_pedidos[20]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 20 dejó efectos parciales';
    END IF;

    RAISE NOTICE 'PASS: DELETE físico recalcula total sin reponer stock';

    -- U. OLD TABLE y NEW TABLE deben recalcular origen y destino.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[21], v_productos[21], 2, 500)
    RETURNING id INTO v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[21]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[21]
           AND producto_id = v_productos[21] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[21]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[21]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 21';
    END IF;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[34]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: U destino no estaba vacío';
    END IF;

    UPDATE detalle_pedido SET pedido_id = v_pedidos[34] WHERE id = v_detalle_id;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[21]) IS DISTINCT FROM 0
       OR EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[21]) THEN
        RAISE EXCEPTION 'TEST FAILED: U origen no se recalculó';
    END IF;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[34]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[34]
           AND producto_id = v_productos[21] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[34]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[21]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 34';
    END IF;

    RAISE NOTICE 'PASS: movimiento recalcula ambos pedidos sin administrar stock';

    -- V. Una sola sentencia por fase: INSERT, baja masiva, reactivación masiva.
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[22], v_productos[22], 1, 100.00),
           (v_pedidos[22], v_productos[32], 2, 200.00),
           (v_pedidos[22], v_productos[33], 3, 300.00);

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[22]) <> 3
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[22] AND cantidad = 1 AND precio_unitario = 100 AND subtotal = 100)
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[32] AND cantidad = 2 AND precio_unitario = 200 AND subtotal = 400)
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[33] AND cantidad = 3 AND precio_unitario = 300 AND subtotal = 900)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[22]) IS DISTINCT FROM 1400 THEN
        RAISE EXCEPTION 'TEST FAILED: V INSERT masivo';
    END IF;

    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = v_pedidos[22];

    IF (SELECT total FROM pedido WHERE id = v_pedidos[22]) IS DISTINCT FROM 0
       OR (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND eliminado) <> 3 THEN
        RAISE EXCEPTION 'TEST FAILED: V baja masiva';
    END IF;

    UPDATE detalle_pedido SET eliminado = FALSE WHERE pedido_id = v_pedidos[22];

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[22]) <> 3
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[22] AND cantidad = 1 AND precio_unitario = 100 AND subtotal = 100)
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[32] AND cantidad = 2 AND precio_unitario = 200 AND subtotal = 400)
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND producto_id = v_productos[33] AND cantidad = 3 AND precio_unitario = 300 AND subtotal = 900)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[22]) IS DISTINCT FROM 1400
       OR EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[22] AND eliminado)
       OR EXISTS (SELECT 1 FROM producto WHERE id IN (v_productos[22], v_productos[32], v_productos[33]) AND stock <> 10) THEN
        RAISE EXCEPTION 'TEST FAILED: V reactivación masiva o stock';
    END IF;

    RAISE NOTICE 'PASS: operaciones masivas mantienen tres subtotales y total por sentencia';

    -- W. Contrato real del agregador, incluso para un ID inexistente.

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[23], v_productos[23], 2, 500)
    RETURNING id INTO v_detalle_id;

    IF calcular_total_pedido(v_pedidos[23]) IS DISTINCT FROM 1000
       OR calcular_total_pedido(v_pedidos[23]) IS DISTINCT FROM (SELECT total FROM pedido WHERE id = v_pedidos[23])
       OR calcular_total_pedido(v_pedidos[24]) IS DISTINCT FROM 0
       OR calcular_total_pedido(v_pedido_inexistente) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: W agregador';
    END IF;

    RAISE NOTICE 'PASS: calcular_total_pedido coincide con total y devuelve cero sin líneas';

    -- X. Cantidad cero produce subtotal cero: no interfiere el CHECK de subtotal.

    BEGIN
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
        VALUES (v_pedidos[24], v_productos[24], 0, 500.00);
        RAISE EXCEPTION 'TEST FAILED: CHECK cantidad; se esperaba 23514';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'chk_detalle_pedido_cantidad' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[24])
       OR (SELECT stock FROM producto WHERE id = v_productos[24]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[24]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 24 dejó efectos parciales';
    END IF;

    RAISE NOTICE 'PASS: CHECK cantidad aislado';

    -- Y. Ruta directa para aislar el CHECK, no la validación del procedimiento.

    BEGIN
        UPDATE producto SET stock = -1 WHERE id = v_productos[25];
        RAISE EXCEPTION 'TEST FAILED: CHECK stock; se esperaba 23514';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'chk_producto_stock' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[25])
       OR (SELECT stock FROM producto WHERE id = v_productos[25]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[25]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 25 dejó efectos parciales';
    END IF;

    RAISE NOTICE 'PASS: CHECK stock aislado';

    -- Z. CHECK del agregado físico, preservando su valor anterior.
    SELECT total INTO v_total FROM pedido WHERE id = v_pedidos[26];

    BEGIN
        UPDATE pedido SET total = -1 WHERE id = v_pedidos[26];
        RAISE EXCEPTION 'TEST FAILED: CHECK total; se esperaba 23514';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
            IF v_restriccion IS DISTINCT FROM 'chk_pedido_total' THEN
                RAISE;
            END IF;
    END;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[26]) IS DISTINCT FROM v_total THEN
        RAISE EXCEPTION 'TEST FAILED: Z alteró total';
    END IF;

    RAISE NOTICE 'PASS: CHECK total aislado';

    -- MAIL_UNIQUE. Resto de atributos válido: solo se duplica mail.

    BEGIN
        INSERT INTO usuario (nombre, apellido, mail, contrasena)
        VALUES ('TPI', 'Duplicado', 'tpi.tests@foodstore.invalid', 'SEED_NO_AUTH');
        RAISE EXCEPTION 'TEST FAILED: mail duplicado; se esperaba 23505';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN NULL;
    END;

    IF (SELECT COUNT(*) FROM usuario WHERE mail = 'tpi.tests@foodstore.invalid') <> 1
       OR NOT EXISTS (SELECT 1 FROM usuario WHERE id = v_usuario_id AND nombre = 'TPI' AND apellido = 'Tests' AND eliminado = FALSE) THEN
        RAISE EXCEPTION 'TEST FAILED: mail duplicado alteró el usuario original';
    END IF;

    RAISE NOTICE 'PASS: UNIQUE usuario.mail rechaza duplicado';

    -- TOTAL_CERO. Pedido vacío, alta y exclusión de la única línea.

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[27])
       OR (SELECT stock FROM producto WHERE id = v_productos[27]) IS DISTINCT FROM 10
       OR (SELECT total FROM pedido WHERE id = v_pedidos[27]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: el escenario 27 dejó efectos parciales';
    END IF;

    IF calcular_total_pedido(v_pedidos[27]) IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: TOTAL_CERO inicial';
    END IF;

    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (v_pedidos[27], v_productos[27], 2, 500)
    RETURNING id INTO v_detalle_id;

    IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[27]) <> 1
       OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[27]
           AND producto_id = v_productos[27] AND cantidad = 2
           AND precio_unitario = 500 AND subtotal = 2 * 500 AND eliminado = FALSE)
       OR (SELECT total FROM pedido WHERE id = v_pedidos[27]) IS DISTINCT FROM 1000
       OR (SELECT stock FROM producto WHERE id = v_productos[27]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 27';
    END IF;

    UPDATE detalle_pedido SET eliminado = TRUE WHERE id = v_detalle_id;

    IF (SELECT total FROM pedido WHERE id = v_pedidos[27]) IS DISTINCT FROM 0
       OR calcular_total_pedido(v_pedidos[27]) IS DISTINCT FROM 0
       OR (SELECT eliminado FROM detalle_pedido WHERE id = v_detalle_id) IS DISTINCT FROM TRUE
       OR (SELECT stock FROM producto WHERE id = v_productos[27]) IS DISTINCT FROM 10 THEN
        RAISE EXCEPTION 'TEST FAILED: TOTAL_CERO tras baja';
    END IF;

    RAISE NOTICE 'PASS: total cero antes del alta y después de excluir la única línea';

    -- ATOMICIDAD. P0099 pertenece exclusivamente a este test.
    SELECT stock INTO v_stock FROM producto WHERE id = v_productos[28];
    SELECT total INTO v_total FROM pedido WHERE id = v_pedidos[28];
    IF v_stock IS DISTINCT FROM 10 OR v_total IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TEST FAILED: preparación de atomicidad';
    END IF;
    BEGIN
        CALL registrar_detalle_pedido(v_pedidos[28], v_productos[28], 3);

        IF (SELECT COUNT(*) FROM detalle_pedido WHERE pedido_id = v_pedidos[28]) <> 1
           OR NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[28]
               AND producto_id = v_productos[28] AND cantidad = 3
               AND precio_unitario = 900 AND subtotal = 3 * 900 AND eliminado = FALSE)
           OR (SELECT total FROM pedido WHERE id = v_pedidos[28]) IS DISTINCT FROM 2700
           OR (SELECT stock FROM producto WHERE id = v_productos[28]) IS DISTINCT FROM 7 THEN
            RAISE EXCEPTION 'TEST FAILED: estado incorrecto en escenario 28';
        END IF;

        RAISE EXCEPTION 'Fallo deliberado después de verificar todos los efectos'
            USING ERRCODE = 'P0099';
    EXCEPTION
        WHEN SQLSTATE 'P0099' THEN NULL;
    END;

    IF EXISTS (SELECT 1 FROM detalle_pedido WHERE pedido_id = v_pedidos[28])
       OR (SELECT stock FROM producto WHERE id = v_productos[28]) IS DISTINCT FROM v_stock
       OR (SELECT total FROM pedido WHERE id = v_pedidos[28]) IS DISTINCT FROM v_total THEN
        RAISE EXCEPTION 'TEST FAILED: atomicidad no revirtió todos los efectos';
    END IF;

    RAISE NOTICE 'PASS: detalle, subtotal, total y stock revierten juntos';

    RAISE NOTICE 'PASS: batería completa de objetos programables del modelo oficial';
END;
$pruebas$;

-- Solo datos de prueba: objetos instalados antes y secuencias no se restauran.
ROLLBACK;

-- Comprobación posterior de solo lectura: cero fixtures y limpieza_ok = TRUE.
SELECT
    (SELECT COUNT(*) FROM categoria WHERE nombre = '__TPI_TEST_CATEGORIA__') AS categorias_restantes,
    (SELECT COUNT(*) FROM usuario WHERE mail IN ('tpi.tests@foodstore.invalid','tpi.tests.baja@foodstore.invalid')) AS usuarios_restantes,
    (SELECT COUNT(*) FROM producto WHERE left(nombre, 6) = '__TPI_') AS productos_restantes,
    NOT EXISTS (SELECT 1 FROM categoria WHERE nombre = '__TPI_TEST_CATEGORIA__')
    AND NOT EXISTS (SELECT 1 FROM usuario WHERE mail IN ('tpi.tests@foodstore.invalid','tpi.tests.baja@foodstore.invalid'))
    AND NOT EXISTS (SELECT 1 FROM producto WHERE left(nombre, 6) = '__TPI_') AS limpieza_ok;

-- Inventario posterior: 12 filas; presente_y_habilitado debe ser TRUE en todas.
-- El NOTICE global anterior acredita aserciones dentro del DO, no sustituye
-- estos resultados de limpieza e inventario posteriores a la reversión.
WITH rutinas(firma, clase, retorno) AS (VALUES
            ('calcular_total_pedido(bigint)', 'f', 'numeric'),
            ('fn_set_subtotal()', 'f', 'trigger'),
            ('fn_validar_detalle_vigente()', 'f', 'trigger'),
            ('fn_recalcular_total_insert()', 'f', 'trigger'),
            ('fn_recalcular_total_update()', 'f', 'trigger'),
            ('fn_recalcular_total_delete()', 'f', 'trigger'),
            ('registrar_detalle_pedido(bigint,bigint,integer)', 'p', 'void')
), disparadores(nombre, funcion, eventos, anterior, nueva) AS (VALUES
            ('trg_subtotal', 'fn_set_subtotal()', 23, NULL, NULL),
            ('trg_detalle_vigente', 'fn_validar_detalle_vigente()', 23, NULL, NULL),
            ('trg_total_detalle_insert', 'fn_recalcular_total_insert()', 4, NULL, 'nuevos'),
            ('trg_total_detalle_update', 'fn_recalcular_total_update()', 16, 'anteriores', 'nuevos'),
            ('trg_total_detalle_delete', 'fn_recalcular_total_delete()', 8, 'anteriores', NULL)
)
SELECT r.firma AS objeto,
       EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(r.firma)
               AND p.prokind::TEXT = r.clase AND p.prorettype = to_regtype(r.retorno)) AS presente_y_habilitado
FROM rutinas r
UNION ALL
SELECT d.nombre,
       EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = to_regclass('detalle_pedido')
               AND t.tgname = d.nombre AND t.tgfoid = to_regprocedure(d.funcion)
               AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype = d.eventos
               AND t.tgoldtable::TEXT IS NOT DISTINCT FROM d.anterior
               AND t.tgnewtable::TEXT IS NOT DISTINCT FROM d.nueva)
FROM disparadores d
ORDER BY objeto;
