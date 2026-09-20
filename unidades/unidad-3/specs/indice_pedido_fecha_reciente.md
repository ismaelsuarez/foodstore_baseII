# Spec: indice_pedido_fecha_reciente

## Objetivo

Optimizar la consulta frecuente de pedidos recientes sobre

foodstore_tp5.

La consulta representa un listado operativo consultado por un usuario

mientras espera frente a la aplicación.

## Consulta afectada

SELECT

    id,

    cliente_id,

    fecha,

    forma_pago

FROM pedido

WHERE fecha >= TIMESTAMPTZ '2026-04-11 12:00:00-03'

ORDER BY fecha DESC;

## Volumen actual

Tabla pedido:

200.005 filas.

Resultado real:

1.280 filas.

Fracción devuelta:

≈0,64 %.

El filtro es altamente selectivo.

## Plan base medido

Plan actual:

Seq Scan on pedido

+

Sort

Filas reales:

1.280

Filas descartadas:

198.725

Buffers del Seq Scan:

shared hit=1471

Ordenamiento:

Sort Key: fecha DESC

Sort Method: quicksort

Memory: 109kB

## Mediciones de línea base

Primera ejecución, descartada como calentamiento:

8.059 ms

Segunda ejecución:

13.983 ms

Tercera ejecución:

11.778 ms

Promedio estable de ejecuciones 2 y 3:

12.8805 ms

## Columnas involucradas

Filtro:

- fecha

ORDER BY:

- fecha DESC

SELECT:

- id

- cliente_id

- fecha

- forma_pago

## Índices existentes relevantes en pedido

pedido_pkey (id)

idx_pedido_cliente (cliente_id)

idx_pedido_forma_pago_fecha (forma_pago, fecha DESC)

## Observación importante

Existe:

idx_pedido_forma_pago_fecha (forma_pago, fecha DESC)

pero el plan real sigue usando Seq Scan para esta consulta que filtra

solo por fecha.

La futura propuesta debe analizar la regla del prefijo izquierdo:

fecha es la segunda columna del índice existente y forma_pago no aparece

en el filtro.

No asumir redundancia ni utilidad únicamente por compartir la columna

fecha: justificarlo mediante el plan real.

## Restricciones de diseño

- PostgreSQL 17.

- No modificar tablas ni restricciones.

- No crear ningún índice todavía.

- Evitar sobreindexación.

- Evaluar B-tree.

- Evaluar si corresponde índice simple o cubridor.

- Evaluar si el ORDER BY fecha DESC puede ser satisfecho directamente

  por el índice.

- Si se pretende Index Only Scan, todas las columnas proyectadas deben

  estar explícitamente disponibles como clave o INCLUDE.

- No inventar columnas que no existen en nuestro modelo real.

- No utilizar estado ni eliminado: esas columnas no existen en pedido.

## Criterios de aceptación

La futura propuesta solo será aceptada si, después de crearla en

foodstore_tp5:

1. el Seq Scan completo desaparece o se demuestra una estrategia

   claramente más eficiente;

2. disminuyen los buffers;

3. baja el Execution Time estable;

4. se elimina el Sort si el índice puede entregar fecha DESC;

5. no duplica capacidad de un índice existente;

6. el beneficio compensa el costo de escritura y almacenamiento.

La medición posterior se hará mediante:

EXPLAIN (ANALYZE, BUFFERS)

ejecutado tres veces, descartando la primera.

## Entrega esperada en la siguiente etapa

Este archivo será entregado a OpenCode.

OpenCode deberá proponer exactamente UN índice candidato principal y

explicar:

- tipo;

- columnas clave;

- orden;

- INCLUDE, si corresponde;

- relación con idx_pedido_forma_pago_fecha;

- nodo esperado antes;

- nodo esperado después;

- impacto sobre INSERT;

- impacto sobre UPDATE fecha;

- impacto sobre UPDATE cliente_id;

- impacto sobre UPDATE forma_pago.

No debe ejecutar SQL.
