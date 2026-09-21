# Spec: vista_productos_vigentes

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`producto`: `id`, `nombre`, `descripcion`, `precio`, `stock`, `disponible`, `categoria_id`, `eliminado`. `categoria`: `id`, `nombre`, `eliminado`. Relación `producto.categoria_id = categoria.id`.

## OBJETIVO

Exponer productos y categorías no eliminados. Mostrar `disponible` sin usarlo como filtro: disponibilidad y existencia lógica son independientes.

## CONSULTA

```sql
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    p.disponible,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE;
```

## OBJETO_CANDIDATO

Definición en [views.sql](../sql/views.sql).

```sql
CREATE OR REPLACE VIEW v_productos_vigentes AS
SELECT
    p.id AS producto_id,
    p.nombre AS producto_nombre,
    p.descripcion,
    p.precio,
    p.stock,
    p.disponible,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
FROM producto p
JOIN categoria c
    ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE;
```

## CRITERIO_DE_ACEPTACION

- Exponer exactamente `producto_id`, `producto_nombre`, `descripcion`, `precio`, `stock`, `disponible`, `categoria_id`, `categoria_nombre`.
- Excluir productos o categorías eliminados.
- Mantener productos no disponibles cuando ellos y su categoría no estén eliminados.
- Cumplir equivalencia bidireccional con la consulta manual.

## RIESGOS

Instalación prevista en una copia limpia. Si existe una versión anterior, `CREATE OR REPLACE VIEW` puede no aceptar cambios de columnas; evaluar dependencias y migración por separado. Este bloque no elimina objetos instalados. El JOIN requiere una categoría asociada. No confundir catálogo vigente con catálogo disponible para venta.

## VALIDACION_PENDIENTE

Pendiente: instalar en una copia con el modelo oficial y comprobar las columnas expuestas. Comparar con la consulta manual mediante `EXCEPT` en ambos sentidos: el criterio esperado es que ambas diferencias estén vacías, no un resultado ya obtenido. Usar un mismo estado de datos para ambas consultas. Una vista convencional no demuestra por sí sola mejora de rendimiento. Probar todas las combinaciones de eliminación de producto/categoría y disponibilidad.