# Spec: vista_productos_vigentes

## Objetivo

Crear una vista para consultar productos vigentes junto con los datos

básicos de su categoría en foodstore_tp5.

La vista debe encapsular una regla única y consistente de vigencia para

el catálogo.

## Nombre esperado

v_productos_vigentes

## Tablas involucradas

producto

categoria

## Regla de vigencia

Un producto debe aparecer únicamente cuando:

producto.activo = TRUE

y además:

categoria.activo = TRUE

La decisión es explícita:

si una categoría queda inactiva, sus productos dejan de aparecer en la

vista aunque el registro de producto siga teniendo activo = TRUE.

## Columnas a exponer

- producto_id

- producto_nombre

- descripcion

- precio

- stock

- categoria_id

- categoria_nombre

No exponer:

- created_at de producto

- created_at de categoria

- columnas internas innecesarias para el reporte

## Relación

producto.categoria_id = categoria.id

## Consulta manual equivalente esperada

SELECT

    p.id AS producto_id,

    p.nombre AS producto_nombre,

    p.descripcion,

    p.precio,

    p.stock,

    c.id AS categoria_id,

    c.nombre AS categoria_nombre

FROM producto p

JOIN categoria c

    ON c.id = p.categoria_id

WHERE p.activo = TRUE

  AND c.activo = TRUE;

## Criterio de aceptación

Después de crear la vista:

SELECT * FROM v_productos_vigentes

debe ser semánticamente equivalente a la consulta manual anterior.

La equivalencia debe verificarse mediante EXCEPT en ambos sentidos:

manual_minus_view = 0

view_minus_manual = 0

## Restricciones

- PostgreSQL 17.

- No modificar las tablas base.

- No inventar columnas.

- No agregar filtros que no estén documentados.

- No usar materialized view en esta etapa.

- No afirmar que una vista mejora rendimiento.

- La vista es un mecanismo de encapsulamiento y consistencia de criterio,

  no una optimización por sí misma.

## Entrega esperada en la siguiente etapa

Este archivo será entregado a OpenCode.

OpenCode deberá generar solamente la definición SQL de:

v_productos_vigentes

No debe ejecutar SQL.
