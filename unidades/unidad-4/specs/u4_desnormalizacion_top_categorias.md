# Spec — Unidad 4 — Desnormalización controlada — Top categorías

## 1. Contexto real del proyecto

El TP de Unidad 4 solicita optimizar el reporte:

Top 5 categorías por monto vendido en el día.

La consigna teórica utiliza:

dp.subtotal

dp.eliminado

ped.eliminado

CURRENT_DATE

Pero el schema.sql REAL de este repositorio contiene:

detalle_pedido(

    pedido_id,

    producto_id,

    cantidad,

    precio_unitario

)

pedido(

    id,

    cliente_id,

    fecha,

    forma_pago

)

No existen:

- detalle_pedido.subtotal

- detalle_pedido.eliminado

- pedido.eliminado

Por lo tanto, NO inventar esas columnas.

El subtotal real utilizado debe ser:

dp.cantidad * dp.precio_unitario

## 2. Adaptación temporal documentada

La copia de trabajo es:

foodstore_u4

Fecha actual durante la práctica:

2026-09-19

Rango real de pedido.fecha en el dataset:

2026-03-01 a 2026-04-11

Pedidos con CURRENT_DATE:

0

Por lo tanto, para obtener una medición representativa se utiliza

el último día existente en el dataset:

2026-04-11

Como pedido.fecha es TIMESTAMPTZ, utilizar:

ped.fecha >= DATE '2026-04-11'

AND ped.fecha < DATE '2026-04-12'

No usar igualdad contra TIMESTAMPTZ.

Para ese día se verificó:

pedidos: 4160

detalles: 10400

## 3. Consulta normalizada baseline

La consulta real medida fue:

SELECT

    c.nombre AS categoria,

    SUM(dp.cantidad * dp.precio_unitario) AS total_vendido

FROM detalle_pedido dp

JOIN producto pr

    ON pr.id = dp.producto_id

JOIN categoria c

    ON c.id = pr.categoria_id

JOIN pedido ped

    ON ped.id = dp.pedido_id

WHERE ped.fecha >= DATE '2026-04-11'

  AND ped.fecha < DATE '2026-04-12'

GROUP BY c.nombre

ORDER BY total_vendido DESC

LIMIT 5;

## 4. Mediciones baseline reales

Se ejecutó EXPLAIN (ANALYZE, BUFFERS) cinco veces.

Execution Time:

1. 234.451 ms

2. 369.073 ms

3. 231.651 ms

4. 239.969 ms

5. 266.980 ms

Debido a variabilidad del entorno, conservar las cinco mediciones

y utilizar la mediana como valor representativo:

MEDIANA BASELINE = 239.969 ms

No ocultar la ejecución de 369.073 ms.

## 5. Diagnóstico del plan

El plan fue estructuralmente consistente.

Elementos principales:

Parallel Seq Scan sobre detalle_pedido

Parallel Seq Scan sobre pedido

Parallel Hash Join entre detalle_pedido y pedido

Nested Loop hacia producto

Index Scan using producto_pkey

Para el día medido:

- 4160 pedidos

- 10400 detalles

- producto_pkey se ejecuta aproximadamente 10400 veces

- buffers totales aproximados: 36400

- producto_pkey acumula aproximadamente 31200 buffers

El Sort final utiliza quicksort y aproximadamente 25 kB.

Por lo tanto:

El Sort NO es el cuello de botella principal.

La evidencia medida muestra que una parte importante del costo está

en el subárbol de JOIN y especialmente en las búsquedas repetidas de

producto necesarias exclusivamente para obtener producto.categoria_id.

## 6. Decisión de desnormalización

Patrón elegido:

Columna redundante derivada mantenida por triggers.

Agregar posteriormente a:

detalle_pedido

la columna:

categoria_id BIGINT

Fuente de verdad:

producto.categoria_id

Objetivo:

Evitar el JOIN detalle_pedido -> producto en el reporte frecuente.

NO eliminar producto.categoria_id.

NO cambiar la fuente de verdad.

NO modificar schema.sql.

El cambio debe vivir exclusivamente en:

tp_desnormalizacion_top_categorias.sql

## 7. Por qué no se elige vista materializada

Una vista materializada sería eficiente para lectura, pero introduce

staleness entre refresh.

El escenario describe un panel de actualización frecuente.

La columna redundante mantenida por triggers permite mantener

sincronización inmediata con la fuente de verdad y elimina precisamente

el JOIN identificado como costoso en la medición.

No afirmar que una vista materializada sea incorrecta:

simplemente no es el patrón elegido para este caso.

## 8. Estrategia de migración

La migración debe realizarse en transacción.

Orden:

1. ALTER TABLE detalle_pedido ADD COLUMN categoria_id BIGINT;

2. Backfill:

UPDATE detalle_pedido dp

SET categoria_id = pr.categoria_id

FROM producto pr

WHERE pr.id = dp.producto_id;

3. Verificar que no queden NULL.

