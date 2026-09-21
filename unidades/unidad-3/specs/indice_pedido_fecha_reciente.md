# Spec: indice_pedido_fecha_reciente

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`pedido`: `id`, `usuario_id`, `fecha DATE`, `estado`, `forma_pago`, `total`, `eliminado`. Relación `pedido.usuario_id = usuario.id`. No se presuponen valores ENUM.

## OBJETIVO

Evaluar el listado de pedidos no eliminados desde una fecha inclusiva. La fecha de corte no tiene hora ni zona horaria.

## CONSULTA

```sql
SELECT
    id,
    usuario_id,
    fecha,
    estado,
    forma_pago,
    total
FROM pedido
WHERE eliminado = FALSE
  AND fecha >= DATE '2026-04-11'
ORDER BY fecha DESC;
```

## OBJETO_CANDIDATO

**CANDIDATO_PENDIENTE_DE_MEDICION**. Definición en [indices.sql](../sql/indices.sql).

```sql
CREATE INDEX idx_pedido_fecha_reciente
    ON pedido (fecha DESC)
    INCLUDE (id, usuario_id, estado, forma_pago, total)
    WHERE eliminado = FALSE;
```

La clave expresa el orden descendente. La cobertura mediante `INCLUDE` es una hipótesis, no una elección óptima demostrada; queda sujeta a `EXPLAIN (ANALYZE, BUFFERS)`.

## CRITERIO_DE_ACEPTACION

- Preservar columnas, filtro inclusivo y orden de la consulta.
- Aceptar el índice solo con beneficio medido que compense escritura y espacio, revisando índices existentes sin asumir su inventario.
- Evaluar el costo de cobertura y el ordenamiento observado; no exigir un plan predeterminado.

## RIESGOS

La selectividad depende del dataset y del corte fijo. Columnas incluidas aumentan espacio y costo de actualización; `estado`, `total` y `forma_pago` pueden cambiar. El orden entre pedidos de una misma fecha no está definido por esta consulta.

## VALIDACION_PENDIENTE

Pendiente: inventariar índices y restricciones reales, obtener una nueva línea base y medir antes/después con `EXPLAIN (ANALYZE, BUFFERS)`. Realizar tres corridas por variante, descartar la primera como calentamiento y comparar el promedio de las otras dos sobre el mismo dataset. Registrar planes, filas, buffers y tiempos reales; medir también almacenamiento y mantenimiento en escrituras. No reutilizar cifras históricas como evidencia de este contrato. Probar pedidos anteriores, iguales y posteriores al corte, con y sin eliminación lógica.