-- ============================================================================
-- tp_fnbc_control_lote.sql
-- Base de Datos II - Unidad 4, Parte 1: FNBC - ControlLoteAlmacen
-- Especificación: ../specs/u4_fnbc_control_lote.md
-- ============================================================================
-- Diseñado para ejecutarse una única vez sobre la copia foodstore_u4.
-- No usa IDENTITY, IF NOT EXISTS, ON CONFLICT ni CASCADE: si algún
-- objeto ya existe o los datos violan una regla de negocio necesaria,
-- el script debe fallar de forma visible, no ocultar el problema.
--
-- El schema.sql real del proyecto Food Store NO contiene lote,
-- deposito ni usuario. La consigna académica las supone existentes.
-- Este script crea versiones mínimas de esas tres tablas (solo id)
-- exclusivamente para que este TP sea reproducible desde GitHub sobre
-- una copia de la base, sin modificar schema.sql ni inventar columnas
-- o reglas de negocio adicionales.
-- ============================================================================

BEGIN;

-- ============================================================================
-- ETAPA 1: Tablas maestras mínimas (soporte reproducible, no del dominio real)
-- ============================================================================

CREATE TABLE deposito (
    id BIGINT PRIMARY KEY
);

CREATE TABLE usuario (
    id BIGINT PRIMARY KEY
);

CREATE TABLE lote (
    id BIGINT PRIMARY KEY
);

INSERT INTO deposito (id) VALUES
    (30),
    (31);

INSERT INTO usuario (id) VALUES
    (801),
    (802);

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
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

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

COMMIT;

-- ============================================================================
-- PLAN DE REVERSIÓN / DOWN
-- ============================================================================
--
-- Los siguientes DROP NO se ejecutan automáticamente. Se documentan
-- para revertir manualmente, en este orden, exclusivamente los objetos
-- creados por esta práctica (sin CASCADE):
--
-- 1. DROP VIEW v_control_lote_almacen;
-- 2. DROP TABLE control_lote_responsable;
-- 3. DROP TABLE responsable_control_deposito;
-- 4. DROP TABLE control_lote_almacen;
-- 5. DROP TABLE lote;
-- 6. DROP TABLE usuario;
-- 7. DROP TABLE deposito;
--
-- Alternativamente, existe un backup externo tomado antes de iniciar
-- esta práctica:
--
-- backups/foodstore_u4_pre_u4.dump
--
-- Ese dump no debe versionarse en Git.
-- ============================================================================
