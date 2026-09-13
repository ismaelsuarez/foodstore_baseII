# Spec de restricciones — Food Store

## Regla 1 — Cantidad válida en detalle de pedido

La columna `detalle_pedido.cantidad` debe aceptar únicamente valores mayores que cero.

No deben permitirse valores iguales a cero ni cantidades negativas.
## Regla 2 — Precio unitario válido en detalle de pedido

La columna `detalle_pedido.precio_unitario` debe aceptar únicamente valores mayores o iguales a cero.

No deben permitirse precios unitarios negativos.