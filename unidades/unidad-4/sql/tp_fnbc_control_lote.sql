-- ============================================================================
-- tp_fnbc_control_lote.sql
-- Base de Datos II - Unidad 4, Parte 1: FNBC - ControlLoteAlmacen
-- Especificación: ../specs/u4_fnbc_control_lote.md
-- ============================================================================
-- Diseñado para ejecutarse una única vez sobre foodstore_u4_revalidacion.
-- No usa IDENTITY, IF NOT EXISTS, ON CONFLICT ni CASCADE: si algún
-- objeto ya existe o los datos violan una regla de negocio necesaria,
-- el script debe fallar de forma visible, no ocultar el problema.
--
-- El modelo oficial ya contiene usuario: esta práctica utiliza los usuarios
-- existentes 1 y 2, no los crea ni elimina. Solo deposito y lote son
-- tablas maestras auxiliares de la extensión académica de Unidad 4.
-- Bootstrap canónico: schema.sql y datos_iniciales.sql del commit base
-- e5282f68a4af6975fb953c4f4b74f2e13240a0a6, más los tres índices TP5.
-- Mapeo del ejemplo: 801 lógico -> usuario 1; 802 lógico -> usuario 2.
-- Los identificadores son fixtures: este cambio no altera las DF.
-- La evidencia anterior (801/802, foodstore_u4_oficial) permanece intacta.
-- Resultados de esta revalidación, sin anticipar PASS:
-- ../informes/evidencia_revalidacion_fnbc_modelo_canonico.md.
-- Ejecutar con psql -X -v ON_ERROR_STOP=1; el script administra su transacción.
-- ============================================================================

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'foodstore_u4_revalidacion' THEN
        RAISE EXCEPTION 'Base no autorizada para la revalidación FNBC';
    END IF;
END;
$$;

-- Precondición: exactamente dos usuarios existentes y no eliminados.
SELECT id
FROM usuario
WHERE id IN (1, 2)
  AND eliminado = FALSE;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM usuario
        WHERE id IN (1, 2) AND eliminado = FALSE) <> 2 THEN
        RAISE EXCEPTION 'Se requieren los usuarios 1 y 2 no eliminados';
    END IF;
END;
$$;

-- ============================================================================
-- ETAPA 1: Tablas maestras mínimas (soporte reproducible, no del dominio real)
-- ============================================================================

CREATE TABLE deposito (
    id BIGINT PRIMARY KEY
);

CREATE TABLE lote (
    id BIGINT PRIMARY KEY
);

INSERT INTO deposito (id) VALUES
    (30),
    (31);

INSERT INTO lote (id) VALUES
    (501),
    (502),
    (503);

-- ============================================================================
-- ETAPA 2: Relación original ControlLoteAlmacen (no está en FNBC)
-- ============================================================================
--
-- Dependencias funcionales (de la regla de negocio de la consigna, no
-- inferidas de los datos):
--
-- {LoteID, DepositoID} -> ResponsableControlID   (R1)
-- ResponsableControlID -> DepositoID              (R2)
--
-- Claves candidatas: {LoteID, DepositoID} y {LoteID, ResponsableControlID}.
-- Todos los atributos son primos (no hay atributos no primos).
--
-- Violación FNBC: ResponsableControlID -> DepositoID, porque
-- ResponsableControlID no es superclave (su clausura es
-- {ResponsableControlID, DepositoID}, no permite obtener LoteID).
-- ============================================================================

CREATE TABLE control_lote_almacen (
    lote_id BIGINT NOT NULL,
    deposito_id BIGINT NOT NULL,
    responsable_control_id BIGINT NOT NULL,

    CONSTRAINT pk_control_lote_almacen
        PRIMARY KEY (lote_id, deposito_id),

    CONSTRAINT fk_control_lote_lote
        FOREIGN KEY (lote_id)
        REFERENCES lote(id),

    CONSTRAINT fk_control_lote_deposito
        FOREIGN KEY (deposito_id)
        REFERENCES deposito(id),

    CONSTRAINT fk_control_lote_responsable
        FOREIGN KEY (responsable_control_id)
        REFERENCES usuario(id)
);

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES
    (501, 30, 1),
    (502, 30, 1),
    (503, 31, 2);

-- ============================================================================
-- ETAPA 3: Evidencia de la dependencia en los datos (diagnóstico, no prueba)
-- ============================================================================
--
-- Resultado esperado para esta instancia: 0 filas.
--
-- IMPORTANTE: 0 filas solamente demuestra que los datos actuales son
-- compatibles con la dependencia ResponsableControlID -> DepositoID.
-- No demuestra la dependencia en sí: esa regla proviene de la regla de
-- negocio de la consigna (R2 en la spec), no de esta consulta.
-- ============================================================================