4. Agregar NOT NULL.

5. Agregar FOREIGN KEY hacia categoria(id).

6. Crear función trigger para nuevas filas y cambios de producto_id.

7. Crear trigger BEFORE INSERT OR UPDATE OF producto_id

   sobre detalle_pedido.

8. Crear mecanismo para mantener sincronizados los detalles existentes

   si cambia producto.categoria_id.

## 9. Sincronización obligatoria

Se requieren DOS caminos de sincronización.

A. detalle_pedido -> producto

Antes de INSERT o UPDATE OF producto_id en detalle_pedido:

buscar producto.categoria_id y asignarlo a NEW.categoria_id.

La aplicación NO debe ser la responsable de decidir categoria_id.

B. producto -> detalle_pedido

Si producto.categoria_id cambia:

actualizar detalle_pedido.categoria_id en todas las filas cuyo

producto_id corresponda al producto modificado.

Esto es necesario para conservar equivalencia con la consulta

normalizada original, que siempre utiliza el categoria_id actual

de producto.

Evitar recursión accidental de triggers.

## 10. Consulta desnormalizada objetivo

Después de la migración, el mismo reporte debe resolverse sin JOIN

con producto:

SELECT

    c.nombre AS categoria,

    SUM(dp.cantidad * dp.precio_unitario) AS total_vendido

FROM detalle_pedido dp

JOIN categoria c

    ON c.id = dp.categoria_id

JOIN pedido ped

    ON ped.id = dp.pedido_id

WHERE ped.fecha >= DATE '2026-04-11'

  AND ped.fecha < DATE '2026-04-12'

GROUP BY c.nombre

ORDER BY total_vendido DESC

LIMIT 5;

Debe medirse posteriormente con:

EXPLAIN (ANALYZE, BUFFERS)

utilizando el mismo protocolo de cinco corridas.

## 11. Equivalencia del reporte

Antes de comparar rendimiento, verificar que consulta normalizada

y consulta desnormalizada produzcan exactamente el mismo resultado.

Usar EXCEPT en ambas direcciones.

original_minus_desnormalizada = 0 filas

desnormalizada_minus_original = 0 filas

No considerar válida una mejora de rendimiento si cambia el resultado.

## 12. Auditoría de desincronización

El SQL final debe incluir una consulta de conciliación:

SELECT

    dp.pedido_id,

    dp.producto_id,

    dp.categoria_id AS categoria_guardada,

    pr.categoria_id AS categoria_real

FROM detalle_pedido dp

JOIN producto pr

    ON pr.id = dp.producto_id

WHERE dp.categoria_id IS DISTINCT FROM pr.categoria_id;

Resultado esperado:

0 filas.

Cualquier fila indica corrupción o desincronización del dato redundante.

## 13. Pruebas del mecanismo

El mecanismo debe probarse de forma reversible.

Prueba A:

Insertar o modificar un detalle dentro de una transacción y comprobar

que categoria_id se complete automáticamente.

Prueba B:

Modificar temporalmente producto.categoria_id dentro de una transacción

y comprobar que los detalles asociados se actualicen.

Finalizar las pruebas con ROLLBACK.

No alterar permanentemente los datos del dataset para probar triggers.

## 14. Reversibilidad

El cambio debe ser reversible.

Documentar un plan DOWN que permita:

- eliminar los triggers de sincronización;

- eliminar las funciones trigger;

- eliminar la FOREIGN KEY agregada;

- eliminar la columna detalle_pedido.categoria_id.

No ejecutar el DOWN automáticamente.

La eliminación de la columna redundante NO pierde información original,

porque la fuente de verdad continúa siendo producto.categoria_id.

Backup previo existente:

backups/foodstore_u4_pre_u4.dump

No versionar el dump.

## 15. Archivo final

La implementación posterior debe estar en:

tp_desnormalizacion_top_categorias.sql

Debe contener:

- ALTER TABLE

- backfill

- constraints

- funciones trigger

- triggers

- consulta desnormalizada

- equivalencia bidireccional

- auditoría de sincronización

- documentación del plan DOWN

## 16. Criterios de aceptación

- El diseño parte del schema real.

- No se inventan subtotal ni eliminado.

- La adaptación de CURRENT_DATE queda documentada.

- Se conservan las cinco mediciones baseline.

- La mediana baseline queda documentada como 239.969 ms.

- La decisión ataca un costo observado en EXPLAIN ANALYZE.

- producto.categoria_id continúa siendo fuente de verdad.

- detalle_pedido.categoria_id se mantiene automáticamente.

- INSERT/UPDATE de detalle se sincroniza.

- Cambio de categoría del producto se sincroniza.

- Auditoría devuelve 0 filas.

- Consulta normalizada y desnormalizada son equivalentes.

- Se mide nuevamente con EXPLAIN ANALYZE.

- Existe plan de reversión.

- No se modifica schema.sql.

- No se ejecuta SQL durante la creación de la spec.
