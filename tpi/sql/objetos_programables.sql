-- A. TPI Food Store — Objetos programables
-- Compatible con PostgreSQL 16 y 17; rutinas escritas en PL/pgSQL.
-- Artefactos específicos del TPI: no modifican los archivos canónicos ni
-- reescriben los trabajos históricos. No se crean tablas ni columnas.
-- Instalar explícitamente sobre una base de laboratorio reconstruida desde
-- ../../schema.sql y ../../datos_iniciales.sql, nunca sobre una base importante.
-- Usar el mismo esquema de resolución de nombres que las tablas canónicas.
-- La instalación debe realizarse en una transacción externa para evitar un UP
-- parcial si falla alguna definición. CREATE simple falla si el objeto existe.
-- Este archivo no ejecuta pruebas ni invoca el procedimiento.
-- SQLSTATE utilizados:
-- 22023: invalid_parameter_value; 23503: foreign_key_violation;
-- 23505: unique_violation; 23514: check_violation.

-- B. Función de validación de actividad para detalle_pedido
-- FOR SHARE coordina la lectura con cambios concurrentes del producto.
-- FOUND distingue una referencia inexistente del valor leído de activo.
-- La FK sigue siendo responsable de rechazar productos inexistentes.
-- La función no modifica NEW, stock ni precio, ni repite los CHECK del detalle.
CREATE FUNCTION fn_validar_producto_activo_detalle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo producto.activo%TYPE;
BEGIN
    SELECT activo
    INTO v_activo
    FROM producto
    WHERE id = NEW.producto_id
    FOR SHARE;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF v_activo = FALSE THEN
        RAISE EXCEPTION
            'El producto % está inactivo y no admite nuevas líneas de pedido',
            NEW.producto_id
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

-- C. Trigger de actividad
-- Protege INSERT directos, UPDATE hacia otro producto y el INSERT realizado
-- por registrar_detalle_pedido. No administra inventario.
-- No recorre ni modifica ventas históricas existentes y no impide la baja
-- posterior del producto; esas ventas conservan su referencia e historial.
-- No valida categoria.activo: no es una regla de venta del esquema base.
-- UPDATE OF producto_id también se dispara si la columna aparece en SET
-- aunque su valor final sea el mismo; en ese caso vuelve a validar actividad.
CREATE TRIGGER trg_detalle_producto_activo
BEFORE INSERT OR UPDATE OF producto_id
ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_producto_activo_detalle();

-- D. Procedimiento de registro de una línea de pedido
-- El INSERT del detalle y el UPDATE de stock pertenecen a la transacción
-- llamante. PostgreSQL realiza ambos cambios dentro de esa misma transacción;
-- si cualquiera falla, el llamante puede hacer ROLLBACK de todo.
-- No hay control transaccional interno ni manejadores que oculten errores.
--
-- SELECT ... FOR UPDATE mantiene bloqueada la fila del producto durante la
-- transacción. Dos llamadas concurrentes no pueden leer y descontar stock
-- simultáneamente basándose ambas en el mismo valor anterior.
-- En READ COMMITTED, la segunda espera y lee el valor actualizado; con
-- aislamientos más fuertes puede producirse un error de serialización.
-- Esto describe el diseño; este archivo no demuestra concurrencia ejecutada.
-- Experimentos reales de aislamiento/concurrencia:
-- ../../unidades/unidad-1/tp2/informes/informe_concurrencia.md
--
-- La validación de actividad aquí y en el trigger es intencional:
-- el procedimiento ofrece una ruta controlada de negocio y el trigger
-- protege también escrituras directas que no pasan por esa ruta.
-- El trigger no reemplaza el descuento de stock del procedimiento.
CREATE PROCEDURE registrar_detalle_pedido(
    p_pedido_id BIGINT,
    p_producto_id BIGINT,
    p_cantidad INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_precio producto.precio%TYPE;
    v_stock producto.stock%TYPE;
    v_activo producto.activo%TYPE;
BEGIN
    IF p_pedido_id IS NULL
       OR p_producto_id IS NULL
       OR p_cantidad IS NULL THEN
        RAISE EXCEPTION
            'pedido_id, producto_id y cantidad son parámetros obligatorios'
            USING ERRCODE = '22023';
    END IF;

    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero: %', p_cantidad
            USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM pedido
    WHERE id = p_pedido_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El pedido % no existe', p_pedido_id
            USING ERRCODE = '23503';
    END IF;

    SELECT precio, stock, activo
    INTO v_precio, v_stock, v_activo
    FROM producto
    WHERE id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe', p_producto_id
            USING ERRCODE = '23503';
    END IF;

    IF v_activo = FALSE THEN
        RAISE EXCEPTION 'El producto % está inactivo y no puede venderse',
            p_producto_id
            USING ERRCODE = '23514';
    END IF;

    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION
            'Stock insuficiente para producto %: disponible %, solicitado %',
            p_producto_id, v_stock, p_cantidad
            USING ERRCODE = '23514';
    END IF;

    PERFORM 1
    FROM detalle_pedido
    WHERE pedido_id = p_pedido_id
      AND producto_id = p_producto_id;

    IF FOUND THEN
        RAISE EXCEPTION 'El producto % ya existe en el pedido %',
            p_producto_id, p_pedido_id
            USING ERRCODE = '23505';
    END IF;

    -- La PK compuesta sigue siendo la protección definitiva ante carreras.
    -- No se acumula cantidad automáticamente en una línea existente.
    -- Se conserva como precio histórico el valor leído bajo bloqueo, sin
    -- consultarlo nuevamente. Este INSERT también activa el trigger.
    INSERT INTO detalle_pedido (
        pedido_id,
        producto_id,
        cantidad,
        precio_unitario
    )
    VALUES (
        p_pedido_id,
        p_producto_id,
        p_cantidad,
        v_precio
    );

    UPDATE producto
    SET stock = stock - p_cantidad
    WHERE id = p_producto_id;
END;
$$;

-- E. Ejemplo de invocación — solo documentación, no ejecutar desde este archivo
-- CALL registrar_detalle_pedido(<pedido_id>, <producto_id>, <cantidad>);
-- La ejecución real se incorporará en un batch posterior a:
-- tpi/pruebas/pruebas_objetos_programables.sql

-- F. Plan DOWN — completamente comentado, requiere decisión explícita
-- Elimina únicamente los objetos del TPI; no revierte ventas confirmadas.
-- No debe ejecutarse automáticamente después del UP.
-- Orden: trigger, función y procedimiento.
-- DROP TRIGGER trg_detalle_producto_activo ON detalle_pedido;
-- DROP FUNCTION fn_validar_producto_activo_detalle();
-- DROP PROCEDURE registrar_detalle_pedido(BIGINT, BIGINT, INTEGER);
