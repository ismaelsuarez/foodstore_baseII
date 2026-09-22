-- TPI Food Store — Objetos programables del modelo oficial, PostgreSQL 17.
-- Instalar después de ../../schema.sql y ../../datos_iniciales.sql sobre una
-- copia de laboratorio, mediante una transacción controlada por el llamante.
-- CREATE simple hace visible una instalación repetida. No se invoca el CALL.
-- Se usan los permisos y la resolución de nombres del llamante.
-- Diseño estático: instalación, atomicidad y concurrencia pendientes de prueba.
-- SQLSTATE: 22023 parámetros; 23503 referencia; 23505 duplicado;
-- 23514 vigencia, disponibilidad o stock. Las constraints del schema permanecen.

-- 1. Única definición del agregado: subtotal físico de las líneas vigentes.
-- No se filtran entidades relacionadas: una baja posterior no borra historia.
CREATE FUNCTION calcular_total_pedido(p_pedido_id BIGINT)
RETURNS NUMERIC(12,2)
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(SUM(subtotal), 0)
    FROM detalle_pedido
    WHERE pedido_id = p_pedido_id
      AND eliminado = FALSE;
$$;

-- 2. Única definición del subtotal; no administra stock ni total del pedido.
CREATE FUNCTION fn_set_subtotal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_buscar_precio BOOLEAN;
    v_precio producto.precio%TYPE;
BEGIN
    v_buscar_precio := NEW.precio_unitario IS NULL;
    IF TG_OP = 'UPDATE' THEN
        IF NEW.producto_id IS DISTINCT FROM OLD.producto_id
           AND NEW.precio_unitario IS NOT DISTINCT FROM OLD.precio_unitario THEN
            v_buscar_precio := TRUE;
        END IF;
    END IF;

    IF v_buscar_precio THEN
        SELECT precio INTO v_precio
        FROM producto
        WHERE id = NEW.producto_id
        FOR SHARE;
        IF FOUND THEN
            NEW.precio_unitario := v_precio;
        END IF;
        -- Sin producto no se inventa un precio ni se reemplaza la FK.
        -- Con precio explícito válido, la referencia será rechazada por la FK.
        -- Si además falta precio, NOT NULL puede fallar antes: son dos defectos.
    END IF;

    -- Un precio explícito distinto se conserva, también al reasignar producto.
    -- Un valor igual a OLD no permite distinguir si el llamante lo escribió.
    -- Cualquier subtotal ingresado directamente se sustituye por el derivado.
    NEW.subtotal := NEW.cantidad * NEW.precio_unitario;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_subtotal
BEFORE INSERT OR UPDATE OF cantidad, precio_unitario, producto_id, subtotal
ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_set_subtotal();

-- 3. Vigencia solo para altas o cambios efectivos de referencias.
-- FOR SHARE coordina la lectura con cambios en las filas referenciadas.
-- Orden de lectura protegida: pedido, usuario, producto.
CREATE FUNCTION fn_validar_detalle_vigente()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario_id pedido.usuario_id%TYPE;
    v_pedido_eliminado pedido.eliminado%TYPE;
    v_usuario_eliminado usuario.eliminado%TYPE;
    v_producto_eliminado producto.eliminado%TYPE;
    v_disponible producto.disponible%TYPE;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.pedido_id IS NOT DISTINCT FROM OLD.pedido_id
           AND NEW.producto_id IS NOT DISTINCT FROM OLD.producto_id THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT usuario_id, eliminado
    INTO v_usuario_id, v_pedido_eliminado
    FROM pedido
    WHERE id = NEW.pedido_id
    FOR SHARE;
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;
    IF v_pedido_eliminado THEN
        RAISE EXCEPTION 'El pedido % está eliminado y no admite nuevas líneas o reasignaciones',
            NEW.pedido_id USING ERRCODE = '23514';
    END IF;

    SELECT eliminado INTO v_usuario_eliminado
    FROM usuario
    WHERE id = v_usuario_id
    FOR SHARE;
    IF NOT FOUND THEN
        -- La integridad del pedido corresponde a fk_pedido_usuario.
        RETURN NEW;
    END IF;
    IF v_usuario_eliminado THEN
        RAISE EXCEPTION 'El usuario % del pedido está eliminado',
            v_usuario_id USING ERRCODE = '23514';
    END IF;

    SELECT eliminado, disponible
    INTO v_producto_eliminado, v_disponible
    FROM producto
    WHERE id = NEW.producto_id
    FOR SHARE;
    IF NOT FOUND THEN
        -- fk_detalle_pedido_producto conserva la autoridad estructural.
        RETURN NEW;
    END IF;
    IF v_producto_eliminado THEN
        RAISE EXCEPTION 'El producto % está eliminado',
            NEW.producto_id USING ERRCODE = '23514';
    END IF;
    IF NOT v_disponible THEN
        RAISE EXCEPTION 'El producto % no está disponible',
            NEW.producto_id USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

