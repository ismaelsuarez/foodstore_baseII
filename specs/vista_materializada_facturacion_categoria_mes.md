# Spec: vista_materializada_facturacion_categoria_mes

## Objetivo

Crear una vista materializada para acelerar el reporte agregado de

facturación por categoría y mes sobre foodstore_tp5.

La vista materializada almacenará físicamente el resultado del reporte

analítico para evitar recalcular en cada consulta los JOIN, el

COUNT(DISTINCT), las sumatorias y el GROUP BY sobre las tablas base.

## Nombre esperado

mv_facturacion_categoria_mes

## Tablas involucradas

- categoria

- producto

- detalle_pedido

- pedido

## Esquema real utilizado

categoria:

- id

- nombre

- activo

producto:

- id

- categoria_id

- activo

detalle_pedido:

- pedido_id

- producto_id

- cantidad

- precio_unitario

pedido:

- id

- fecha

No inventar columnas.

## Consulta original que se materializa

SELECT

    c.id AS categoria_id,

    c.nombre AS categoria_nombre,

    DATE_TRUNC('month', pe.fecha) AS mes,

    COUNT(DISTINCT pe.id) AS cantidad_pedidos,

    SUM(dp.cantidad) AS unidades_vendidas,

    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total

FROM categoria c

JOIN producto pr

    ON pr.categoria_id = c.id

JOIN detalle_pedido dp

    ON dp.producto_id = pr.id

JOIN pedido pe

    ON pe.id = dp.pedido_id

WHERE c.activo = TRUE

  AND pr.activo = TRUE

GROUP BY

    c.id,

    c.nombre,

    DATE_TRUNC('month', pe.fecha);

## Semántica

La vista materializada debe preservar exactamente la semántica del

reporte original utilizado en TP4.

Por lo tanto debe conservar:

- categoria.activo = TRUE

- producto.activo = TRUE

No modificar la regla de negocio en esta etapa.

La materialización es una optimización de almacenamiento del resultado,

no un rediseño semántico del reporte.

## Columnas de la vista materializada

- categoria_id

- categoria_nombre

- mes

- cantidad_pedidos

- unidades_vendidas

- facturacion_total

## Clave lógica del resultado

Cada fila representa una combinación única de:

categoria_id + mes

Por lo tanto el índice UNIQUE esperado debe utilizar:

(categoria_id, mes)

## Vista materializada esperada

La implementación posterior deberá utilizar:

CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes

AS

...

WITH DATA;

WITH DATA es obligatorio porque la vista debe quedar poblada desde su

creación para permitir las mediciones posteriores.

## Índice único esperado

La implementación posterior deberá crear un índice UNIQUE sobre:

mv_facturacion_categoria_mes (categoria_id, mes)

El propósito de este índice es permitir posteriormente:

REFRESH MATERIALIZED VIEW CONCURRENTLY

    mv_facturacion_categoria_mes;

No agregar columnas innecesarias al índice.

## Criterio de equivalencia

Después de crear la vista materializada con WITH DATA, su contenido debe

ser semánticamente equivalente a la consulta original.

Se deberá verificar manualmente mediante EXCEPT en ambos sentidos:

original_minus_materialized = 0

materialized_minus_original = 0

## Medición de rendimiento

La consulta original y la consulta sobre la vista materializada deberán

medirse manualmente mediante:

EXPLAIN (ANALYZE, BUFFERS)

Protocolo:

- ejecutar 3 veces la consulta original;

- considerar la primera ejecución como calentamiento;

- promediar las ejecuciones 2 y 3;

- ejecutar 3 veces la consulta sobre la vista materializada;

- considerar la primera ejecución como calentamiento;

- promediar las ejecuciones 2 y 3;

- documentar plan, Execution Time y buffers reales;

- no inventar valores.

Para consultar la vista materializada se utilizará:

SELECT

    categoria_id,

    categoria_nombre,

    mes,

    cantidad_pedidos,

    unidades_vendidas,

    facturacion_total

FROM mv_facturacion_categoria_mes

ORDER BY

    mes ASC,

    facturacion_total DESC;

Para la comparación temporal, la consulta original deberá utilizar el

mismo ORDER BY:

ORDER BY

    mes ASC,

    facturacion_total DESC;

## Política de REFRESH propuesta

Frecuencia inicial propuesta:

cada 60 minutos mientras el sistema se encuentre en operación.

Motivo:

es un reporte agregado para análisis y gestión, no una fuente

transaccional utilizada para confirmar una venta individual.

Una actualización cada 60 minutos reduce significativamente el costo de

recalcular el reporte en cada lectura y mantiene una antigüedad máxima

esperada de aproximadamente una hora.

También debe poder ejecutarse manualmente un refresh cuando sea

necesario disponer de información actualizada antes del próximo ciclo.

## Staleness / dato no actualizado

La vista materializada NO se actualiza automáticamente cuando se

insertan nuevos pedidos o detalles.

Entre dos refresh, los usuarios pueden observar información atrasada.

Con una política cada 60 minutos, una venta nueva podría tardar hasta

aproximadamente una hora en verse reflejada en el reporte.

Esto debe documentarse expresamente y no debe presentarse la vista

materializada como información transaccional en tiempo real.

## REFRESH esperado a futuro

Después de que exista el índice UNIQUE adecuado:

REFRESH MATERIALIZED VIEW CONCURRENTLY

    mv_facturacion_categoria_mes;

El uso de CONCURRENTLY busca permitir consultas sobre la vista mientras

se realiza el refresh.

No ejecutar el REFRESH desde Kiro ni desde OpenCode en esta etapa.

## Restricciones

- PostgreSQL 17.

- No modificar tablas base.

- No inventar columnas.

- No modificar las tres vistas convencionales existentes.

- No agregar filtros distintos de la consulta original.

- No cambiar COUNT(DISTINCT pe.id).

- No cambiar las expresiones SUM.

- No eliminar DATE_TRUNC.

- No crear triggers para mantener la vista.

- No simular actualización automática.

- No ejecutar SQL.

- No inventar tiempos ni planes de ejecución.

- No afirmar una mejora de rendimiento antes de medirla.

- No reutilizar como medición del TP5 los tiempos obtenidos en TP4.

## Entrega esperada en la siguiente etapa

Este archivo será entregado a OpenCode.

OpenCode deberá generar posteriormente:

1. CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes ... WITH DATA;

2. CREATE UNIQUE INDEX sobre (categoria_id, mes);

La implementación podrá agregarse a views.sql o a un archivo separado

materializadas.sql, según la decisión posterior del estudiante.

No debe ejecutar SQL.