SELECT
    responsable_control_id,
    COUNT(DISTINCT deposito_id) AS depositos_distintos
FROM control_lote_almacen
GROUP BY responsable_control_id
HAVING COUNT(DISTINCT deposito_id) > 1;

-- ============================================================================
-- ETAPA 4: Descomposición - tabla maestra descompuesta
-- ============================================================================
--
-- responsable_control_deposito representa ResponsableControlID ->
-- DepositoID como una tabla propia, con responsable_control_id como
-- clave primaria (por lo tanto, superclave de esta relación).
-- ============================================================================

CREATE TABLE responsable_control_deposito (
    responsable_control_id BIGINT PRIMARY KEY,
    deposito_id BIGINT NOT NULL,

    CONSTRAINT fk_responsable_control_usuario
        FOREIGN KEY (responsable_control_id)
        REFERENCES usuario(id),

    CONSTRAINT fk_responsable_control_deposito
        FOREIGN KEY (deposito_id)
        REFERENCES deposito(id)
);

-- No se usa ON CONFLICT: si un responsable_control_id apareciera
-- asociado a dos deposito_id distintos en control_lote_almacen, este
-- INSERT debe fallar por violación de la PK. Eso es intencional: significa
-- que los datos contradicen la regla de negocio R2, y la migración no
-- debe continuar silenciosamente en ese caso.
INSERT INTO responsable_control_deposito (
    responsable_control_id,
    deposito_id
)
SELECT DISTINCT
    responsable_control_id,
    deposito_id
FROM control_lote_almacen;

-- ============================================================================
-- ETAPA 5: Descomposición - tabla transaccional descompuesta
-- ============================================================================
--
-- control_lote_responsable representa la relación transaccional de
-- control (qué lote controló cada responsable), sin repetir el dato
-- maestro deposito_id.
-- ============================================================================

CREATE TABLE control_lote_responsable (
    lote_id BIGINT NOT NULL,
    responsable_control_id BIGINT NOT NULL,

    CONSTRAINT pk_control_lote_responsable
        PRIMARY KEY (lote_id, responsable_control_id),

    CONSTRAINT fk_control_lote_responsable_lote
        FOREIGN KEY (lote_id)
        REFERENCES lote(id),

    CONSTRAINT fk_control_lote_responsable_maestro
        FOREIGN KEY (responsable_control_id)
        REFERENCES responsable_control_deposito(responsable_control_id)
);

INSERT INTO control_lote_responsable (
    lote_id,
    responsable_control_id
)
SELECT DISTINCT
    lote_id,
    responsable_control_id
FROM control_lote_almacen;

-- ============================================================================
-- ETAPA 6: Vista de compatibilidad
-- ============================================================================
--
-- Reconstruye la relación original mediante JOIN sobre el atributo
-- común responsable_control_id, que es clave primaria de
-- responsable_control_deposito. Por lo tanto ese atributo es
-- superclave de una de las dos relaciones resultantes, lo que
-- garantiza que la descomposición es sin pérdida (lossless-join):
--
-- control_lote_responsable JOIN responsable_control_deposito
--     USING (responsable_control_id)
-- ============================================================================

CREATE VIEW v_control_lote_almacen AS
SELECT
    clr.lote_id,
    rcd.deposito_id,
    clr.responsable_control_id
FROM control_lote_responsable clr
JOIN responsable_control_deposito rcd
    ON rcd.responsable_control_id = clr.responsable_control_id;

-- ============================================================================
-- ETAPA 7: Verificación de conteo
-- ============================================================================
-- Resultado esperado: 3 | 3
-- ============================================================================

SELECT
    (SELECT COUNT(*) FROM control_lote_almacen) AS filas_original,
    (SELECT COUNT(*) FROM v_control_lote_almacen) AS filas_reconstruidas;

-- ============================================================================
-- ETAPA 8: Verificación de contenido - original menos vista
-- ============================================================================
-- Esta dirección detecta pérdida de filas: cualquier fila del original
-- que no aparezca reconstruida en la vista aparecería acá.
-- Resultado esperado: 0 filas.
-- ============================================================================

SELECT
    lote_id,
    deposito_id,
    responsable_control_id
FROM control_lote_almacen

EXCEPT

SELECT
    lote_id,
    deposito_id,
    responsable_control_id
FROM v_control_lote_almacen;

-- ============================================================================
-- ETAPA 9: Verificación de contenido - vista menos original
-- ============================================================================
-- Esta dirección detecta filas espurias: cualquier fila que la vista
-- reconstruya y que no exista en el original aparecería acá.
-- Resultado esperado: 0 filas.
-- ============================================================================

