-- ============================================================================
-- tp_desnormalizacion_top_categorias.sql
-- Base de Datos II - Unidad 4, Parte 2: Desnormalización controlada
-- Reporte: "Top categorías por monto vendido"
-- Especificación: ../specs/u4_desnormalizacion_top_categorias.md
-- ============================================================================
--
-- CONTEXTO REAL DEL SCHEMA
--
-- El schema.sql real de este repositorio NO contiene:
-- - detalle_pedido.subtotal
-- - detalle_pedido.eliminado
-- - pedido.eliminado
--
-- Esas columnas aparecen en la consigna teórica, pero no existen acá.
-- No se inventan: el subtotal real utilizado en todo este archivo es
-- cantidad * precio_unitario.
--
-- MOTIVO MEDIDO DE LA DESNORMALIZACIÓN
--
-- Se ejecutó EXPLAIN (ANALYZE, BUFFERS) cinco veces sobre la consulta
-- normalizada (Sección "CONSULTA NORMALIZADA (BASELINE)" más abajo),
-- para el día 2026-04-11 (4160 pedidos, 10400 detalles ese día):
--
-- Execution Time:
-- 1. 234.451 ms
-- 2. 369.073 ms
-- 3. 231.651 ms
-- 4. 239.969 ms
-- 5. 266.980 ms
--
-- Mediana baseline = 239.969 ms. No se oculta la corrida de 369.073 ms.
--
-- El plan mostró Parallel Seq Scan sobre detalle_pedido y pedido,
-- Parallel Hash Join entre ambos, y un Nested Loop hacia producto con
-- Index Scan using producto_pkey ejecutado aproximadamente 10400 veces
-- (una por detalle), acumulando aproximadamente 31200 de los 36400
-- buffers totales. El Sort final (quicksort, ~25 kB) NO es el cuello
-- de botella: el costo medido está concentrado en las búsquedas
-- repetidas contra producto, hechas únicamente para obtener
-- producto.categoria_id.
--
-- DECISIÓN: columna redundante derivada, mantenida por triggers,
-- en lugar de una vista materializada — el escenario es un panel de
-- actualización frecuente, y la columna redundante mantiene
-- sincronización inmediata en vez de aceptar staleness entre refresh.
-- Esto no implica que una vista materializada sea incorrecta en
-- general; simplemente no es el patrón elegido para este caso.
--
-- producto.categoria_id sigue siendo la ÚNICA fuente de verdad.
-- detalle_pedido.categoria_id es redundancia controlada, cuyo dueño
-- son los triggers de este archivo (nunca la aplicación).
-- Mecanismo de auditoría: consulta de conciliación (Sección
-- "AUDITORÍA INICIAL DE CONSISTENCIA").
-- Reversibilidad: ver "PLAN DE REVERSIÓN / DOWN" al final del archivo.
-- Costo asumido: mayor trabajo de escritura, especialmente si cambia
-- la categoría de un producto con muchas ventas históricas (ver
-- comentario en fn_producto_sync_categoria_detalle más abajo).
-- ============================================================================

BEGIN;

-- ============================================================================
-- ETAPA 1: Agregar columna redundante (sin NOT NULL todavía)
-- ============================================================================

ALTER TABLE detalle_pedido
    ADD COLUMN categoria_id BIGINT;

-- ============================================================================
-- ETAPA 2: Backfill desde la fuente de verdad (producto.categoria_id)
-- ============================================================================

UPDATE detalle_pedido dp
SET categoria_id = pr.categoria_id
FROM producto pr
WHERE pr.id = dp.producto_id;

-- Verificación: debe devolver 0. Si no, la migración no es válida.
SELECT COUNT(*) AS categorias_nulas
FROM detalle_pedido
WHERE categoria_id IS NULL;

-- ============================================================================
-- ETAPA 3: Constraints (NOT NULL + FOREIGN KEY explícita)
-- ============================================================================

ALTER TABLE detalle_pedido
    ALTER COLUMN categoria_id SET NOT NULL;

ALTER TABLE detalle_pedido
    ADD CONSTRAINT fk_detalle_pedido_categoria
        FOREIGN KEY (categoria_id)
        REFERENCES categoria(id)
        ON DELETE RESTRICT;

-- No se agrega UNIQUE: categoria_id no es candidata a clave acá.

-- ============================================================================
-- ETAPA 4: Sincronización A — detalle_pedido -> producto
-- ============================================================================
--
-- Antes de INSERT o de UPDATE de producto_id sobre detalle_pedido,
-- obtiene producto.categoria_id usando NEW.producto_id y lo asigna a
-- NEW.categoria_id. Si NEW.producto_id no identifica un producto
-- existente, la función no oculta ni corrige el problema: no podrá
-- obtener una categoria_id válida y la operación será rechazada por
-- las restricciones del esquema. La FOREIGN KEY existente sobre
-- producto_id continúa garantizando además la integridad referencial
-- hacia producto.
--
-- La aplicación NO decide categoria_id: el valor proviene
-- exclusivamente de la fuente de verdad producto.categoria_id.
-- ============================================================================

