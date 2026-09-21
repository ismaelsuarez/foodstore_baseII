# Spec: indice_producto_stock_bajo

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`producto`: `id`, `nombre`, `stock`, `precio`, `eliminado`, `disponible`. Eliminación lógica y disponibilidad tienen significados distintos.

## OBJETIVO

Evaluar un acceso para el panel de reposición. Incluir productos no disponibles: pueden ser precisamente los que requieren reposición. No filtrar por `disponible`.

## CONSULTA

```sql
SELECT
    id,
    nombre,
    stock,
    precio
FROM producto
WHERE eliminado = FALSE
  AND stock <= 5
ORDER BY stock ASC, nombre ASC;
```

## OBJETO_CANDIDATO

**CANDIDATO_PENDIENTE_DE_MEDICION**. Definición en [indices.sql](../sql/indices.sql).

```sql
CREATE INDEX idx_producto_stock_bajo
    ON producto (stock ASC, nombre ASC)
    INCLUDE (id, precio)
    WHERE eliminado = FALSE;
```

Claves B-tree alineadas con stock y orden por nombre. `INCLUDE (id, precio)` propone cobertura sin incorporar esas columnas al orden.

## CRITERIO_DE_ACEPTACION

- Mantener exactamente las filas, columnas y orden de la consulta de referencia.
- Aceptar el índice solo si la evidencia real justifica beneficio de lectura frente al costo de escritura y espacio, sin duplicar capacidad existente.
- No exigir un nodo de plan específico ni afirmar de antemano que desaparecerá el ordenamiento.

## RIESGOS

Un predicado parcial no garantiza alta selectividad. `INCLUDE` amplía el índice; las actualizaciones de stock, nombre, precio o eliminación pueden aumentar su mantenimiento. La cobertura no garantiza un Index Only Scan ni ausencia de accesos al heap.

## VALIDACION_PENDIENTE

Pendiente: inventariar índices y restricciones reales, obtener una nueva línea base y medir antes/después con `EXPLAIN (ANALYZE, BUFFERS)`. Realizar tres corridas por variante, descartar la primera como calentamiento y comparar el promedio de las otras dos sobre el mismo dataset. Registrar planes, filas, buffers y tiempos reales; medir también almacenamiento y mantenimiento en escrituras. No reutilizar cifras históricas como evidencia de este contrato. Probar productos eliminados y no eliminados, disponibles y no disponibles, incluidos los límites de stock 5 y 6.