-- ============================================================================
-- tp_desnormalizacion_top_categorias.sql
-- Base de Datos II - Unidad 4, Parte 2: Desnormalización controlada
-- Reporte: "Top categorías por monto vendido"
-- Especificación: ../specs/u4_desnormalizacion_top_categorias.md
-- ============================================================================
--
-- STATUS: EXPERIMENTAL_CANDIDATE_REJECTED
-- FINAL_DECISION: DO_NOT_ADOPT
-- MODELO OFICIAL Y ESTADO DE VALIDACIÓN
--
-- detalle_pedido.subtotal es una columna física; detalle_pedido y pedido
-- tienen eliminado. pedido.fecha es DATE y el reporte usa CURRENT_DATE.
-- Se suman dp.subtotal con filtros de borrado lógico sobre detalle y pedido.
-- No se filtran producto/categoria por eliminado ni producto.disponible:
-- una baja actual no debe ocultar las ventas históricas del día consultado.
--
-- Resultado real en foodstore_u4_oficial, PostgreSQL 17.11 (Bloque 2):
-- baseline median = 200.392 ms; candidate median = 196.507 ms
-- time delta = -1.94 %; buffers = +59.70 %; write cost = +34.97 %
-- Evidencia: ../informes/evidencia_modelo_oficial.md.
-- Implementación experimental válida, no una mejora robusta ni una
-- migración pendiente de incorporar a schema.sql. Candidato descartado
-- por relación costo/beneficio; conservar producto.categoria_id.
--
-- HIPÓTESIS: eliminar el JOIN a producto puede reducir trabajo de lectura.
-- Se conserva la columna redundante mantenida por triggers en lugar de una
-- vista materializada, evitando un ciclo de refresh para este dato derivado.
-- Equivalencia 0 / 0, pruebas A/B/C PASS y auditoría final 0.
-- Concurrencia ensayada: dos UPDATE del mismo producto, espera y auditoría 0.
-- No se probó INSERT concurrente de detalle frente a UPDATE de producto.
-- No se incorpora aquí una estrategia adicional de bloqueo.
-- La hipótesis y el SQL se conservan como evidencia del experimento.
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
-- Antes de INSERT o de UPDATE de producto_id o categoria_id en detalle_pedido,
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

-- También intercepta UPDATE directo de categoria_id: la aplicación no
-- puede imponer un valor distinto de producto.categoria_id mediante DML
-- ordinario con estos triggers habilitados. La función solo asigna NEW;
-- no ejecuta UPDATE sobre producto ni detalle, por lo que no hay ciclo.
-- El UPDATE de sincronización B vuelve a derivar el mismo valor vigente.
-- No se filtra eliminado/disponible: las bajas lógicas no excluyen filas
-- de la sincronización. Esto requiere verificación posterior en ejecución.
CREATE TRIGGER trg_detalle_pedido_set_categoria
    BEFORE INSERT OR UPDATE OF producto_id, categoria_id
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
-- Consulta oficial medida: mediana 200.392 ms de las cinco corridas.
-- Los resultados completos permanecen en la evidencia del Bloque 2.
-- ============================================================================

SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr
    ON pr.id = dp.producto_id
JOIN categoria c
    ON c.id = pr.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA DESNORMALIZADA (sin JOIN a producto)
-- ============================================================================
-- Consulta oficial medida: mediana 196.507 ms de las cinco corridas.
-- No se incrustan planes en el script; consultar evidencia del Bloque 2.
-- ============================================================================

SELECT
    c.nombre AS categoria,
    SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN categoria c
    ON c.id = dp.categoria_id
JOIN pedido ped
    ON ped.id = dp.pedido_id
WHERE ped.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND ped.fecha = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ============================================================================
-- EQUIVALENCIA — ORIGINAL MENOS DESNORMALIZADA
-- ============================================================================
-- Resultado esperado: 0 filas. Se comparan todos los grupos, sin LIMIT.
-- ORDER BY total_vendido DESC no desempata: categorías con igual importe
-- en el límite pueden dar distintos Top 5 igualmente válidos. No confundir
-- esa selección no determinista con una diferencia de agregados.
-- ============================================================================