CREATE FUNCTION fn_detalle_pedido_set_categoria()
RETURNS TRIGGER AS $$
BEGIN
    SELECT pr.categoria_id
    INTO NEW.categoria_id
    FROM producto pr
    WHERE pr.id = NEW.producto_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- IMPORTANTE: la condición WHEN evita que este trigger se dispare
-- cuando solo cambia categoria_id (por ejemplo, por efecto del
-- trigger de sincronización B sobre producto), evitando una recursión
-- accidental entre ambos mecanismos.
CREATE TRIGGER trg_detalle_pedido_set_categoria
    BEFORE INSERT OR UPDATE OF producto_id
    ON detalle_pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_detalle_pedido_set_categoria();

-- ============================================================================
-- ETAPA 5: Sincronización B — producto -> detalle_pedido
-- ============================================================================
--
-- Si producto.categoria_id cambia, propaga el nuevo valor a todas las
-- filas de detalle_pedido asociadas a ese producto. Esto es necesario
-- para conservar equivalencia con la consulta normalizada original,
-- que siempre usa el categoria_id ACTUAL de producto.
--
-- COSTO DELIBERADO: este UPDATE puede afectar muchas filas históricas
-- si el producto tiene muchas ventas. Es un costo de escritura
-- asumido conscientemente por la desnormalización, a cambio de
-- mantener equivalencia exacta con la consulta normalizada, cuya
-- fuente de verdad sigue siendo producto.categoria_id.
-- ============================================================================

CREATE FUNCTION fn_producto_sync_categoria_detalle()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.categoria_id IS DISTINCT FROM OLD.categoria_id THEN
        UPDATE detalle_pedido
        SET categoria_id = NEW.categoria_id
        WHERE producto_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_producto_sync_categoria_detalle
    AFTER UPDATE OF categoria_id
    ON producto
    FOR EACH ROW
    EXECUTE FUNCTION fn_producto_sync_categoria_detalle();

-- ============================================================================
-- ETAPA 6: Auditoría inicial de consistencia
-- ============================================================================
-- Resultado esperado: 0 filas. Cualquier fila indica desincronización
-- entre el dato redundante y la fuente de verdad.
-- ============================================================================

SELECT
    dp.pedido_id,
    dp.producto_id,
    dp.categoria_id AS categoria_guardada,
    pr.categoria_id AS categoria_real
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id;

COMMIT;

-- ============================================================================
-- CONSULTA NORMALIZADA (BASELINE, con JOIN a producto)
-- ============================================================================
-- Se conserva como consulta de referencia; es la que se midió con
-- EXPLAIN (ANALYZE, BUFFERS) para obtener las cinco corridas del
-- encabezado.
-- ============================================================================

SELECT
    c.nombre AS categoria,
    SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
JOIN categoria c
    ON c.id = pr.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.fecha >= DATE '2026-04-11'
  AND ped.fecha < DATE '2026-04-12'
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA DESNORMALIZADA (sin JOIN a producto)
-- ============================================================================
-- No se agrega EXPLAIN fijo como resultado medido acá: las mediciones
-- reales de esta consulta se ejecutarán manualmente después, según el
-- protocolo documentado en "MEDICIÓN POSTERIOR" más abajo.
-- ============================================================================

SELECT
    c.nombre AS categoria,
    SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c
    ON c.id = dp.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.fecha >= DATE '2026-04-11'
  AND ped.fecha < DATE '2026-04-12'
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ============================================================================
-- EQUIVALENCIA — ORIGINAL MENOS DESNORMALIZADA
-- ============================================================================
-- Resultado esperado: 0 filas.
-- ============================================================================

WITH original AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto pr
        ON pr.id = dp.producto_id
    JOIN categoria c
        ON c.id = pr.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.fecha >= DATE '2026-04-11'
      AND ped.fecha < DATE '2026-04-12'
    GROUP BY c.nombre
),
desnormalizada AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
    FROM detalle_pedido dp
    JOIN categoria c
        ON c.id = dp.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.fecha >= DATE '2026-04-11'
      AND ped.fecha < DATE '2026-04-12'
    GROUP BY c.nombre
)
SELECT *
FROM original
EXCEPT
SELECT *
FROM desnormalizada;

-- ============================================================================
-- EQUIVALENCIA — DESNORMALIZADA MENOS ORIGINAL
-- ============================================================================
-- Resultado esperado: 0 filas. Ambas direcciones son obligatorias:
-- una detecta pérdida de categorías, la otra categorías espurias.
-- ============================================================================

WITH original AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto pr
        ON pr.id = dp.producto_id
    JOIN categoria c
        ON c.id = pr.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.fecha >= DATE '2026-04-11'
      AND ped.fecha < DATE '2026-04-12'
    GROUP BY c.nombre
),
desnormalizada AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
    FROM detalle_pedido dp
    JOIN categoria c
        ON c.id = dp.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.fecha >= DATE '2026-04-11'
      AND ped.fecha < DATE '2026-04-12'
    GROUP BY c.nombre
)
SELECT *
FROM desnormalizada
EXCEPT
SELECT *
FROM original;