SELECT
    lote_id,
    deposito_id,
    responsable_control_id
FROM v_control_lote_almacen

EXCEPT

SELECT
    lote_id,
    deposito_id,
    responsable_control_id
FROM control_lote_almacen;

-- ============================================================================
-- ETAPA 10: Preservación de dependencias tras la descomposición
-- ============================================================================
--
-- ResponsableControlID -> DepositoID (R2) queda preservada localmente
-- en responsable_control_deposito: su propia PK la garantiza.
--
-- Pero {LoteID, DepositoID} -> ResponsableControlID (R1) ya NO puede
-- verificarse observando una sola tabla: control_lote_responsable no
-- tiene deposito_id, y responsable_control_deposito no tiene lote_id.
-- Reconstruir esa verificación requiere el JOIN de v_control_lote_almacen.
--
-- Esto es un costo posible de la descomposición a FNBC. NO se
-- implementa ningún trigger en este script para resolverlo: el
-- eventual mecanismo para preservar R1 (trigger, validación explícita
-- en la capa de aplicación, u otro mecanismo diseñado específicamente
-- para preservar R1) requiere una decisión explícita de ingeniería
-- posterior, documentada por separado antes de implementarse.
-- ============================================================================

-- ============================================================================
-- ETAPA 11: Aserciones de migración y equivalencia
-- ============================================================================
-- EXCEPT usa semántica de conjuntos; el control separado de duplicados evita
-- que esa semántica oculte multiplicidades indebidas en la reconstrucción.
DO $$
BEGIN
    IF EXISTS (
        SELECT responsable_control_id FROM control_lote_almacen
        GROUP BY responsable_control_id HAVING COUNT(DISTINCT deposito_id) > 1
    ) THEN
        RAISE EXCEPTION 'F2 incompatible con la instancia original';
    END IF;
    IF (SELECT COUNT(*) FROM control_lote_almacen) <> 3
       OR (SELECT COUNT(*) FROM v_control_lote_almacen) <> 3 THEN
        RAISE EXCEPTION 'Conteos de migración distintos de 3 / 3';
    END IF;
    IF EXISTS (
        SELECT * FROM control_lote_almacen EXCEPT SELECT * FROM v_control_lote_almacen
    ) OR EXISTS (
        SELECT * FROM v_control_lote_almacen EXCEPT SELECT * FROM control_lote_almacen
    ) THEN
        RAISE EXCEPTION 'EXCEPT detectó pérdida o filas espurias';
    END IF;
    IF EXISTS (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM v_control_lote_almacen
        GROUP BY lote_id, deposito_id, responsable_control_id HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'La vista contiene filas duplicadas';
    END IF;
    RAISE NOTICE 'PASS: migración 3 / 3, diagnóstico F2 = 0, EXCEPT 0 / 0, duplicados = 0';
END;
$$;

-- ============================================================================
-- ETAPA 12: Pruebas negativas reversibles
-- ============================================================================
-- Cada DO captura exclusivamente el SQLSTATE esperado y verifica además la
-- restricción concreta. Los errores inesperados abortan con ON_ERROR_STOP.
-- Las subtransacciones de EXCEPTION y los SAVEPOINT no dejan fixtures nuevos.
SAVEPOINT negativa_pk_responsable;
DO $$
DECLARE
    v_estado TEXT;
    v_restriccion TEXT;
BEGIN
    BEGIN
        INSERT INTO responsable_control_deposito VALUES (1, 31);
        RAISE EXCEPTION 'TEST FAILED: se admitió un responsable duplicado';
    EXCEPTION WHEN SQLSTATE '23505' THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion IS DISTINCT FROM 'responsable_control_deposito_pkey' THEN
            RAISE EXCEPTION 'Restricción inesperada: %', v_restriccion;
        END IF;
        RAISE NOTICE 'PASS: responsable duplicado; SQLSTATE=%; CONSTRAINT=%',
            v_estado, v_restriccion;
    END;
END;
$$;
ROLLBACK TO SAVEPOINT negativa_pk_responsable;
RELEASE SAVEPOINT negativa_pk_responsable;

SAVEPOINT negativa_fk_responsable;
DO $$
DECLARE
    v_inexistente BIGINT;
    v_estado TEXT;
    v_restriccion TEXT;
BEGIN
    SELECT MAX(responsable_control_id) + 1 INTO v_inexistente
    FROM responsable_control_deposito;
    BEGIN
        INSERT INTO control_lote_responsable VALUES (501, v_inexistente);
        RAISE EXCEPTION 'TEST FAILED: se admitió un responsable inexistente';
    EXCEPTION WHEN SQLSTATE '23503' THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion IS DISTINCT FROM 'fk_control_lote_responsable_maestro' THEN
            RAISE EXCEPTION 'Restricción inesperada: %', v_restriccion;
        END IF;
        RAISE NOTICE 'PASS: responsable inexistente; SQLSTATE=%; CONSTRAINT=%',
            v_estado, v_restriccion;
    END;
END;
$$;
ROLLBACK TO SAVEPOINT negativa_fk_responsable;
RELEASE SAVEPOINT negativa_fk_responsable;

SAVEPOINT negativa_fk_lote;
DO $$
DECLARE
    v_inexistente BIGINT;
    v_estado TEXT;
    v_restriccion TEXT;
BEGIN
    SELECT MAX(id) + 1 INTO v_inexistente FROM lote;
    BEGIN
        INSERT INTO control_lote_responsable VALUES (v_inexistente, 1);
        RAISE EXCEPTION 'TEST FAILED: se admitió un lote inexistente';
    EXCEPTION WHEN SQLSTATE '23503' THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion IS DISTINCT FROM 'fk_control_lote_responsable_lote' THEN
            RAISE EXCEPTION 'Restricción inesperada: %', v_restriccion;
        END IF;
        RAISE NOTICE 'PASS: lote inexistente; SQLSTATE=%; CONSTRAINT=%',
            v_estado, v_restriccion;
    END;
END;
$$;
ROLLBACK TO SAVEPOINT negativa_fk_lote;
RELEASE SAVEPOINT negativa_fk_lote;

SAVEPOINT negativa_fk_deposito;
-- Liberar el responsable 2 solamente dentro del SAVEPOINT aísla la FK de
-- depósito sin provocar antes un duplicado de PK ni crear otro usuario.
DELETE FROM control_lote_responsable WHERE responsable_control_id = 2;
DELETE FROM responsable_control_deposito WHERE responsable_control_id = 2;
DO $$
DECLARE
    v_inexistente BIGINT;
    v_estado TEXT;
    v_restriccion TEXT;
BEGIN
    SELECT MAX(id) + 1 INTO v_inexistente FROM deposito;
    BEGIN
        INSERT INTO responsable_control_deposito VALUES (2, v_inexistente);
        RAISE EXCEPTION 'TEST FAILED: se admitió un depósito inexistente';
    EXCEPTION WHEN SQLSTATE '23503' THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE,
                                v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion IS DISTINCT FROM 'fk_responsable_control_deposito' THEN
            RAISE EXCEPTION 'Restricción inesperada: %', v_restriccion;
        END IF;
        RAISE NOTICE 'PASS: depósito inexistente; SQLSTATE=%; CONSTRAINT=%',
            v_estado, v_restriccion;
    END;
END;
$$;
ROLLBACK TO SAVEPOINT negativa_fk_deposito;
RELEASE SAVEPOINT negativa_fk_deposito;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM responsable_control_deposito) <> 2
       OR (SELECT COUNT(*) FROM control_lote_responsable) <> 3
       OR EXISTS (SELECT * FROM control_lote_almacen
                  EXCEPT SELECT * FROM v_control_lote_almacen)
       OR EXISTS (SELECT * FROM v_control_lote_almacen
                  EXCEPT SELECT * FROM control_lote_almacen) THEN
        RAISE EXCEPTION 'Las pruebas negativas no restauraron la instancia';
    END IF;
    RAISE NOTICE 'PASS: instancia conservada después de las cuatro pruebas negativas';
