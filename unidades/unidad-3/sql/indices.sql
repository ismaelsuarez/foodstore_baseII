-- Base de Datos II - Unidad 3 / Semana 5 - TP5
-- Requiere el modelo oficial indicado en las specs de este bloque.
-- No migra tablas ni acredita compatibilidad con schema.sql de la raíz.
-- Definiciones no ejecutadas en este bloque; validación real pendiente.
-- Instalación futura en una copia con el modelo oficial y sin estos objetos.
-- Si ya existen índices homónimos, evaluar sus definiciones antes de instalar.
-- No se incluyen DROP, mediciones ni resultados de ejecuciones anteriores.

-- CANDIDATO_PENDIENTE_DE_MEDICION
-- Spec: ../specs/indice_producto_stock_bajo.md
-- El panel incluye productos no disponibles que pueden requerir reposición.
-- Las claves siguen el filtro/orden; INCLUDE es una hipótesis de cobertura.
CREATE INDEX idx_producto_stock_bajo
    ON producto (stock ASC, nombre ASC)
    INCLUDE (id, precio)
    WHERE eliminado = FALSE;

-- CANDIDATO_PENDIENTE_DE_MEDICION
-- Spec: ../specs/indice_pedido_fecha_reciente.md
-- Fecha DATE; sin valores supuestos para estado o forma_pago.
-- INCLUDE está sujeto a EXPLAIN (ANALYZE, BUFFERS) y costo de escritura.
CREATE INDEX idx_pedido_fecha_reciente
    ON pedido (fecha DESC)
    INCLUDE (id, usuario_id, estado, forma_pago, total)
    WHERE eliminado = FALSE;

-- CANDIDATO_PENDIENTE_DE_MEDICION
-- Spec: ../specs/indice_usuario_mail_lower.md
-- Índice de expresión no UNIQUE: no establece unicidad case-insensitive.
-- Una eventual restricción UNIQUE(mail) no equivale a lower(mail).
CREATE INDEX idx_usuario_mail_lower
    ON usuario (lower(mail))
    WHERE eliminado = FALSE;