-- Los BEFORE de igual evento se ejecutan por nombre: detalle_vigente antes
-- de subtotal. Una baja/reactivación por sí sola no vuelve a validar vigencia.
CREATE TRIGGER trg_detalle_vigente
BEFORE INSERT OR UPDATE OF pedido_id, producto_id
ON detalle_pedido
FOR EACH ROW
EXECUTE FUNCTION fn_validar_detalle_vigente();

-- 4. Una actualización por pedido afectado y por sentencia, no por línea.
-- Funciones trigger VOLATILE por defecto: el SQL interno se ejecuta después
-- de los cambios de detalle; el agregador STABLE usa el snapshot de ese SQL.
-- IDs ordenados y aritmética centralizada. DML directo concurrente requiere
-- un protocolo externo: estos triggers no garantizan serialización completa.
CREATE FUNCTION fn_recalcular_total_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_pedido_id pedido.id%TYPE;
BEGIN
    FOR v_pedido_id IN
        SELECT DISTINCT pedido_id FROM nuevos ORDER BY pedido_id
    LOOP
        UPDATE pedido p
        SET total = calcular_total_pedido(p.id)
        WHERE p.id = v_pedido_id;
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE FUNCTION fn_recalcular_total_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_pedido_id pedido.id%TYPE;
BEGIN
    FOR v_pedido_id IN
        SELECT pedido_id FROM anteriores
        UNION
        SELECT pedido_id FROM nuevos
        ORDER BY pedido_id
    LOOP
        UPDATE pedido p
        SET total = calcular_total_pedido(p.id)
        WHERE p.id = v_pedido_id;
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE FUNCTION fn_recalcular_total_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_pedido_id pedido.id%TYPE;
BEGIN
    FOR v_pedido_id IN
        SELECT DISTINCT pedido_id FROM anteriores ORDER BY pedido_id
    LOOP
        UPDATE pedido p
        SET total = calcular_total_pedido(p.id)
        WHERE p.id = v_pedido_id;
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_total_detalle_insert
AFTER INSERT ON detalle_pedido
REFERENCING NEW TABLE AS nuevos
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total_insert();

-- Sin lista de columnas: incluye eliminado, pedido_id y created_at.
CREATE TRIGGER trg_total_detalle_update
AFTER UPDATE ON detalle_pedido
REFERENCING OLD TABLE AS anteriores NEW TABLE AS nuevos
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total_update();

CREATE TRIGGER trg_total_detalle_delete
AFTER DELETE ON detalle_pedido
REFERENCING OLD TABLE AS anteriores
FOR EACH STATEMENT
EXECUTE FUNCTION fn_recalcular_total_delete();

