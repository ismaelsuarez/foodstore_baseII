# Spec: vista_detalle_pedido_producto

## Objetivo

Crear una vista para consultar el detalle de cada pedido junto con

el nombre del producto asociado en foodstore_tp5.

La vista debe evitar repetir manualmente el JOIN entre detalle_pedido

y producto en los reportes operativos.

## Nombre esperado

v_detalle_pedido_producto

## Tablas involucradas

detalle_pedido

producto

## Columnas reales involucradas

detalle_pedido:

- pedido_id

- producto_id

- cantidad

- precio_unitario

producto:

- id

- nombre

No inventar columnas inexistentes.

## Columnas a exponer

- pedido_id

- producto_id

- producto_nombre

- cantidad

- precio_unitario

- subtotal

## Columna calculada

subtotal debe calcularse como:

cantidad * precio_unitario

El subtotal representa el importe de esa línea del pedido.

No existe una columna subtotal física en detalle_pedido.

Debe calcularse únicamente dentro de la vista.

## Relación

detalle_pedido.producto_id = producto.id

## Regla de negocio

La vista debe representar todas las líneas históricas de pedido.

NO filtrar por producto.activo.

Motivo:

un pedido histórico debe continuar mostrando el producto asociado

aunque ese producto posteriormente sea marcado como inactivo.

No agregar filtros de vigencia, estado o eliminación.

## Consulta manual equivalente esperada

SELECT

    dp.pedido_id,

    dp.producto_id,

    p.nombre AS producto_nombre,

    dp.cantidad,

    dp.precio_unitario,

    dp.cantidad * dp.precio_unitario AS subtotal

FROM detalle_pedido dp

JOIN producto p

    ON p.id = dp.producto_id;

## Criterio de aceptación

Después de crear la vista:

SELECT * FROM v_detalle_pedido_producto

debe ser semánticamente equivalente a la consulta manual anterior.

Verificar mediante EXCEPT en ambos sentidos:

manual_minus_view = 0

view_minus_manual = 0

## Restricciones

- PostgreSQL 17.

- No modificar tablas base.

- No inventar columnas.

- No agregar total del pedido.

- No agregar cliente.

- No agregar categoria.

- No agregar fecha.

- No agregar filtros no especificados.

- No usar materialized view.

- No afirmar que una vista mejora rendimiento.

- Usar JOIN normal entre detalle_pedido y producto.

- Mantener el cálculo subtotal exactamente como:

  cantidad * precio_unitario.

## Entrega esperada

Este archivo será entregado a OpenCode.

OpenCode deberá agregar únicamente la definición SQL de:

v_detalle_pedido_producto

a views.sql.

No debe ejecutar SQL.
