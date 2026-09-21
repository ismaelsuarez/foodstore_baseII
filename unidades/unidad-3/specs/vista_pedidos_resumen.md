# Spec: vista_pedidos_resumen

Contrato del modelo oficial de TP5. Requiere una copia de pruebas que lo implemente; no migra tablas ni acredita compatibilidad con `schema.sql` de la raíz. Este bloque no ejecuta SQL ni produce resultados.

## MODELO_OFICIAL

`pedido`: `id`, `usuario_id`, `fecha DATE`, `estado`, `forma_pago`, `total`, `eliminado`. `usuario`: `id`, `nombre`, `apellido`, `eliminado`. Relación `pedido.usuario_id = usuario.id`.

## OBJETIVO

Exponer pedidos no eliminados con identificación del usuario. No filtrar `usuario.eliminado`: su baja lógica posterior no debe ocultar el historial de pedidos.

## CONSULTA

```sql
SELECT
    ped.id AS pedido_id,
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
FROM pedido ped
JOIN usuario u
    ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE;
```

## OBJETO_CANDIDATO

Definición en [views.sql](../sql/views.sql).

```sql
CREATE OR REPLACE VIEW v_pedidos_resumen AS
SELECT
    ped.id AS pedido_id,
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
FROM pedido ped
JOIN usuario u
    ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE;
```

## CRITERIO_DE_ACEPTACION

- Exponer exactamente `pedido_id`, `usuario_id`, `usuario`, `fecha`, `estado`, `forma_pago`, `total`.
- Excluir pedidos eliminados y conservar pedidos no eliminados cuyo usuario tenga baja lógica.
- Obtener `total` de la columna física del pedido, sin recalcularlo.
- Cumplir equivalencia bidireccional con la consulta manual.

## RIESGOS

Instalación prevista en una copia limpia. Si existe una versión anterior, `CREATE OR REPLACE VIEW` puede no aceptar cambios de columnas; evaluar dependencias y migración por separado. Este bloque no elimina objetos instalados. No se inventan estados ni formas de pago. La vista usa el nombre actual del usuario, no una instantánea histórica; su concatenación conserva la semántica SQL de valores nulos. La vista de seguridad se especifica por separado.

## VALIDACION_PENDIENTE

Pendiente: instalar en una copia con el modelo oficial y comprobar las columnas expuestas. Comparar con la consulta manual mediante `EXCEPT` en ambos sentidos: el criterio esperado es que ambas diferencias estén vacías, no un resultado ya obtenido. Usar un mismo estado de datos para ambas consultas. Una vista convencional no demuestra por sí sola mejora de rendimiento. Probar pedidos eliminados y no eliminados asociados a usuarios con y sin baja lógica.