-- ============================================================================
-- PRUEBA REVERSIBLE A — DETALLE
-- ============================================================================
--
-- Objetivo: comprobar que al modificar producto_id de un detalle
-- existente, categoria_id se actualiza automáticamente desde producto.
--
-- Esta prueba requiere elegir, con datos reales de foodstore_u4:
-- - un detalle existente (pedido_id, producto_id) determinado;
-- - un producto_id alternativo válido, de categoría distinta, que no
--   provoque conflicto con la PK (pedido_id, producto_id) de
--   detalle_pedido (es decir, que ese pedido_id no tenga ya una fila
--   con ese producto_id alternativo).
--
-- Esos IDs concretos no están documentados en la spec y no se
-- inventan acá. La prueba queda parametrizada/documentada para
-- ejecutarse manualmente con IDs válidos seleccionados previamente
-- por el estudiante (por ejemplo, verificando de antemano con un
-- SELECT que el producto alternativo exista, tenga categoría distinta
-- y no choque con la PK del detalle elegido):
--
-- BEGIN;
--
-- UPDATE detalle_pedido
-- SET producto_id = :producto_id_alternativo_valido
-- WHERE pedido_id = :pedido_id_elegido
--   AND producto_id = :producto_id_original;
--
-- SELECT pedido_id, producto_id, categoria_id
-- FROM detalle_pedido
-- WHERE pedido_id = :pedido_id_elegido
--   AND producto_id = :producto_id_alternativo_valido;
-- -- categoria_id debe coincidir con la categoría real del producto
-- -- alternativo.
--
-- ROLLBACK;
-- ============================================================================

-- ============================================================================
-- PRUEBA REVERSIBLE B — PRODUCTO
-- ============================================================================
--
-- Objetivo: comprobar que al modificar producto.categoria_id, todas
-- las filas de detalle_pedido asociadas a ese producto reciben la
-- nueva categoria_id.
--
-- Esta prueba requiere elegir, con datos reales de foodstore_u4:
-- - un producto que tenga detalles asociados;
-- - una categoria_id alternativa válida y distinta de la actual.
--
-- Esos IDs concretos tampoco están documentados y no se inventan acá.
-- Queda parametrizada/documentada para ejecución manual:
--
-- BEGIN;
--
-- UPDATE producto
-- SET categoria_id = :categoria_id_alternativa_valida
-- WHERE id = :producto_id_con_detalles;
--
-- SELECT dp.pedido_id, dp.producto_id, dp.categoria_id
-- FROM detalle_pedido dp
-- WHERE dp.producto_id = :producto_id_con_detalles;
-- -- Todas las filas deben mostrar categoria_id =
-- -- :categoria_id_alternativa_valida.
--
-- SELECT
--     dp.pedido_id,
--     dp.producto_id,
--     dp.categoria_id AS categoria_guardada,
--     pr.categoria_id AS categoria_real
-- FROM detalle_pedido dp
-- JOIN producto pr
--     ON pr.id = dp.producto_id
-- WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id;
-- -- Debe devolver 0 filas.
--
-- ROLLBACK;
-- ============================================================================

-- ============================================================================
-- MEDICIÓN POSTERIOR
-- ============================================================================
--
-- Medir manualmente la consulta desnormalizada con:
--
-- EXPLAIN (ANALYZE, BUFFERS)
--
-- Protocolo:
-- - ejecutar 5 veces;
-- - conservar las cinco mediciones (no descartar ninguna);
-- - calcular la mediana como valor representativo;
-- - comparar la mediana contra el baseline: 239.969 ms;
-- - comparar también el tipo de nodo dominante y los buffers totales
--   contra el plan normalizado documentado en el encabezado de este
--   archivo (Parallel Hash Join + Nested Loop hacia producto,
--   ~36400 buffers, ~31200 de ellos en producto_pkey);
-- - no declarar mejora de rendimiento hasta obtener esa evidencia
--   real.
-- ============================================================================

-- ============================================================================
-- PLAN DE REVERSIÓN / DOWN
-- ============================================================================
--
-- Los siguientes comandos NO se ejecutan automáticamente. Revertir en
-- este orden, sin CASCADE:
--
-- 1. DROP TRIGGER trg_producto_sync_categoria_detalle ON producto;
-- 2. DROP FUNCTION fn_producto_sync_categoria_detalle();
-- 3. DROP TRIGGER trg_detalle_pedido_set_categoria ON detalle_pedido;
-- 4. DROP FUNCTION fn_detalle_pedido_set_categoria();
-- 5. ALTER TABLE detalle_pedido
--        DROP CONSTRAINT fk_detalle_pedido_categoria;
-- 6. ALTER TABLE detalle_pedido
--        DROP COLUMN categoria_id;
--
-- Eliminar categoria_id no pierde información original: la fuente de
-- verdad continúa siendo producto.categoria_id en todo momento.
--
-- Backup externo previo a esta práctica:
--
-- backups/foodstore_u4_pre_u4.dump
--
-- Ese dump no debe versionarse en Git.
-- ============================================================================
