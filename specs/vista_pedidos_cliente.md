# Spec: vista_pedidos_cliente

## Objetivo

Crear una vista para consultar pedidos junto con los datos mínimos

necesarios del cliente asociado en foodstore_tp5.

La vista debe simplificar los reportes y aplicar un criterio explícito

de minimización de datos.

## Nombre esperado

v_pedidos_cliente

## Tablas involucradas

pedido

cliente

## Contexto del esquema real

La consigna teórica original menciona usuario y una columna contraseña.

Nuestro esquema real NO contiene:

- usuario

- contraseña

- password

La tabla equivalente del dominio actual es:

cliente

con las columnas:

- id

- nombre

- email

- telefono

- created_at

No inventar columnas inexistentes.

## Columnas a exponer

- pedido_id

- fecha

- forma_pago

- cliente_id

- cliente_nombre

- cliente_email

## Columnas que NO deben exponerse

- cliente.telefono

- cliente.created_at

Motivo:

aplicar minimización de datos para reportes.

El reporte necesita identificar al cliente y disponer de su email,

pero no necesita exponer teléfono ni metadatos internos.

No existe contraseña en el esquema real, por lo que no puede

documentarse como columna ocultada físicamente.

## Relación

pedido.cliente_id = cliente.id

## Regla de negocio

Todos los pedidos válidos tienen un cliente existente debido a la

clave foránea.

No agregar filtros de vigencia porque cliente no posee columna activo

ni eliminado en el esquema real.

La vista representa historial de pedidos, no solamente clientes

considerados "vigentes".

## Consulta manual equivalente esperada

SELECT

    p.id AS pedido_id,

    p.fecha,

    p.forma_pago,

    c.id AS cliente_id,

    c.nombre AS cliente_nombre,

    c.email AS cliente_email

FROM pedido p

JOIN cliente c

    ON c.id = p.cliente_id;

## Criterio de aceptación

Después de crear la vista:

SELECT * FROM v_pedidos_cliente

debe ser semánticamente equivalente a la consulta manual anterior.

Verificar mediante EXCEPT en ambos sentidos:

manual_minus_view = 0

view_minus_manual = 0

## Seguridad y minimización

Esta vista debe documentarse como la vista de la Parte B que aplica

minimización de información.

No afirmar que oculta una contraseña, porque esa columna no existe

en nuestro esquema.

Sí documentar expresamente que:

- no expone telefono;

- no expone created_at;

- expone únicamente los datos de cliente necesarios para el reporte.

## Restricciones

- PostgreSQL 17.

- No modificar tablas base.

- No inventar columnas.

- No agregar total, estado, usuario_id, activo o eliminado:

  esas columnas no existen en pedido/cliente según corresponda.

- No agregar filtros no especificados.

- No usar materialized view.

- No afirmar mejora de rendimiento por usar una vista.

- Usar JOIN normal, porque pedido.cliente_id es obligatorio y tiene FK.

## Entrega esperada

Este archivo será entregado a OpenCode.

OpenCode deberá agregar únicamente la definición SQL de:

v_pedidos_cliente

a views.sql.

No debe ejecutar SQL.
