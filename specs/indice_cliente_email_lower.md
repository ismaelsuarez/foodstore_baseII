# Spec: indice_cliente_email_lower

## Objetivo

Optimizar la búsqueda de clientes por correo electrónico sin distinguir

mayúsculas y minúsculas sobre foodstore_tp5.

La consulta representa una búsqueda puntual de cliente y forma parte

del camino crítico de autenticación/identificación.

## Consulta afectada

SELECT

    id,

    nombre,

    email

FROM cliente

WHERE lower(email) = lower('ANA.GOMEZ@FOODSTORE.TEST');

## Volumen actual

Tabla cliente:

20.003 filas.

Resultado real:

1 fila.

Fracción devuelta:

≈0,005 %.

El filtro es extremadamente selectivo.

## Plan base medido

Plan actual:

Seq Scan on cliente

Filas reales:

1

Filas descartadas:

20.002

Buffers:

shared hit=267

Filtro:

lower(email) = 'ana.gomez@foodstore.test'

## Mediciones de línea base

Primera ejecución, descartada como calentamiento:

10.440 ms

Segunda ejecución:

10.322 ms

Tercera ejecución:

10.222 ms

Promedio estable de ejecuciones 2 y 3:

10.272 ms

## Columnas involucradas

Filtro:

- lower(email)

SELECT:

- id

- nombre

- email

## Índices existentes relevantes

cliente_pkey (id)

cliente_email_key (email)

## Observación importante

Existe un índice UNIQUE sobre:

email

pero la consulta aplica:

lower(email)

El plan real sigue usando Seq Scan.

La futura propuesta debe analizar explícitamente por qué un índice común

sobre email no puede resolver directamente una condición sobre

lower(email).

Debe evaluarse un índice de expresión.

## Restricciones de diseño

- PostgreSQL 17.

- No modificar tablas ni restricciones.

- No crear ningún índice todavía.

- Evitar sobreindexación.

- Evaluar B-tree de expresión.

- La expresión indexada debe coincidir con la usada por la consulta.

- No asumir que cliente_email_key es redundante:

  el índice UNIQUE sobre email sigue protegiendo la unicidad exacta y

  sirve para búsquedas case-sensitive.

- Evaluar si corresponde incluir columnas adicionales mediante INCLUDE.

- Si se pretende Index Only Scan, todas las columnas proyectadas deben

  estar disponibles explícitamente en el índice.

- Analizar el costo adicional de mantener dos índices relacionados con

  email.

- Analizar si el índice de expresión debería ser UNIQUE o no.

- No cambiar la semántica actual de la restricción UNIQUE existente

  sin una decisión explícita de negocio.

## Criterios de aceptación

La futura propuesta solo será aceptada si:

1. desaparece el Seq Scan o se obtiene una estrategia claramente más

   eficiente;

2. disminuyen los buffers;

3. baja el Execution Time estable;

4. el índice realmente usa lower(email);

5. no reemplaza ni invalida injustificadamente cliente_email_key;

6. el beneficio compensa el costo adicional de escritura y almacenamiento.

La medición posterior se hará con:

EXPLAIN (ANALYZE, BUFFERS)

ejecutado tres veces, descartando la primera.

## Entrega esperada en la siguiente etapa

Este archivo será entregado a OpenCode.

OpenCode deberá proponer exactamente UN índice candidato principal y

explicar:

- tipo;

- expresión;

- si debe ser UNIQUE o no;

- INCLUDE, si corresponde;

- relación con cliente_email_key;

- nodo esperado antes;

- nodo esperado después;

- impacto sobre INSERT;

- impacto sobre UPDATE email.

No debe ejecutar SQL.
