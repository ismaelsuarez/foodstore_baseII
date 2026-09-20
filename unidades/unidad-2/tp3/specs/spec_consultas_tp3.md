# Especificaciones de consultas — TP3 Parte 4

Base de Datos II — Semana 3, Unidad 2: Optimización de Consultas

## Consulta A — Resumen de productos vigentes por categoría

### Objetivo

Obtener un resumen de los productos activos agrupados por categoría activa.

### Tablas involucradas

- categoria
- producto

### Reglas y filtros

- Incluir únicamente categorías con `categoria.activo = TRUE`.
- Considerar como productos vigentes únicamente aquellos con `producto.activo = TRUE`.
- Deben aparecer también las categorías activas que no tengan productos activos.
- No usar `SELECT *`.

### Columnas de salida

1. `categoria_id`
2. `categoria_nombre`
3. `cantidad_productos`
4. `precio_promedio`

### Reglas de resultado

- `cantidad_productos` debe ser 0 si la categoría no posee productos activos.
- `precio_promedio` debe ser NULL si la categoría no posee productos activos.
- El promedio debe calcularse únicamente sobre productos activos.

### Orden

1. `cantidad_productos` de mayor a menor.
2. En caso de empate, `categoria_nombre` alfabéticamente ascendente.

### Corte

No utilizar LIMIT.

---

## Consulta B — Productos con precio superior al promedio de su categoría

### Objetivo

Obtener los productos activos cuyo precio sea estrictamente superior al
precio promedio de los productos activos pertenecientes a su misma categoría.

### Tablas involucradas

- producto
- categoria

### Reglas y filtros

- Incluir únicamente productos con `producto.activo = TRUE`.
- La categoría del producto también debe tener `categoria.activo = TRUE`.
- Para calcular el promedio de una categoría, considerar únicamente
  productos activos de esa misma categoría.
- La comparación debe ser estricta: `precio > promedio`.
- No usar `SELECT *`.

### Columnas de salida

1. `producto_id`
2. `producto_nombre`
3. `categoria_id`
4. `categoria_nombre`
5. `precio`
6. `precio_promedio_categoria`

### Subconsulta requerida

La primera solución generada debe utilizar una subconsulta correlacionada
para calcular o comparar el promedio de precio de la categoría correspondiente
a cada producto.

### Orden

1. `categoria_nombre` ascendente.
2. Dentro de cada categoría, `precio` descendente.
3. En caso de empate de precio, `producto_nombre` ascendente.

### Corte

No utilizar LIMIT.

---

## Verificación de equivalencia

Para cada consulta se construirá posteriormente una segunda implementación
con estructura SQL diferente.

La equivalencia deberá verificarse formalmente mediante:

```sql
(consulta_A) EXCEPT (consulta_B);
(consulta_B) EXCEPT (consulta_A);