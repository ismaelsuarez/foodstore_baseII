# Spec: vista_pedido_detalle

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`detalle_pedido`: `id`, `pedido_id`, `producto_id`, `cantidad`, `precio_unitario`, `subtotal` físico, `eliminado`. `producto`: `id`, `nombre`, `eliminado`. Relación `detalle_pedido.producto_id = producto.id`.

## OBJETIVO

Exponer detalles no eliminados con nombre de producto y subtotal físico. No filtrar `producto.eliminado`: una baja lógica posterior no debe ocultar el detalle histórico.

## CONSULTA

```sql
SELECT
    dp.id AS detalle_id,
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id
WHERE dp.eliminado = FALSE;
```

## OBJETO_CANDIDATO

Definición en [views.sql](../sql/views.sql).

```sql
CREATE OR REPLACE VIEW v_pedido_detalle AS
SELECT
    dp.id AS detalle_id,
    dp.pedido_id,
    dp.producto_id,
    p.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
FROM detalle_pedido dp
JOIN producto p
    ON p.id = dp.producto_id
WHERE dp.eliminado = FALSE;
```

## CRITERIO_DE_ACEPTACION

- Exponer exactamente `detalle_id`, `pedido_id`, `producto_id`, `producto_nombre`, `cantidad`, `precio_unitario`, `subtotal`.
- Leer `dp.subtotal` sin sustituirlo por una multiplicación.
- Excluir detalles eliminados; mantener detalles no eliminados de productos con baja lógica.
- Cumplir equivalencia bidireccional con la consulta manual.

## RIESGOS

Instalación prevista en una copia limpia. Si existe una versión anterior, `CREATE OR REPLACE VIEW` puede no aceptar cambios de columnas; evaluar dependencias y migración por separado. Este bloque no elimina objetos instalados. El nombre expuesto es el actual, no una instantánea. El contrato no incorpora un JOIN ni filtro sobre `pedido`: no debe añadirse sin un cambio explícito de requisitos.

## VALIDACION_PENDIENTE

Pendiente: instalar en una copia con el modelo oficial y comprobar las columnas expuestas. Comparar con la consulta manual mediante `EXCEPT` en ambos sentidos: el criterio esperado es que ambas diferencias estén vacías, no un resultado ya obtenido. Usar un mismo estado de datos para ambas consultas. Una vista convencional no demuestra por sí sola mejora de rendimiento. Probar detalles con y sin eliminación, productos dados de baja y correspondencia directa con el subtotal almacenado.