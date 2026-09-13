# Especificaciones de consultas — TP4 Parte 3

Base de Datos II — Semana 4, Unidad 2: Optimización de Consultas

## Consulta A — Ranking de clientes por gasto total

### Objetivo

Obtener un ranking de clientes según el gasto total acumulado en sus pedidos.

### Tablas involucradas

- cliente
- pedido
- detalle_pedido

### Reglas y filtros

- Incluir únicamente clientes que tengan al menos un pedido.
- Considerar todos los pedidos existentes del cliente.
- El gasto total se calcula como:

  cantidad * precio_unitario

  sumado sobre todos los detalles de todos los pedidos del cliente.

- No usar SELECT *.

### Columnas de salida

1. cliente_id
2. cliente_nombre
3. cantidad_pedidos
4. gasto_total
5. puesto

### Ranking

- Usar una función de ventana.
- El ranking debe ordenar por gasto_total de mayor a menor.
- En caso de empate exacto en gasto_total, los clientes deben compartir puesto.
- Por eso debe utilizarse RANK() y no ROW_NUMBER().
- El criterio de desempate visual final será cliente_nombre ASC,
  pero ese desempate NO debe alterar el puesto compartido.

### Orden final

1. puesto ASC
2. cliente_nombre ASC

### Corte

No usar LIMIT.

---

## Consulta B — Productos cuyo gasto total supera el promedio de su categoría

### Objetivo

Obtener los productos cuyo total facturado supera el promedio de facturación
de los productos pertenecientes a su misma categoría.

### Tablas involucradas

- producto
- categoria
- detalle_pedido

### Definición de facturación por producto

Para cada producto:

SUM(detalle_pedido.cantidad * detalle_pedido.precio_unitario)

### Reglas y filtros

- Incluir únicamente productos con producto.activo = TRUE.
- Incluir únicamente categorías con categoria.activo = TRUE.
- Para calcular el promedio de facturación de una categoría,
  considerar únicamente productos activos de esa categoría.
- La comparación debe ser estricta:

  facturacion_producto > promedio_facturacion_categoria

- No usar SELECT *.

### Columnas de salida

1. producto_id
2. producto_nombre
3. categoria_id
4. categoria_nombre
5. facturacion_producto
6. promedio_facturacion_categoria

### Subconsulta requerida

La primera versión debe usar una subconsulta correlacionada para obtener
el promedio de facturación de la categoría correspondiente al producto exterior.

### Orden final

1. categoria_nombre ASC
2. facturacion_producto DESC
3. producto_nombre ASC

### Corte

No usar LIMIT.

---

## Verificación de equivalencia

Para cada consulta se construirá una segunda implementación con estructura
SQL diferente.

La equivalencia se verificará mediante:

```sql
(consulta_v1) EXCEPT (consulta_v2);
(consulta_v2) EXCEPT (consulta_v1);