-- 5. Ruta de negocio soportada: una línea por CALL.
-- Orden: pedido FOR UPDATE, usuario FOR SHARE, producto FOR UPDATE.
-- El primer bloqueo serializa CALL sobre el mismo pedido, incluso para
-- productos distintos; el último protege el stock compartido.
-- En READ COMMITTED, una llamada que espera continúa con filas actualizadas;
-- aislamientos más fuertes pueden requerir reintento por serialización.
-- No es evidencia experimental ni garantía contra deadlocks de transacciones
-- externas que mezclen varias operaciones en otro orden.
-- La transacción pertenece al llamante; ningún error se captura para continuar.
CREATE PROCEDURE registrar_detalle_pedido(
    p_pedido_id BIGINT,
    p_producto_id BIGINT,
    p_cantidad INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario_id pedido.usuario_id%TYPE;
    v_usuario_eliminado usuario.eliminado%TYPE;
    v_precio producto.precio%TYPE;
    v_stock producto.stock%TYPE;
    v_disponible producto.disponible%TYPE;
    v_producto_eliminado producto.eliminado%TYPE;
BEGIN
    IF p_pedido_id IS NULL OR p_producto_id IS NULL OR p_cantidad IS NULL THEN
        RAISE EXCEPTION 'pedido_id, producto_id y cantidad son obligatorios'
            USING ERRCODE = '22023';
    END IF;
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero: %', p_cantidad
            USING ERRCODE = '22023';
    END IF;

    SELECT usuario_id INTO v_usuario_id
    FROM pedido
    WHERE id = p_pedido_id AND eliminado = FALSE
    FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM 1 FROM pedido WHERE id = p_pedido_id;
        IF FOUND THEN
            RAISE EXCEPTION 'El pedido % está eliminado', p_pedido_id
                USING ERRCODE = '23514';
        ELSE
            RAISE EXCEPTION 'El pedido % no existe', p_pedido_id
                USING ERRCODE = '23503';
        END IF;
    END IF;

    SELECT eliminado INTO v_usuario_eliminado
    FROM usuario
    WHERE id = v_usuario_id
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % del pedido no existe', v_usuario_id
            USING ERRCODE = '23503';
    END IF;
    IF v_usuario_eliminado THEN
        RAISE EXCEPTION 'El usuario % del pedido está eliminado', v_usuario_id
            USING ERRCODE = '23514';
    END IF;

    SELECT precio, stock, disponible, eliminado
    INTO v_precio, v_stock, v_disponible, v_producto_eliminado
    FROM producto
    WHERE id = p_producto_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe', p_producto_id
            USING ERRCODE = '23503';
    END IF;
    IF v_producto_eliminado THEN
        RAISE EXCEPTION 'El producto % está eliminado', p_producto_id
            USING ERRCODE = '23514';
    END IF;
    IF NOT v_disponible THEN
        RAISE EXCEPTION 'El producto % no está disponible', p_producto_id
            USING ERRCODE = '23514';
    END IF;
    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para producto %: disponible %, solicitado %',
            p_producto_id, v_stock, p_cantidad USING ERRCODE = '23514';
    END IF;

    PERFORM 1 FROM detalle_pedido
    WHERE pedido_id = p_pedido_id AND producto_id = p_producto_id;
    IF FOUND THEN
        RAISE EXCEPTION 'El producto % ya existe en el pedido %',
            p_producto_id, p_pedido_id USING ERRCODE = '23505';
    END IF;

    -- Incluye duplicados eliminados; uq_detalle_pedido_pedido_producto es la
    -- garantía definitiva. El precio leído bajo bloqueo queda como histórico.
    -- Los triggers administran subtotal y total, sin otra definición en el CALL.
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    VALUES (p_pedido_id, p_producto_id, p_cantidad, v_precio);

    UPDATE producto
    SET stock = stock - p_cantidad
    WHERE id = p_producto_id;
END;
$$;

-- Límites: DML directo mantiene derivados y valida altas/reasignaciones,
-- pero no administra inventario. Cambiar cantidad/producto directamente no
-- ajusta stock. Baja lógica, reactivación o DELETE tampoco reponen/descuentan
-- stock: requieren una política de negocio separada, no definida aquí.
-- Cambiar eliminado excluye/reincorpora la línea al total sin validar de nuevo
-- referencias históricas. Mover pedido_id recalcula ambos pedidos sin stock.
-- Una escritura directa de pedido.total queda fuera de estos triggers de detalle.

-- Ejemplo documental; usar IDs existentes y vigentes en la prueba posterior:
-- CALL registrar_detalle_pedido(<pedido_id>, <producto_id>, <cantidad>);

-- Plan DOWN comentado: solo objetos de este archivo, sin CASCADE ni datos.
-- Retirar primero los triggers, luego sus funciones y el procedimiento;
-- eliminar el agregador al final, después de sus consumidores.
-- DROP TRIGGER trg_total_detalle_delete ON detalle_pedido;
-- DROP TRIGGER trg_total_detalle_update ON detalle_pedido;
-- DROP TRIGGER trg_total_detalle_insert ON detalle_pedido;
-- DROP TRIGGER trg_detalle_vigente ON detalle_pedido;
-- DROP TRIGGER trg_subtotal ON detalle_pedido;
-- DROP FUNCTION fn_recalcular_total_delete();
-- DROP FUNCTION fn_recalcular_total_update();
-- DROP FUNCTION fn_recalcular_total_insert();
-- DROP FUNCTION fn_validar_detalle_vigente();
-- DROP FUNCTION fn_set_subtotal();
-- DROP PROCEDURE registrar_detalle_pedido(BIGINT, BIGINT, INTEGER);
-- DROP FUNCTION calcular_total_pedido(BIGINT);
