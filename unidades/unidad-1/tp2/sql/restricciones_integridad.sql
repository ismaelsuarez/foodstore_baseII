ALTER TABLE detalle_pedido
    ADD CONSTRAINT chk_detalle_pedido_cantidad CHECK (cantidad > 0),
    ADD CONSTRAINT chk_detalle_pedido_precio_unitario CHECK (precio_unitario >= 0);