WITH original AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.subtotal) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto pr
        ON pr.id = dp.producto_id
    JOIN categoria c
        ON c.id = pr.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.eliminado = FALSE
      AND dp.eliminado = FALSE
      AND ped.fecha = CURRENT_DATE
    GROUP BY c.nombre
),
desnormalizada AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.subtotal) AS total_vendido
    FROM detalle_pedido dp
    JOIN categoria c
        ON c.id = dp.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.eliminado = FALSE
      AND dp.eliminado = FALSE
      AND ped.fecha = CURRENT_DATE
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
        SUM(dp.subtotal) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto pr
        ON pr.id = dp.producto_id
    JOIN categoria c
        ON c.id = pr.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.eliminado = FALSE
      AND dp.eliminado = FALSE
      AND ped.fecha = CURRENT_DATE
    GROUP BY c.nombre
),
desnormalizada AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.subtotal) AS total_vendido
    FROM detalle_pedido dp
    JOIN categoria c
        ON c.id = dp.categoria_id
    JOIN pedido ped
        ON ped.id = dp.pedido_id
    WHERE ped.eliminado = FALSE
      AND dp.eliminado = FALSE
      AND ped.fecha = CURRENT_DATE
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
-- Esta prueba requiere elegir, con datos reales de foodstore_u4_oficial:
-- - un detalle existente (pedido_id, producto_id) determinado;
-- - un producto_id alternativo válido, de categoría distinta, que no
--   provoque conflicto con UNIQUE (pedido_id, producto_id) de
--   detalle_pedido; su PK es id (es decir, que ese pedido_id no tenga ya una fila
--   con ese producto_id alternativo).
--
-- Esos IDs concretos no están documentados en la spec y no se
-- inventan acá. La prueba queda parametrizada/documentada para
-- ejecutarse manualmente con IDs válidos seleccionados previamente
-- por el estudiante (por ejemplo, verificando de antemano con un
-- SELECT que el producto alternativo exista, tenga categoría distinta
-- y no choque con UNIQUE del detalle elegido):
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
-- PRUEBA REVERSIBLE A2 — ASIGNACIÓN DIRECTA DE CATEGORÍA
-- ============================================================================
-- Con un detalle y una categoría alternativa válidos elegidos del dataset:
-- BEGIN;
-- UPDATE detalle_pedido
-- SET categoria_id = :categoria_id_alternativa_valida
-- WHERE id = :detalle_id_elegido;
-- SELECT dp.id, dp.categoria_id, pr.categoria_id AS categoria_real
-- FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
-- WHERE dp.id = :detalle_id_elegido;
-- -- Debe prevalecer producto.categoria_id, no el valor proporcionado.
-- ROLLBACK;
-- Repetir los controles con bajas lógicas reversibles; la sincronización
-- incluye esas filas, aunque pedido/detalle eliminados no integren el reporte.
-- Bloque 2: INSERT de 1000 detalles medido y dos UPDATE concurrentes
-- del mismo producto validados. La carrera INSERT/UPDATE no fue ensayada.
-- ============================================================================

-- ============================================================================
-- PRUEBA REVERSIBLE B — PRODUCTO
-- ============================================================================
--
-- Objetivo: comprobar que al modificar producto.categoria_id, todas
-- las filas de detalle_pedido asociadas a ese producto reciben la
-- nueva categoria_id.
--
-- Esta prueba requiere elegir, con datos reales de foodstore_u4_oficial:
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
-- MEDICIÓN REAL Y PROTOCOLO CONSERVADO
-- ============================================================================
--
-- Bloque 2: cinco corridas por variante, ninguna descartada.
-- Normalizada (ms): 191.465, 188.192, 210.285, 237.785, 200.392.
-- Candidato (ms): 174.459, 177.794, 287.053, 196.507, 307.298.
-- Buffers hit + read: 8382 -> 13386. Mayor dispersión posterior.
-- INSERT de 1000 detalles: promedio válido 21.3385 -> 28.8015 ms.
-- Costo incremental del trigger, no todo el costo de la columna/FK.
-- Propagación del producto 17: 18 detalles, 57.540 ms (observación puntual).
-- Backfill: 550000; NULL y desincronizadas: 0. EXCEPT: 0 / 0.
-- Protocolo: EXPLAIN (ANALYZE, BUFFERS); registrar todas las corridas,
-- nodos, filas y buffers; mediana sin seleccionar solo resultados favorables.
-- Las cachés y el estado físico posterior al backfill limitan la comparación.
-- Beneficio temporal marginal: no adoptar el candidato como diseño permanente.
-- ============================================================================

-- ============================================================================
-- PLAN DE REVERSIÓN / DOWN
-- ============================================================================
--
-- DOWN validado estáticamente en el Bloque 2, no ejecutado.
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
-- Antes de ejecutar, crear y verificar un backup de la copia oficial fuera
-- del repositorio. El backup histórico no acredita respaldo de esta nueva
-- base. No versionar el dump.
-- ============================================================================
