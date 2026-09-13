# Spec: indice_producto_stock_bajo

## Objetivo

Optimizar la consulta frecuente del panel de productos con stock bajo

sobre la base foodstore_tp5.

La consulta representa un listado del camino crítico, consultado por un

usuario mientras espera frente a la aplicación.

## Consulta afectada

SELECT

    id,

    nombre,

    stock,

    precio

FROM producto

WHERE activo = TRUE

  AND stock <= 5

ORDER BY stock ASC, nombre ASC;

## Volumen actual

Tabla producto:

50.003 filas.

Productos activos:

50.003.

Productos inactivos:

0.

Resultado de la consulta:

1.493 filas.

Selectividad aproximada:

2,99 %.

## Plan base medido

Plan actual:

Seq Scan on producto

Filas reales:

1.493

Filas descartadas:

48.510

Buffers del Seq Scan:

shared hit=900

Ordenamiento:

Sort Method: quicksort

Memory: 130kB

## Mediciones de línea base

Primera ejecución, descartada como calentamiento:

12.195 ms

Segunda ejecución:

9.694 ms

Tercera ejecución:

10.366 ms

Promedio estable de ejecuciones 2 y 3:

10.030 ms

## Columnas involucradas

Filtro:

- activo

- stock

ORDER BY:

- stock ASC

- nombre ASC

SELECT:

- id

- nombre

- stock

- precio

## Índices existentes relevantes

producto_pkey (id)

idx_producto_categoria (categoria_id)

idx_producto_nombre (nombre)

idx_producto_precio_desc (precio DESC)

No existe actualmente un índice cuya primera clave sea stock.

## Restricciones de diseño

- PostgreSQL 17.

- No modificar tablas ni restricciones.

- No crear el índice todavía.

- Evitar índices redundantes.

- No usar activo como clave principal solamente por aparecer en el filtro,

  ya que es booleano y de baja cardinalidad.

- Se puede evaluar activo = TRUE como condición de índice parcial, pero

  debe reconocerse que en el conjunto de datos actual todos los productos

  están activos, por lo que hoy esa condición no reduce físicamente el

  número de entradas.

- Evaluar B-tree, índice compuesto, parcial y/o INCLUDE.

- Si se propone un índice cubridor, recordar que el heap TID interno no

  reemplaza las columnas proyectadas por la consulta: id debe estar

  disponible explícitamente como clave o INCLUDE si se pretende un

  Index Only Scan.

- Justificar el orden de las columnas.

## Criterios de aceptación

La propuesta futura solo será aceptada si después de crearla en

foodstore_tp5:

1. el plan mejora respecto del Seq Scan actual;

2. disminuyen los buffers;

3. baja el Execution Time estable;

4. no duplica un índice existente;

5. el beneficio de lectura compensa el costo de escritura y almacenamiento.

La medición posterior se hará con:

EXPLAIN (ANALYZE, BUFFERS)

ejecutado tres veces y descartando la primera.

## Entrega esperada en la siguiente etapa

Este archivo será entregado a OpenCode.

OpenCode deberá proponer exactamente un índice candidato principal y

justificar:

- tipo;

- columnas;

- orden;

- condición parcial, si corresponde;

- INCLUDE, si corresponde;

- nodo del plan que espera cambiar;

- costo sobre INSERT y UPDATE.

Kiro no debe generar ahora el CREATE INDEX.