END;
$$;

COMMIT;

-- ============================================================================
-- PLAN DE REVERSIÓN / DOWN
-- ============================================================================
--
-- Los siguientes DROP NO se ejecutan automáticamente. Se documentan
-- para revertir manualmente, en este orden, exclusivamente los objetos
-- creados por esta práctica (sin CASCADE):
--
-- BEGIN;
-- DO $$
-- BEGIN
--     IF current_database() <> 'foodstore_u4_revalidacion' THEN
--         RAISE EXCEPTION 'Base no autorizada para DOWN FNBC';
--     END IF;
-- END;
-- $$;
-- DROP VIEW v_control_lote_almacen;
-- DROP TABLE control_lote_responsable;
-- DROP TABLE responsable_control_deposito;
-- DROP TABLE control_lote_almacen;
-- DROP TABLE lote;
-- DROP TABLE deposito;
-- COMMIT;
-- usuario pertenece al modelo base y no forma parte del DOWN.
--
-- Esta fase usa exclusivamente el laboratorio descartable autorizado.
-- Comparar el snapshot previo/posterior del catálogo y de los datos canónicos:
-- cinco tablas base y seis índices explícitos raíz + TP5 deben seguir intactos.
-- No restaurar dumps históricos ni ejecutar otros DOWN de Unidad 4.
-- ============================================================================
